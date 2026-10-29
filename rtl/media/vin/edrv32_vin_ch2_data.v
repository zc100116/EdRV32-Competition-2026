// File: edrv32_vin_ch2_data.v
// Spec: vin 2.8; SoC 4.5, 8.5.
// Description: RGB565 horizontal sums and one shared line RAM implement 2x2 averaging.
//              Delay each reduced row until the next even row to stream letterbox beats.
// Clock domain: clk_mem.
module edrv32_vin_ch2_data (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Admitted 1280x720 source words; the parent throttles memory frames.
    input wire valid_i,
    input wire [31:0] data_i,
    input wire sof_i,
    input wire eol_i,
    input wire eof_i,
    input wire abort_i,

    // Packed INT8_C4 beats, including twelve top and bottom rows.
    input wire padding_ready_i,
    output wire top_pending_o,
    output reg valid_o,
    output reg [255:0] data_o,
    output reg eof_o,
    output reg blocked_o
);
    reg [9:0] column_r;
    reg [9:0] row_r;
    reg flushing_r;
    reg [9:0] flush_column_r;
    reg [9:0] top_r;
    reg [9:0] bottom_r;
    reg horizontal_valid_r;
    reg horizontal_odd_r;
    reg horizontal_output_r;
    reg horizontal_write_r;
    reg horizontal_last_r;
    reg [9:0] horizontal_addr_r;
    reg [26:0] horizontal_data_r;
    reg read_valid_r;
    reg read_odd_r;
    reg read_output_r;
    reg read_write_r;
    reg read_last_r;
    reg [9:0] read_addr_r;
    reg [26:0] read_horizontal_r;
    wire [47:0] line_data_w;
    reg write_r;
    reg [9:0] write_addr_r;
    reg [47:0] write_data_r;
    reg pixel_valid_r;
    reg pixel_last_r;
    reg [31:0] pixel_data_r;
    reg [2:0] pack_word_r;
    reg [223:0] pack_r;
    wire flush_read_w;
    wire [9:0] column_w;
    wire [9:0] row_w;
    wire [8:0] horizontal_red_w;
    wire [8:0] horizontal_green_w;
    wire [8:0] horizontal_blue_w;
    wire [9:0] vertical_red_w;
    wire [9:0] vertical_green_w;
    wire [9:0] vertical_blue_w;
    wire unused_line_w;
    wire padding_w;
    wire packed_w;

    assign top_pending_o = top_r != 0;
    assign padding_w = (top_r != 0 || bottom_r != 0) && padding_ready_i;
    assign packed_w = pixel_valid_r && pack_word_r == 3'd7;
    assign column_w = sof_i ? 10'd0 : column_r;
    assign row_w = sof_i ? 10'd0 : row_r;
    assign flush_read_w = flushing_r;
    assign horizontal_red_w = {1'b0, data_i[15:11], data_i[15:13]} +
        {1'b0, data_i[31:27], data_i[31:29]};
    assign horizontal_green_w = {1'b0, data_i[10:5], data_i[10:9]} +
        {1'b0, data_i[26:21], data_i[26:25]};
    assign horizontal_blue_w = {1'b0, data_i[4:0], data_i[4:2]} +
        {1'b0, data_i[20:16], data_i[20:18]};
    assign vertical_red_w = {1'b0, line_data_w[8:0]} +
        {1'b0, read_horizontal_r[8:0]} + 10'd2;
    assign vertical_green_w = {1'b0, line_data_w[17:9]} +
        {1'b0, read_horizontal_r[17:9]} + 10'd2;
    assign vertical_blue_w = {1'b0, line_data_w[26:18]} +
        {1'b0, read_horizontal_r[26:18]} + 10'd2;
    assign unused_line_w = |line_data_w[47:27] || |vertical_red_w[2:0] ||
        |vertical_green_w[2:0] || |vertical_blue_w[2:0];

    // Read before replacing a location. Even rows store horizontal sums; odd rows
    // replace them with the reduced pixels, consumed on the following even row.
    edrv32_ram_pix_line u_line (
        .clk_i(clk_i),
        .wr_en_i(write_r),
        .wr_addr_i(write_addr_r),
        .wr_data_i(write_data_r),
        .rd_en_i(horizontal_valid_r && (horizontal_odd_r || horizontal_output_r)),
        .rd_addr_i(horizontal_addr_r),
        .rd_data_o(line_data_w)
    );

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            column_r <= 10'd0;
            row_r <= 10'd0;
            flushing_r <= 1'b0;
            flush_column_r <= 10'd0;
            top_r <= 10'd0;
            bottom_r <= 10'd0;
            horizontal_valid_r <= 1'b0;
            horizontal_odd_r <= 1'b0;
            horizontal_output_r <= 1'b0;
            horizontal_write_r <= 1'b0;
            horizontal_last_r <= 1'b0;
            read_valid_r <= 1'b0;
            read_odd_r <= 1'b0;
            read_output_r <= 1'b0;
            read_write_r <= 1'b0;
            read_last_r <= 1'b0;
            write_r <= 1'b0;
            pixel_valid_r <= 1'b0;
            pixel_last_r <= 1'b0;
            pack_word_r <= 3'd0;
            valid_o <= 1'b0;
            eof_o <= 1'b0;
            blocked_o <= 1'b0;
        end else begin
            horizontal_valid_r <= valid_i || flush_read_w;
            horizontal_odd_r <= valid_i && row_w[0];
            horizontal_output_r <= flush_read_w || (valid_i && !row_w[0] && row_w >= 2);
            horizontal_write_r <= valid_i;
            horizontal_last_r <= flush_read_w && flush_column_r == 10'd639;
            read_valid_r <= horizontal_valid_r;
            read_odd_r <= horizontal_odd_r;
            read_output_r <= horizontal_output_r;
            read_write_r <= horizontal_write_r;
            read_last_r <= horizontal_last_r;
            write_r <= read_valid_r && read_write_r;
            pixel_valid_r <= read_valid_r && read_output_r;
            pixel_last_r <= read_last_r;
            valid_o <= padding_w || packed_w;
            eof_o <= bottom_r == 10'd1 && padding_ready_i;
            // vin 2.8: a camera's effective beat cannot overtake top padding.
            blocked_o <= packed_w && top_r != 0;
            if (valid_i) begin
                column_r <= eol_i ? 10'd0 : column_w + 10'd1;
                row_r <= eol_i ? row_w + 10'd1 : row_w;
                if (sof_i)
                    top_r <= 10'd960;
                if (eof_i) begin
                    flushing_r <= 1'b1;
                    flush_column_r <= 10'd0;
                end
            end
            if (flushing_r) begin
                if (flush_column_r == 10'd639)
                    flushing_r <= 1'b0;
                else
                    flush_column_r <= flush_column_r + 10'd1;
            end
            if (top_r != 0 && padding_ready_i)
                top_r <= top_r - 10'd1;
            if (bottom_r != 0 && padding_ready_i)
                bottom_r <= bottom_r - 10'd1;
            if (pixel_valid_r) begin
                pack_word_r <= pack_word_r + 3'd1;
                if (pixel_last_r)
                    bottom_r <= 10'd960;
            end
            if (abort_i) begin
                flushing_r <= 1'b0;
                top_r <= 10'd0;
                bottom_r <= 10'd0;
                horizontal_valid_r <= 1'b0;
                read_valid_r <= 1'b0;
                write_r <= 1'b0;
                pixel_valid_r <= 1'b0;
                pack_word_r <= 3'd0;
                valid_o <= 1'b0;
                eof_o <= 1'b0;
                blocked_o <= 1'b0;
            end
        end
    end

    // Each wide enable comes directly from a local pipeline register (V-R8).
    // For every c in [0,255], floor((254*c+255)/510) == floor(c/2).
    // Therefore average then quantize is exactly (four_pixel_sum + 2) >> 3.
    always @(posedge clk_i) begin
        if (valid_i) begin
            horizontal_addr_r <= column_w;
            horizontal_data_r <= {horizontal_blue_w, horizontal_green_w, horizontal_red_w};
        end else if (flush_read_w) begin
            horizontal_addr_r <= flush_column_r;
        end
        if (horizontal_valid_r) begin
            read_addr_r <= horizontal_addr_r;
            read_horizontal_r <= horizontal_data_r;
        end
        if (read_valid_r) begin
            write_addr_r <= read_addr_r;
            write_data_r <= read_odd_r ?
                {24'd0, 1'b0, vertical_blue_w[9:3], 1'b0, vertical_green_w[9:3],
                    1'b0, vertical_red_w[9:3]} : {21'd0, read_horizontal_r};
            pixel_data_r <= {8'd0, line_data_w[23:0]};
        end
        if (pixel_valid_r)
            pack_r <= {pixel_data_r, pack_r[223:32]};
        if (top_r != 0 || bottom_r != 0)
            data_o <= {8{32'h0039_3939}};
        else
            data_o <= {pixel_data_r, pack_r};
    end
endmodule
