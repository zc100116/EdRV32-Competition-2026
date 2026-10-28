// File: edrv32_pix_filter.v
// Spec: pix-spec 2.4, 2.7, 2.9, 7.
// Description: Two-pixel RGB888 3x3 stage with two rotating one-cycle line RAMs.
// The previous pair waits for its right neighbor; EOL uses explicit zero padding.
// Clock: clk_mem.
module edrv32_pix_filter (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Input stream.
    input wire valid_i,
    input wire [47:0] data_i,
    input wire sof_i,
    input wire eol_i,
    input wire eof_i,

    // Output stream.
    output wire valid_o,
    output wire [47:0] data_o,
    output wire sof_o,
    output wire eol_o,
    output wire eof_o,

    // Pipeline and frame configuration.
    input wire advance_i,
    input wire clear_i,
    input wire [2:0] op_i
);
    wire enabled_w;
    reg [9:0] column_r;
    reg [9:0] width_r;
    reg [1:0] row_kind_r;
    reg bank_r;
    reg flush_r;
    reg [9:0] flush_column_r;
    wire request_w;
    wire [9:0] request_column_w;
    wire request_last_w;
    wire request_bank_w;
    wire [1:0] request_row_w;
    wire wr0_w;
    wire wr1_w;
    wire forward0_w;
    wire forward1_w;
    wire [47:0] ram0_w;
    wire [47:0] ram1_w;

    reg read_valid_r;
    reg [47:0] read_data_r;
    reg [9:0] read_column_r;
    reg [1:0] read_row_r;
    reg read_bank_r;
    reg read_last_r;
    reg read_flush_r;
    reg read_forward0_r;
    reg read_forward1_r;
    reg [47:0] read_forward_data_r;
    // Capture raw DRM outputs before forwarding, bank selection or window logic.
    reg [47:0] capture_ram0_r;
    reg [47:0] capture_ram1_r;
    reg capture_valid_r;
    reg [47:0] capture_data_r;
    reg [9:0] capture_column_r;
    reg [1:0] capture_row_r;
    reg capture_bank_r;
    reg capture_last_r;
    reg capture_flush_r;
    reg capture_forward0_r;
    reg capture_forward1_r;
    reg [47:0] capture_forward_data_r;
    reg [7:0] kernel_valid_r;
    reg [7:0] kernel_sof_r;
    reg [7:0] kernel_eol_r;
    reg [7:0] kernel_eof_r;
    reg bypass_valid_r;
    reg [47:0] bypass_data_r;
    reg bypass_sof_r;
    reg bypass_eol_r;
    reg bypass_eof_r;
    wire [47:0] line0_w;
    wire [47:0] line1_w;
    wire [47:0] top_w;
    wire [47:0] middle_w;
    wire [47:0] bottom_w;

    reg pending_r;
    reg pending_sof_r;
    reg pending_eol_r;
    reg pending_eof_r;
    reg [47:0] top_r;
    reg [47:0] middle_r;
    reg [47:0] bottom_r;
    reg [23:0] top_left_r;
    reg [23:0] middle_left_r;
    reg [23:0] bottom_left_r;
    wire emit_w;
    wire [23:0] right_top_w;
    wire [23:0] right_middle_w;
    wire [23:0] right_bottom_w;
    wire [215:0] window0_w;
    wire [215:0] window1_w;
    wire [47:0] result_w;

    assign enabled_w = op_i != 3'd0 && op_i != 3'd7;
    assign request_w = enabled_w && (valid_i || flush_r);
    assign request_column_w = flush_r ? flush_column_r : column_r;
    assign request_last_w = flush_r ? flush_column_r == width_r : eol_i;
    assign request_bank_w = bank_r;
    assign request_row_w = row_kind_r;
    assign wr0_w = advance_i && !clear_i && read_valid_r && !read_flush_r
        && !read_bank_r;
    assign wr1_w = advance_i && !clear_i && read_valid_r && !read_flush_r
        && read_bank_r;
    // A one-beat line reads the preceding delayed write: forward it explicitly.
    // Suppressing that read honors the RAM wrapper's undefined collision contract.
    assign forward0_w = wr0_w && read_column_r == request_column_w;
    assign forward1_w = wr1_w && read_column_r == request_column_w;

    edrv32_ram_pix_line u_line0 (
        .clk_i(clk_i),

        .wr_en_i(wr0_w),
        .wr_addr_i(read_column_r),
        .wr_data_i(read_data_r),

        .rd_en_i(advance_i && !clear_i && request_w && !forward0_w),
        .rd_addr_i(request_column_w),
        .rd_data_o(ram0_w)
    );

    edrv32_ram_pix_line u_line1 (
        .clk_i(clk_i),

        .wr_en_i(wr1_w),
        .wr_addr_i(read_column_r),
        .wr_data_i(read_data_r),

        .rd_en_i(advance_i && !clear_i && request_w && !forward1_w),
        .rd_addr_i(request_column_w),
        .rd_data_o(ram1_w)
    );

    assign line0_w = capture_forward0_r ? capture_forward_data_r : capture_ram0_r;
    assign line1_w = capture_forward1_r ? capture_forward_data_r : capture_ram1_r;
    assign top_w = capture_row_r == 2'd2 ? (capture_bank_r ? line1_w : line0_w) : 48'd0;
    assign middle_w = capture_row_r != 2'd0 ? (capture_bank_r ? line0_w : line1_w) : 48'd0;
    assign bottom_w = capture_flush_r ? 48'd0 : capture_data_r;
    assign emit_w = pending_r && (capture_valid_r || pending_eol_r);
    assign right_top_w = pending_eol_r ? 24'd0 : top_w[23:0];
    assign right_middle_w = pending_eol_r ? 24'd0 : middle_w[23:0];
    assign right_bottom_w = pending_eol_r ? 24'd0 : bottom_w[23:0];
    assign window0_w = {bottom_r, bottom_left_r, middle_r, middle_left_r,
        top_r, top_left_r};
    assign window1_w = {right_bottom_w, bottom_r,
        right_middle_w, middle_r, right_top_w, top_r};

    edrv32_pix_kernel u_kernel0 (
        .clk_i(clk_i),
        .advance_i(advance_i),

        .window_i(window0_w),

        .data_o(result_w[23:0]),

        .op_i(op_i)
    );

    edrv32_pix_kernel u_kernel1 (
        .clk_i(clk_i),
        .advance_i(advance_i),

        .window_i(window1_w),

        .data_o(result_w[47:24]),

        .op_i(op_i)
    );

    assign valid_o = enabled_w ? kernel_valid_r[7] : bypass_valid_r;
    assign data_o = enabled_w ? result_w : bypass_data_r;
    assign sof_o = enabled_w ? kernel_sof_r[7] : bypass_sof_r;
    assign eol_o = enabled_w ? kernel_eol_r[7] : bypass_eol_r;
    assign eof_o = enabled_w ? kernel_eof_r[7] : bypass_eof_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            column_r <= 10'd0;
            width_r <= 10'd0;
            row_kind_r <= 2'd0;
            bank_r <= 1'b0;
            flush_r <= 1'b0;
            flush_column_r <= 10'd0;
            read_valid_r <= 1'b0;
            pending_r <= 1'b0;
            capture_valid_r <= 1'b0;
            kernel_valid_r <= 8'd0;
            bypass_valid_r <= 1'b0;
        end else if (clear_i) begin
            column_r <= 10'd0;
            width_r <= 10'd0;
            row_kind_r <= 2'd0;
            bank_r <= 1'b0;
            flush_r <= 1'b0;
            flush_column_r <= 10'd0;
            read_valid_r <= 1'b0;
            pending_r <= 1'b0;
            capture_valid_r <= 1'b0;
            kernel_valid_r <= 8'd0;
            bypass_valid_r <= 1'b0;
        end else if (advance_i) begin
            read_valid_r <= request_w;
            capture_valid_r <= read_valid_r;
            bypass_valid_r <= valid_i;
            kernel_valid_r <= {kernel_valid_r[6:0], emit_w};
            if (emit_w) begin
                pending_r <= 1'b0;
            end
            if (capture_valid_r) begin
                pending_r <= capture_row_r != 2'd0;
            end
            if (request_w) begin
                if (request_last_w) begin
                    column_r <= 10'd0;
                    bank_r <= !bank_r;
                    if (row_kind_r != 2'd2) begin
                        row_kind_r <= row_kind_r + 2'd1;
                    end
                end else if (!flush_r) begin
                    column_r <= column_r + 10'd1;
                end
                if (!flush_r && eol_i && row_kind_r == 2'd0) begin
                    width_r <= column_r;
                end
                if (!flush_r && eof_i) begin
                    flush_r <= 1'b1;
                    flush_column_r <= 10'd0;
                end else if (flush_r) begin
                    flush_column_r <= flush_column_r + 10'd1;
                    if (request_last_w) begin
                        flush_r <= 1'b0;
                    end
                end
            end
            // The next frame arrives only after all pipeline outputs have drained.
            if (valid_o && eof_o) begin
                column_r <= 10'd0;
                row_kind_r <= 2'd0;
                bank_r <= 1'b0;
            end
        end
    end

    always @(posedge clk_i) begin
        if (advance_i) begin
            if (request_w) begin
                read_data_r <= data_i;
                read_column_r <= request_column_w;
                read_row_r <= request_row_w;
                read_bank_r <= request_bank_w;
                read_last_r <= request_last_w;
                read_flush_r <= flush_r;
                read_forward0_r <= forward0_w;
                read_forward1_r <= forward1_w;
                read_forward_data_r <= read_data_r;
            end
            if (capture_valid_r) begin
                top_r <= top_w;
                middle_r <= middle_w;
                bottom_r <= bottom_w;
                top_left_r <= capture_column_r == 10'd0 ? 24'd0 : top_r[47:24];
                middle_left_r <= capture_column_r == 10'd0 ? 24'd0 : middle_r[47:24];
                bottom_left_r <= capture_column_r == 10'd0 ? 24'd0 : bottom_r[47:24];
                pending_sof_r <= capture_row_r == 2'd1 && capture_column_r == 10'd0;
                pending_eol_r <= capture_last_r;
                pending_eof_r <= capture_flush_r && capture_last_r;
            end
            capture_ram0_r <= ram0_w;
            capture_ram1_r <= ram1_w;
            capture_data_r <= read_data_r;
            capture_column_r <= read_column_r;
            capture_row_r <= read_row_r;
            capture_bank_r <= read_bank_r;
            capture_last_r <= read_last_r;
            capture_flush_r <= read_flush_r;
            capture_forward0_r <= read_forward0_r;
            capture_forward1_r <= read_forward1_r;
            capture_forward_data_r <= read_forward_data_r;
            kernel_sof_r <= {kernel_sof_r[6:0], pending_sof_r};
            kernel_eol_r <= {kernel_eol_r[6:0], pending_eol_r};
            kernel_eof_r <= {kernel_eof_r[6:0], pending_eof_r};
            bypass_data_r <= data_i;
            bypass_sof_r <= sof_i;
            bypass_eol_r <= eol_i;
            bypass_eof_r <= eof_i;
        end
    end
endmodule
