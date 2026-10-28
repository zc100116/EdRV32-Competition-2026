// File: edrv32_geo_desc.v
// Spec: geo-spec 2.6.
// Description: Decode only the specified descriptor fields.
// Clock domain: clk_mem.
module edrv32_geo_desc (
    // Descriptor image, little-endian words.
    input wire [511:0] data_i,
    // Decoded fields; unlisted bits have no fanout.
    output wire [31:0] src_base_o,
    output wire [31:0] src_stride_o,
    output wire [11:0] src_w_o,
    output wire [11:0] src_h_o,
    output wire [31:0] dst_base_o,
    output wire [31:0] dst_stride_o,
    output wire [11:0] rect_x_o,
    output wire [11:0] rect_y_o,
    output wire [11:0] rect_w_o,
    output wire [11:0] rect_h_o,
    output wire [15:0] bg_o,
    output wire [31:0] a_o,
    output wire [31:0] b_o,
    output wire [31:0] tx_o,
    output wire [31:0] c_o,
    output wire [31:0] d_o,
    output wire [31:0] ty_o
);
    wire unused_w;
    assign unused_w = &{data_i[511:448], data_i[255:240], data_i[223:220],
        data_i[207:204], data_i[192], data_i[191:188], data_i[175:172],
        data_i[163:160], data_i[159:144], data_i[132:128], data_i[107:96],
        data_i[95:92], data_i[79:76], data_i[63:48], data_i[36:32], data_i[11:0]};
    assign src_base_o = {data_i[31:12], 12'd0};
    assign src_stride_o = {16'd0, data_i[47:37], 5'd0};
    assign src_w_o = data_i[75:64];
    assign src_h_o = data_i[91:80];
    assign dst_base_o = {data_i[127:108], 12'd0};
    assign dst_stride_o = {16'd0, data_i[143:133], 5'd0};
    assign rect_x_o = {data_i[171:164], 4'd0};
    assign rect_y_o = data_i[187:176];
    assign rect_w_o = {data_i[203:193], 1'b0};
    assign rect_h_o = data_i[219:208];
    assign bg_o = data_i[239:224];
    assign a_o = data_i[287:256];
    assign b_o = data_i[319:288];
    assign tx_o = data_i[351:320];
    assign c_o = data_i[383:352];
    assign d_o = data_i[415:384];
    assign ty_o = data_i[447:416];
endmodule
