// ============================================================================
// File        : edrv32_vision_uart_command.v
// Description : Decode mode, point and geometry ASCII UART commands.
// Notes       : CR/LF is optional. A short inter-byte idle gap commits a
//               numeric command; A and S act immediately.
// ============================================================================

module edrv32_vision_uart_command #(
    parameter integer CLK_HZ = 27000000,
    parameter integer GAP_MS = 10
) (
    input  wire       clk_i,
    input  wire       rst_n_i,
    input  wire       data_valid_i,
    input  wire [7:0] data_i,
    output wire       command_valid_o,
    output wire [2:0] command_kind_o,
    output wire [15:0] command_value_o
);

    localparam [1:0] STATE_IDLE    = 2'd0;
    localparam [1:0] STATE_NUMBER  = 2'd1;
    localparam [1:0] STATE_DISCARD = 2'd2;
    localparam [2:0] KIND_MODE     = 3'd0;
    localparam [2:0] KIND_POINT    = 3'd1;
    localparam [2:0] KIND_AUTO     = 3'd2;
    localparam [2:0] KIND_STOP     = 3'd3;
    localparam [2:0] KIND_ANGLE    = 3'd4;
    localparam [2:0] KIND_WIDTH    = 3'd5;
    localparam [2:0] KIND_HEIGHT   = 3'd6;
    localparam integer GAP_CYCLES = (CLK_HZ / 1000) * GAP_MS;
    localparam integer GAP_COUNT_W = GAP_CYCLES <= 2 ? 1 :
        $clog2(GAP_CYCLES);

    reg [1:0] state_r;
    reg [2:0] kind_r;
    reg [15:0] value_r;
    reg [2:0] digit_count_r;
    reg [GAP_COUNT_W-1:0] gap_count_r;
    reg command_valid_r;
    reg [2:0] command_kind_r;
    reg [15:0] command_value_r;

    wire digit_w = (data_i >= 8'h30) && (data_i <= 8'h39);
    wire end_line_w = (data_i == 8'h0d) || (data_i == 8'h0a);
    wire [19:0] digit_value_w = {16'b0, data_i[3:0]};
    wire [19:0] next_value_w = ({4'b0, value_r} << 3) +
        ({4'b0, value_r} << 1) + digit_value_w;
    wire command_legal_w = (digit_count_r != 0) &&
        (((kind_r == KIND_MODE) && (value_r <= 16'd31)) ||
         ((kind_r == KIND_POINT) && (value_r <= 16'd7)) ||
         ((kind_r == KIND_ANGLE) && (value_r <= 16'd359)) ||
         ((kind_r == KIND_WIDTH) &&
          (value_r >= 16'd640) && (value_r <= 16'd2560)) ||
         ((kind_r == KIND_HEIGHT) &&
          (value_r >= 16'd360) && (value_r <= 16'd1440)));

    assign command_valid_o = command_valid_r;
    assign command_kind_o = command_kind_r;
    assign command_value_o = command_value_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= STATE_IDLE;
            kind_r <= KIND_MODE;
            value_r <= 16'b0;
            digit_count_r <= 3'b0;
            gap_count_r <= {GAP_COUNT_W{1'b0}};
            command_valid_r <= 1'b0;
            command_kind_r <= KIND_MODE;
            command_value_r <= 16'b0;
        end else begin
            command_valid_r <= 1'b0;
            if (data_valid_i) begin
                gap_count_r <= {GAP_COUNT_W{1'b0}};
                case (state_r)
                    STATE_IDLE: begin
                        if ((data_i == "M") || (data_i == "m") ||
                            (data_i == "P") || (data_i == "p") ||
                            (data_i == "R") || (data_i == "r") ||
                            (data_i == "X") || (data_i == "x") ||
                            (data_i == "Y") || (data_i == "y")) begin
                            kind_r <= ((data_i == "P") || (data_i == "p")) ?
                                KIND_POINT :
                                ((data_i == "R") || (data_i == "r")) ?
                                KIND_ANGLE :
                                ((data_i == "X") || (data_i == "x")) ?
                                KIND_WIDTH :
                                ((data_i == "Y") || (data_i == "y")) ?
                                KIND_HEIGHT : KIND_MODE;
                            value_r <= 16'b0;
                            digit_count_r <= 3'b0;
                            state_r <= STATE_NUMBER;
                        end else if ((data_i == "A") || (data_i == "a")) begin
                            command_valid_r <= 1'b1;
                            command_kind_r <= KIND_AUTO;
                            command_value_r <= 16'b0;
                        end else if ((data_i == "S") || (data_i == "s")) begin
                            command_valid_r <= 1'b1;
                            command_kind_r <= KIND_STOP;
                            command_value_r <= 16'b0;
                        end else if (!end_line_w) begin
                            state_r <= STATE_DISCARD;
                        end
                    end
                    STATE_NUMBER: begin
                        if (digit_w) begin
                            if ((digit_count_r < 3'd4) &&
                                (next_value_w <= 20'd9999)) begin
                                value_r <= next_value_w[15:0];
                                digit_count_r <= digit_count_r + 1'b1;
                            end else begin
                                state_r <= STATE_DISCARD;
                            end
                        end else if (end_line_w) begin
                            if (command_legal_w) begin
                                command_valid_r <= 1'b1;
                                command_kind_r <= kind_r;
                                command_value_r <= value_r;
                            end
                            state_r <= STATE_IDLE;
                        end else begin
                            state_r <= STATE_DISCARD;
                        end
                    end
                    STATE_DISCARD: begin
                        if (end_line_w)
                            state_r <= STATE_IDLE;
                    end
                    default: state_r <= STATE_IDLE;
                endcase
            end else if ((state_r == STATE_NUMBER) ||
                         (state_r == STATE_DISCARD)) begin
                if (gap_count_r == GAP_CYCLES - 1) begin
                    gap_count_r <= {GAP_COUNT_W{1'b0}};
                    if ((state_r == STATE_NUMBER) && command_legal_w) begin
                        command_valid_r <= 1'b1;
                        command_kind_r <= kind_r;
                        command_value_r <= value_r;
                    end
                    state_r <= STATE_IDLE;
                end else begin
                    gap_count_r <= gap_count_r + 1'b1;
                end
            end
        end
    end

endmodule
