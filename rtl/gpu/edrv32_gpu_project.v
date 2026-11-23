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
    wire enable_w;
    wire accept_w;
    wire reciprocal_valid_w;
    wire [30:0] reciprocal_w;
    wire [5:0] exponent_w;
    reg [263:0] data_r [0:10];
    reg [3:0] valid_r;
    reg [9:0] input_valid_r;
    reg [34:0] q_r [10:13];
    reg signed [74:0] position_r [0:2];
    reg signed [93:0] viewport_r [0:2];
    reg [101:0] uv_r [11:13];
    reg [71:0] color_r [11:13];
    reg [49:0] screen_r;
    reg [1:0] count_r;
    reg read_r;
    reg write_r;
    reg [258:0] output_r [0:1];
    wire push_w;
    wire pop_w;
    wire [34:0] restored_w;
    wire [49:0] screen_w;
    wire [50:0] uv_product_w [0:1];
    integer stage_r;
    integer axis_r;

    function [34:0] restore;
        input [30:0] reciprocal_i;
        input [5:0] exponent_i;
        reg [39:0] unused_result;
        begin
            if (exponent_i > 16) begin
                unused_result = ({9'd0, reciprocal_i}
                    + (40'd1 << (exponent_i - 17))) >> (exponent_i - 16);
            end else begin
                unused_result = {9'd0, reciprocal_i} << (16 - exponent_i);
            end
            restore = unused_result[34:0];
        end
    endfunction

    function [16:0] screen_coordinate;
        input signed [93:0] value_i;
        input signed [15:0] offset_i;
        reg [93:0] magnitude;
        reg signed [94:0] rounded;
        begin
            magnitude = value_i[93] ? -value_i : value_i;
            rounded = $signed(({1'b0, magnitude} + (95'd1 << 45)) >> 46);
            if (value_i[93]) rounded = -rounded;
            rounded = rounded + ($signed({{79{offset_i[15]}}, offset_i}) <<< 4);
            if (rounded > 65535) screen_coordinate = 17'h0ffff;
            else if (rounded < -65536) screen_coordinate = 17'h10000;
            else screen_coordinate = rounded[16:0];
        end
    endfunction

    function [15:0] depth;
        input signed [93:0] value_i;
        reg [93:0] rounded;
        begin
            rounded = (value_i + (94'sd1 << 45)) >>> 46;
            if (value_i < 0) depth = 16'd0;
            else if (rounded > 65535) depth = 16'hffff;
            else depth = rounded[15:0];
        end
    endfunction

    assign enable_w = count_r != 2 && !stop_i;
    assign clipped_ready_o = enable_w;
    assign accept_w = clipped_valid_i && clipped_ready_o;
    assign projected_valid_o = count_r != 0;
    assign projected_data_o = output_r[read_r];
    assign push_w = enable_w && valid_r[3];
    assign pop_w = projected_valid_o && projected_ready_i;
    assign restored_w = restore(reciprocal_w, exponent_w);
    assign uv_product_w[0] = data_r[10][175:160] * q_r[10];
    assign uv_product_w[1] = data_r[10][191:176] * q_r[10];
    assign screen_w = {depth(viewport_r[2]),
        screen_coordinate(viewport_r[1], viewport_i[31:16]),
        screen_coordinate(viewport_r[0], viewport_i[15:0])};
    assign idle_o = count_r == 0 && valid_r == 0 && !reciprocal_valid_w
        && input_valid_r == 0;

    edrv32_gpu_project_recip u_reciprocal (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .enable_i(enable_w),
        .stop_i(stop_i),
        .value_valid_i(accept_w),
        .value_i(clipped_data_i[159:120]),
        .value_valid_o(reciprocal_valid_w),
        .reciprocal_o(reciprocal_w),
        .exponent_o(exponent_w)
    );

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
            data_r[0] <= clipped_data_i;
            for (stage_r = 1; stage_r < 11; stage_r = stage_r + 1) begin
                data_r[stage_r] <= data_r[stage_r - 1];
            end
            q_r[10] <= restored_w;
            for (stage_r = 11; stage_r < 14; stage_r = stage_r + 1) begin
                q_r[stage_r] <= q_r[stage_r - 1];
            end
            for (axis_r = 0; axis_r < 3; axis_r = axis_r + 1) begin
                position_r[axis_r] <= $signed(data_r[10][axis_r * 40 +: 40])
                    * $signed({1'b0, q_r[10]});
            end
            uv_r[11] <= {uv_product_w[1], uv_product_w[0]};
            color_r[11] <= data_r[10][263:192];
            uv_r[12] <= uv_r[11];
            uv_r[13] <= uv_r[12];
            color_r[12] <= color_r[11];
            color_r[13] <= color_r[12];
            viewport_r[0] <= (($signed({{19{position_r[0][74]}}, position_r[0]})
                + (94'sd1 << 46)) * $signed({1'b0, viewport_i[47:32]})) <<< 3;
            viewport_r[1] <= (((94'sd1 << 46)
                - $signed({{19{position_r[1][74]}}, position_r[1]}))
                * $signed({1'b0, viewport_i[63:48]})) <<< 3;
            viewport_r[2] <= ($signed({{19{position_r[2][74]}}, position_r[2]}) <<< 16)
                - $signed({{19{position_r[2][74]}}, position_r[2]});
            screen_r <= screen_w;
        end
        if (push_w) begin
            output_r[write_r] <= {color_r[13], uv_r[13], q_r[13], screen_r};
        end
    end
endmodule
