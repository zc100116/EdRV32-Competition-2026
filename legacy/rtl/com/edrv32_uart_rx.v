// ============================================================================
// File        : edrv32_uart_rx.v
// Description : Synchronized 8-N-1 UART byte receiver.
// ============================================================================

module edrv32_uart_rx #(
    parameter integer CLK_HZ = 27000000,
    parameter integer BAUD = 115200
) (
    input  wire       clk_i,
    input  wire       rst_n_i,
    input  wire       rx_i,
    output wire       data_valid_o,
    output wire [7:0] data_o,
    output wire       frame_error_o
);

    localparam integer BAUD_DIV = (CLK_HZ + BAUD / 2) / BAUD;
    localparam integer COUNT_W = BAUD_DIV <= 2 ? 1 : $clog2(BAUD_DIV);
    localparam [1:0] STATE_IDLE  = 2'd0;
    localparam [1:0] STATE_START = 2'd1;
    localparam [1:0] STATE_DATA  = 2'd2;
    localparam [1:0] STATE_STOP  = 2'd3;

    reg rx_meta_r;
    reg rx_sync_r;
    reg [1:0] state_r;
    reg [COUNT_W-1:0] count_r;
    reg [2:0] bit_index_r;
    reg [7:0] data_r;
    reg data_valid_r;
    reg frame_error_r;

    assign data_valid_o = data_valid_r;
    assign data_o = data_r;
    assign frame_error_o = frame_error_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rx_meta_r <= 1'b1;
            rx_sync_r <= 1'b1;
            state_r <= STATE_IDLE;
            count_r <= {COUNT_W{1'b0}};
            bit_index_r <= 3'b0;
            data_r <= 8'b0;
            data_valid_r <= 1'b0;
            frame_error_r <= 1'b0;
        end else begin
            rx_meta_r <= rx_i;
            rx_sync_r <= rx_meta_r;
            data_valid_r <= 1'b0;
            frame_error_r <= 1'b0;
            case (state_r)
                STATE_IDLE: begin
                    if (!rx_sync_r) begin
                        count_r <= (BAUD_DIV / 2) - 1;
                        state_r <= STATE_START;
                    end
                end
                STATE_START: begin
                    if (count_r != 0) begin
                        count_r <= count_r - 1'b1;
                    end else if (rx_sync_r) begin
                        state_r <= STATE_IDLE;
                    end else begin
                        count_r <= BAUD_DIV - 1;
                        bit_index_r <= 3'b0;
                        state_r <= STATE_DATA;
                    end
                end
                STATE_DATA: begin
                    if (count_r != 0) begin
                        count_r <= count_r - 1'b1;
                    end else begin
                        data_r[bit_index_r] <= rx_sync_r;
                        count_r <= BAUD_DIV - 1;
                        if (bit_index_r == 3'd7)
                            state_r <= STATE_STOP;
                        else
                            bit_index_r <= bit_index_r + 1'b1;
                    end
                end
                STATE_STOP: begin
                    if (count_r != 0) begin
                        count_r <= count_r - 1'b1;
                    end else begin
                        data_valid_r <= rx_sync_r;
                        frame_error_r <= !rx_sync_r;
                        state_r <= STATE_IDLE;
                    end
                end
                default: state_r <= STATE_IDLE;
            endcase
        end
    end

endmodule
