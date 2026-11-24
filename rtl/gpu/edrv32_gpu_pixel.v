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
    reg [63:0] depth_r [0:31];
    reg [95:0] color_r [0:31];
    reg [31:0] alpha_r [0:31];
    reg [159:0] old_r [0:31];
    reg [159:0] result_r [0:31];
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
    reg [14:0] pipe_valid_r;
    reg [4:0] pipe_slot_r [0:14];
    wire [159:0] pipe_data_w;
    wire [3:0] pipe_pass_w;
    reg predecessor_w;
    reg [4:0] predecessor_slot_w;
    reg reached_w;
    reg [4:0] scan_slot_w;
    wire accept_w;
    wire commit_w;
    wire dispatch_w;
    wire process_w;
    wire read_w;
    wire returned_w;
    wire old_write_w;
    wire [4:0] old_addr_w;
    wire [159:0] old_data_w;
    wire [159:0] old_read_w;
    wire signed [16:0] local_x_w;
    wire signed [16:0] local_y_w;
    wire [31:0] address_w;
    integer scan;
    integer stage;
    genvar lane;
    assign render_state_ready_o = count_r == 0 && !request_valid_r && !stop_i;
    assign shaded_ready_o = count_r < 6'd32 && !stop_i;
    assign accept_w = shaded_valid_i && shaded_ready_o;
    assign local_x_w = {shaded_x_i[15], shaded_x_i} - {target_r[47], target_r[47:32]};
    assign local_y_w = {shaded_y_i[15], shaded_y_i} - {target_r[63], target_r[63:48]};
    assign address_w = {15'b0, local_y_w} * (wide_r ? 32'd320 : 32'd160) +
        {17'b0, local_x_w[16:2]};
    assign target_read_valid_o = request_valid_r && !stop_i;
    assign target_read_addr_o = addr_r[request_slot_r];
    assign read_w = target_read_valid_o && target_read_ready_i;
    assign target_old_ready_o = return_count_r != 0;
    assign returned_w = target_old_valid_i && target_old_ready_o;
    assign target_write_valid_o = valid_r[head_r] && result_valid_r[head_r] && !stop_i;
    assign target_write_addr_o = addr_r[head_r];
    assign target_write_data_o = result_r[head_r];
    assign commit_w = valid_r[head_r] && (stop_i ? result_valid_r[head_r] :
        (target_write_valid_o && target_write_ready_i));
    assign dispatch_w = undispatched_r != 0 &&
        !(returned_w && (predecessor_w || stop_i)) && (stop_i ||
        ((!request_valid_r || read_w) &&
        (!predecessor_w || result_valid_r[predecessor_slot_w])));
    // Target returns own the single old-value write port; forwarding waits one cycle.
    assign old_read_w = old_r[process_r];
    assign old_write_w = returned_w || (dispatch_w && (predecessor_w || stop_i));
    assign old_addr_w = returned_w ? return_slot_r[return_rd_r] : dispatch_r;
    assign old_data_w = returned_w ? target_old_data_i :
        stop_i ? 160'b0 : result_r[predecessor_slot_w];
    assign process_w = unprocessed_r != 0 && old_valid_r[process_r];
    always @(*) begin
        predecessor_w = 0;
        predecessor_slot_w = 0;
        reached_w = 0;
        scan_slot_w = head_r;
        for (scan = 0; scan < 32; scan = scan + 1) begin
            scan_slot_w = head_r + scan[4:0];
            if (scan_slot_w == dispatch_r) begin
                reached_w = 1;
            end
            if (!reached_w && valid_r[scan_slot_w] &&
                addr_r[scan_slot_w] == addr_r[dispatch_r]) begin
                predecessor_w = 1;
                predecessor_slot_w = scan_slot_w;
            end
        end
    end
    generate
        for (lane = 0; lane < 4; lane = lane + 1) begin : g_lane
            edrv32_gpu_pixel_lane u_lane (
                .clk_i(clk_i),
                .mask_i(mask_r[process_r][lane] && !stop_i),
                .old_i(old_read_w[lane*40 +: 40]),
                .depth_i(depth_r[process_r][lane*16 +: 16]),
                .color_i(color_r[process_r][lane*24 +: 24]),
                .alpha_i(alpha_r[process_r][lane*8 +: 8]),
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
            pipe_valid_r <= {pipe_valid_r[13:0], process_w};
            perf_pixel_count_o <= 0;
            if (pipe_valid_r[14]) begin
                result_valid_r[pipe_slot_r[14]] <= 1;
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
            depth_r[tail_r] <= shaded_depth_i;
            color_r[tail_r] <= shaded_color_i;
            alpha_r[tail_r] <= shaded_alpha_i;
        end
        if (dispatch_w && !predecessor_w && !stop_i) begin
            request_slot_r <= dispatch_r;
        end
        if (read_w) begin
            return_slot_r[return_wr_r] <= request_slot_r;
        end
        pipe_slot_r[0] <= process_r;
        for (stage = 1; stage < 15; stage = stage + 1) begin
            pipe_slot_r[stage] <= pipe_slot_r[stage-1];
        end
        if (pipe_valid_r[14]) begin
            result_r[pipe_slot_r[14]] <= pipe_data_w;
        end
    end
    always @(posedge clk_i) begin
        if (old_write_w) old_r[old_addr_w] <= old_data_w;
    end
    wire [479:0] unused_state_w;
    wire [17:0] unused_address_w;
    assign unused_state_w = {render_state_tex_i, render_state_target_i[255:64],
        render_state_target_i[31:0]};
    assign unused_address_w = {address_w[31:16], local_x_w[1:0]};
endmodule
