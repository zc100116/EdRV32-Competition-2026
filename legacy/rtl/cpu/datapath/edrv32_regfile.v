// ============================================================================
// File        : edrv32_regfile.v
// Description : 32 x 32 integer register file with optional four asynchronous
//               reads and two synchronous architectural writes.
// Notes       : Data storage is deliberately not reset. x0 is forced to zero,
//               writes to x0 are ignored, and same-cycle read/write collisions
//               have explicit write-first behavior independent of RAM semantics.
// ============================================================================
`include "edrv32_isa.vh"

module edrv32_regfile #(
    parameter integer SECOND_ENABLE = 0
)(
    input  wire                          clk_i,

    input  wire [4:0]                       second_rs1_addr_i,
    input  wire [4:0]                       second_rs2_addr_i,
    output wire [31:0]                      second_rs1_data_o,
    output wire [31:0]                      second_rs2_data_o,
    input  wire                             second_rd_write_i,
    input  wire [4:0]                       second_rd_addr_i,
    input  wire [31:0]                      second_rd_data_i,

    input  wire [`EDRV32_REG_ADDR_W-1:0] rs1_addr_i,
    output wire [`EDRV32_XLEN-1:0]       rs1_data_o,
    input  wire [`EDRV32_REG_ADDR_W-1:0] rs2_addr_i,
    output wire [`EDRV32_XLEN-1:0]       rs2_data_o,
    input  wire                          rd_write_i,
    input  wire [`EDRV32_REG_ADDR_W-1:0] rd_addr_i,
    input  wire [`EDRV32_XLEN-1:0]       rd_data_i
);

    reg [`EDRV32_XLEN-1:0] regs_r [1:31];

    wire second_write_w = (SECOND_ENABLE != 0) && second_rd_write_i &&
        (second_rd_addr_i != 5'd0);
    // Port B is younger and wins every same-address read/write collision.
    assign rs1_data_o = (rs1_addr_i == 5'd0) ? 32'd0 :
        (second_write_w && second_rd_addr_i == rs1_addr_i) ? second_rd_data_i :
        (rd_write_i && rd_addr_i == rs1_addr_i) ? rd_data_i : regs_r[rs1_addr_i];
    assign rs2_data_o = (rs2_addr_i == 5'd0) ? 32'd0 :
        (second_write_w && second_rd_addr_i == rs2_addr_i) ? second_rd_data_i :
        (rd_write_i && rd_addr_i == rs2_addr_i) ? rd_data_i : regs_r[rs2_addr_i];
    assign second_rs1_data_o = ((SECOND_ENABLE == 0) || second_rs1_addr_i == 5'd0) ? 32'd0 :
        (second_write_w && second_rd_addr_i == second_rs1_addr_i) ? second_rd_data_i :
        (rd_write_i && rd_addr_i == second_rs1_addr_i) ? rd_data_i : regs_r[second_rs1_addr_i];
    assign second_rs2_data_o = ((SECOND_ENABLE == 0) || second_rs2_addr_i == 5'd0) ? 32'd0 :
        (second_write_w && second_rd_addr_i == second_rs2_addr_i) ? second_rd_data_i :
        (rd_write_i && rd_addr_i == second_rs2_addr_i) ? rd_data_i : regs_r[second_rs2_addr_i];

    always @(posedge clk_i) begin
        if (rd_write_i && rd_addr_i != 5'd0)
            regs_r[rd_addr_i] <= rd_data_i;
        if (second_write_w)
            regs_r[second_rd_addr_i] <= second_rd_data_i;
    end
endmodule
