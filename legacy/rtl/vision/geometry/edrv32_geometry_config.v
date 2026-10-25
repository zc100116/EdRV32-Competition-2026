// ============================================================================
// File        : edrv32_geometry_config.v
// Description : Autonomous inverse-affine setup engine for Geometry.
// Notes       : Coefficients are retained across frames with identical
//               geometry.  A frame launch still occurs for every cfg_start_i;
//               only a changed configuration re-reads the trig ROM and runs
//               the divider. Outputs use signed Q16.16.
// ============================================================================

module edrv32_geometry_config (
    input  wire                     clk_i,
    input  wire                     rst_n_i,

    input  wire                     cfg_start_i,
    input  wire [15:0]              cfg_src_width_i,
    input  wire [15:0]              cfg_src_height_i,
    input  wire [15:0]              cfg_crop_x_i,
    input  wire [15:0]              cfg_crop_y_i,
    input  wire [15:0]              cfg_crop_width_i,
    input  wire [15:0]              cfg_crop_height_i,
    input  wire [15:0]              cfg_dst_width_i,
    input  wire [15:0]              cfg_dst_height_i,
    input  wire [15:0]              cfg_image_width_i,
    input  wire [15:0]              cfg_image_height_i,
    input  wire [8:0]               cfg_angle_i,
    input  wire                     cfg_flip_x_i,
    input  wire                     cfg_flip_y_i,

    output wire                     walker_start_o,
    output wire [15:0]              walker_dst_width_o,
    output wire [15:0]              walker_dst_height_o,
    output wire [15:0]              walker_src_width_o,
    output wire [15:0]              walker_src_height_o,
    output wire signed [31:0]       walker_origin_x_o,
    output wire signed [31:0]       walker_origin_y_o,
    output wire signed [31:0]       walker_pixel_step_x_o,
    output wire signed [31:0]       walker_pixel_step_y_o,
    output wire signed [31:0]       walker_row_step_x_o,
    output wire signed [31:0]       walker_row_step_y_o,

    output wire                     busy_o,
    output wire                     done_o,
    output wire                     error_o
);

    localparam [3:0] STATE_IDLE        = 4'd0;
    localparam [3:0] STATE_ROM_REQUEST = 4'd1;
    localparam [3:0] STATE_ROM_CAPTURE = 4'd2;
    localparam [3:0] STATE_BBOX        = 4'd3;
    localparam [3:0] STATE_DIV_X_START = 4'd4;
    localparam [3:0] STATE_DIV_X_WAIT  = 4'd5;
    localparam [3:0] STATE_DIV_Y_START = 4'd6;
    localparam [3:0] STATE_DIV_Y_WAIT  = 4'd7;
    localparam [3:0] STATE_STEPS       = 4'd8;
    localparam [3:0] STATE_ORIGIN      = 4'd9;
    localparam [3:0] STATE_LAUNCH      = 4'd10;
    localparam [3:0] STATE_SCALE_SELECT = 4'd11;
    localparam [3:0] STATE_TRIG_MUL     = 4'd12;
    localparam [3:0] STATE_ORIGIN_PARTIAL = 4'd13;
    localparam [3:0] STATE_ORIGIN_SUM = 4'd14;
    localparam [3:0] STATE_ORIGIN_CHECK = 4'd15;

    reg [3:0] state_r;
    reg done_r;
    reg error_r;
    reg walker_start_r;
    reg cache_valid_r;

    reg [15:0] src_width_r;
    reg [15:0] src_height_r;
    reg [15:0] crop_x_r;
    reg [15:0] crop_y_r;
    reg [15:0] crop_width_r;
    reg [15:0] crop_height_r;
    reg [15:0] dst_width_r;
    reg [15:0] dst_height_r;
    reg [15:0] image_width_r;
    reg [15:0] image_height_r;
    reg [8:0] angle_r;
    reg flip_x_r;
    reg flip_y_r;

    reg signed [17:0] cos_r;
    reg signed [17:0] sin_r;
    reg [47:0] bbox_x_r;
    reg [47:0] bbox_y_r;
    reg [31:0] scale_x_r;
    reg [31:0] scale_y_r;
    reg signed [63:0] cos_scale_x_r;
    reg signed [63:0] sin_scale_x_r;
    reg signed [63:0] cos_scale_y_r;
    reg signed [63:0] sin_scale_y_r;
    reg signed [47:0] dst_x_offset_r;
    reg signed [47:0] dst_y_to_x_offset_r;
    reg signed [47:0] dst_x_to_y_offset_r;
    reg signed [47:0] dst_y_offset_r;
    reg signed [47:0] origin_x_partial_r;
    reg signed [47:0] origin_y_partial_r;
    reg signed [47:0] origin_x_full_r;
    reg signed [47:0] origin_y_full_r;
    reg signed [18:0] image_center_x_q1_r;
    reg signed [18:0] image_center_y_q1_r;

    reg signed [31:0] origin_x_r;
    reg signed [31:0] origin_y_r;
    reg signed [31:0] pixel_step_x_r;
    reg signed [31:0] pixel_step_y_r;
    reg signed [31:0] row_step_x_r;
    reg signed [31:0] row_step_y_r;

    wire [35:0] trig_data_w;
    wire signed [17:0] trig_cos_w = trig_data_w[35:18];
    wire signed [17:0] trig_sin_w = trig_data_w[17:0];

    edrv32_geometry_trig_rom u_trig_rom (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .addr_i (angle_r),
        .data_o (trig_data_w)
    );

    wire [15:0] crop_x_span_w = crop_width_r - 1'b1;
    wire [15:0] crop_y_span_w = crop_height_r - 1'b1;

    reg div_start_r;
    reg [47:0] div_dividend_r;
    reg [15:0] div_divisor_r;
    wire div_busy_w;
    wire div_done_w;
    wire div_zero_w;
    wire [47:0] div_quotient_w;

    edrv32_geometry_udiv48_16 u_divider (
        .clk_i      (clk_i),
        .rst_n_i    (rst_n_i),
        .start_i    (div_start_r),
        .dividend_i (div_dividend_r),
        .divisor_i  (div_divisor_r),
        .busy_o     (div_busy_w),
        .done_o     (div_done_w),
        .div_zero_o (div_zero_w),
        .quotient_o (div_quotient_w)
    );

    // Forward geometry scales the cropped image on its own X/Y axes, then
    // rotates that rectangle.  The inverse map is S^-1 * R^-1, keeping a
    // square square even when the source crop has a different aspect ratio.
    wire signed [47:0] base_pixel_x_w = cos_scale_x_r >>> 16;
    wire signed [47:0] base_pixel_y_w = -(sin_scale_y_r >>> 16);
    wire signed [47:0] base_row_x_w = sin_scale_x_r >>> 16;
    wire signed [47:0] base_row_y_w = cos_scale_y_r >>> 16;

    wire signed [47:0] selected_pixel_x_w = flip_x_r ?
        -base_pixel_x_w : base_pixel_x_w;
    wire signed [47:0] selected_pixel_y_w = flip_y_r ?
        -base_pixel_y_w : base_pixel_y_w;
    wire signed [47:0] selected_row_x_w = flip_x_r ?
        -base_row_x_w : base_row_x_w;
    wire signed [47:0] selected_row_y_w = flip_y_r ?
        -base_row_y_w : base_row_y_w;

    wire steps_fit_w =
        (selected_pixel_x_w[47:31] == {17{selected_pixel_x_w[31]}}) &&
        (selected_pixel_y_w[47:31] == {17{selected_pixel_y_w[31]}}) &&
        (selected_row_x_w[47:31] == {17{selected_row_x_w[31]}}) &&
        (selected_row_y_w[47:31] == {17{selected_row_y_w[31]}});

    wire signed [47:0] crop_center_x_w =
        $signed({16'b0, crop_x_r, 16'b0}) +
        $signed({17'b0, crop_x_span_w, 15'b0});
    wire signed [47:0] crop_center_y_w =
        $signed({16'b0, crop_y_r, 16'b0}) +
        $signed({17'b0, crop_y_span_w, 15'b0});
    wire signed [17:0] image_left_w =
        ($signed({2'b0, dst_width_r}) -
         $signed({2'b0, image_width_r})) >>> 1;
    wire signed [17:0] image_top_w =
        ($signed({2'b0, dst_height_r}) -
         $signed({2'b0, image_height_r})) >>> 1;
    wire signed [18:0] image_center_x_q1_w =
        ($signed({image_left_w[17], image_left_w}) <<< 1) +
        $signed({3'b0, image_width_r}) - 19'sd1;
    wire signed [18:0] image_center_y_q1_w =
        ($signed({image_top_w[17], image_top_w}) <<< 1) +
        $signed({3'b0, image_height_r}) - 19'sd1;
    wire signed [47:0] dst_x_offset_w =
        ($signed(pixel_step_x_r) * image_center_x_q1_r) >>> 1;
    wire signed [47:0] dst_y_to_x_offset_w =
        ($signed(row_step_x_r) * image_center_y_q1_r) >>> 1;
    wire signed [47:0] dst_x_to_y_offset_w =
        ($signed(pixel_step_y_r) * image_center_x_q1_r) >>> 1;
    wire signed [47:0] dst_y_offset_w =
        ($signed(row_step_y_r) * image_center_y_q1_r) >>> 1;
    wire origins_fit_w =
        (origin_x_full_r[47:31] == {17{origin_x_full_r[31]}}) &&
        (origin_y_full_r[47:31] == {17{origin_y_full_r[31]}});

    wire [16:0] crop_x_end_w = {1'b0, cfg_crop_x_i} +
        {1'b0, cfg_crop_width_i};
    wire [16:0] crop_y_end_w = {1'b0, cfg_crop_y_i} +
        {1'b0, cfg_crop_height_i};
    wire [16:0] min_image_width_w =
        ({1'b0, cfg_crop_width_i} + 17'd1) >> 1;
    wire [16:0] min_image_height_w =
        ({1'b0, cfg_crop_height_i} + 17'd1) >> 1;
    wire cfg_legal_w =
        (cfg_src_width_i != 0) && (cfg_src_height_i != 0) &&
        (cfg_src_width_i <= 16'd32768) &&
        (cfg_src_height_i <= 16'd32768) &&
        (cfg_crop_width_i != 0) && (cfg_crop_height_i != 0) &&
        (cfg_dst_width_i != 0) && (cfg_dst_height_i != 0) &&
        (cfg_image_width_i != 0) && (cfg_image_height_i != 0) &&
        ({1'b0, cfg_image_width_i} >= min_image_width_w) &&
        ({1'b0, cfg_image_height_i} >= min_image_height_w) &&
        (cfg_angle_i <= 9'd359) &&
        (crop_x_end_w <= {1'b0, cfg_src_width_i}) &&
        (crop_y_end_w <= {1'b0, cfg_src_height_i});
    wire cfg_cache_hit_w = cache_valid_r &&
        (cfg_src_width_i == src_width_r) &&
        (cfg_src_height_i == src_height_r) &&
        (cfg_crop_x_i == crop_x_r) &&
        (cfg_crop_y_i == crop_y_r) &&
        (cfg_crop_width_i == crop_width_r) &&
        (cfg_crop_height_i == crop_height_r) &&
        (cfg_dst_width_i == dst_width_r) &&
        (cfg_dst_height_i == dst_height_r) &&
        (cfg_image_width_i == image_width_r) &&
        (cfg_image_height_i == image_height_r) &&
        (cfg_angle_i == angle_r) &&
        (cfg_flip_x_i == flip_x_r) &&
        (cfg_flip_y_i == flip_y_r);

    assign walker_start_o = walker_start_r;
    assign walker_dst_width_o = dst_width_r;
    assign walker_dst_height_o = dst_height_r;
    assign walker_src_width_o = src_width_r;
    assign walker_src_height_o = src_height_r;
    assign walker_origin_x_o = origin_x_r;
    assign walker_origin_y_o = origin_y_r;
    assign walker_pixel_step_x_o = pixel_step_x_r;
    assign walker_pixel_step_y_o = pixel_step_y_r;
    assign walker_row_step_x_o = row_step_x_r;
    assign walker_row_step_y_o = row_step_y_r;
    assign busy_o = state_r != STATE_IDLE;
    assign done_o = done_r;
    assign error_o = error_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= STATE_IDLE;
            done_r <= 1'b0;
            error_r <= 1'b0;
            walker_start_r <= 1'b0;
            cache_valid_r <= 1'b0;
            src_width_r <= 16'b0;
            src_height_r <= 16'b0;
            crop_x_r <= 16'b0;
            crop_y_r <= 16'b0;
            crop_width_r <= 16'b0;
            crop_height_r <= 16'b0;
            dst_width_r <= 16'b0;
            dst_height_r <= 16'b0;
            image_width_r <= 16'b0;
            image_height_r <= 16'b0;
            angle_r <= 9'b0;
            flip_x_r <= 1'b0;
            flip_y_r <= 1'b0;
            cos_r <= 18'sb0;
            sin_r <= 18'sb0;
            bbox_x_r <= 48'b0;
            bbox_y_r <= 48'b0;
            scale_x_r <= 32'b0;
            scale_y_r <= 32'b0;
            cos_scale_x_r <= 64'sb0;
            sin_scale_x_r <= 64'sb0;
            cos_scale_y_r <= 64'sb0;
            sin_scale_y_r <= 64'sb0;
            image_center_x_q1_r <= 19'sb0;
            image_center_y_q1_r <= 19'sb0;
            origin_x_r <= 32'sb0;
            origin_y_r <= 32'sb0;
            pixel_step_x_r <= 32'sb0;
            pixel_step_y_r <= 32'sb0;
            row_step_x_r <= 32'sb0;
            row_step_y_r <= 32'sb0;
            div_start_r <= 1'b0;
            div_dividend_r <= 48'b0;
            div_divisor_r <= 16'b0;
        end else begin
            done_r <= 1'b0;
            walker_start_r <= 1'b0;
            div_start_r <= 1'b0;

            case (state_r)
                STATE_IDLE: begin
                    if (cfg_start_i) begin
                        if (!cfg_legal_w) begin
                            error_r <= 1'b1;
                            done_r <= 1'b1;
                        end else if (cfg_cache_hit_w) begin
                            // The source/target Surface base is frame-local
                            // and owned by the caller, not by this matrix.
                            error_r <= 1'b0;
                            walker_start_r <= 1'b1;
                            done_r <= 1'b1;
                        end else begin
                            error_r <= 1'b0;
                            cache_valid_r <= 1'b0;
                            src_width_r <= cfg_src_width_i;
                            src_height_r <= cfg_src_height_i;
                            crop_x_r <= cfg_crop_x_i;
                            crop_y_r <= cfg_crop_y_i;
                            crop_width_r <= cfg_crop_width_i;
                            crop_height_r <= cfg_crop_height_i;
                            dst_width_r <= cfg_dst_width_i;
                            dst_height_r <= cfg_dst_height_i;
                            image_width_r <= cfg_image_width_i;
                            image_height_r <= cfg_image_height_i;
                            angle_r <= cfg_angle_i;
                            flip_x_r <= cfg_flip_x_i;
                            flip_y_r <= cfg_flip_y_i;
                            state_r <= STATE_ROM_REQUEST;
                        end
                    end
                end

                STATE_ROM_REQUEST: state_r <= STATE_ROM_CAPTURE;

                STATE_ROM_CAPTURE: begin
                    cos_r <= trig_cos_w;
                    sin_r <= trig_sin_w;
                    state_r <= STATE_BBOX;
                end

                STATE_BBOX: begin
                    // Scale from the unrotated crop.  Using the rotated bbox
                    // here would zoom every angled image down to fit.
                    bbox_x_r <= {16'b0, crop_x_span_w, 16'b0};
                    bbox_y_r <= {16'b0, crop_y_span_w, 16'b0};
                    image_center_x_q1_r <= image_center_x_q1_w;
                    image_center_y_q1_r <= image_center_y_q1_w;
                    state_r <= STATE_DIV_X_START;
                end

                STATE_DIV_X_START: begin
                    if (image_width_r == 16'd1) begin
                        scale_x_r <= 32'b0;
                        state_r <= STATE_DIV_Y_START;
                    end else begin
                        div_dividend_r <= bbox_x_r;
                        div_divisor_r <= image_width_r - 1'b1;
                        div_start_r <= 1'b1;
                        state_r <= STATE_DIV_X_WAIT;
                    end
                end

                STATE_DIV_X_WAIT: begin
                    if (div_done_w) begin
                        if (div_zero_w || (|div_quotient_w[47:31])) begin
                            error_r <= 1'b1;
                            done_r <= 1'b1;
                            state_r <= STATE_IDLE;
                        end else begin
                            scale_x_r <= div_quotient_w[31:0];
                            state_r <= STATE_DIV_Y_START;
                        end
                    end
                end

                STATE_DIV_Y_START: begin
                    if (image_height_r == 16'd1) begin
                        scale_y_r <= 32'b0;
                        state_r <= STATE_SCALE_SELECT;
                    end else begin
                        div_dividend_r <= bbox_y_r;
                        div_divisor_r <= image_height_r - 1'b1;
                        div_start_r <= 1'b1;
                        state_r <= STATE_DIV_Y_WAIT;
                    end
                end

                STATE_DIV_Y_WAIT: begin
                    if (div_done_w) begin
                        if (div_zero_w || (|div_quotient_w[47:31])) begin
                            error_r <= 1'b1;
                            done_r <= 1'b1;
                            state_r <= STATE_IDLE;
                        end else begin
                            scale_y_r <= div_quotient_w[31:0];
                            state_r <= STATE_SCALE_SELECT;
                        end
                    end
                end

                STATE_SCALE_SELECT: begin
                    // Two DSP products per cycle preserve the previous
                    // configuration timing while allowing distinct axes.
                    cos_scale_x_r <= $signed(cos_r) *
                        $signed({1'b0, scale_x_r});
                    sin_scale_x_r <= $signed(sin_r) *
                        $signed({1'b0, scale_x_r});
                    state_r <= STATE_TRIG_MUL;
                end

                STATE_TRIG_MUL: begin
                    cos_scale_y_r <= $signed(cos_r) *
                        $signed({1'b0, scale_y_r});
                    sin_scale_y_r <= $signed(sin_r) *
                        $signed({1'b0, scale_y_r});
                    state_r <= STATE_STEPS;
                end

                STATE_STEPS: begin
                    if (!steps_fit_w) begin
                        error_r <= 1'b1;
                        done_r <= 1'b1;
                        state_r <= STATE_IDLE;
                    end else begin
                        pixel_step_x_r <= selected_pixel_x_w[31:0];
                        pixel_step_y_r <= selected_pixel_y_w[31:0];
                        row_step_x_r <= selected_row_x_w[31:0];
                        row_step_y_r <= selected_row_y_w[31:0];
                        state_r <= STATE_ORIGIN;
                    end
                end

                STATE_ORIGIN: begin
                    // The four DSP products, two 48-bit subtractors and
                    // range check must not occupy one DDR-clock cycle.
                    dst_x_offset_r <= dst_x_offset_w;
                    dst_y_to_x_offset_r <= dst_y_to_x_offset_w;
                    dst_x_to_y_offset_r <= dst_x_to_y_offset_w;
                    dst_y_offset_r <= dst_y_offset_w;
                    state_r <= STATE_ORIGIN_PARTIAL;
                end

                STATE_ORIGIN_PARTIAL: begin
                    origin_x_partial_r <= crop_center_x_w - dst_x_offset_r;
                    origin_y_partial_r <= crop_center_y_w - dst_x_to_y_offset_r;
                    state_r <= STATE_ORIGIN_SUM;
                end

                STATE_ORIGIN_SUM: begin
                    origin_x_full_r <= origin_x_partial_r -
                        dst_y_to_x_offset_r;
                    origin_y_full_r <= origin_y_partial_r - dst_y_offset_r;
                    state_r <= STATE_ORIGIN_CHECK;
                end

                STATE_ORIGIN_CHECK: begin
                    if (!origins_fit_w) begin
                        error_r <= 1'b1;
                        done_r <= 1'b1;
                        state_r <= STATE_IDLE;
                    end else begin
                        origin_x_r <= origin_x_full_r[31:0];
                        origin_y_r <= origin_y_full_r[31:0];
                        state_r <= STATE_LAUNCH;
                    end
                end

                STATE_LAUNCH: begin
                    walker_start_r <= 1'b1;
                    done_r <= 1'b1;
                    cache_valid_r <= 1'b1;
                    state_r <= STATE_IDLE;
                end

                default: begin
                    error_r <= 1'b1;
                    done_r <= 1'b1;
                    state_r <= STATE_IDLE;
                end
            endcase

            if (cfg_start_i && (state_r != STATE_IDLE))
                error_r <= 1'b1;
        end
    end

endmodule
