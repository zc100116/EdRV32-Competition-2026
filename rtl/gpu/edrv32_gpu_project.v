// File: edrv32_gpu_project.v
// Spec: gpu-spec 2.4, 2.12; GPU microarchitecture 4.3.
// Description: Q30 perspective division with full coordinate and viewport products.
//              Only the final screen coordinate and depth conversions round and saturate.
// Clock domain: clk_gpu.
module edrv32_gpu_project (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Clipped vertex with stable viewport.
    input wire clipped_valid_i,
    output wire clipped_ready_o,
    input wire [263:0] clipped_data_i,
    input wire [63:0] viewport_i,

    // Screen vertex: x/y/depth/q/uq/vq/RGB, low fields first.
    output wire projected_valid_o,
    input wire projected_ready_i,
    output wire [258:0] projected_data_o,

    // Drain control.
    input wire stop_i,
    output wire idle_o
);
    reg [8:0] input_delay_write_r;
    wire [8:0] input_delay_read_w;
    wire [223:0] input_prefix_w;
    wire [287:0] unused_input_delay_w;
    wire [5:0] reciprocal_exponent_wr_w;
    wire [5:0] reciprocal_exponent_rd_w;
    wire enable_w;
    wire accept_w;
    wire reciprocal_valid_w;
    wire [30:0] reciprocal_w;
    wire [5:0] exponent_w;
    wire [39:0] position_input_w [0:2];
    wire [15:0] uv_input_w [0:1];
    wire [71:0] color_input_w;
    reg [3:0] valid_r;
    reg [9:0] input_valid_r;
    wire [34:0] q_w [10:13];
    wire signed [74:0] position_w [0:2];
    wire signed [93:0] viewport_w [0:2];
    wire [101:0] uv_w [11:13];
    wire [71:0] color_w [11:13];
    reg [49:0] screen_r;
    reg [1:0] count_r;
    reg read_r;
    reg write_r;
    wire [16:0] screen_coordinate_w [0:1];
    wire [15:0] depth_w;
    reg [39:0] unused_restored_w;
    wire [93:0] depth_rounded_w;
    wire push_w;
    wire pop_w;
    wire [34:0] restored_w;
    wire [49:0] screen_w;
    wire [50:0] uv_product_w [0:1];


    assign enable_w = count_r != 2 && !stop_i;
    assign clipped_ready_o = enable_w;
    assign accept_w = clipped_valid_i && clipped_ready_o;
    assign projected_valid_o = count_r != 0;
    assign push_w = enable_w && valid_r[3];
    assign pop_w = projected_valid_o && projected_ready_i;
    // Restore stage: one rounded barrel shifter, preserving the original u40 intermediate.
    always @(*) begin
        unused_restored_w = 40'd0;
        if (exponent_w > 6'd16) begin
            unused_restored_w = ({9'd0, reciprocal_w}
                + (40'd1 << (exponent_w - 6'd17))) >> (exponent_w - 6'd16);
        end else begin
            unused_restored_w = {9'd0, reciprocal_w} << (6'd16 - exponent_w);
        end
    end
    assign restored_w = unused_restored_w[34:0];
    // Position stage also contains two 16x35 UV multipliers.
    assign uv_product_w[0] = uv_input_w[0] * q_w[10];
    assign uv_product_w[1] = uv_input_w[1] * q_w[10];
    // Final conversion stage: depth add/shift/clamp, plus two screen converters below.
    assign depth_rounded_w = (viewport_w[2] + (94'sd1 << 45)) >>> 46;
    assign depth_w = viewport_w[2] < 0 ? 16'd0
        : (depth_rounded_w > 65535 ? 16'hffff : depth_rounded_w[15:0]);
    assign screen_w = {depth_w, screen_coordinate_w[1], screen_coordinate_w[0]};
    assign idle_o = count_r == 0 && valid_r == 0 && !reciprocal_valid_w
        && input_valid_r == 0;

    edrv32_gpu_project_recip u_reciprocal (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .enable_i(enable_w),
        .delay_exponent_wr_data_o(reciprocal_exponent_wr_w),
        .delay_exponent_rd_data_i(reciprocal_exponent_rd_w),
        .stop_i(stop_i),
        .value_valid_i(accept_w),
        .value_i(clipped_data_i[159:120]),
        .value_valid_o(reciprocal_valid_w),
        .reciprocal_o(reciprocal_w),
        .exponent_o(exponent_w)
    );

    // Payload latency is 1+10; the reciprocal exponent uses the same ten RAM cycles.
    assign input_delay_read_w = input_delay_write_r - 9'd9;
    assign reciprocal_exponent_rd_w = unused_input_delay_w[229:224];
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) input_delay_write_r <= 0;
        else if (enable_w) input_delay_write_r <= input_delay_write_r + 1'b1;
    end
    edrv32_ram_gpu_delay u_input_delay_0 (
        .clk_i(clk_i),
        .wr_en_i(enable_w),
        .wr_addr_i(input_delay_write_r),
        .wr_data_i(input_prefix_w[0 +: 72]),
        .rd_en_i(enable_w),
        .rd_addr_i(input_delay_read_w),
        .rd_data_o(unused_input_delay_w[0 +: 72])
    );
    edrv32_ram_gpu_delay u_input_delay_1 (
        .clk_i(clk_i),
        .wr_en_i(enable_w),
        .wr_addr_i(input_delay_write_r),
        .wr_data_i(input_prefix_w[72 +: 72]),
        .rd_en_i(enable_w),
        .rd_addr_i(input_delay_read_w),
        .rd_data_o(unused_input_delay_w[72 +: 72])
    );
    edrv32_ram_gpu_delay u_input_delay_2 (
        .clk_i(clk_i),
        .wr_en_i(enable_w),
        .wr_addr_i(input_delay_write_r),
        .wr_data_i(input_prefix_w[144 +: 72]),
        .rd_en_i(enable_w),
        .rd_addr_i(input_delay_read_w),
        .rd_data_o(unused_input_delay_w[144 +: 72])
    );
    edrv32_ram_gpu_delay u_input_delay_3 (
        .clk_i(clk_i),
        .wr_en_i(enable_w),
        .wr_addr_i(input_delay_write_r),
        .wr_data_i({58'b0, reciprocal_exponent_wr_w, input_prefix_w[223:216]}),
        .rd_en_i(enable_w),
        .rd_addr_i(input_delay_read_w),
        .rd_data_o(unused_input_delay_w[216 +: 72])
    );

    genvar field_g;
    genvar stage_g;
    genvar axis_g;
    generate
        // Eight payload fields, with one prefix register each; W is used by the reciprocal.
        for (field_g = 0; field_g < 8; field_g = field_g + 1) begin : g_input_field
            localparam WIDTH = field_g < 3 ? 40 : (field_g < 5 ? 16 : 24);
            localparam INPUT_OFFSET = field_g < 3 ? field_g * 40
                : (field_g < 5 ? 160 + (field_g - 3) * 16 : 192 + (field_g - 5) * 24);
            localparam RAM_OFFSET = field_g < 3 ? field_g * 40
                : (field_g < 5 ? 120 + (field_g - 3) * 16 : 152 + (field_g - 5) * 24);
            reg [WIDTH-1:0] prefix_r;
            always @(posedge clk_i) begin
                if (enable_w) prefix_r <= clipped_data_i[INPUT_OFFSET +: WIDTH];
            end
            assign input_prefix_w[RAM_OFFSET +: WIDTH] = prefix_r;
            if (field_g < 3) begin : g_position
                assign position_input_w[field_g] = unused_input_delay_w[RAM_OFFSET +: WIDTH];
            end else if (field_g < 5) begin : g_uv
                assign uv_input_w[field_g - 3] = unused_input_delay_w[RAM_OFFSET +: WIDTH];
            end else begin : g_color
                assign color_input_w[(field_g - 5) * 24 +: 24] =
                    unused_input_delay_w[RAM_OFFSET +: WIDTH];
            end
        end
        // Position stage: three signed 40x36 products; viewport stage remains unchanged.
        for (axis_g = 0; axis_g < 3; axis_g = axis_g + 1) begin : g_position
            reg signed [74:0] data_r;
            assign position_w[axis_g] = data_r;
            always @(posedge clk_i) begin
                if (enable_w) data_r <= $signed(position_input_w[axis_g])
                    * $signed({1'b0, q_w[10]});
            end
        end
        // Final screen stage: two copies of absolute value, round, offset add and saturation.
        for (axis_g = 0; axis_g < 2; axis_g = axis_g + 1) begin : g_screen
            wire [93:0] magnitude_w;
            wire signed [94:0] rounded_w;
            wire signed [94:0] signed_w;
            wire signed [94:0] offset_w;
            assign magnitude_w = viewport_w[axis_g][93]
                ? -viewport_w[axis_g] : viewport_w[axis_g];
            assign rounded_w = $signed(({1'b0, magnitude_w} + (95'd1 << 45)) >> 46);
            assign signed_w = viewport_w[axis_g][93] ? -rounded_w : rounded_w;
            assign offset_w = signed_w
                + ($signed({{79{viewport_i[axis_g * 16 + 15]}},
                    viewport_i[axis_g * 16 +: 16]}) <<< 4);
            assign screen_coordinate_w[axis_g] = offset_w > 65535 ? 17'h0ffff
                : (offset_w < -65536 ? 17'h10000 : offset_w[16:0]);
        end
        // Output FIFO: seven fields, two slots each, packed only at the output port.
        for (field_g = 0; field_g < 7; field_g = field_g + 1) begin : g_output
            localparam WIDTH = field_g < 2 ? 17 : (field_g == 2 ? 16
                : (field_g == 3 ? 35 : (field_g < 6 ? 51 : 72)));
            localparam OFFSET = field_g == 0 ? 0 : (field_g == 1 ? 17
                : (field_g == 2 ? 34 : (field_g == 3 ? 50
                : (field_g == 4 ? 85 : (field_g == 5 ? 136 : 187)))));
            reg [WIDTH-1:0] data_r [0:1];
            wire [WIDTH-1:0] next_w;
            if (field_g < 3) begin : g_screen
                assign next_w = screen_r[OFFSET +: WIDTH];
            end else if (field_g == 3) begin : g_q
                assign next_w = q_w[13];
            end else if (field_g < 6) begin : g_uv
                assign next_w = uv_w[13][(field_g - 4) * 51 +: 51];
            end else begin : g_color
                assign next_w = color_w[13];
            end
            assign projected_data_o[OFFSET +: WIDTH] = data_r[read_r];
            always @(posedge clk_i) begin
                if (push_w) data_r[write_r] <= next_w;
            end
        end
        for (stage_g = 10; stage_g <= 13; stage_g = stage_g + 1) begin : g_q
            reg [34:0] data_r;
            wire [34:0] next_w;
            if (stage_g == 10) begin : g_first
                assign next_w = restored_w;
            end else begin : g_delay
                assign next_w = q_w[stage_g - 1];
            end
            assign q_w[stage_g] = data_r;
            always @(posedge clk_i) begin
                if (enable_w) data_r <= next_w;
            end
        end
        for (stage_g = 11; stage_g <= 13; stage_g = stage_g + 1) begin : g_uv
            reg [101:0] data_r;
            wire [101:0] next_w;
            if (stage_g == 11) begin : g_first
                assign next_w = {uv_product_w[1], uv_product_w[0]};
            end else begin : g_delay
                assign next_w = uv_w[stage_g - 1];
            end
            assign uv_w[stage_g] = data_r;
            always @(posedge clk_i) begin
                if (enable_w) data_r <= next_w;
            end
        end
        for (stage_g = 11; stage_g <= 13; stage_g = stage_g + 1) begin : g_color
            reg [71:0] data_r;
            wire [71:0] next_w;
            if (stage_g == 11) begin : g_first
                assign next_w = color_input_w;
            end else begin : g_delay
                assign next_w = color_w[stage_g - 1];
            end
            assign color_w[stage_g] = data_r;
            always @(posedge clk_i) begin
                if (enable_w) data_r <= next_w;
            end
        end
        // Viewport stage: two signed products and one depth shift/subtract unit.
        for (axis_g = 0; axis_g < 3; axis_g = axis_g + 1) begin : g_viewport
            reg signed [93:0] data_r;
            wire signed [93:0] next_w;
            if (axis_g == 0) begin : g_x
                assign next_w = (($signed({{19{position_w[0][74]}}, position_w[0]})
                    + (94'sd1 << 46)) * $signed({1'b0, viewport_i[47:32]})) <<< 3;
            end else if (axis_g == 1) begin : g_y
                assign next_w = (((94'sd1 << 46)
                    - $signed({{19{position_w[1][74]}}, position_w[1]}))
                    * $signed({1'b0, viewport_i[63:48]})) <<< 3;
            end else begin : g_depth
                assign next_w = ($signed({{19{position_w[2][74]}}, position_w[2]}) <<< 16)
                    - $signed({{19{position_w[2][74]}}, position_w[2]});
            end
            assign viewport_w[axis_g] = data_r;
            always @(posedge clk_i) begin
                if (enable_w) data_r <= next_w;
            end
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_r <= 4'd0;
            input_valid_r <= 10'd0;
            count_r <= 2'd0;
            read_r <= 1'b0;
            write_r <= 1'b0;
        end else if (stop_i) begin
            valid_r <= 4'd0;
            input_valid_r <= 10'd0;
            count_r <= 2'd0;
            read_r <= 1'b0;
            write_r <= 1'b0;
        end else begin
            if (enable_w) begin
                valid_r <= {valid_r[2:0], reciprocal_valid_w};
                input_valid_r <= {input_valid_r[8:0], accept_w};
            end
            if (push_w) write_r <= !write_r;
            if (pop_w) read_r <= !read_r;
            begin
                case ({push_w, pop_w})
                    2'b10: count_r <= count_r + 2'd1;
                    2'b01: count_r <= count_r - 2'd1;
                    default: count_r <= count_r;
                endcase
            end
        end
    end

    always @(posedge clk_i) begin
        if (enable_w) begin
            screen_r <= screen_w;
        end
    end
endmodule
