// File: edrv32_sync_fifo_ram.v
// Spec: edrv32-soc-spec 5.2, 5.3; vin-spec 2.3, 2.6; disp-spec 2.6.
// Description: Ready/valid FIFO controller for external one-cycle-read RAM.
//              A held head and RAM output provide elastic prefetch and full throughput.
// Clock domain: clk_i.
module edrv32_sync_fifo_ram #(
    parameter WIDTH = 32,
    parameter DEPTH = 16
) (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Producer input (write domain).
    input wire valid_i,
    output wire ready_o,
    input wire [WIDTH-1:0] data_i,

    // Consumer output (read domain).
    output wire valid_o,
    input wire ready_i,
    output wire [WIDTH-1:0] data_o,

    // External RAM write port (write domain).
    output wire wr_en_o,
    output wire [$clog2(DEPTH)-1:0] wr_addr_o,
    output wire [WIDTH-1:0] wr_data_o,

    // External RAM enabled read port (read domain), latency one.
    output wire rd_en_o,
    output wire [$clog2(DEPTH)-1:0] rd_addr_o,
    input wire [WIDTH-1:0] rd_data_i
);
    localparam PTR_WIDTH = $clog2(DEPTH);
    reg [PTR_WIDTH:0] write_bin_r;
    reg [PTR_WIDTH:0] read_bin_r;
    reg [PTR_WIDTH:0] fetch_bin_r;
    reg head_valid_r;
    reg pending_r;
    reg [WIDTH-1:0] head_data_r;
    wire write_w;
    wire read_w;
    wire head_load_w;
    wire pending_hold_w;
    wire [PTR_WIDTH:0] write_next_w;
    wire [PTR_WIDTH:0] read_next_w;

    assign ready_o = (write_bin_r != (read_bin_r ^ {1'b1, {PTR_WIDTH{1'b0}}}));
    assign rd_en_o = (fetch_bin_r != write_bin_r) && !pending_hold_w;
    assign valid_o = head_valid_r || pending_r;
    assign data_o = head_valid_r ? head_data_r : rd_data_i;
    assign write_w = valid_i && ready_o;
    assign read_w = valid_o && ready_i;
    assign write_next_w = write_bin_r + {{PTR_WIDTH{1'b0}}, write_w};
    assign read_next_w = read_bin_r + {{PTR_WIDTH{1'b0}}, read_w};
    assign wr_en_o = write_w;
    assign wr_addr_o = write_bin_r[PTR_WIDTH-1:0];
    assign wr_data_o = data_i;
    assign rd_addr_o = fetch_bin_r[PTR_WIDTH-1:0];

    // Keep RAM's output while both slots are occupied and the consumer stalls.
    // Otherwise move it into the head when needed, or consume it directly.
    assign pending_hold_w = pending_r && head_valid_r && !read_w;
    assign head_load_w = pending_r && (head_valid_r ? read_w : !ready_i);

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            write_bin_r <= {(PTR_WIDTH+1){1'b0}};
        end else begin
            write_bin_r <= write_next_w;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            read_bin_r <= {(PTR_WIDTH+1){1'b0}};
            fetch_bin_r <= {(PTR_WIDTH+1){1'b0}};
            head_valid_r <= 1'b0;
            pending_r <= 1'b0;
        end else begin
            read_bin_r <= read_next_w;
            if (rd_en_o) begin
                fetch_bin_r <= fetch_bin_r + 1'b1;
            end
            head_valid_r <= head_load_w || (head_valid_r && !read_w);
            pending_r <= rd_en_o || pending_hold_w;
        end
    end

    always @(posedge clk_i) begin
        if (head_load_w) begin
            head_data_r <= rd_data_i;
        end
    end
endmodule
