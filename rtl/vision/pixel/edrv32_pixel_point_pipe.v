// ============================================================================
// File        : edrv32_pixel_point_pipe.v
// Description : Two-pixel RGB565 point-operation elastic pipeline.
// Notes       : A small registered input queue breaks the unpack lane-select
//               path. Contrast, brightness, grayscale and final selection are
//               separate stages, preserving one accepted pair per clock.
// ============================================================================

module edrv32_pixel_point_pipe (
    input  wire                clk_i,
    input  wire                rst_n_i,

    input  wire [15:0]         pixel0_i,
    input  wire [15:0]         pixel1_i,
    input  wire                sof_i,
    input  wire                eof_i,
    input  wire                sol_i,
    input  wire                eol_i,
    input  wire                pair_valid_i,
    output wire                pair_ready_o,

    output wire [15:0]         pixel0_o,
    output wire [15:0]         pixel1_o,
    output wire                sof_o,
    output wire                eof_o,
    output wire                sol_o,
    output wire                eol_o,
    output wire                pair_valid_o,
    input  wire                pair_ready_i,

    input  wire                cfg_commit_i,
    input  wire                cfg_enable_i,
    input  wire                cfg_grayscale_i,
    input  wire                cfg_threshold_enable_i,
    input  wire                cfg_invert_i,
    input  wire signed [8:0]   cfg_brightness_i,
    input  wire [8:0]          cfg_contrast_i,
    input  wire [7:0]          cfg_threshold_i,
    output wire                cfg_pending_o
);

    localparam integer INPUT_DEPTH = 8;
    localparam integer INPUT_ADDR_W = 3;

    localparam integer CTRL_ENABLE    = 3;
    localparam integer CTRL_GRAYSCALE = 2;
    localparam integer CTRL_THRESHOLD = 1;
    localparam integer CTRL_INVERT    = 0;

    function [7:0] expand_r5;
        input [4:0] value;
        begin
            expand_r5 = {value, value[4:2]};
        end
    endfunction

    function [7:0] expand_g6;
        input [5:0] value;
        begin
            expand_g6 = {value, value[5:4]};
        end
    endfunction

    function [7:0] finish_channel;
        input signed [19:0] product;
        input signed [8:0] brightness;
        reg signed [20:0] adjusted;
        begin
            adjusted = (product >>> 8) + 21'sd128 + brightness;
            if (adjusted < 0)
                finish_channel = 8'b0;
            else if (adjusted > 21'sd255)
                finish_channel = 8'hff;
            else
                finish_channel = adjusted[7:0];
        end
    endfunction

    function [7:0] rgb_to_gray;
        input [7:0] red;
        input [7:0] green;
        input [7:0] blue;
        reg [16:0] weighted;
        begin
            weighted = red * 8'd77 + green * 8'd150 +
                blue * 8'd29 + 17'd128;
            rgb_to_gray = weighted[15:8];
        end
    endfunction

    function [15:0] select_result;
        input [15:0] raw_pixel;
        input [7:0] red;
        input [7:0] green;
        input [7:0] blue;
        input [7:0] gray;
        input [3:0] control;
        input [7:0] threshold;
        reg binary_white;
        begin
            if (!control[CTRL_ENABLE]) begin
                select_result = raw_pixel;
            end else if (control[CTRL_THRESHOLD]) begin
                binary_white = (gray >= threshold) ^
                    control[CTRL_INVERT];
                select_result = binary_white ? 16'hffff : 16'h0000;
            end else if (control[CTRL_GRAYSCALE]) begin
                select_result = {gray[7:3], gray[7:2], gray[7:3]};
            end else begin
                select_result = {red[7:3], green[7:2], blue[7:3]};
            end
        end
    endfunction

    // Frame-atomic configuration. Attach the active configuration to every
    // queued pair so older data cannot see a following frame's configuration.
    reg shadow_enable_r;
    reg shadow_grayscale_r;
    reg shadow_threshold_enable_r;
    reg shadow_invert_r;
    reg signed [8:0] shadow_brightness_r;
    reg [8:0] shadow_contrast_r;
    reg [7:0] shadow_threshold_r;
    reg commit_pending_r;

    reg active_enable_r;
    reg active_grayscale_r;
    reg active_threshold_enable_r;
    reg active_invert_r;
    reg signed [8:0] active_brightness_r;
    reg [8:0] active_contrast_r;
    reg [7:0] active_threshold_r;

    wire apply_config_w = sof_i && (commit_pending_r || cfg_commit_i);
    wire input_enable_w = apply_config_w ?
        (cfg_commit_i ? cfg_enable_i : shadow_enable_r) : active_enable_r;
    wire input_grayscale_w = apply_config_w ?
        (cfg_commit_i ? cfg_grayscale_i : shadow_grayscale_r) :
        active_grayscale_r;
    wire input_threshold_enable_w = apply_config_w ?
        (cfg_commit_i ? cfg_threshold_enable_i :
         shadow_threshold_enable_r) : active_threshold_enable_r;
    wire input_invert_w = apply_config_w ?
        (cfg_commit_i ? cfg_invert_i : shadow_invert_r) : active_invert_r;
    wire signed [8:0] input_brightness_w = apply_config_w ?
        (cfg_commit_i ? cfg_brightness_i : shadow_brightness_r) :
        active_brightness_r;
    wire [8:0] input_contrast_w = apply_config_w ?
        (cfg_commit_i ? cfg_contrast_i : shadow_contrast_r) :
        active_contrast_r;
    wire [7:0] input_threshold_w = apply_config_w ?
        (cfg_commit_i ? cfg_threshold_i : shadow_threshold_r) :
        active_threshold_r;

    assign cfg_pending_o = commit_pending_r;

    // Registered input queue. pair_ready_o depends only on local capacity,
    // cutting the ready path between the spatial stage and pixel unpacker.
    reg [15:0] input_pixel0_r [0:INPUT_DEPTH-1];
    reg [15:0] input_pixel1_r [0:INPUT_DEPTH-1];
    reg [3:0] input_sideband_r [0:INPUT_DEPTH-1];
    reg [3:0] input_control_r [0:INPUT_DEPTH-1];
    reg signed [8:0] input_brightness_r [0:INPUT_DEPTH-1];
    reg [8:0] input_contrast_r [0:INPUT_DEPTH-1];
    reg [7:0] input_threshold_r [0:INPUT_DEPTH-1];
    reg [INPUT_ADDR_W-1:0] input_write_ptr_r;
    reg [INPUT_ADDR_W-1:0] input_read_ptr_r;
    reg [INPUT_ADDR_W:0] input_count_r;

    wire input_push_w = pair_valid_i && pair_ready_o;

    // Fixed-latency arithmetic pipeline. It advances as a unit while its
    // output slot is available. The queue absorbs ordinary downstream stalls.
    reg s0_valid_r;
    reg [15:0] s0_pixel0_r;
    reg [15:0] s0_pixel1_r;
    reg [3:0] s0_sideband_r;
    reg [3:0] s0_control_r;
    reg signed [8:0] s0_brightness_r;
    reg [8:0] s0_contrast_r;
    reg [7:0] s0_threshold_r;

    reg s1_valid_r;
    reg [15:0] s1_pixel0_r;
    reg [15:0] s1_pixel1_r;
    reg [3:0] s1_sideband_r;
    reg [3:0] s1_control_r;
    reg signed [8:0] s1_brightness_r;
    reg [7:0] s1_threshold_r;
    reg signed [19:0] s1_p0_red_product_r;
    reg signed [19:0] s1_p0_green_product_r;
    reg signed [19:0] s1_p0_blue_product_r;
    reg signed [19:0] s1_p1_red_product_r;
    reg signed [19:0] s1_p1_green_product_r;
    reg signed [19:0] s1_p1_blue_product_r;

    reg s2_valid_r;
    reg [15:0] s2_pixel0_r;
    reg [15:0] s2_pixel1_r;
    reg [3:0] s2_sideband_r;
    reg [3:0] s2_control_r;
    reg [7:0] s2_threshold_r;
    reg [7:0] s2_p0_red_r;
    reg [7:0] s2_p0_green_r;
    reg [7:0] s2_p0_blue_r;
    reg [7:0] s2_p1_red_r;
    reg [7:0] s2_p1_green_r;
    reg [7:0] s2_p1_blue_r;

    reg s3_valid_r;
    reg [15:0] s3_pixel0_r;
    reg [15:0] s3_pixel1_r;
    reg [3:0] s3_sideband_r;
    reg [3:0] s3_control_r;
    reg [7:0] s3_threshold_r;
    reg [7:0] s3_p0_red_r;
    reg [7:0] s3_p0_green_r;
    reg [7:0] s3_p0_blue_r;
    reg [7:0] s3_p1_red_r;
    reg [7:0] s3_p1_green_r;
    reg [7:0] s3_p1_blue_r;
    reg [7:0] s3_p0_gray_r;
    reg [7:0] s3_p1_gray_r;

    reg s4_valid_r;
    reg [15:0] s4_pixel0_r;
    reg [15:0] s4_pixel1_r;
    reg [3:0] s4_sideband_r;

    wire pipeline_advance_w = !s4_valid_r || pair_ready_i;
    wire input_pop_w = pipeline_advance_w && (input_count_r != 0);

    assign pair_ready_o = input_count_r < INPUT_DEPTH;
    assign pixel0_o = s4_pixel0_r;
    assign pixel1_o = s4_pixel1_r;
    assign sof_o = s4_sideband_r[3];
    assign eof_o = s4_sideband_r[2];
    assign sol_o = s4_sideband_r[1];
    assign eol_o = s4_sideband_r[0];
    assign pair_valid_o = s4_valid_r;

    wire signed [9:0] s0_p0_red_center_w =
        $signed({1'b0, expand_r5(s0_pixel0_r[15:11])}) - 10'sd128;
    wire signed [9:0] s0_p0_green_center_w =
        $signed({1'b0, expand_g6(s0_pixel0_r[10:5])}) - 10'sd128;
    wire signed [9:0] s0_p0_blue_center_w =
        $signed({1'b0, expand_r5(s0_pixel0_r[4:0])}) - 10'sd128;
    wire signed [9:0] s0_p1_red_center_w =
        $signed({1'b0, expand_r5(s0_pixel1_r[15:11])}) - 10'sd128;
    wire signed [9:0] s0_p1_green_center_w =
        $signed({1'b0, expand_g6(s0_pixel1_r[10:5])}) - 10'sd128;
    wire signed [9:0] s0_p1_blue_center_w =
        $signed({1'b0, expand_r5(s0_pixel1_r[4:0])}) - 10'sd128;
    wire signed [9:0] s0_contrast_w = $signed({1'b0, s0_contrast_r});

    wire [7:0] s1_p0_red_w = finish_channel(
        s1_p0_red_product_r, s1_brightness_r);
    wire [7:0] s1_p0_green_w = finish_channel(
        s1_p0_green_product_r, s1_brightness_r);
    wire [7:0] s1_p0_blue_w = finish_channel(
        s1_p0_blue_product_r, s1_brightness_r);
    wire [7:0] s1_p1_red_w = finish_channel(
        s1_p1_red_product_r, s1_brightness_r);
    wire [7:0] s1_p1_green_w = finish_channel(
        s1_p1_green_product_r, s1_brightness_r);
    wire [7:0] s1_p1_blue_w = finish_channel(
        s1_p1_blue_product_r, s1_brightness_r);

    wire [7:0] s2_p0_gray_w = rgb_to_gray(
        s2_p0_red_r, s2_p0_green_r, s2_p0_blue_r);
    wire [7:0] s2_p1_gray_w = rgb_to_gray(
        s2_p1_red_r, s2_p1_green_r, s2_p1_blue_r);

    wire [15:0] s3_pixel0_result_w = select_result(
        s3_pixel0_r, s3_p0_red_r, s3_p0_green_r, s3_p0_blue_r,
        s3_p0_gray_r, s3_control_r, s3_threshold_r);
    wire [15:0] s3_pixel1_result_w = select_result(
        s3_pixel1_r, s3_p1_red_r, s3_p1_green_r, s3_p1_blue_r,
        s3_p1_gray_r, s3_control_r, s3_threshold_r);

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            shadow_enable_r <= 1'b0;
            shadow_grayscale_r <= 1'b0;
            shadow_threshold_enable_r <= 1'b0;
            shadow_invert_r <= 1'b0;
            shadow_brightness_r <= 9'sd0;
            shadow_contrast_r <= 9'd256;
            shadow_threshold_r <= 8'd128;
            commit_pending_r <= 1'b0;
            active_enable_r <= 1'b0;
            active_grayscale_r <= 1'b0;
            active_threshold_enable_r <= 1'b0;
            active_invert_r <= 1'b0;
            active_brightness_r <= 9'sd0;
            active_contrast_r <= 9'd256;
            active_threshold_r <= 8'd128;
        end else begin
            if (cfg_commit_i) begin
                shadow_enable_r <= cfg_enable_i;
                shadow_grayscale_r <= cfg_grayscale_i;
                shadow_threshold_enable_r <= cfg_threshold_enable_i;
                shadow_invert_r <= cfg_invert_i;
                shadow_brightness_r <= cfg_brightness_i;
                shadow_contrast_r <= cfg_contrast_i;
                shadow_threshold_r <= cfg_threshold_i;
                commit_pending_r <= 1'b1;
            end

            if (input_push_w && apply_config_w) begin
                active_enable_r <= cfg_commit_i ?
                    cfg_enable_i : shadow_enable_r;
                active_grayscale_r <= cfg_commit_i ?
                    cfg_grayscale_i : shadow_grayscale_r;
                active_threshold_enable_r <= cfg_commit_i ?
                    cfg_threshold_enable_i : shadow_threshold_enable_r;
                active_invert_r <= cfg_commit_i ?
                    cfg_invert_i : shadow_invert_r;
                active_brightness_r <= cfg_commit_i ?
                    cfg_brightness_i : shadow_brightness_r;
                active_contrast_r <= cfg_commit_i ?
                    cfg_contrast_i : shadow_contrast_r;
                active_threshold_r <= cfg_commit_i ?
                    cfg_threshold_i : shadow_threshold_r;
                commit_pending_r <= 1'b0;
            end
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            input_write_ptr_r <= {INPUT_ADDR_W{1'b0}};
            input_read_ptr_r <= {INPUT_ADDR_W{1'b0}};
            input_count_r <= {(INPUT_ADDR_W+1){1'b0}};
        end else begin
            if (input_push_w) begin
                input_pixel0_r[input_write_ptr_r] <= pixel0_i;
                input_pixel1_r[input_write_ptr_r] <= pixel1_i;
                input_sideband_r[input_write_ptr_r] <= {
                    sof_i, eof_i, sol_i, eol_i
                };
                input_control_r[input_write_ptr_r] <= {
                    input_enable_w, input_grayscale_w,
                    input_threshold_enable_w, input_invert_w
                };
                input_brightness_r[input_write_ptr_r] <= input_brightness_w;
                input_contrast_r[input_write_ptr_r] <= input_contrast_w;
                input_threshold_r[input_write_ptr_r] <= input_threshold_w;
                input_write_ptr_r <= input_write_ptr_r + 1'b1;
            end

            if (input_pop_w)
                input_read_ptr_r <= input_read_ptr_r + 1'b1;

            case ({input_push_w, input_pop_w})
                2'b10: input_count_r <= input_count_r + 1'b1;
                2'b01: input_count_r <= input_count_r - 1'b1;
                default: input_count_r <= input_count_r;
            endcase
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            s0_valid_r <= 1'b0;
            s1_valid_r <= 1'b0;
            s2_valid_r <= 1'b0;
            s3_valid_r <= 1'b0;
            s4_valid_r <= 1'b0;
        end else if (pipeline_advance_w) begin
            s4_valid_r <= s3_valid_r;
            if (s3_valid_r) begin
                s4_pixel0_r <= s3_pixel0_result_w;
                s4_pixel1_r <= s3_pixel1_result_w;
                s4_sideband_r <= s3_sideband_r;
            end

            s3_valid_r <= s2_valid_r;
            if (s2_valid_r) begin
                s3_pixel0_r <= s2_pixel0_r;
                s3_pixel1_r <= s2_pixel1_r;
                s3_sideband_r <= s2_sideband_r;
                s3_control_r <= s2_control_r;
                s3_threshold_r <= s2_threshold_r;
                s3_p0_red_r <= s2_p0_red_r;
                s3_p0_green_r <= s2_p0_green_r;
                s3_p0_blue_r <= s2_p0_blue_r;
                s3_p1_red_r <= s2_p1_red_r;
                s3_p1_green_r <= s2_p1_green_r;
                s3_p1_blue_r <= s2_p1_blue_r;
                s3_p0_gray_r <= s2_p0_gray_w;
                s3_p1_gray_r <= s2_p1_gray_w;
            end

            s2_valid_r <= s1_valid_r;
            if (s1_valid_r) begin
                s2_pixel0_r <= s1_pixel0_r;
                s2_pixel1_r <= s1_pixel1_r;
                s2_sideband_r <= s1_sideband_r;
                s2_control_r <= s1_control_r;
                s2_threshold_r <= s1_threshold_r;
                s2_p0_red_r <= s1_p0_red_w;
                s2_p0_green_r <= s1_p0_green_w;
                s2_p0_blue_r <= s1_p0_blue_w;
                s2_p1_red_r <= s1_p1_red_w;
                s2_p1_green_r <= s1_p1_green_w;
                s2_p1_blue_r <= s1_p1_blue_w;
            end

            s1_valid_r <= s0_valid_r;
            if (s0_valid_r) begin
                s1_pixel0_r <= s0_pixel0_r;
                s1_pixel1_r <= s0_pixel1_r;
                s1_sideband_r <= s0_sideband_r;
                s1_control_r <= s0_control_r;
                s1_brightness_r <= s0_brightness_r;
                s1_threshold_r <= s0_threshold_r;
                s1_p0_red_product_r <=
                    s0_p0_red_center_w * s0_contrast_w;
                s1_p0_green_product_r <=
                    s0_p0_green_center_w * s0_contrast_w;
                s1_p0_blue_product_r <=
                    s0_p0_blue_center_w * s0_contrast_w;
                s1_p1_red_product_r <=
                    s0_p1_red_center_w * s0_contrast_w;
                s1_p1_green_product_r <=
                    s0_p1_green_center_w * s0_contrast_w;
                s1_p1_blue_product_r <=
                    s0_p1_blue_center_w * s0_contrast_w;
            end

            s0_valid_r <= input_pop_w;
            if (input_pop_w) begin
                s0_pixel0_r <= input_pixel0_r[input_read_ptr_r];
                s0_pixel1_r <= input_pixel1_r[input_read_ptr_r];
                s0_sideband_r <= input_sideband_r[input_read_ptr_r];
                s0_control_r <= input_control_r[input_read_ptr_r];
                s0_brightness_r <= input_brightness_r[input_read_ptr_r];
                s0_contrast_r <= input_contrast_r[input_read_ptr_r];
                s0_threshold_r <= input_threshold_r[input_read_ptr_r];
            end
        end
    end

endmodule
