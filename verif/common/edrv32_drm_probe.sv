// File: edrv32_drm_probe.sv
// Spec: npu-spec 5.2; vin-spec 2.6; disp-spec 2.6; Task T-DRM1.
// Description: Passive address envelope measurement, including enabled speculative reads.
// Lifetime statistics include all resets; -1 denotes no accesses, not address zero.
// Clock domain: the observed RAM write and read domains independently.
module edrv32_drm_probe (
    input wire wr_clk_i,
    input wire wr_en_i,
    input wire [31:0] wr_addr_i,
    input wire rd_clk_i,
    input wire rd_en_i,
    input wire [31:0] rd_addr_i
);
    integer wr_min_r = -1;
    integer wr_max_r = -1;
    integer rd_min_r = -1;
    integer rd_max_r = -1;
    reg [63:0] cycles_r = 0;
    reg [63:0] writes_r = 0;
    reg [63:0] reads_r = 0;
    always @(posedge wr_clk_i) begin
        cycles_r <= cycles_r + 1;
        if (wr_en_i) begin
            writes_r <= writes_r + 1;
            if (wr_min_r == -1 || $signed(wr_addr_i) < wr_min_r)
                wr_min_r <= $signed(wr_addr_i);
            if ($signed(wr_addr_i) > wr_max_r) wr_max_r <= $signed(wr_addr_i);
        end
    end
    always @(posedge rd_clk_i) begin
        if (rd_en_i) begin
            reads_r <= reads_r + 1;
            if (rd_min_r == -1 || $signed(rd_addr_i) < rd_min_r)
                rd_min_r <= $signed(rd_addr_i);
            if ($signed(rd_addr_i) > rd_max_r) rd_max_r <= $signed(rd_addr_i);
        end
    end
    final begin
        $display("DRM_ADDR %m writes=%0d wr=%0d:%0d reads=%0d rd=%0d:%0d cycles=%0d",
            writes_r, wr_min_r, wr_max_r, reads_r, rd_min_r, rd_max_r, cycles_r);
    end
endmodule
