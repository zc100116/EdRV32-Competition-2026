// ============================================================================
// File        : edrv32_pixel_window_3x3_2p.v
// Description : Two-pixel RGB565 3x3 window, line buffering and filter stage.
// Notes       : Three rotating line RAMs provide a centered vertical window.
//               A synthetic zero row flushes the final image row.
// ============================================================================

module edrv32_pixel_window_3x3_2p #(
    parameter integer H_ACTIVE = 1280,
    parameter integer LINE_ADDR_W = 10
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire [15:0]  pixel0_i,
    input  wire [15:0]  pixel1_i,
    input  wire         sof_i,
    input  wire         eof_i,
    input  wire         sol_i,
    input  wire         eol_i,
    input  wire         pair_valid_i,
    output wire         pair_ready_o,

    output wire [15:0]  pixel0_o,
    output wire [15:0]  pixel1_o,
    output wire         sof_o,
    output wire         eof_o,
    output wire         sol_o,
    output wire         eol_o,
    output wire         pair_valid_o,
    input  wire         pair_ready_i,

    input  wire         cfg_commit_i,
    input  wire         cfg_enable_i,
    input  wire [2:0]   cfg_mode_i,
    input  wire [7:0]   cfg_threshold_i,
    output wire         cfg_pending_o
);

    localparam integer PAIRS_PER_LINE = H_ACTIVE / 2;

    function [7:0] rgb565_to_gray;
        input [15:0] pixel;
        reg [7:0] red;
        reg [7:0] green;
        reg [7:0] blue;
        reg [16:0] weighted;
        begin
            red = {pixel[15:11], pixel[15:13]};
            green = {pixel[10:5], pixel[10:9]};
            blue = {pixel[4:0], pixel[4:2]};
            weighted = red * 8'd77 + green * 8'd150 +
                blue * 8'd29 + 17'd128;
            rgb565_to_gray = weighted[15:8];
        end
    endfunction

    function [31:0] select_bank;
        input [1:0] bank;
        input [31:0] bank0;
        input [31:0] bank1;
        input [31:0] bank2;
        begin
            case (bank)
                2'd0: select_bank = bank0;
                2'd1: select_bank = bank1;
                default: select_bank = bank2;
            endcase
        end
    endfunction

    // ---------------------------------------------------------------------
    // Frame-atomic spatial configuration.
    // ---------------------------------------------------------------------
    reg shadow_enable_r;
    reg [2:0] shadow_mode_r;
    reg [7:0] shadow_threshold_r;
    reg active_enable_r;
    reg [2:0] active_mode_r;
    reg [7:0] active_threshold_r;
    reg cfg_pending_r;

    assign cfg_pending_o = cfg_pending_r;

    // ---------------------------------------------------------------------
    // Three line stores. One bank is written while the previous two are read.
    // ---------------------------------------------------------------------
    wire [31:0] ram0_read_data_w;
    wire [31:0] ram1_read_data_w;
    wire [31:0] ram2_read_data_w;
    wire ram_read_enable_w;
    wire [LINE_ADDR_W-1:0] ram_read_addr_w;
    wire [LINE_ADDR_W-1:0] ram_write_addr_w;
    wire [31:0] ram_write_data_w;
    wire ram0_write_enable_w;
    wire ram1_write_enable_w;
    wire ram2_write_enable_w;

    edrv32_pixel_line_ram #(.ADDR_W(LINE_ADDR_W)) u_line_ram0 (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .rd_en_i(ram_read_enable_w), .rd_addr_i(ram_read_addr_w),
        .rd_data_o(ram0_read_data_w),
        .wr_en_i(ram0_write_enable_w), .wr_addr_i(ram_write_addr_w),
        .wr_data_i(ram_write_data_w)
    );

    edrv32_pixel_line_ram #(.ADDR_W(LINE_ADDR_W)) u_line_ram1 (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .rd_en_i(ram_read_enable_w), .rd_addr_i(ram_read_addr_w),
        .rd_data_o(ram1_read_data_w),
        .wr_en_i(ram1_write_enable_w), .wr_addr_i(ram_write_addr_w),
        .wr_data_i(ram_write_data_w)
    );

    edrv32_pixel_line_ram #(.ADDR_W(LINE_ADDR_W)) u_line_ram2 (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .rd_en_i(ram_read_enable_w), .rd_addr_i(ram_read_addr_w),
        .rd_data_o(ram2_read_data_w),
        .wr_en_i(ram2_write_enable_w), .wr_addr_i(ram_write_addr_w),
        .wr_data_i(ram_write_data_w)
    );

    // ---------------------------------------------------------------------
    // Synchronous RAM request and aligned-row stages.
    // ---------------------------------------------------------------------
    reg [1:0] write_bank_r;
    reg [1:0] prev1_bank_r;
    reg [1:0] prev2_bank_r;
    reg [1:0] valid_rows_r;
    reg [LINE_ADDR_W-1:0] pair_addr_r;
    reg flush_active_r;
    reg drain_active_r;
    reg [LINE_ADDR_W-1:0] flush_addr_r;
    reg output_started_r;

    reg req_valid_r;
    reg [1:0] req_prev1_bank_r;
    reg [1:0] req_prev2_bank_r;
    reg req_prev1_valid_r;
    reg req_prev2_valid_r;
    reg [31:0] req_bottom_rgb_r;
    reg req_bottom_valid_r;
    reg req_sof_r;
    reg req_eof_r;
    reg req_sol_r;
    reg req_eol_r;

    reg aligned_valid_r;
    reg [31:0] aligned_top_rgb_r;
    reg [31:0] aligned_mid_rgb_r;
    reg [31:0] aligned_bottom_rgb_r;
    reg aligned_sof_r;
    reg aligned_eof_r;
    reg aligned_sol_r;
    reg aligned_eol_r;

    wire horizontal_ready_w;
    wire aligned_slot_w = !aligned_valid_r || horizontal_ready_w;
    wire request_slot_w = !req_valid_r || aligned_slot_w;
    wire input_allowed_w = !flush_active_r && !drain_active_r;
    wire input_fire_w = pair_valid_i && pair_ready_o;
    wire flush_fire_w = flush_active_r && request_slot_w;
    wire source_fire_w = input_fire_w || flush_fire_w;
    wire source_is_flush_w = flush_fire_w;
    wire [LINE_ADDR_W-1:0] input_addr_w = sol_i ?
        {LINE_ADDR_W{1'b0}} : pair_addr_r;
    wire [LINE_ADDR_W-1:0] source_addr_w = source_is_flush_w ?
        flush_addr_r : input_addr_w;
    wire source_last_w = source_addr_w == PAIRS_PER_LINE - 1;
    wire [1:0] source_write_bank_w = sof_i ? 2'd0 : write_bank_r;
    wire source_center_valid_w = source_is_flush_w ?
        1'b1 : (!sof_i && (valid_rows_r != 0));
    wire source_top_valid_w = !sof_i && (valid_rows_r >= 2);
    wire source_sof_w = source_center_valid_w && !output_started_r &&
        (source_addr_w == 0);

    assign pair_ready_o = input_allowed_w && request_slot_w;
    assign ram_read_enable_w = source_fire_w;
    assign ram_read_addr_w = source_addr_w;
    assign ram_write_addr_w = input_addr_w;
    assign ram_write_data_w = {pixel1_i, pixel0_i};
    assign ram0_write_enable_w = input_fire_w &&
        (source_write_bank_w == 2'd0);
    assign ram1_write_enable_w = input_fire_w &&
        (source_write_bank_w == 2'd1);
    assign ram2_write_enable_w = input_fire_w &&
        (source_write_bank_w == 2'd2);

    wire [31:0] selected_prev1_w = select_bank(
        req_prev1_bank_r, ram0_read_data_w,
        ram1_read_data_w, ram2_read_data_w);
    wire [31:0] selected_prev2_w = select_bank(
        req_prev2_bank_r, ram0_read_data_w,
        ram1_read_data_w, ram2_read_data_w);

    // ---------------------------------------------------------------------
    // Horizontal look-ahead. Four columns produce two adjacent 3x3 windows.
    // ---------------------------------------------------------------------
    reg hold_valid_r;
    reg horizontal_flush_r;
    reg [31:0] hold_top_rgb_r;
    reg [31:0] hold_mid_rgb_r;
    reg [31:0] hold_bottom_rgb_r;
    reg hold_sof_r;
    reg hold_eof_r;
    reg hold_sol_r;
    reg hold_eol_r;
    reg [7:0] left_top_gray_r;
    reg [7:0] left_mid_gray_r;
    reg [7:0] left_bottom_gray_r;

    // Registered pair of 3x3 windows. This boundary separates RGB-to-gray
    // conversion and horizontal look-ahead from the selected filter kernel.
    reg filter_valid_r;
    reg [7:0] filter0_p00_r;
    reg [7:0] filter0_p01_r;
    reg [7:0] filter0_p02_r;
    reg [7:0] filter0_p10_r;
    reg [7:0] filter0_p11_r;
    reg [7:0] filter0_p12_r;
    reg [7:0] filter0_p20_r;
    reg [7:0] filter0_p21_r;
    reg [7:0] filter0_p22_r;
    reg [7:0] filter1_p00_r;
    reg [7:0] filter1_p01_r;
    reg [7:0] filter1_p02_r;
    reg [7:0] filter1_p10_r;
    reg [7:0] filter1_p11_r;
    reg [7:0] filter1_p12_r;
    reg [7:0] filter1_p20_r;
    reg [7:0] filter1_p21_r;
    reg [7:0] filter1_p22_r;
    reg [15:0] filter_center0_rgb_r;
    reg [15:0] filter_center1_rgb_r;
    reg filter_enable_r;
    reg [2:0] filter_mode_r;
    reg [7:0] filter_threshold_r;
    reg filter_sof_r;
    reg filter_eof_r;
    reg filter_sol_r;
    reg filter_eol_r;

    reg [15:0] pixel0_r;
    reg [15:0] pixel1_r;
    reg sof_r;
    reg eof_r;
    reg sol_r;
    reg eol_r;
    reg pair_valid_r;

    wire output_slot_w = !pair_valid_r || pair_ready_i;
    wire output_fire_w = pair_valid_r && pair_ready_i;
    wire filter_fire_w = filter_valid_r && output_slot_w;
    wire filter_ready_w = !filter_valid_r || output_slot_w;
    wire aligned_fire_w = aligned_valid_r && horizontal_ready_w;

    assign horizontal_ready_w = !horizontal_flush_r && filter_ready_w;
    assign pixel0_o = pixel0_r;
    assign pixel1_o = pixel1_r;
    assign sof_o = sof_r;
    assign eof_o = eof_r;
    assign sol_o = sol_r;
    assign eol_o = eol_r;
    assign pair_valid_o = pair_valid_r;

    wire [7:0] hold_top0_gray_w = rgb565_to_gray(hold_top_rgb_r[15:0]);
    wire [7:0] hold_top1_gray_w = rgb565_to_gray(hold_top_rgb_r[31:16]);
    wire [7:0] hold_mid0_gray_w = rgb565_to_gray(hold_mid_rgb_r[15:0]);
    wire [7:0] hold_mid1_gray_w = rgb565_to_gray(hold_mid_rgb_r[31:16]);
    wire [7:0] hold_bottom0_gray_w =
        rgb565_to_gray(hold_bottom_rgb_r[15:0]);
    wire [7:0] hold_bottom1_gray_w =
        rgb565_to_gray(hold_bottom_rgb_r[31:16]);
    wire [7:0] next_top0_gray_w =
        rgb565_to_gray(aligned_top_rgb_r[15:0]);
    wire [7:0] next_mid0_gray_w =
        rgb565_to_gray(aligned_mid_rgb_r[15:0]);
    wire [7:0] next_bottom0_gray_w =
        rgb565_to_gray(aligned_bottom_rgb_r[15:0]);

    wire [15:0] filtered0_w;
    wire [15:0] filtered1_w;
    edrv32_pixel_filter_3x3 u_filter0 (
        .p00_i(filter0_p00_r), .p01_i(filter0_p01_r),
        .p02_i(filter0_p02_r), .p10_i(filter0_p10_r),
        .p11_i(filter0_p11_r), .p12_i(filter0_p12_r),
        .p20_i(filter0_p20_r), .p21_i(filter0_p21_r),
        .p22_i(filter0_p22_r),
        .center_rgb_i(filter_center0_rgb_r),
        .enable_i(filter_enable_r), .mode_i(filter_mode_r),
        .threshold_i(filter_threshold_r), .pixel_o(filtered0_w)
    );

    edrv32_pixel_filter_3x3 u_filter1 (
        .p00_i(filter1_p00_r), .p01_i(filter1_p01_r),
        .p02_i(filter1_p02_r), .p10_i(filter1_p10_r),
        .p11_i(filter1_p11_r), .p12_i(filter1_p12_r),
        .p20_i(filter1_p20_r), .p21_i(filter1_p21_r),
        .p22_i(filter1_p22_r),
        .center_rgb_i(filter_center1_rgb_r),
        .enable_i(filter_enable_r), .mode_i(filter_mode_r),
        .threshold_i(filter_threshold_r), .pixel_o(filtered1_w)
    );

    // Configuration and vertical request state.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            shadow_enable_r <= 1'b0;
            shadow_mode_r <= 3'b0;
            shadow_threshold_r <= 8'd128;
            active_enable_r <= 1'b0;
            active_mode_r <= 3'b0;
            active_threshold_r <= 8'd128;
            cfg_pending_r <= 1'b0;
            write_bank_r <= 2'd0;
            prev1_bank_r <= 2'd0;
            prev2_bank_r <= 2'd0;
            valid_rows_r <= 2'd0;
            pair_addr_r <= {LINE_ADDR_W{1'b0}};
            flush_active_r <= 1'b0;
            drain_active_r <= 1'b0;
            flush_addr_r <= {LINE_ADDR_W{1'b0}};
            output_started_r <= 1'b0;
        end else begin
            if (cfg_commit_i) begin
                shadow_enable_r <= cfg_enable_i;
                shadow_mode_r <= cfg_mode_i;
                shadow_threshold_r <= cfg_threshold_i;
                cfg_pending_r <= 1'b1;
            end

            if (output_fire_w && eof_r) begin
                drain_active_r <= 1'b0;
                output_started_r <= 1'b0;
            end

            if (input_fire_w) begin
                if (sof_i) begin
                    write_bank_r <= 2'd0;
                    prev1_bank_r <= 2'd0;
                    prev2_bank_r <= 2'd0;
                    valid_rows_r <= 2'd0;
                    output_started_r <= 1'b0;
                    if (cfg_pending_r || cfg_commit_i) begin
                        active_enable_r <= cfg_commit_i ?
                            cfg_enable_i : shadow_enable_r;
                        active_mode_r <= cfg_commit_i ?
                            cfg_mode_i : shadow_mode_r;
                        active_threshold_r <= cfg_commit_i ?
                            cfg_threshold_i : shadow_threshold_r;
                        cfg_pending_r <= 1'b0;
                    end
                end

                if (eol_i) begin
                    prev2_bank_r <= prev1_bank_r;
                    prev1_bank_r <= source_write_bank_w;
                    write_bank_r <= (source_write_bank_w == 2'd2) ?
                        2'd0 : source_write_bank_w + 1'b1;
                    if (valid_rows_r < 2)
                        valid_rows_r <= valid_rows_r + 1'b1;
                    pair_addr_r <= {LINE_ADDR_W{1'b0}};
                end else begin
                    pair_addr_r <= input_addr_w + 1'b1;
                end

                if (eof_i) begin
                    flush_active_r <= 1'b1;
                    flush_addr_r <= {LINE_ADDR_W{1'b0}};
                end
            end

            if (source_fire_w && source_center_valid_w &&
                !output_started_r)
                output_started_r <= 1'b1;

            if (flush_fire_w) begin
                if (source_last_w) begin
                    flush_active_r <= 1'b0;
                    drain_active_r <= 1'b1;
                    flush_addr_r <= {LINE_ADDR_W{1'b0}};
                end else begin
                    flush_addr_r <= flush_addr_r + 1'b1;
                end
            end
        end
    end

    // Request metadata aligns with the synchronous RAM outputs.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            req_valid_r <= 1'b0;
            req_prev1_bank_r <= 2'b0;
            req_prev2_bank_r <= 2'b0;
            req_prev1_valid_r <= 1'b0;
            req_prev2_valid_r <= 1'b0;
            req_bottom_rgb_r <= 32'b0;
            req_bottom_valid_r <= 1'b0;
            req_sof_r <= 1'b0;
            req_eof_r <= 1'b0;
            req_sol_r <= 1'b0;
            req_eol_r <= 1'b0;
        end else begin
            if (req_valid_r && aligned_slot_w)
                req_valid_r <= 1'b0;

            if (source_fire_w) begin
                req_valid_r <= 1'b1;
                req_prev1_bank_r <= prev1_bank_r;
                req_prev2_bank_r <= prev2_bank_r;
                req_prev1_valid_r <= source_center_valid_w;
                req_prev2_valid_r <= source_top_valid_w;
                req_bottom_rgb_r <= source_is_flush_w ?
                    32'b0 : {pixel1_i, pixel0_i};
                req_bottom_valid_r <= !source_is_flush_w;
                req_sof_r <= source_sof_w;
                req_eof_r <= source_is_flush_w && source_last_w;
                req_sol_r <= source_addr_w == 0;
                req_eol_r <= source_last_w;
            end
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            aligned_valid_r <= 1'b0;
            aligned_top_rgb_r <= 32'b0;
            aligned_mid_rgb_r <= 32'b0;
            aligned_bottom_rgb_r <= 32'b0;
            aligned_sof_r <= 1'b0;
            aligned_eof_r <= 1'b0;
            aligned_sol_r <= 1'b0;
            aligned_eol_r <= 1'b0;
        end else begin
            if (aligned_valid_r && horizontal_ready_w)
                aligned_valid_r <= 1'b0;

            if (req_valid_r && aligned_slot_w) begin
                aligned_valid_r <= req_prev1_valid_r;
                aligned_top_rgb_r <= req_prev2_valid_r ?
                    selected_prev2_w : 32'b0;
                aligned_mid_rgb_r <= req_prev1_valid_r ?
                    selected_prev1_w : 32'b0;
                aligned_bottom_rgb_r <= req_bottom_valid_r ?
                    req_bottom_rgb_r : 32'b0;
                aligned_sof_r <= req_sof_r;
                aligned_eof_r <= req_eof_r;
                aligned_sol_r <= req_sol_r;
                aligned_eol_r <= req_eol_r;
            end
        end
    end

    // Horizontal pair look-ahead and output register.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            hold_valid_r <= 1'b0;
            horizontal_flush_r <= 1'b0;
            hold_top_rgb_r <= 32'b0;
            hold_mid_rgb_r <= 32'b0;
            hold_bottom_rgb_r <= 32'b0;
            hold_sof_r <= 1'b0;
            hold_eof_r <= 1'b0;
            hold_sol_r <= 1'b0;
            hold_eol_r <= 1'b0;
            left_top_gray_r <= 8'b0;
            left_mid_gray_r <= 8'b0;
            left_bottom_gray_r <= 8'b0;
            filter_valid_r <= 1'b0;
            pixel0_r <= 16'b0;
            pixel1_r <= 16'b0;
            sof_r <= 1'b0;
            eof_r <= 1'b0;
            sol_r <= 1'b0;
            eol_r <= 1'b0;
            pair_valid_r <= 1'b0;
        end else begin
            if (output_fire_w)
                pair_valid_r <= 1'b0;

            if (filter_fire_w) begin
                pixel0_r <= filtered0_w;
                pixel1_r <= filtered1_w;
                sof_r <= filter_sof_r;
                eof_r <= filter_eof_r;
                sol_r <= filter_sol_r;
                eol_r <= filter_eol_r;
                pair_valid_r <= 1'b1;
                filter_valid_r <= 1'b0;
            end

            if (horizontal_flush_r && filter_ready_w) begin
                filter0_p00_r <= left_top_gray_r;
                filter0_p01_r <= hold_top0_gray_w;
                filter0_p02_r <= hold_top1_gray_w;
                filter0_p10_r <= left_mid_gray_r;
                filter0_p11_r <= hold_mid0_gray_w;
                filter0_p12_r <= hold_mid1_gray_w;
                filter0_p20_r <= left_bottom_gray_r;
                filter0_p21_r <= hold_bottom0_gray_w;
                filter0_p22_r <= hold_bottom1_gray_w;
                filter1_p00_r <= hold_top0_gray_w;
                filter1_p01_r <= hold_top1_gray_w;
                filter1_p02_r <= 8'b0;
                filter1_p10_r <= hold_mid0_gray_w;
                filter1_p11_r <= hold_mid1_gray_w;
                filter1_p12_r <= 8'b0;
                filter1_p20_r <= hold_bottom0_gray_w;
                filter1_p21_r <= hold_bottom1_gray_w;
                filter1_p22_r <= 8'b0;
                filter_center0_rgb_r <= hold_mid_rgb_r[15:0];
                filter_center1_rgb_r <= hold_mid_rgb_r[31:16];
                filter_enable_r <= active_enable_r;
                filter_mode_r <= active_mode_r;
                filter_threshold_r <= active_threshold_r;
                filter_sof_r <= hold_sof_r;
                filter_eof_r <= hold_eof_r;
                filter_sol_r <= hold_sol_r;
                filter_eol_r <= hold_eol_r;
                filter_valid_r <= 1'b1;
                hold_valid_r <= 1'b0;
                horizontal_flush_r <= 1'b0;
                left_top_gray_r <= 8'b0;
                left_mid_gray_r <= 8'b0;
                left_bottom_gray_r <= 8'b0;
            end else if (aligned_fire_w) begin
                if (!hold_valid_r || aligned_sol_r) begin
                    hold_valid_r <= 1'b1;
                    hold_top_rgb_r <= aligned_top_rgb_r;
                    hold_mid_rgb_r <= aligned_mid_rgb_r;
                    hold_bottom_rgb_r <= aligned_bottom_rgb_r;
                    hold_sof_r <= aligned_sof_r;
                    hold_eof_r <= aligned_eof_r;
                    hold_sol_r <= aligned_sol_r;
                    hold_eol_r <= aligned_eol_r;
                    left_top_gray_r <= 8'b0;
                    left_mid_gray_r <= 8'b0;
                    left_bottom_gray_r <= 8'b0;
                end else begin
                    filter0_p00_r <= left_top_gray_r;
                    filter0_p01_r <= hold_top0_gray_w;
                    filter0_p02_r <= hold_top1_gray_w;
                    filter0_p10_r <= left_mid_gray_r;
                    filter0_p11_r <= hold_mid0_gray_w;
                    filter0_p12_r <= hold_mid1_gray_w;
                    filter0_p20_r <= left_bottom_gray_r;
                    filter0_p21_r <= hold_bottom0_gray_w;
                    filter0_p22_r <= hold_bottom1_gray_w;
                    filter1_p00_r <= hold_top0_gray_w;
                    filter1_p01_r <= hold_top1_gray_w;
                    filter1_p02_r <= next_top0_gray_w;
                    filter1_p10_r <= hold_mid0_gray_w;
                    filter1_p11_r <= hold_mid1_gray_w;
                    filter1_p12_r <= next_mid0_gray_w;
                    filter1_p20_r <= hold_bottom0_gray_w;
                    filter1_p21_r <= hold_bottom1_gray_w;
                    filter1_p22_r <= next_bottom0_gray_w;
                    filter_center0_rgb_r <= hold_mid_rgb_r[15:0];
                    filter_center1_rgb_r <= hold_mid_rgb_r[31:16];
                    filter_enable_r <= active_enable_r;
                    filter_mode_r <= active_mode_r;
                    filter_threshold_r <= active_threshold_r;
                    filter_sof_r <= hold_sof_r;
                    filter_eof_r <= hold_eof_r;
                    filter_sol_r <= hold_sol_r;
                    filter_eol_r <= hold_eol_r;
                    filter_valid_r <= 1'b1;
                    left_top_gray_r <= hold_top1_gray_w;
                    left_mid_gray_r <= hold_mid1_gray_w;
                    left_bottom_gray_r <= hold_bottom1_gray_w;
                    hold_top_rgb_r <= aligned_top_rgb_r;
                    hold_mid_rgb_r <= aligned_mid_rgb_r;
                    hold_bottom_rgb_r <= aligned_bottom_rgb_r;
                    hold_sof_r <= aligned_sof_r;
                    hold_eof_r <= aligned_eof_r;
                    hold_sol_r <= aligned_sol_r;
                    hold_eol_r <= aligned_eol_r;
                    if (aligned_eol_r)
                        horizontal_flush_r <= 1'b1;
                end
            end
        end
    end

    generate
        if ((H_ACTIVE < 16) || ((H_ACTIVE % 16) != 0) ||
            (PAIRS_PER_LINE > (1 << LINE_ADDR_W))) begin : gen_bad_geometry
            edrv32_pixel_window_geometry_is_invalid
                u_static_assert ();
        end
    endgenerate

endmodule
