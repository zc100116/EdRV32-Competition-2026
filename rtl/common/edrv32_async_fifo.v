// File: edrv32_async_fifo.v
// Spec: edrv32-soc-spec 5.2, 5.3; infra-plan I-06
// Description: Dual-clock ready/valid FIFO using synchronized Gray pointers.
//              Interface and use constraints are in rtl/common/README.md.
// Clock domain: ports identify the source and destination clocks.
module edrv32_async_fifo #(
    parameter WIDTH = 32,
    parameter DEPTH = 16
) (
    // Independent write and read domains.
    input wire clk_write_i,
    input wire rst_write_n_i,
    input wire clk_read_i,
    input wire rst_read_n_i,

    // Producer input in the write domain.
    input wire valid_i,
    output wire ready_o,
    input wire [WIDTH-1:0] data_i,

    // Consumer output in the read domain.
    output wire valid_o,
    input wire ready_i,
    output wire [WIDTH-1:0] data_o
);
    localparam PTR_WIDTH = $clog2(DEPTH);
    reg [WIDTH-1:0] memory_r [0:DEPTH-1];
    reg [PTR_WIDTH:0] write_bin_r;
    reg [PTR_WIDTH:0] read_bin_r;
    reg [PTR_WIDTH:0] write_gray_r;
    reg [PTR_WIDTH:0] read_gray_r;
    reg [PTR_WIDTH:0] read_meta_r;
    reg [PTR_WIDTH:0] read_sync_r;
    reg [PTR_WIDTH:0] write_meta_r;
    reg [PTR_WIDTH:0] write_sync_r;
    reg full_r;
    reg empty_r;
    wire [PTR_WIDTH:0] write_next_w;
    wire [PTR_WIDTH:0] read_next_w;
    wire [PTR_WIDTH:0] write_gray_next_w;
    wire [PTR_WIDTH:0] read_gray_next_w;
    wire write_w;
    wire read_w;

    assign ready_o = ~full_r;
    assign valid_o = ~empty_r;
    assign write_w = valid_i && ready_o;
    assign read_w = valid_o && ready_i;
    assign write_next_w = write_bin_r + {{PTR_WIDTH{1'b0}}, write_w};
    assign read_next_w = read_bin_r + {{PTR_WIDTH{1'b0}}, read_w};
    assign write_gray_next_w = write_next_w ^ (write_next_w >> 1);
    assign read_gray_next_w = read_next_w ^ (read_next_w >> 1);
    assign data_o = memory_r[read_bin_r[PTR_WIDTH-1:0]];

    always @(posedge clk_write_i) begin
        if (write_w) begin
            memory_r[write_bin_r[PTR_WIDTH-1:0]] <= data_i;
        end
    end

    always @(posedge clk_write_i or negedge rst_write_n_i) begin
        if (!rst_write_n_i) begin
            write_bin_r <= {(PTR_WIDTH+1){1'b0}};
            write_gray_r <= {(PTR_WIDTH+1){1'b0}};
            full_r <= 1'b0;
        end else begin
            write_bin_r <= write_next_w;
            write_gray_r <= write_gray_next_w;
            full_r <= (write_gray_next_w ==
                        (read_sync_r ^ {2'b11, {(PTR_WIDTH-1){1'b0}}}));
        end
    end

    always @(posedge clk_read_i or negedge rst_read_n_i) begin
        if (!rst_read_n_i) begin
            read_bin_r <= {(PTR_WIDTH+1){1'b0}};
            read_gray_r <= {(PTR_WIDTH+1){1'b0}};
            empty_r <= 1'b1;
        end else begin
            read_bin_r <= read_next_w;
            read_gray_r <= read_gray_next_w;
            empty_r <= (read_gray_next_w == write_sync_r);
        end
    end

    always @(posedge clk_write_i or negedge rst_write_n_i) begin
        if (!rst_write_n_i) begin
            read_meta_r <= {(PTR_WIDTH+1){1'b0}};
            read_sync_r <= {(PTR_WIDTH+1){1'b0}};
        end else begin
            read_meta_r <= read_gray_r;
            read_sync_r <= read_meta_r;
        end
    end

    always @(posedge clk_read_i or negedge rst_read_n_i) begin
        if (!rst_read_n_i) begin
            write_meta_r <= {(PTR_WIDTH+1){1'b0}};
            write_sync_r <= {(PTR_WIDTH+1){1'b0}};
        end else begin
            write_meta_r <= write_gray_r;
            write_sync_r <= write_meta_r;
        end
    end
endmodule
