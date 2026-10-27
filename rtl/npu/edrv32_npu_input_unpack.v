// File: edrv32_npu_input_unpack.v
// Spec: npu-spec 2.2, 5.1; datapath design 4.2.4, 4.3.2, 4.4.2.
// Description: Write C16 beats directly and normalize each C4 beat into four writes.
//              Row completion follows the final cache write, including overlapping rows.
// Clock: clk_npu.
module edrv32_npu_input_unpack (
    // Clock and cancellation.
    input wire clk_i,
    input wire rst_n_i,
    input wire cancel_i,

    // Input DMA and layer format.
    input wire cfg_in_c4_i,
    input wire line_wr_valid_i,
    output wire line_wr_ready_o,
    input wire line_wr_bank_i,
    input wire [9:0] line_wr_addr_i,
    input wire [255:0] line_wr_data_i,
    input wire line_wr_row_last_i,
    output reg line_wr_row_done_o,
    output wire line_wr_idle_o,

    // Normalized cache writes.
    output wire cache_wr_valid_o,
    output wire cache_wr_bank_o,
    output wire [9:0] cache_wr_addr_o,
    output wire [255:0] cache_wr_data_o
);
    reg [2:0] remaining_r;
    reg [1:0] phase_r;
    reg [255:0] data_r;
    reg [9:0] addr_r;
    reg row_last_r;
    wire accept_w;
    wire expanding_w;

    assign expanding_w = remaining_r != 3'd0;
    assign line_wr_ready_o = !cancel_i && (!cfg_in_c4_i || remaining_r <= 3'd1);
    assign accept_w = line_wr_valid_i && line_wr_ready_o;
    assign line_wr_idle_o = !expanding_w;
    assign cache_wr_valid_o = !cancel_i && (expanding_w ||
        (!cfg_in_c4_i && line_wr_valid_i));
    assign cache_wr_bank_o = expanding_w ? phase_r[0] : line_wr_bank_i;
    assign cache_wr_addr_o = expanding_w ? addr_r + {9'd0, phase_r[1]} : line_wr_addr_i;
    assign cache_wr_data_o = expanding_w ?
        {96'd0, data_r[63:32], 96'd0, data_r[31:0]} : line_wr_data_i;

    // The fourth write can share its edge with acceptance of the next DMA beat.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            remaining_r <= 3'd0;
            phase_r <= 2'd0;
        end else if (cancel_i) begin
            remaining_r <= 3'd0;
            phase_r <= 2'd0;
        end else if (accept_w && cfg_in_c4_i) begin
            remaining_r <= 3'd4;
            phase_r <= 2'd0;
        end else if (expanding_w) begin
            remaining_r <= remaining_r - 3'd1;
            phase_r <= phase_r + 2'd1;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            line_wr_row_done_o <= 1'b0;
        end else if (cancel_i) begin
            line_wr_row_done_o <= 1'b0;
        end else begin
            line_wr_row_done_o <= cache_wr_valid_o &&
                (expanding_w ? (remaining_r == 3'd1 && row_last_r) : line_wr_row_last_i);
        end
    end

    always @(posedge clk_i) begin
        if (accept_w && cfg_in_c4_i) begin
            data_r <= line_wr_data_i;
            addr_r <= line_wr_addr_i;
            row_last_r <= line_wr_row_last_i;
        end else if (expanding_w) begin
            data_r <= {64'd0, data_r[255:64]};
        end
    end
endmodule
