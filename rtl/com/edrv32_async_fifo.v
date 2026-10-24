// ============================================================================
// File        : edrv32_async_fifo.v
// Description : Power-of-two asynchronous FIFO for clock-domain crossings.
// Notes       : Gray pointers are synchronized independently in both domains.
//               Payload memory is not reset; synchronized ownership guarantees
//               that only committed entries are visible to the read domain.
// ============================================================================

module edrv32_async_fifo #(
    parameter integer DATA_W = 32,
    parameter integer ADDR_W = 3
) (
    input  wire                 wr_clk_i,
    input  wire                 wr_rst_n_i,
    input  wire [DATA_W-1:0]    wr_data_i,
    input  wire                 wr_valid_i,
    output wire                 wr_ready_o,

    input  wire                 rd_clk_i,
    input  wire                 rd_rst_n_i,
    output wire [DATA_W-1:0]    rd_data_o,
    output wire                 rd_valid_o,
    input  wire                 rd_ready_i
);

    localparam integer PTR_W = ADDR_W + 1;

    reg [DATA_W-1:0] mem_r [0:(1 << ADDR_W)-1];

    reg [PTR_W-1:0] wr_bin_r;
    reg [PTR_W-1:0] wr_gray_r;
    reg             wr_full_r;
    reg [PTR_W-1:0] rd_gray_wr_meta_r;
    reg [PTR_W-1:0] rd_gray_wr_sync_r;

    reg [PTR_W-1:0] rd_bin_r;
    reg [PTR_W-1:0] rd_gray_r;
    reg             rd_empty_r;
    reg [PTR_W-1:0] wr_gray_rd_meta_r;
    reg [PTR_W-1:0] wr_gray_rd_sync_r;

    wire wr_fire_w = wr_valid_i && !wr_full_r;
    wire rd_fire_w = rd_ready_i && !rd_empty_r;

    wire [PTR_W-1:0] wr_bin_next_w = wr_bin_r + wr_fire_w;
    wire [PTR_W-1:0] wr_gray_next_w =
        (wr_bin_next_w >> 1) ^ wr_bin_next_w;
    wire [PTR_W-1:0] rd_bin_next_w = rd_bin_r + rd_fire_w;
    wire [PTR_W-1:0] rd_gray_next_w =
        (rd_bin_next_w >> 1) ^ rd_bin_next_w;

    wire [PTR_W-1:0] rd_gray_full_compare_w = {
        ~rd_gray_wr_sync_r[PTR_W-1:PTR_W-2],
         rd_gray_wr_sync_r[PTR_W-3:0]
    };
    wire full_next_w = wr_gray_next_w == rd_gray_full_compare_w;
    wire empty_next_w = rd_gray_next_w == wr_gray_rd_sync_r;

    assign wr_ready_o = !wr_full_r;
    assign rd_valid_o = !rd_empty_r;
    assign rd_data_o = mem_r[rd_bin_r[ADDR_W-1:0]];

    always @(posedge wr_clk_i or negedge wr_rst_n_i) begin
        if (!wr_rst_n_i) begin
            wr_bin_r <= {PTR_W{1'b0}};
            wr_gray_r <= {PTR_W{1'b0}};
            wr_full_r <= 1'b0;
        end else begin
            if (wr_fire_w)
                mem_r[wr_bin_r[ADDR_W-1:0]] <= wr_data_i;
            wr_bin_r <= wr_bin_next_w;
            wr_gray_r <= wr_gray_next_w;
            wr_full_r <= full_next_w;
        end
    end

    always @(posedge wr_clk_i or negedge wr_rst_n_i) begin
        if (!wr_rst_n_i) begin
            rd_gray_wr_meta_r <= {PTR_W{1'b0}};
            rd_gray_wr_sync_r <= {PTR_W{1'b0}};
        end else begin
            rd_gray_wr_meta_r <= rd_gray_r;
            rd_gray_wr_sync_r <= rd_gray_wr_meta_r;
        end
    end

    always @(posedge rd_clk_i or negedge rd_rst_n_i) begin
        if (!rd_rst_n_i) begin
            rd_bin_r <= {PTR_W{1'b0}};
            rd_gray_r <= {PTR_W{1'b0}};
            rd_empty_r <= 1'b1;
        end else begin
            rd_bin_r <= rd_bin_next_w;
            rd_gray_r <= rd_gray_next_w;
            rd_empty_r <= empty_next_w;
        end
    end

    always @(posedge rd_clk_i or negedge rd_rst_n_i) begin
        if (!rd_rst_n_i) begin
            wr_gray_rd_meta_r <= {PTR_W{1'b0}};
            wr_gray_rd_sync_r <= {PTR_W{1'b0}};
        end else begin
            wr_gray_rd_meta_r <= wr_gray_r;
            wr_gray_rd_sync_r <= wr_gray_rd_meta_r;
        end
    end

endmodule
