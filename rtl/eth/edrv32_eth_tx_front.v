// File: edrv32_eth_tx_front.v
// Spec: eth 2.6, 5.2, 5.3.
// Description: Serialize a prepared frame with preamble, minimum padding, CRC and IFG.
//              FIFO input marks the last byte before padding/FCS with bit 8.
// Clock domain: eth_tx_clk.
module edrv32_eth_tx_front (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Prepared byte stream.
    input wire valid_i,
    output wire ready_o,
    input wire [8:0] data_i,

    // MAC transmit interface.
    output reg [7:0] data_o,
    output wire valid_o,
    output wire error_o,

    // Frame completion in this clock domain.
    output wire done_o
);
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_PREAMBLE = 3'd1;
    localparam [2:0] S_DATA = 3'd2;
    localparam [2:0] S_PAD = 3'd3;
    localparam [2:0] S_FCS = 3'd4;
    localparam [2:0] S_GAP = 3'd5;
    reg [2:0] state_r;
    reg [3:0] idx_r;
    reg [10:0] count_r;
    reg [31:0] crc_r;
    wire [31:0] crc_w;
    edrv32_eth_crc u_crc (
        .crc_i(crc_r),
        .data_i(data_o),
        .crc_o(crc_w)
    );
    assign ready_o = state_r == S_DATA;
    assign valid_o = state_r != S_IDLE && state_r != S_GAP;
    assign error_o = 1'b0;
    assign done_o = state_r == S_FCS && idx_r == 4'd3;
    always @(*) begin
        data_o = 8'd0;
        case (state_r)
            S_PREAMBLE: data_o = idx_r == 4'd7 ? 8'hd5 : 8'h55;
            S_DATA: data_o = data_i[7:0];
            S_FCS: data_o = ~crc_r[7:0];
            default: data_o = 8'd0;
        endcase
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            idx_r <= 4'd0;
            count_r <= 11'd0;
        end else begin
            case (state_r)
                S_IDLE: begin
                    if (valid_i) begin
                        state_r <= S_PREAMBLE;
                        idx_r <= 4'd0;
                        count_r <= 11'd0;
                    end
                end
                S_PREAMBLE: begin
                    idx_r <= idx_r + 4'd1;
                    if (idx_r == 4'd7)
                        state_r <= S_DATA;
                end
                S_DATA: begin
                    count_r <= count_r + 11'd1;
                    if (data_i[8]) begin
                        idx_r <= 4'd0;
                        state_r <= count_r < 11'd59 ? S_PAD : S_FCS;
                    end
                end
                S_PAD: begin
                    count_r <= count_r + 11'd1;
                    if (count_r == 11'd59) begin
                        state_r <= S_FCS;
                        idx_r <= 4'd0;
                    end
                end
                S_FCS: begin
                    idx_r <= idx_r + 4'd1;
                    if (idx_r == 4'd3) begin
                        state_r <= S_GAP;
                        idx_r <= 4'd0;
                    end
                end
                S_GAP: begin
                    idx_r <= idx_r + 4'd1;
                    if (idx_r == 4'd11)
                        state_r <= S_IDLE;
                end
                default: state_r <= S_IDLE;
            endcase
        end
    end
    always @(posedge clk_i) begin
        if (state_r == S_IDLE)
            crc_r <= 32'hffffffff;
        else if (state_r == S_DATA || state_r == S_PAD)
            crc_r <= crc_w;
        else if (state_r == S_FCS)
            crc_r <= {8'd0, crc_r[31:8]};
    end
endmodule
