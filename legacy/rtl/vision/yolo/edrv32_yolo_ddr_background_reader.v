// ============================================================================
// File        : edrv32_yolo_ddr_background_reader.v
// Description : Bounded read traffic for DDR interconnect contention tests.
// Notes       : One 16-beat AXI request may be outstanding. It stops issuing
//               when disabled and always drains an already accepted burst.
// ============================================================================

module edrv32_yolo_ddr_background_reader (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         enable_i,
    output wire [3:0]   arid_o,
    output wire [31:0]  araddr_o,
    output wire [7:0]   arlen_o,
    output wire [2:0]   arsize_o,
    output wire [1:0]   arburst_o,
    output wire [3:0]   arqos_o,
    output wire         arvalid_o,
    input  wire         arready_i,
    input  wire [3:0]   rid_i,
    input  wire [1:0]   rresp_i,
    input  wire         rlast_i,
    input  wire         rvalid_i,
    output wire         rready_o,
    output wire [31:0]  beat_count_o,
    output wire [31:0]  max_gap_o,
    output wire         active_o,
    output wire         error_o
);
    reg busy_r;
    reg [3:0] burst_index_r;
    reg [31:0] beat_count_r;
    reg [31:0] gap_count_r;
    reg [31:0] max_gap_r;
    reg error_r;

    assign arid_o = 4'h0;
    assign araddr_o = 32'h0004_0000 + {14'd0, burst_index_r, 9'd0};
    assign arlen_o = 8'd15;
    assign arsize_o = 3'd5;
    assign arburst_o = 2'b01;
    assign arqos_o = 4'd0;
    assign arvalid_o = enable_i && !busy_r;
    assign rready_o = 1'b1;
    assign beat_count_o = beat_count_r;
    assign max_gap_o = max_gap_r;
    assign active_o = busy_r || arvalid_o;
    assign error_o = error_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            busy_r <= 1'b0;
            burst_index_r <= 4'd0;
            beat_count_r <= 32'd0;
            gap_count_r <= 32'd0;
            max_gap_r <= 32'd0;
            error_r <= 1'b0;
        end else begin
            if (active_o && !(rvalid_i && rready_o)) begin
                gap_count_r <= gap_count_r + 32'd1;
                if (gap_count_r >= max_gap_r)
                    max_gap_r <= gap_count_r + 32'd1;
            end else begin
                gap_count_r <= 32'd0;
            end
            if (arvalid_o && arready_i) begin
                busy_r <= 1'b1;
                burst_index_r <= burst_index_r + 4'd1;
            end
            if (rvalid_i && rready_o) begin
                beat_count_r <= beat_count_r + 32'd1;
                if (rid_i != 4'h0 || rresp_i != 2'b00 || !busy_r)
                    error_r <= 1'b1;
                if (rlast_i)
                    busy_r <= 1'b0;
            end
        end
    end
endmodule
