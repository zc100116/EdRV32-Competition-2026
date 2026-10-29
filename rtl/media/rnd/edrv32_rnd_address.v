// File: edrv32_rnd_address.v
// Spec: rnd-spec 2.1, 2.6 GLYPH/BLIT/COPY/TILEMAP, 5.2.
// Description: Byte and sub-byte source addressing, nearest-neighbor sampling and tile maps.
//              All DDR descriptors use aligned beats; the offsets select bytes within beats.
// Clock domain: combinational.
module edrv32_rnd_address (
    // Command and target coordinate in its clipped drawing region.
    input wire [511:0] command_i,
    input wire [11:0] x_i,
    input wire [11:0] y_i,
    input wire [15:0] map_entry_i,
    output wire [31:0] dst_addr_o,
    output wire [31:0] src_addr_o,
    output wire [31:0] map_addr_o,
    output wire [2:0] sub_shift_o,
    output wire [7:0] sub_mask_o,
    output wire [31:0] sample_x_o,
    output wire [31:0] sample_y_o
);
    wire [7:0] op_w;
    wire [3:0] format_w;
    reg [2:0] bits_log2_w;
    wire [31:0] kx_w;
    wire [31:0] ky_w;
    wire [63:0] scaled_x_w;
    wire [63:0] scaled_y_w;
    wire [31:0] u_w;
    wire [31:0] v_w;
    wire [31:0] mx_w;
    wire [31:0] my_w;
    wire [4:0] tile_log2_w;
    wire [31:0] tile_mask_w;
    wire [31:0] tile_x_w;
    wire [31:0] tile_y_w;
    wire [31:0] tile_pixel_w;
    wire [34:0] pixel_bits_w;
    wire [31:0] source_base_w;
    wire [31:0] source_row_w;
    wire unused_command_w;

    assign op_w = command_i[7:0];
    assign format_w = command_i[15:12];
    assign kx_w = (op_w == 8'h04 && command_i[16]) ?
        {{16{command_i[207]}}, command_i[207:192]} - {20'd0, x_i} :
        {20'd0, x_i} - {{16{command_i[175]}}, command_i[175:160]};
    assign ky_w = (op_w == 8'h04 && command_i[17]) ?
        {{16{command_i[223]}}, command_i[223:208]} - {20'd0, y_i} :
        {20'd0, y_i} - {{16{command_i[191]}}, command_i[191:176]};
    assign scaled_x_w = kx_w * command_i[383:352];
    assign scaled_y_w = ky_w * command_i[415:384];
    assign u_w = {16'd0, command_i[335:320]} +
        (op_w == 8'h04 ? scaled_x_w[47:16] : kx_w);
    assign v_w = {16'd0, command_i[351:336]} +
        (op_w == 8'h04 ? scaled_y_w[47:16] : ky_w);
    assign mx_w = {16'd0, command_i[367:352]} + kx_w;
    assign my_w = {16'd0, command_i[383:368]} + ky_w;
    assign tile_log2_w = command_i[16] ? 5'd4 : 5'd3;
    assign tile_mask_w = command_i[16] ? 32'd15 : 32'd7;
    assign tile_x_w = (map_entry_i[12] ? tile_mask_w - (mx_w & tile_mask_w) :
        mx_w & tile_mask_w);
    assign tile_y_w = (map_entry_i[13] ? tile_mask_w - (my_w & tile_mask_w) :
        my_w & tile_mask_w);
    assign tile_pixel_w = ({20'd0, map_entry_i[11:0]} << (2 * tile_log2_w)) +
        (tile_y_w << tile_log2_w) + tile_x_w;
    assign pixel_bits_w = {3'd0, (op_w == 8'h08 ? tile_pixel_w : u_w)} << bits_log2_w;
    assign source_base_w = command_i[287:256];
    assign source_row_w = op_w == 8'h08 ? 32'd0 : v_w * {16'd0, command_i[303:288]};
    assign src_addr_o = source_base_w + source_row_w + pixel_bits_w[34:3];
    assign dst_addr_o = command_i[63:32] + {20'd0, y_i} * {16'd0, command_i[79:64]} +
        ({20'd0, x_i} << (command_i[8] ? 2 : 1));
    assign map_addr_o = command_i[319:288] +
        (my_w >> tile_log2_w) * {16'd0, command_i[335:320]} +
        ((mx_w >> tile_log2_w) << 1);
    assign sample_x_o = op_w == 8'h08 ? mx_w : u_w;
    assign sample_y_o = op_w == 8'h08 ? my_w : v_w;
    assign sub_shift_o = (3'd0 - (3'd1 << bits_log2_w)) - pixel_bits_w[2:0];
    assign sub_mask_o = bits_log2_w >= 3'd3 ? 8'hff :
        8'hff >> (8 - (1 << bits_log2_w));
    assign unused_command_w = ^{command_i[511:416], command_i[255:224],
        command_i[191:176], command_i[175:160], command_i[159:80],
        command_i[31:18], command_i[11:9], scaled_x_w[63:48], scaled_x_w[15:0],
        scaled_y_w[63:48], scaled_y_w[15:0], map_entry_i[15:14]};
    always @(*) begin
        bits_log2_w = 3'd0;
        case (format_w)
            4'd0: bits_log2_w = 3'd4;
            4'd1: bits_log2_w = 3'd5;
            4'd2, 4'd6: bits_log2_w = 3'd3;
            4'd3, 4'd7: bits_log2_w = 3'd2;
            4'd4, 4'd8: bits_log2_w = 3'd1;
            4'd5, 4'd9: bits_log2_w = 3'd0;
            default: bits_log2_w = 3'd0;
        endcase
    end
endmodule
