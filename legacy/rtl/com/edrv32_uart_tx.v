// ============================================================================
// File        : edrv32_uart_tx.v
// Description : Small 8-N-1 byte transmitter for standalone board telemetry.
// ============================================================================

module edrv32_uart_tx #(
    parameter integer CLK_HZ = 125000000,
    parameter integer BAUD = 115200
) (
    input  wire       clk_i,
    input  wire       rst_n_i,
    input  wire       data_valid_i,
    output wire       data_ready_o,
    input  wire [7:0] data_i,
    output wire       tx_o
);

    localparam integer BAUD_DIV = (CLK_HZ + BAUD / 2) / BAUD;
    localparam integer BAUD_COUNT_W = BAUD_DIV <= 2 ?
        1 : $clog2(BAUD_DIV);

    reg busy_r;
    reg [9:0] shift_r;
    reg [3:0] bit_r;
    reg [BAUD_COUNT_W-1:0] baud_count_r;

    assign data_ready_o = !busy_r;
    assign tx_o = busy_r ? shift_r[0] : 1'b1;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            busy_r <= 1'b0;
            shift_r <= 10'h3ff;
            bit_r <= 4'b0;
            baud_count_r <= {BAUD_COUNT_W{1'b0}};
        end else if (!busy_r) begin
            if (data_valid_i) begin
                shift_r <= {1'b1, data_i, 1'b0};
                bit_r <= 4'b0;
                baud_count_r <= BAUD_DIV - 1;
                busy_r <= 1'b1;
            end
        end else if (baud_count_r == 0) begin
            baud_count_r <= BAUD_DIV - 1;
            shift_r <= {1'b1, shift_r[9:1]};
            if (bit_r == 4'd9)
                busy_r <= 1'b0;
            else
                bit_r <= bit_r + 1'b1;
        end else begin
            baud_count_r <= baud_count_r - 1'b1;
        end
    end

endmodule
