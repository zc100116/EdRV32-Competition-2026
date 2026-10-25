// ============================================================================
// File        : edrv32_mdu_scoreboard.v
// Description : One-slot scoreboard for the decoupled integer MDU only.
// Notes       : No transparent reuse on writeback; alloc_ready depends only on
//               registered slot state, keeping COMMIT-to-EX timing out of the path.
// ============================================================================
`include "edrv32_isa.vh"

module edrv32_mdu_scoreboard (
    input  wire                          clk_i,
    input  wire                          rst_n_i,

    input  wire                          alloc_valid_i,
    output wire                          alloc_ready_o,
    input  wire [`EDRV32_REG_ADDR_W-1:0] alloc_rd_i,
    input  wire                          alloc_rd_write_i,

    input  wire                          authorize_i,
    input  wire                          cancel_i,
    input  wire                          writeback_fire_i,
    input  wire                          pass_mem1_i,
    input  wire                          pass_mem2_i,

    input  wire [`EDRV32_REG_ADDR_W-1:0] rs1_addr_i,
    input  wire                          uses_rs1_i,
    input  wire [`EDRV32_REG_ADDR_W-1:0] rs2_addr_i,
    input  wire                          uses_rs2_i,
    input  wire [`EDRV32_REG_ADDR_W-1:0] issue_rd_i,
    input  wire                          issue_rd_write_i,

    output wire                          pending_o,
    output wire [`EDRV32_REG_ADDR_W-1:0] pending_rd_o,
    output wire                          authorized_o,
    output wire                          passed_mem1_o,
    output wire                          passed_mem2_o,
    output wire                          raw_hazard_o,
    output wire                          waw_hazard_o
);

    reg                          valid_r;
    reg [`EDRV32_REG_ADDR_W-1:0] rd_r;
    reg                          authorized_r;
    reg                          passed_mem1_r;
    reg                          passed_mem2_r;

    assign alloc_ready_o = ~valid_r;
    assign pending_o     = valid_r;
    assign pending_rd_o  = rd_r;
    assign authorized_o  = authorized_r;
    assign passed_mem1_o = passed_mem1_r;
    assign passed_mem2_o = passed_mem2_r;

    assign raw_hazard_o = valid_r && (
                              (uses_rs1_i && (rs1_addr_i != 5'd0) && (rs1_addr_i == rd_r)) ||
                              (uses_rs2_i && (rs2_addr_i != 5'd0) && (rs2_addr_i == rd_r))
                          );
    assign waw_hazard_o = valid_r && issue_rd_write_i && (issue_rd_i != 5'd0) &&
                          (issue_rd_i == rd_r);

    wire allocation_fire_w = alloc_valid_i && alloc_ready_o &&
                             alloc_rd_write_i && (alloc_rd_i != 5'd0);

    // In-order stage crossings locate the MDU relative to ordinary writers.
    // Once its token has left a boundary, every later record at that boundary
    // is younger. These age flags belong to this slot and never alter capacity.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            passed_mem1_r <= 1'b0;
            passed_mem2_r <= 1'b0;
        end else if (cancel_i || writeback_fire_i || allocation_fire_w) begin
            passed_mem1_r <= 1'b0;
            passed_mem2_r <= 1'b0;
        end else if (valid_r) begin
            if (pass_mem1_i)
                passed_mem1_r <= 1'b1;
            if (pass_mem2_i)
                passed_mem2_r <= 1'b1;
        end
    end

    // Pending-entry lifecycle only.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            valid_r <= 1'b0;
        else if (cancel_i || writeback_fire_i)
            valid_r <= 1'b0;
        else if (allocation_fire_w)
            valid_r <= 1'b1;
    end

    // Pending destination-register payload only.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            rd_r <= {`EDRV32_REG_ADDR_W{1'b0}};
        else if (allocation_fire_w)
            rd_r <= alloc_rd_i;
    end

    // COMMIT-authorization lifecycle only.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            authorized_r <= 1'b0;
        else if (cancel_i || writeback_fire_i || allocation_fire_w)
            authorized_r <= 1'b0;
        else if (authorize_i && valid_r)
            authorized_r <= 1'b1;
    end

endmodule
