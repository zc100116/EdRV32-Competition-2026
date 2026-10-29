// File: edrv32_fpga_imgtest_sccb.v
// Spec: Task B3-9; design b2-software 3.2; legacy edrv32_ov5640_sccb.
// Description: Fixed 100 kHz write-only OV5640 SCCB sender at 125 MHz.
//              The ninth bit is SCCB don't-care; the board owns open-drain pins.
// Clock domain: clk_mem.
module edrv32_fpga_imgtest_sccb (
    // Clock and domain reset.
    input wire clk_i,
    input wire rst_n_i,

    // One sensor register transaction.
    input wire start_i,
    input wire [23:0] data_i,
    output wire done_o,

    // Pin drive requests, high means release.
    output reg scl_o,
    output reg sda_o
);
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_START = 3'd1;
    localparam [2:0] S_SEND = 3'd2;
    localparam [2:0] S_ACK = 3'd3;
    localparam [2:0] S_STOP = 3'd4;
    reg [2:0] state_r;
    reg [10:0] div_cnt_r;
    reg [2:0] bit_idx_r;
    reg [1:0] byte_idx_r;
    reg [31:0] data_r;
    wire tick_w = div_cnt_r == 11'd1249;
    assign done_o = state_r == S_STOP && tick_w;

    always @(*) begin
        scl_o = 1'b1;
        sda_o = 1'b1;
        case (state_r)
            S_START: sda_o = div_cnt_r < 11'd625;
            S_SEND: begin
                scl_o = div_cnt_r >= 11'd312 && div_cnt_r < 11'd937;
                sda_o = data_r[{byte_idx_r, bit_idx_r}];
            end
            S_ACK: scl_o = div_cnt_r >= 11'd312 && div_cnt_r < 11'd937;
            S_STOP: begin
                scl_o = div_cnt_r >= 11'd312;
                sda_o = div_cnt_r >= 11'd937;
            end
            default: begin
                scl_o = 1'b1;
                sda_o = 1'b1;
            end
        endcase
    end

    always @(posedge clk_i) begin
        if (start_i) begin
            data_r <= {8'h78, data_i};
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            div_cnt_r <= 11'd0;
            bit_idx_r <= 3'd7;
            byte_idx_r <= 2'd3;
        end else begin
            if (state_r == S_IDLE || tick_w) begin
                div_cnt_r <= 11'd0;
            end else begin
                div_cnt_r <= div_cnt_r + 1'b1;
            end
            case (state_r)
                S_IDLE: begin
                    if (start_i) begin
                        state_r <= S_START;
                        bit_idx_r <= 3'd7;
                        byte_idx_r <= 2'd3;
                    end
                end
                S_START: if (tick_w) state_r <= S_SEND;
                S_SEND: begin
                    if (tick_w) begin
                        if (bit_idx_r == 3'd0) begin
                            bit_idx_r <= 3'd7;
                            state_r <= S_ACK;
                        end else begin
                            bit_idx_r <= bit_idx_r - 1'b1;
                        end
                    end
                end
                S_ACK: begin
                    if (tick_w) begin
                        if (byte_idx_r == 2'd0) begin
                            state_r <= S_STOP;
                        end else begin
                            byte_idx_r <= byte_idx_r - 1'b1;
                            state_r <= S_SEND;
                        end
                    end
                end
                S_STOP: if (tick_w) state_r <= S_IDLE;
                default: state_r <= S_IDLE;
            endcase
        end
    end
endmodule
