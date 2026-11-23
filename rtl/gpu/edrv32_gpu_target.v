// File: edrv32_gpu_target.v
// Spec: gpu-spec 2.1, 2.3; GPU microarchitecture 4.2, 4.4, 4.7, 4.8.
// Description: Ordered target read/write and exclusive RESOLVE access.
// CLEAR streams full words through the same tree, preserving every unselected field.
// Clock: clk_gpu.
module edrv32_gpu_target (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // CLEAR command and target snapshot.
    input wire clear_valid_i,
    output wire clear_ready_o,
    input wire [255:0] clear_command_i,
    input wire [255:0] clear_target_i,
    input wire clear_wide_i,

    // Pixel access.
    input wire target_read_valid_i,
    output wire target_read_ready_o,
    input wire [15:0] target_read_addr_i,
    output wire target_old_valid_o,
    input wire target_old_ready_i,
    output wire [159:0] target_old_data_o,
    input wire target_write_valid_i,
    output wire target_write_ready_o,
    input wire [15:0] target_write_addr_i,
    input wire [159:0] target_write_data_i,

    // RESOLVE color access.
    input wire resolve_read_valid_i,
    output wire resolve_read_ready_o,
    input wire [15:0] resolve_read_addr_i,
    output wire resolve_color_valid_o,
    input wire resolve_color_ready_i,
    output wire [63:0] resolve_color_data_o,

    // Command drain.
    input wire finish_i,
    input wire stop_i,
    output reg unit_done_o
);
    reg clear_active_r;
    reg clear_issued_r;
    reg [1:0] clear_prepare_r;
    reg [10:0] clear_first_x_r;
    reg [10:0] clear_last_x_r;
    reg [7:0] clear_last_y_r;
    reg [15:0] clear_row_step_r;
    reg signed [17:0] clear_x0_w;
    reg signed [17:0] clear_y0_w;
    reg signed [17:0] clear_x1_w;
    reg signed [17:0] clear_y1_w;
    reg signed [17:0] unused_clear_last_x_w;
    reg signed [17:0] unused_clear_last_y_w;
    reg clear_empty_w;
    wire [15:0] clear_first_addr_w;
    wire [15:0] clear_row_step_w;
    reg [15:0] clear_addr_r;
    reg [10:0] clear_x_r;
    reg [7:0] clear_y_r;
    reg [74:32] clear_command_r;
    reg [127:32] clear_target_r;
    reg clear_wide_r;
    reg [3:0] clear_mask_w;
    reg signed [17:0] screen_x_w;
    reg signed [17:0] screen_y_w;
    wire read_valid_w;
    wire read_ready_w;
    wire [15:0] read_addr_w;
    wire [5:0] read_meta_w;
    wire old_valid_w;
    wire old_ready_w;
    wire [159:0] old_data_w;
    wire [15:0] old_addr_w;
    wire [5:0] old_meta_w;
    wire write_valid_w;
    wire [15:0] write_addr_w;
    wire [159:0] write_data_w;
    wire idle_w;
    reg [159:0] cleared_w;
    integer lane;
    assign clear_ready_o = !clear_active_r && idle_w && !stop_i;
    assign target_read_ready_o = !clear_active_r && read_ready_w && !stop_i;
    assign resolve_read_ready_o = !clear_active_r && read_ready_w && !stop_i &&
        !target_read_valid_i;
    assign target_write_ready_o = !clear_active_r && !stop_i;
    assign clear_first_addr_w = clear_wide_r
        ? {8'd0, clear_y_r} * 16'd320 + {7'd0, clear_x_r[10:2]}
        : {8'd0, clear_y_r} * 16'd160 + {7'd0, clear_x_r[10:2]};
    assign clear_row_step_w = (clear_wide_r ? 16'd320 : 16'd160)
        - ({7'd0, clear_last_x_r[10:2]} - {7'd0, clear_first_x_r[10:2]});
    assign read_valid_w = !stop_i && (clear_active_r
        ? (clear_prepare_r == 0 && !clear_issued_r) :
        (target_read_valid_i || resolve_read_valid_i));
    assign read_addr_w = clear_active_r ? clear_addr_r :
        (target_read_valid_i ? target_read_addr_i : resolve_read_addr_i);
    assign read_meta_w = clear_active_r ? {2'd2, clear_mask_w} :
        {1'b0, !target_read_valid_i, 4'b0};
    assign target_old_valid_o = old_valid_w && old_meta_w[5:4] == 0;
    assign target_old_data_o = old_data_w;
    assign resolve_color_valid_o = old_valid_w && old_meta_w[5:4] == 1;
    assign old_ready_w = stop_i || old_meta_w[5] ||
        (old_meta_w[4] ? resolve_color_ready_i : target_old_ready_i);
    assign write_valid_w = !stop_i && (clear_active_r ? old_valid_w && old_meta_w[5] :
        target_write_valid_i);
    assign write_addr_w = clear_active_r ? old_addr_w : target_write_addr_i;
    assign write_data_w = clear_active_r ? cleared_w : target_write_data_i;

    // Work in target-local coordinates, then retain whole words at partial lane edges.
    // The two preparation clocks separate clipping from row-address arithmetic.
    always @(*) begin
        clear_x0_w = $signed({{2{clear_target_r[79]}}, clear_target_r[79:64]})
            - $signed({{2{clear_target_r[47]}}, clear_target_r[47:32]});
        clear_y0_w = $signed({{2{clear_target_r[95]}}, clear_target_r[95:80]})
            - $signed({{2{clear_target_r[63]}}, clear_target_r[63:48]});
        clear_x1_w = $signed({{2{clear_target_r[111]}}, clear_target_r[111:96]})
            - $signed({{2{clear_target_r[47]}}, clear_target_r[47:32]});
        clear_y1_w = $signed({{2{clear_target_r[127]}}, clear_target_r[127:112]})
            - $signed({{2{clear_target_r[63]}}, clear_target_r[63:48]});
        unused_clear_last_x_w = 18'sd0;
        unused_clear_last_y_w = 18'sd0;
        clear_empty_w = 1'b0;
        if (clear_x0_w < 0) clear_x0_w = 18'sd0;
        if (clear_y0_w < 0) clear_y0_w = 18'sd0;
        if (clear_x1_w > (clear_wide_r ? 18'sd1280 : 18'sd640))
            clear_x1_w = clear_wide_r ? 18'sd1280 : 18'sd640;
        if (clear_y1_w > (clear_wide_r ? 18'sd90 : 18'sd180))
            clear_y1_w = clear_wide_r ? 18'sd90 : 18'sd180;
        unused_clear_last_x_w = clear_x1_w - 18'sd1;
        unused_clear_last_y_w = clear_y1_w - 18'sd1;
        clear_empty_w = clear_x0_w >= clear_x1_w || clear_y0_w >= clear_y1_w;
    end

    genvar color_lane;
    generate
        for (color_lane = 0; color_lane < 4; color_lane = color_lane + 1) begin : g_color
            assign resolve_color_data_o[color_lane*16 +: 16] =
                old_data_w[color_lane*40 +: 16];
        end
    endgenerate
    always @(*) begin
        clear_mask_w = 0;
        screen_x_w = 0;
        screen_y_w = $signed({{2{clear_target_r[63]}}, clear_target_r[63:48]}) +
            $signed({10'b0, clear_y_r});
        cleared_w = old_data_w;
        for (lane = 0; lane < 4; lane = lane + 1) begin
            screen_x_w = $signed({{2{clear_target_r[47]}}, clear_target_r[47:32]}) +
                $signed({7'b0, clear_x_r}) + $signed({16'b0, lane[1:0]});
            clear_mask_w[lane] =
                screen_x_w >= $signed({{2{clear_target_r[79]}}, clear_target_r[79:64]}) &&
                screen_x_w < $signed({{2{clear_target_r[111]}}, clear_target_r[111:96]}) &&
                screen_y_w >= $signed({{2{clear_target_r[95]}}, clear_target_r[95:80]}) &&
                screen_y_w < $signed({{2{clear_target_r[127]}}, clear_target_r[127:112]});
            if (old_meta_w[lane]) begin
                if (clear_command_r[72]) begin
                    cleared_w[lane*40 +: 16] = clear_command_r[47:32];
                end
                if (clear_command_r[73]) begin
                    cleared_w[lane*40+16 +: 16] = clear_command_r[63:48];
                end
                if (clear_command_r[74]) begin
                    cleared_w[lane*40+32 +: 8] = clear_command_r[71:64];
                end
            end
        end
    end
    edrv32_gpu_target_store u_store (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .read_valid_i(read_valid_w),
        .read_ready_o(read_ready_w),
        .read_addr_i(read_addr_w),
        .read_meta_i(read_meta_w),
        .old_valid_o(old_valid_w),
        .old_ready_i(old_ready_w),
        .old_data_o(old_data_w),
        .old_addr_o(old_addr_w),
        .old_meta_o(old_meta_w),
        .write_valid_i(write_valid_w),
        .write_addr_i(write_addr_w),
        .write_data_i(write_data_w),
        .idle_o(idle_w)
    );
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            clear_active_r <= 0;
            clear_issued_r <= 0;
            clear_prepare_r <= 0;
            clear_addr_r <= 0;
            clear_x_r <= 0;
            clear_y_r <= 0;
            unit_done_o <= 0;
        end else begin
            if (clear_valid_i && clear_ready_o) begin
                clear_active_r <= 1;
                clear_issued_r <= 0;
                clear_prepare_r <= 2;
                clear_addr_r <= 0;
                clear_x_r <= 0;
                clear_y_r <= 0;
                unit_done_o <= 0;
            end
            if (clear_prepare_r != 0) begin
                clear_prepare_r <= clear_prepare_r - 1'b1;
                if (clear_prepare_r == 2) begin
                    clear_x_r <= {clear_x0_w[10:2], 2'b00};
                    clear_y_r <= clear_y0_w[7:0];
                    clear_issued_r <= clear_empty_w;
                end else begin
                    clear_addr_r <= clear_first_addr_w;
                end
            end
            if (clear_active_r && read_valid_w && read_ready_w) begin
                if (clear_x_r == clear_last_x_r) begin
                    if (clear_y_r == clear_last_y_r) begin
                        clear_issued_r <= 1;
                    end else begin
                        clear_addr_r <= clear_addr_r + clear_row_step_r;
                        clear_x_r <= clear_first_x_r;
                        clear_y_r <= clear_y_r + 1'b1;
                    end
                end else begin
                    clear_addr_r <= clear_addr_r + 1'b1;
                    clear_x_r <= clear_x_r + 11'd4;
                end
            end
            if (stop_i) clear_prepare_r <= 0;
            if (clear_active_r && (clear_issued_r || stop_i) && idle_w
                && (clear_prepare_r == 0 || stop_i)) begin
                clear_active_r <= 0;
            end
            if (target_read_valid_i || resolve_read_valid_i || target_write_valid_i) begin
                unit_done_o <= 0;
            end
            // A new command can spend many clocks upstream before its first target access.
            // microarch 4.2: finish low must clear the previous command's completion.
            if (!finish_i) begin
                unit_done_o <= 0;
            end else if (idle_w && !clear_active_r && !read_valid_w && !write_valid_w) begin
                unit_done_o <= 1;
            end
        end
    end
    always @(posedge clk_i) begin
        if (clear_prepare_r == 2) begin
            clear_first_x_r <= {clear_x0_w[10:2], 2'b00};
            clear_last_x_r <= {unused_clear_last_x_w[10:2], 2'b00};
            clear_last_y_r <= unused_clear_last_y_w[7:0];
        end
        if (clear_prepare_r == 1) clear_row_step_r <= clear_row_step_w;
        if (clear_valid_i && clear_ready_o) begin
            clear_command_r <= clear_command_i[74:32];
            clear_target_r <= clear_target_i[127:32];
            clear_wide_r <= clear_wide_i;
        end
    end
    wire [212:0] unused_command_w;
    wire [159:0] unused_target_w;
    assign unused_command_w = {clear_command_i[255:75], clear_command_i[31:0]};
    assign unused_target_w = {clear_target_i[255:128], clear_target_i[31:0]};
endmodule
