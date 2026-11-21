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
    reg write_valid_r;
    reg write_last_r;
    reg write_bank_r;
    reg [9:0] write_addr_r;
    reg [255:0] write_data_r;
    wire decode_valid_w;
    wire accept_w;
    wire expanding_w;
    wire [255:0] expanded_data_w;
    wire [255:0] shifted_data_w;

    assign expanding_w = remaining_r != 3'd0;
    assign line_wr_ready_o = !cancel_i && (!cfg_in_c4_i || remaining_r <= 3'd1);
    assign accept_w = line_wr_valid_i && line_wr_ready_o;
    assign line_wr_idle_o = !expanding_w && !write_valid_r;
    assign decode_valid_w = !cancel_i && (expanding_w ||
        (!cfg_in_c4_i && line_wr_valid_i));
    assign cache_wr_valid_o = write_valid_r && !cancel_i;
    assign cache_wr_bank_o = write_bank_r;
    assign cache_wr_addr_o = write_addr_r;
    assign cache_wr_data_o = write_data_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            write_valid_r <= 1'b0;
        end else if (cancel_i) begin
            write_valid_r <= 1'b0;
        end else begin
            write_valid_r <= decode_valid_w;
        end
    end
    // Selection and address carry end here; the next edge is a local RAM write.
    always @(posedge clk_i) begin
        write_bank_r <= expanding_w ? phase_r[0] : line_wr_bank_i;
        write_addr_r <= expanding_w ? addr_r + {9'd0, phase_r[1]} : line_wr_addr_i;
        write_last_r <= expanding_w ? (remaining_r == 3'd1 && row_last_r)
            : line_wr_row_last_i;
    end

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
                write_last_r;
        end
    end

    always @(posedge clk_i) begin
        if (accept_w && cfg_in_c4_i) begin
            addr_r <= line_wr_addr_i;
            row_last_r <= line_wr_row_last_i;
        end
    end
    assign expanded_data_w = {96'd0, data_r[63:32], 96'd0, data_r[31:0]};
    assign shifted_data_w = {64'd0, data_r[255:64]};
    genvar slice;
    generate
        for (slice = 0; slice < 8; slice = slice + 1) begin : g_write_slice
            (* keep = "true", syn_keep = 1 *) wire local_expanding_w;
            (* keep = "true", syn_keep = 1 *) wire capture_w;
            (* keep = "true", syn_keep = 1 *) wire shift_w;
            assign local_expanding_w = remaining_r != 3'd0;
            assign shift_w = remaining_r != 3'd0;
            assign capture_w = line_wr_valid_i && !cancel_i && cfg_in_c4_i
                && remaining_r <= 3'd1;
            always @(posedge clk_i) begin
                write_data_r[32*slice +: 32] <= local_expanding_w
                    ? expanded_data_w[32*slice +: 32] : line_wr_data_i[32*slice +: 32];
                if (capture_w) begin
                    data_r[32*slice +: 32] <= line_wr_data_i[32*slice +: 32];
                end else if (shift_w) begin
                    data_r[32*slice +: 32] <= shifted_data_w[32*slice +: 32];
                end
            end
        end
    endgenerate
endmodule
