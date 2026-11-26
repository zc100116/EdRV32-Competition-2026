// File: edrv32_gpu_target_store.v
// Spec: gpu-spec 2.1; GPU microarchitecture 4.4, 4.7, 4.8.
// Description: 14 nine-chip segments and a three-chip tail, five-stage read tree.
// Read credits reserve response storage; sampling captures logical write bypass.
// Clock: clk_gpu.
module edrv32_gpu_target_store (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Read requests; metadata follows the same ordered response.
    input wire read_valid_i,
    output wire read_ready_o,
    input wire [15:0] read_addr_i,
    input wire [5:0] read_meta_i,
    output wire old_valid_o,
    input wire old_ready_i,
    output wire [159:0] old_data_o,
    output wire [15:0] old_addr_o,
    output wire [5:0] old_meta_o,

    // Complete-word logical commits.
    input wire write_valid_i,
    input wire [15:0] write_addr_i,
    input wire [159:0] write_data_i,
    output wire idle_o
);
    reg [3:0] valid_r;
    reg [15:0] addr_r [0:3];
    reg [5:0] meta_r [0:3];
    reg write_valid_r;
    reg [15:0] write_addr_r;
    reg [159:0] write_data_r;
    reg recent_valid_r;
    reg [15:0] recent_addr_r;
    reg [159:0] recent_data_r;
    reg [1:0] bypass_valid_r;
    reg [159:0] bypass_data_r [0:1];
    wire [159:0] segment_data_w [0:14];
    reg [159:0] group_data_r [0:3];
    wire [159:0] selected_w;
    reg [159:0] fifo_data_r [0:15];
    reg [15:0] fifo_addr_r [0:15];
    reg [5:0] fifo_meta_r [0:15];
    reg [3:0] wr_ptr_r;
    reg [3:0] rd_ptr_r;
    reg [4:0] count_r;
    reg [4:0] reserved_r;
    wire push_w;
    wire pop_w;
    wire accept_w;
    integer stage;
    genvar segment;
    genvar chip;
    assign read_ready_o = reserved_r < 5'd16;
    assign accept_w = read_valid_i && read_ready_o;
    assign push_w = valid_r[3];
    assign pop_w = old_valid_o && old_ready_i;
    assign old_valid_o = count_r != 0;
    assign old_data_o = fifo_data_r[rd_ptr_r];
    assign old_addr_o = fifo_addr_r[rd_ptr_r];
    wire [23:0] meta_quarters_w;
    genvar meta_quarter;
    generate
        for (meta_quarter = 0; meta_quarter < 4; meta_quarter = meta_quarter + 1)
        begin : g_meta_select
            assign meta_quarters_w[meta_quarter*6 +: 6] = rd_ptr_r[1] ?
                (rd_ptr_r[0] ? fifo_meta_r[meta_quarter*4+3] :
                fifo_meta_r[meta_quarter*4+2]) :
                (rd_ptr_r[0] ? fifo_meta_r[meta_quarter*4+1] : fifo_meta_r[meta_quarter*4]);
        end
    endgenerate
    assign old_meta_o = rd_ptr_r[3] ?
        (rd_ptr_r[2] ? meta_quarters_w[18 +: 6] : meta_quarters_w[12 +: 6]) :
        (rd_ptr_r[2] ? meta_quarters_w[6 +: 6] : meta_quarters_w[0 +: 6]);
    assign idle_o = reserved_r == 0 && !write_valid_r;
    assign selected_w = group_data_r[addr_r[3][14:13]];

    reg tail_read_enable_r;
    reg tail_write_enable_r;
    reg [8:0] tail_read_row_r;
    reg [8:0] tail_write_row_r;
    reg [159:0] tail_write_word_r;
    wire tail_read_w;
    wire tail_write_w;
    wire [215:0] tail_padded_w;
    assign tail_read_w = accept_w && read_addr_i[15:11] == 5'd14;
    assign tail_write_w = write_valid_i && write_addr_i[15:11] == 5'd14;
    assign tail_padded_w = {56'b0, tail_write_word_r};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            tail_read_enable_r <= 0;
            tail_write_enable_r <= 0;
        end else begin
            tail_read_enable_r <= tail_read_w;
            tail_write_enable_r <= tail_write_w;
        end
    end
    always @(posedge clk_i) begin
        if (tail_read_w) begin
            tail_read_row_r <= read_addr_i[8:0];
        end
        if (tail_write_w) begin
            tail_write_row_r <= write_addr_i[8:0];
            tail_write_word_r <= write_data_i;
        end
    end
    generate
        for (segment = 0; segment < 14; segment = segment + 1) begin : g_segment
            wire [161:0] data_w;
            reg read_enable_r;
            reg write_enable_r;
            reg [10:0] read_row_r;
            reg [10:0] write_row_r;
            reg [159:0] write_word_r;
            wire [161:0] padded_w;
            wire select_read_w;
            wire select_write_w;
            assign select_read_w = accept_w && read_addr_i[15:11] == segment;
            assign select_write_w = write_valid_i && write_addr_i[15:11] == segment;
            assign padded_w = {2'b0, write_word_r};
            // Local enables/addresses keep each control copy within its nine RAMs.
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    read_enable_r <= 0;
                    write_enable_r <= 0;
                end else begin
                    read_enable_r <= select_read_w;
                    write_enable_r <= select_write_w;
                end
            end
            always @(posedge clk_i) begin
                if (select_read_w) begin
                    read_row_r <= read_addr_i[10:0];
                end
                if (select_write_w) begin
                    write_row_r <= write_addr_i[10:0];
                    write_word_r <= write_data_i;
                end
            end
            for (chip = 0; chip < 9; chip = chip + 1) begin : g_chip
                edrv32_ram_gpu_target_segment u_ram (
                    .clk_i(clk_i),
                    .wr_en_i(write_enable_r),
                    .wr_addr_i(write_row_r),
                    .wr_data_i(padded_w[chip*18 +: 18]),
                    .rd_en_i(read_enable_r),
                    .rd_addr_i(read_row_r),
                    .rd_data_o(data_w[chip*18 +: 18])
                );
            end
            wire [1:0] unused_padding_w;
            assign unused_padding_w = data_w[161:160];
            assign segment_data_w[segment] = data_w[159:0];
        end
        for (chip = 0; chip < 3; chip = chip + 1) begin : g_tail
            wire [71:0] data_w;
            edrv32_ram_gpu_target_tail u_ram (
                .clk_i(clk_i),
                .wr_en_i(tail_write_enable_r),
                .wr_addr_i(tail_write_row_r),
                .wr_data_i(tail_padded_w[chip*72 +: 72]),
                .rd_en_i(tail_read_enable_r),
                .rd_addr_i(tail_read_row_r),
                .rd_data_o(data_w)
            );
            if (chip < 2) begin : g_full
                assign segment_data_w[14][chip*72 +: 72] = data_w;
            end else begin : g_partial
                wire [55:0] unused_padding_w;
                assign unused_padding_w = data_w[71:16];
                assign segment_data_w[14][159:144] = data_w[15:0];
            end
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_r <= 0;
            bypass_valid_r <= 0;
            write_valid_r <= 0;
            recent_valid_r <= 0;
            wr_ptr_r <= 0;
            rd_ptr_r <= 0;
            count_r <= 0;
            reserved_r <= 0;
        end else begin
            valid_r <= {valid_r[2:0], accept_w};
            write_valid_r <= write_valid_i;
            if (write_valid_r) begin
                recent_valid_r <= 1;
            end
            bypass_valid_r[0] <= valid_r[0] &&
                ((write_valid_r && write_addr_r == addr_r[0]) ||
                (recent_valid_r && recent_addr_r == addr_r[0]));
            bypass_valid_r[1] <= bypass_valid_r[0];
            if (push_w) begin
                wr_ptr_r <= wr_ptr_r + 1'b1;
            end
            if (pop_w) begin
                rd_ptr_r <= rd_ptr_r + 1'b1;
            end
            if (push_w && !pop_w) begin
                count_r <= count_r + 1'b1;
            end else if (!push_w && pop_w) begin
                count_r <= count_r - 1'b1;
            end
            if (accept_w && !pop_w) begin
                reserved_r <= reserved_r + 1'b1;
            end else if (!accept_w && pop_w) begin
                reserved_r <= reserved_r - 1'b1;
            end
        end
    end
    always @(posedge clk_i) begin
        if (accept_w) begin
            addr_r[0] <= read_addr_i;
            meta_r[0] <= read_meta_i;
        end
        for (stage = 1; stage < 4; stage = stage + 1) begin
            addr_r[stage] <= addr_r[stage-1];
            meta_r[stage] <= meta_r[stage-1];
        end
        if (write_valid_i) begin
            write_addr_r <= write_addr_i;
            write_data_r <= write_data_i;
        end
        if (write_valid_r) begin
            recent_addr_r <= write_addr_r;
            recent_data_r <= write_data_r;
        end
        bypass_data_r[0] <= write_valid_r && write_addr_r == addr_r[0] ?
            write_data_r : recent_data_r;
        bypass_data_r[1] <= bypass_data_r[0];
        group_data_r[0] <= bypass_valid_r[1] ? bypass_data_r[1] :
            segment_data_w[{2'b0, addr_r[2][12:11]}];
        group_data_r[1] <= bypass_valid_r[1] ? bypass_data_r[1] :
            segment_data_w[{2'b1, addr_r[2][12:11]}];
        group_data_r[2] <= bypass_valid_r[1] ? bypass_data_r[1] :
            segment_data_w[{2'd2, addr_r[2][12:11]}];
        if (push_w) begin
            fifo_data_r[wr_ptr_r] <= selected_w;
            fifo_addr_r[wr_ptr_r] <= addr_r[3];
            fifo_meta_r[wr_ptr_r] <= meta_r[3];
        end
        // The last group has only three physical segments.
        case (addr_r[2][12:11])
            2'd0: group_data_r[3] <= bypass_valid_r[1] ? bypass_data_r[1] : segment_data_w[12];
            2'd1: group_data_r[3] <= bypass_valid_r[1] ? bypass_data_r[1] : segment_data_w[13];
            default: group_data_r[3] <= bypass_valid_r[1] ? bypass_data_r[1] :
                segment_data_w[14];
        endcase
    end
endmodule
