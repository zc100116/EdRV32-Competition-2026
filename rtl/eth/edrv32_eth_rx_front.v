// File: edrv32_eth_rx_front.v
// Spec: eth 2.2, 5.1.
// Description: Strip preamble/SFD and emit every frame octet followed by one status token.
//              The FIFO consumer runs continuously; the interframe gap carries the token.
// Clock domain: eth_rx_clk.
module edrv32_eth_rx_front (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // MAC receive interface.
    input wire [7:0] data_i,
    input wire valid_i,
    input wire error_i,

    // FIFO stream: bit 9 marks frame end; bit 8 is accumulated link error.
    output wire valid_o,
    output wire [9:0] data_o
);
    reg frame_r;
    reg error_r;
    reg [31:0] crc_r;
    wire [31:0] crc_w;
    edrv32_eth_crc u_crc (
        .crc_i(crc_r),
        .data_i(data_i),
        .crc_o(crc_w)
    );
    assign valid_o = frame_r;
    assign data_o = valid_i ? {2'b00, data_i} :
        {1'b1, error_r || (crc_r != 32'hdebb20e3), 8'd0};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            frame_r <= 1'b0;
            error_r <= 1'b0;
        end else begin
            if (!valid_i) begin
                frame_r <= 1'b0;
                error_r <= 1'b0;
            end else if (!frame_r && data_i == 8'hd5) begin
                frame_r <= 1'b1;
                error_r <= error_i;
            end else if (frame_r) begin
                error_r <= error_r || error_i;
            end
        end
    end
    always @(posedge clk_i) begin
        if (!frame_r)
            crc_r <= 32'hffffffff;
        else if (valid_i)
            crc_r <= crc_w;
    end
endmodule
