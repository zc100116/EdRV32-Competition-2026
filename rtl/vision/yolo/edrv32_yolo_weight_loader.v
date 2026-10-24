// ============================================================================
// File        : edrv32_yolo_weight_loader.v
// Description : Load one 32-output-channel weight tile from DDR.
// Notes       : DDR tile order is [K row][8 output-channel banks], one 256-bit
//               beat per bank. The tile store accepts one beat per clock.
// ============================================================================

module edrv32_yolo_weight_loader (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [31:0]  weight_addr_i,
    input  wire [9:0]   k_count_i,
    output wire         rd_req_valid_o,
    input  wire         rd_req_ready_i,
    output wire [31:0]  rd_req_addr_o,
    output wire [15:0]  rd_req_beats_o,
    input  wire         rd_beat_valid_i,
    input  wire [15:0]  rd_beat_index_i,
    input  wire [255:0] rd_beat_data_i,
    input  wire         rd_done_i,
    input  wire         rd_error_i,
    output wire         weight_valid_o,
    input  wire         weight_ready_i,
    output wire [11:0]  weight_addr_o,
    output wire [255:0] weight_data_o,
    output wire         busy_o,
    output wire         done_o,
    output wire         error_o
);

    localparam [1:0] IDLE = 2'd0;
    localparam [1:0] ISSUE = 2'd1;
    localparam [1:0] WAIT_READ = 2'd2;
    reg [1:0] state_r;
    reg done_r;
    reg error_r;
    reg [31:0] weight_addr_r;
    reg [9:0] k_count_r;

    assign start_ready_o = state_r == IDLE && k_count_i != 10'd0 &&
                           k_count_i <= 10'd512;
    assign rd_req_valid_o = state_r == ISSUE;
    assign rd_req_addr_o = weight_addr_r;
    assign rd_req_beats_o = {3'd0, k_count_r, 3'd0};
    assign weight_valid_o = state_r == WAIT_READ && rd_beat_valid_i;
    assign weight_addr_o = rd_beat_index_i[11:0];
    assign weight_data_o = rd_beat_data_i;
    assign busy_o = state_r != IDLE;
    assign done_o = done_r;
    assign error_o = error_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r       <= IDLE;
            done_r        <= 1'b0;
            error_r       <= 1'b0;
            weight_addr_r <= 32'd0;
            k_count_r     <= 10'd0;
        end else begin
            done_r <= 1'b0;
            if (start_i && start_ready_o) begin
                state_r       <= ISSUE;
                error_r       <= 1'b0;
                weight_addr_r <= weight_addr_i;
                k_count_r     <= k_count_i;
            end else begin
                case (state_r)
                    ISSUE: if (rd_req_valid_o && rd_req_ready_i)
                        state_r <= WAIT_READ;
                    WAIT_READ: begin
                        if (rd_beat_valid_i && !weight_ready_i)
                            error_r <= 1'b1;
                        if (rd_done_i) begin
                            if (rd_error_i)
                                error_r <= 1'b1;
                            state_r <= IDLE;
                            done_r <= 1'b1;
                        end
                    end
                    default: state_r <= IDLE;
                endcase
            end
        end
    end
endmodule
