// File: edrv32_gpu_pixel.v
// Spec: gpu-spec 2.1, 2.7; GPU microarchitecture 4.2, 4.4, 4.7.
// Description: Four-lane pixel pipeline with a 32-entry ordered RMW scoreboard.
// Dispatch waits for the nearest same-word predecessor, then forwards its final word.
// Clock: clk_gpu.
module edrv32_gpu_pixel (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Draw snapshot.
    input wire render_state_valid_i,
    output wire render_state_ready_o,
    input wire [255:0] render_state_tex_i,
    input wire [255:0] render_state_pixel_i,
    input wire [255:0] render_state_target_i,
    input wire render_state_wide_i,

    // Four adjacent shaded pixels; transparent texels have their mask cleared.
    input wire shaded_valid_i,
    output wire shaded_ready_o,
    input wire [15:0] shaded_x_i,
    input wire [15:0] shaded_y_i,
    input wire [3:0] shaded_mask_i,
    input wire [63:0] shaded_depth_i,
    input wire [95:0] shaded_color_i,
    input wire [31:0] shaded_alpha_i,

    // Target read and ordered old-word return.
    output wire target_read_valid_o,
    input wire target_read_ready_i,
    output wire [15:0] target_read_addr_o,
    input wire target_old_valid_i,
    output wire target_old_ready_o,
    input wire [159:0] target_old_data_i,

    // Full merged target word.
    output wire target_write_valid_o,
    input wire target_write_ready_i,
    output wire [15:0] target_write_addr_o,
    output wire [159:0] target_write_data_o,

    // Completion and pixel event.
    input wire finish_i,
    input wire stop_i,
    output reg unit_done_o,
    output reg [2:0] perf_pixel_count_o
);
    reg [255:0] state_r;
    reg [63:32] target_r;
    reg wide_r;
    reg [31:0] valid_r;
    reg [31:0] old_valid_r;
    reg [31:0] result_valid_r;
    reg [15:0] addr_r [0:31];
    reg [3:0] mask_r [0:31];

    reg [4:0] head_r;
    reg [4:0] tail_r;
    reg [4:0] dispatch_r;
    reg [4:0] process_r;
    reg [5:0] count_r;
    reg [5:0] undispatched_r;
    reg [5:0] unprocessed_r;
    reg request_valid_r;
    reg [4:0] request_slot_r;
    reg [4:0] return_slot_r [0:31];
    reg [4:0] return_wr_r;
    reg [4:0] return_rd_r;
    reg [5:0] return_count_r;
    reg [15:0] pipe_valid_r;
    reg [4:0] pipe_slot_r [0:15];
    wire [159:0] pipe_data_w;
    wire [3:0] pipe_pass_w;
    wire predecessor_w;
    wire [4:0] predecessor_slot_w;
    wire accept_w;
    wire commit_w;
    wire dispatch_w;
    wire process_w;
    wire read_w;
    wire returned_w;
    wire old_write_w;
    wire [4:0] old_addr_w;
    wire [159:0] old_data_w;
    reg [159:0] old_read_r;
    reg [3:0] input_mask_r;
    reg [63:0] input_depth_r;
    reg [95:0] input_color_r;
    reg [31:0] input_alpha_r;
    wire signed [16:0] local_x_w;
    wire signed [16:0] local_y_w;
    wire [31:0] address_w;
    wire [31:0] row_times_five_w;
    integer stage;
    genvar lane;
    assign render_state_ready_o = count_r == 0 && !request_valid_r && !stop_i;
    assign shaded_ready_o = count_r < 6'd32 && !stop_i;
    assign accept_w = shaded_valid_i && shaded_ready_o;
    assign local_x_w = {shaded_x_i[15], shaded_x_i} - {target_r[47], target_r[47:32]};
    assign local_y_w = {shaded_y_i[15], shaded_y_i} - {target_r[63], target_r[63:48]};
    assign row_times_five_w = {15'b0, local_y_w} + ({15'b0, local_y_w} << 2);
    assign address_w = (wide_r ? row_times_five_w << 6 : row_times_five_w << 5)
        + {17'b0, local_x_w[16:2]};
    assign target_read_valid_o = request_valid_r && !stop_i;
    assign target_read_addr_o = addr_r[request_slot_r];
    assign read_w = target_read_valid_o && target_read_ready_i;
    assign target_old_ready_o = return_count_r != 0;
    assign returned_w = target_old_valid_i && target_old_ready_o;
    assign target_write_valid_o = valid_r[head_r] && result_valid_r[head_r] && !stop_i;
    assign target_write_addr_o = addr_r[head_r];
    assign target_write_data_o = unused_result_word_read0_w[0 +: 160];
    assign commit_w = valid_r[head_r] && (stop_i ? result_valid_r[head_r] :
        (target_write_valid_o && target_write_ready_i));
    assign dispatch_w = undispatched_r != 0 && dependency_ready_r[dispatch_r] &&
        !(returned_w && (predecessor_w || stop_i)) && (stop_i ||
        ((!request_valid_r || read_w) &&
        (!predecessor_w || result_valid_r[predecessor_slot_w])));
    // Target returns own the single old-value write port; forwarding waits one cycle.
    always @(posedge clk_i) begin
        old_read_r <= unused_old_word_read0_w[0 +: 160];
        input_mask_r <= mask_r[process_r] & {4{!stop_i}};
        input_depth_r <= unused_shade_context_read0_w[0 +: 64];
        input_color_r <= unused_shade_context_read0_w[64 +: 96];
        input_alpha_r <= unused_shade_context_read0_w[160 +: 32];
    end
    assign old_write_w = returned_w || (dispatch_w && (predecessor_w || stop_i));
    assign old_addr_w = returned_w ? return_slot_r[return_rd_r] : dispatch_r;
    assign old_data_w = returned_w ? target_old_data_i :
        stop_i ? 160'b0 : unused_result_word_read1_w[0 +: 160];
    assign process_w = unprocessed_r != 0 && old_valid_r[process_r];
    // Accept-side dependency search is four stages at one word per clock.
    // Six-bit queue tickets distinguish a committed predecessor from a reused slot.
    reg tail_epoch_r;
    reg head_epoch_r;
    reg [3:0] dependency_valid_r;
    reg [31:0] dependency_ready_r;
    reg [5:0] ticket_0_r;
    reg [5:0] ticket_1_r;
    reg [5:0] ticket_2_r;
    reg [31:0] matches_r;
    wire [31:0] matches_w;
    reg [63:0] rotation_r;
    wire [63:0] unused_rotated_w;
    reg [4:0] priority_w;
    reg [4:0] priority_r;
    reg found_r;
    wire [5:0] predecessor_ticket_w;
    wire [11:0] unused_dependency_w;
    wire [11:0] dependency_input_w;
    wire [3:0] dependency_even_index_w;
    assign unused_rotated_w = rotation_r >> {ticket_1_r[4:3], 3'b0};
    assign predecessor_ticket_w = ticket_2_r - 6'd32 + {1'b0, priority_r};
    assign dependency_input_w = {found_r, predecessor_ticket_w,
        predecessor_ticket_w[4:0]};
    assign predecessor_slot_w = unused_dependency_w[4:0];
    assign predecessor_w = unused_dependency_w[11];
    assign dependency_even_index_w = dispatch_r[4:1] + {3'b0, dispatch_r[0]};
    genvar dependency_slot;
    generate
        for (dependency_slot = 0; dependency_slot < 32;
            dependency_slot = dependency_slot + 1) begin : g_dependency_match
            assign matches_w[dependency_slot] = valid_r[dependency_slot] &&
                addr_r[dependency_slot] == address_w[15:0] &&
                !(commit_w && head_r == dependency_slot);
        end
        begin : g_dependency_pool
            reg [11:0] even_r [0:15];
            reg [11:0] odd_r [0:15];
            reg [11:0] even_cache_r;
            reg [11:0] odd_cache_r;
            wire [11:0] even_read_w;
            wire [11:0] odd_read_w;
            wire [5:0] unused_even_age_w;
            wire [5:0] unused_odd_age_w;
            assign even_read_w = even_r[dependency_even_index_w];
            assign odd_read_w = odd_r[dispatch_r[4:1]];
            assign unused_even_age_w = even_read_w[10:5] - {head_epoch_r, head_r};
            assign unused_odd_age_w = odd_read_w[10:5] - {head_epoch_r, head_r};
            // A predecessor committed on this clock may still forward its unchanged result.
            // Reuse cannot replace that result before the new word traverses the lane pipeline.
            assign unused_dependency_w = dispatch_r[0] ? odd_cache_r : even_cache_r;
            always @(posedge clk_i) begin
                if (dependency_valid_r[2] && !ticket_2_r[0])
                    even_r[ticket_2_r[4:1]] <= dependency_input_w;
            end
            always @(posedge clk_i) begin
                if (dependency_valid_r[2] && ticket_2_r[0])
                    odd_r[ticket_2_r[4:1]] <= dependency_input_w;
            end
            always @(posedge clk_i) begin
                even_cache_r <= {even_read_w[11] && !unused_even_age_w[5], even_read_w[10:0]};
                odd_cache_r <= {odd_read_w[11] && !unused_odd_age_w[5], odd_read_w[10:0]};
            end
        end
    endgenerate
    always @(*) begin
        priority_w = 0;
        casez (unused_rotated_w[31:0])
            32'b1???????????????????????????????: priority_w = 5'd31;
            32'b01??????????????????????????????: priority_w = 5'd30;
            32'b001?????????????????????????????: priority_w = 5'd29;
            32'b0001????????????????????????????: priority_w = 5'd28;
            32'b00001???????????????????????????: priority_w = 5'd27;
            32'b000001??????????????????????????: priority_w = 5'd26;
            32'b0000001?????????????????????????: priority_w = 5'd25;
            32'b00000001????????????????????????: priority_w = 5'd24;
            32'b000000001???????????????????????: priority_w = 5'd23;
            32'b0000000001??????????????????????: priority_w = 5'd22;
            32'b00000000001?????????????????????: priority_w = 5'd21;
            32'b000000000001????????????????????: priority_w = 5'd20;
            32'b0000000000001???????????????????: priority_w = 5'd19;
            32'b00000000000001??????????????????: priority_w = 5'd18;
            32'b000000000000001?????????????????: priority_w = 5'd17;
            32'b0000000000000001????????????????: priority_w = 5'd16;
            32'b00000000000000001???????????????: priority_w = 5'd15;
            32'b000000000000000001??????????????: priority_w = 5'd14;
            32'b0000000000000000001?????????????: priority_w = 5'd13;
            32'b00000000000000000001????????????: priority_w = 5'd12;
            32'b000000000000000000001???????????: priority_w = 5'd11;
            32'b0000000000000000000001??????????: priority_w = 5'd10;
            32'b00000000000000000000001?????????: priority_w = 5'd9;
            32'b000000000000000000000001????????: priority_w = 5'd8;
            32'b0000000000000000000000001???????: priority_w = 5'd7;
            32'b00000000000000000000000001??????: priority_w = 5'd6;
            32'b000000000000000000000000001?????: priority_w = 5'd5;
            32'b0000000000000000000000000001????: priority_w = 5'd4;
            32'b00000000000000000000000000001???: priority_w = 5'd3;
            32'b000000000000000000000000000001??: priority_w = 5'd2;
            32'b0000000000000000000000000000001?: priority_w = 5'd1;
            32'b00000000000000000000000000000001: priority_w = 5'd0;
            default: priority_w = 0;
        endcase
    end
    always @(posedge clk_i) begin
        matches_r <= matches_w;
        ticket_0_r <= {tail_epoch_r, tail_r};
        rotation_r <= {matches_r, matches_r} >> ticket_0_r[2:0];
        ticket_1_r <= ticket_0_r;
        priority_r <= priority_w;
        found_r <= |unused_rotated_w[31:0];
        ticket_2_r <= ticket_1_r;
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            tail_epoch_r <= 0;
            head_epoch_r <= 0;
            dependency_valid_r <= 0;
            dependency_ready_r <= 0;
        end else begin
            if (accept_w && tail_r == 31) tail_epoch_r <= !tail_epoch_r;
            if (commit_w && head_r == 31) head_epoch_r <= !head_epoch_r;
            dependency_valid_r <= {dependency_valid_r[2:0], accept_w};
            if (dependency_valid_r[3]) dependency_ready_r[ticket_3_r] <= 1;
            if (accept_w) dependency_ready_r[tail_r] <= 0;
        end
    end
    reg [4:0] ticket_3_r;
    always @(posedge clk_i) ticket_3_r <= ticket_2_r[4:0];
    generate
        for (lane = 0; lane < 4; lane = lane + 1) begin : g_lane
            edrv32_gpu_pixel_lane u_lane (
                .clk_i(clk_i),
                .mask_i(input_mask_r[lane]),
                .old_i(old_read_r[lane*40 +: 40]),
                .depth_i(input_depth_r[lane*16 +: 16]),
                .color_i(input_color_r[lane*24 +: 24]),
                .alpha_i(input_alpha_r[lane*8 +: 8]),
                .result_o(pipe_data_w[lane*40 +: 40]),
                .passed_o(pipe_pass_w[lane]),
                .state_i(state_r)
            );
        end
    endgenerate
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_r <= 0;
            old_valid_r <= 0;
            result_valid_r <= 0;
            head_r <= 0;
            tail_r <= 0;
            dispatch_r <= 0;
            process_r <= 0;
            count_r <= 0;
            undispatched_r <= 0;
            unprocessed_r <= 0;
            request_valid_r <= 0;
            return_wr_r <= 0;
            return_rd_r <= 0;
            return_count_r <= 0;
            pipe_valid_r <= 0;
            unit_done_o <= 0;
            perf_pixel_count_o <= 0;
        end else begin
            pipe_valid_r <= {pipe_valid_r[14:0], process_w};
            perf_pixel_count_o <= 0;
            if (pipe_valid_r[15]) begin
                result_valid_r[pipe_slot_r[15]] <= 1;
                if (!stop_i) begin
                    perf_pixel_count_o <= {2'b0, pipe_pass_w[0]} +
                        {2'b0, pipe_pass_w[1]} + {2'b0, pipe_pass_w[2]} +
                        {2'b0, pipe_pass_w[3]};
                end
            end
            if (accept_w) begin
                valid_r[tail_r] <= 1;
                old_valid_r[tail_r] <= 0;
                result_valid_r[tail_r] <= 0;
                tail_r <= tail_r + 1'b1;
                unit_done_o <= 0;
            end
            if (commit_w) begin
                valid_r[head_r] <= 0;
                head_r <= head_r + 1'b1;
            end
            if (accept_w && !commit_w) begin
                count_r <= count_r + 1'b1;
            end else if (!accept_w && commit_w) begin
                count_r <= count_r - 1'b1;
            end
            if (accept_w && !dispatch_w) begin
                undispatched_r <= undispatched_r + 1'b1;
            end else if (!accept_w && dispatch_w) begin
                undispatched_r <= undispatched_r - 1'b1;
            end
            if (accept_w && !process_w) begin
                unprocessed_r <= unprocessed_r + 1'b1;
            end else if (!accept_w && process_w) begin
                unprocessed_r <= unprocessed_r - 1'b1;
            end
            if (stop_i && request_valid_r) begin
                request_valid_r <= 0;
                old_valid_r[request_slot_r] <= 1;
            end
            if (read_w) begin
                request_valid_r <= 0;
                return_wr_r <= return_wr_r + 1'b1;
            end
            if (dispatch_w) begin
                dispatch_r <= dispatch_r + 1'b1;
                if (predecessor_w || stop_i) begin
                    old_valid_r[dispatch_r] <= 1;
                end else begin
                    request_valid_r <= 1;
                end
            end
            if (returned_w) begin
                old_valid_r[return_slot_r[return_rd_r]] <= 1;
                return_rd_r <= return_rd_r + 1'b1;
            end
            if (read_w && !returned_w) begin
                return_count_r <= return_count_r + 1'b1;
            end else if (!read_w && returned_w) begin
                return_count_r <= return_count_r - 1'b1;
            end
            if (process_w) begin
                process_r <= process_r + 1'b1;
            end
            // Completion belongs to the command lifetime, including empty commands.
            if (!finish_i || (render_state_valid_i && render_state_ready_o)) begin
                unit_done_o <= 0;
            end else if (count_r == 0 && !request_valid_r) begin
                unit_done_o <= 1;
            end
        end
    end
    always @(posedge clk_i) begin
        if (render_state_valid_i && render_state_ready_o) begin
            state_r <= render_state_pixel_i;
            target_r <= render_state_target_i[63:32];
            wide_r <= render_state_wide_i;
        end
        if (accept_w) begin
            addr_r[tail_r] <= address_w[15:0];
            mask_r[tail_r] <= shaded_mask_i;

        end
        if (dispatch_w && !predecessor_w && !stop_i) begin
            request_slot_r <= dispatch_r;
        end
        if (read_w) begin
            return_slot_r[return_wr_r] <= request_slot_r;
        end
        pipe_slot_r[0] <= process_r;
        for (stage = 1; stage < 16; stage = stage + 1) begin
            pipe_slot_r[stage] <= pipe_slot_r[stage-1];
        end
    end
    wire [479:0] unused_state_w;
    wire [17:0] unused_address_w;
    assign unused_state_w = {render_state_tex_i, render_state_target_i[255:64],
        render_state_target_i[31:0]};
    assign unused_address_w = {address_w[31:16], local_x_w[1:0]};
    // Explicit LUTRAM shade_context: 3 slice(s) per combinational read port.
    wire [215:0] shade_context_input_w;
    assign shade_context_input_w = {24'b0, shaded_alpha_i, shaded_color_i, shaded_depth_i};
    wire [215:0] unused_shade_context_read0_w;
    edrv32_ram_gpu_table u_shade_context_p0_b0 (
        .clk_i(clk_i),
        .wr_en_i(accept_w),
        .wr_addr_i({1'b0, tail_r}),
        .wr_data_i(shade_context_input_w[0 +: 72]),
        .rd_addr_i({1'b0, process_r}),
        .rd_data_o(unused_shade_context_read0_w[0 +: 72])
    );
    edrv32_ram_gpu_table u_shade_context_p0_b1 (
        .clk_i(clk_i),
        .wr_en_i(accept_w),
        .wr_addr_i({1'b0, tail_r}),
        .wr_data_i(shade_context_input_w[72 +: 72]),
        .rd_addr_i({1'b0, process_r}),
        .rd_data_o(unused_shade_context_read0_w[72 +: 72])
    );
    edrv32_ram_gpu_table u_shade_context_p0_b2 (
        .clk_i(clk_i),
        .wr_en_i(accept_w),
        .wr_addr_i({1'b0, tail_r}),
        .wr_data_i(shade_context_input_w[144 +: 72]),
        .rd_addr_i({1'b0, process_r}),
        .rd_data_o(unused_shade_context_read0_w[144 +: 72])
    );
    // Explicit LUTRAM old_word: 3 slice(s) per combinational read port.
    wire [215:0] old_word_input_w;
    assign old_word_input_w = {56'b0, old_data_w};
    wire [215:0] unused_old_word_read0_w;
    edrv32_ram_gpu_table u_old_word_p0_b0 (
        .clk_i(clk_i),
        .wr_en_i(old_write_w),
        .wr_addr_i({1'b0, old_addr_w}),
        .wr_data_i(old_word_input_w[0 +: 72]),
        .rd_addr_i({1'b0, process_r}),
        .rd_data_o(unused_old_word_read0_w[0 +: 72])
    );
    edrv32_ram_gpu_table u_old_word_p0_b1 (
        .clk_i(clk_i),
        .wr_en_i(old_write_w),
        .wr_addr_i({1'b0, old_addr_w}),
        .wr_data_i(old_word_input_w[72 +: 72]),
        .rd_addr_i({1'b0, process_r}),
        .rd_data_o(unused_old_word_read0_w[72 +: 72])
    );
    edrv32_ram_gpu_table u_old_word_p0_b2 (
        .clk_i(clk_i),
        .wr_en_i(old_write_w),
        .wr_addr_i({1'b0, old_addr_w}),
        .wr_data_i(old_word_input_w[144 +: 72]),
        .rd_addr_i({1'b0, process_r}),
        .rd_data_o(unused_old_word_read0_w[144 +: 72])
    );
    // Explicit LUTRAM result_word: 3 slice(s) per combinational read port.
    wire [215:0] result_word_input_w;
    assign result_word_input_w = {56'b0, pipe_data_w};
    wire [215:0] unused_result_word_read0_w;
    edrv32_ram_gpu_table u_result_word_p0_b0 (
        .clk_i(clk_i),
        .wr_en_i(pipe_valid_r[15]),
        .wr_addr_i({1'b0, pipe_slot_r[15]}),
        .wr_data_i(result_word_input_w[0 +: 72]),
        .rd_addr_i({1'b0, head_r}),
        .rd_data_o(unused_result_word_read0_w[0 +: 72])
    );
    edrv32_ram_gpu_table u_result_word_p0_b1 (
        .clk_i(clk_i),
        .wr_en_i(pipe_valid_r[15]),
        .wr_addr_i({1'b0, pipe_slot_r[15]}),
        .wr_data_i(result_word_input_w[72 +: 72]),
        .rd_addr_i({1'b0, head_r}),
        .rd_data_o(unused_result_word_read0_w[72 +: 72])
    );
    edrv32_ram_gpu_table u_result_word_p0_b2 (
        .clk_i(clk_i),
        .wr_en_i(pipe_valid_r[15]),
        .wr_addr_i({1'b0, pipe_slot_r[15]}),
        .wr_data_i(result_word_input_w[144 +: 72]),
        .rd_addr_i({1'b0, head_r}),
        .rd_data_o(unused_result_word_read0_w[144 +: 72])
    );
    wire [215:0] unused_result_word_read1_w;
    edrv32_ram_gpu_table u_result_word_p1_b0 (
        .clk_i(clk_i),
        .wr_en_i(pipe_valid_r[15]),
        .wr_addr_i({1'b0, pipe_slot_r[15]}),
        .wr_data_i(result_word_input_w[0 +: 72]),
        .rd_addr_i({1'b0, predecessor_slot_w}),
        .rd_data_o(unused_result_word_read1_w[0 +: 72])
    );
    edrv32_ram_gpu_table u_result_word_p1_b1 (
        .clk_i(clk_i),
        .wr_en_i(pipe_valid_r[15]),
        .wr_addr_i({1'b0, pipe_slot_r[15]}),
        .wr_data_i(result_word_input_w[72 +: 72]),
        .rd_addr_i({1'b0, predecessor_slot_w}),
        .rd_data_o(unused_result_word_read1_w[72 +: 72])
    );
    edrv32_ram_gpu_table u_result_word_p1_b2 (
        .clk_i(clk_i),
        .wr_en_i(pipe_valid_r[15]),
        .wr_addr_i({1'b0, pipe_slot_r[15]}),
        .wr_data_i(result_word_input_w[144 +: 72]),
        .rd_addr_i({1'b0, predecessor_slot_w}),
        .rd_data_o(unused_result_word_read1_w[144 +: 72])
    );
endmodule
