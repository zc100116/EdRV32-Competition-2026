// File: edrv32_cpu2_id_agu.v
// Spec: cpu-v2-spec 3.4, 5.2; interface-freeze C05/C06.
// Description: Independent RF read copies preserve the measured RF/WB-to-ID-AGU boundary.
// I02 rs1_pending includes same-group and all uncommitted producers; WB is already committed.
// Clock domain: clk_sys.
module edrv32_cpu2_id_agu #(
    parameter ISSUE_WIDTH = 2,
    parameter [31:0] FPU_FORMAT = "NONE"
) (
    // ID qualification and actual allocation pulse, never speculative IB presence.
    input wire clk_i,
    input wire rst_n_i,
    input wire id_valid_i,
    input wire id_load_i,
    input wire id_store_i,
    input wire [4:0] id_rs1_i,
    input wire [4:0] id_candidates_i,
    input wire [31:0] id_imm_i,
    input wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] id_tag_i,
    input wire rs1_pending_i,
    // Committed values, forwarded before the address adder.
    input wire wb0_valid_i,
    input wire [4:0] wb0_rd_i,
    input wire [31:0] wb0_data_i,
    input wire wb1_valid_i,
    input wire [4:0] wb1_rd_i,
    input wire [31:0] wb1_data_i,
    // Fixed-latency query accepted by LSU only with actual load issue.
    output wire id_eligible_o,
    output wire [31:0] id_addr_o,
    output wire early_req_valid_o,
    output wire [31:0] early_req_addr_o,
    output wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] early_req_tag_o
);
    wire [31:0] bank0_data_w;
    wire [31:0] bank1_data_w;
    wire [31:0] owner_data_w;
    wire [31:0] source_w;
    wire wb0_write_w;
    wire wb1_write_w;
    wire owner_w;
    assign wb0_write_w = wb0_valid_i && (wb0_rd_i != 5'd0);
    assign wb1_write_w = (ISSUE_WIDTH == 2) && wb1_valid_i && (wb1_rd_i != 5'd0);
    edrv32_ram_cpu2_rf u_bank0 (
        .clk_i(clk_i),
        .wr_en_i(wb0_write_w),
        .wr_addr_i(wb0_rd_i),
        .wr_data_i(wb0_data_i),
        .rd_addr_i(id_rs1_i),
        .rd_data_o(bank0_data_w)
    );
    generate
        if (ISSUE_WIDTH == 2) begin : g_dual
            edrv32_ram_cpu2_rf u_bank1 (
                .clk_i(clk_i),
                .wr_en_i(wb1_write_w),
                .wr_addr_i(wb1_rd_i),
                .wr_data_i(wb1_data_i),
                .rd_addr_i(id_rs1_i),
                .rd_data_o(bank1_data_w)
            );
            assign owner_w = id_candidates_i[4] ? id_candidates_i[2] : id_candidates_i[0];
        end else begin : g_single
            assign bank1_data_w = 32'd0;
            assign owner_w = 1'b0;
        end
    endgenerate
    assign owner_data_w = owner_w ? bank1_data_w : bank0_data_w;
    assign source_w = (id_rs1_i == 5'd0) ? 32'd0 :
        (wb1_write_w && (wb1_rd_i == id_rs1_i)) ? wb1_data_i :
        (wb0_write_w && (wb0_rd_i == id_rs1_i)) ? wb0_data_i : owner_data_w;
    assign id_eligible_o = id_load_i && !id_store_i &&
        ((id_rs1_i == 5'd0) || !rs1_pending_i);
    assign id_addr_o = source_w + id_imm_i;
    assign early_req_valid_o = id_valid_i && id_eligible_o;
    assign early_req_addr_o = id_addr_o;
    assign early_req_tag_o = id_tag_i;
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused_w = ^{rst_n_i, id_candidates_i, wb1_valid_i, wb1_rd_i, wb1_data_i};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
