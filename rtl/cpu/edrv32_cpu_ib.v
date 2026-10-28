// File: edrv32_cpu_ib.v
// Spec: cpu-spec 4.1, 4.2
// Description: Queue instruction records between F2 and D in program order.
// Accept up to two records and retire up to two queue entries per clock.
// Clock domain: clk_sys.
module edrv32_cpu_ib (
    // Clock and queue control reset.
    input wire clk_i,
    input wire rst_n_i,
    // F2 input: each 179-bit record is described in rtl/cpu/README.md.
    input wire [1:0] push_count_i,
    input wire [357:0] push_data_i,
    output wire [2:0] free_count_o,
    // D observes the oldest two records and consumes 0, 1 or 2.
    input wire [1:0] pop_count_i,
    output wire [357:0] data_o,
    output wire [1:0] valid_count_o,
    // A stalled D redirect retains its head; older redirects discard the whole queue.
    input wire flush_i,
    input wire keep_head_i,
    output wire [2:0] count_o
);
    localparam RECORD_BITS = 179;
    localparam [2:0] DEPTH = 3'd4;
    reg [RECORD_BITS-1:0] entries_r [0:DEPTH-1];
    reg [1:0] read_ptr_r;
    reg [1:0] write_ptr_r;
    reg [2:0] count_r;
    wire [1:0] read_next_w;
    wire [1:0] write_next_w;
    assign read_next_w = read_ptr_r + 1'b1;
    assign write_next_w = write_ptr_r + 1'b1;
    assign data_o = {entries_r[read_next_w], entries_r[read_ptr_r]};
    assign valid_count_o = count_r >= 2 ? 2'd2 : count_r[1:0];
    // cpu-spec 4.1: only slots empty at cycle start can accept F2 records.
    assign free_count_o = DEPTH - count_r;
    assign count_o = count_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            read_ptr_r <= 0;
            write_ptr_r <= 0;
            count_r <= 0;
        end else if (flush_i) begin
            read_ptr_r <= keep_head_i ? read_ptr_r : 2'd0;
            write_ptr_r <= keep_head_i ? read_next_w : 2'd0;
            count_r <= keep_head_i ? 3'd1 : 3'd0;
        end else begin
            read_ptr_r <= read_ptr_r + pop_count_i;
            write_ptr_r <= write_ptr_r + push_count_i;
            count_r <= count_r + {1'b0, push_count_i} - {1'b0, pop_count_i};
        end
    end
    always @(posedge clk_i) begin
        if (!flush_i) begin
            if (push_count_i != 0)
                entries_r[write_ptr_r] <= push_data_i[178:0];
            if (push_count_i == 2)
                entries_r[write_next_w] <= push_data_i[357:179];
        end
    end
endmodule
