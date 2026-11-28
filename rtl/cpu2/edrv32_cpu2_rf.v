// File: edrv32_cpu2_rf.v
// Spec: cpu-v2-spec 2.2, 3.4, 5.2.
// Description: Asynchronous 2R1W or two-owner 4R2W register file.
// Explicit WB forwarding and younger-write priority preserve the architectural RF.
// Clock domain: clk_sys.
module edrv32_cpu2_rf #(
    parameter ISSUE_WIDTH = 2
) (
    // ID read ports and committed writes; unused configuration ports are tied off.
    input wire clk_i,
    input wire rst_n_i,
    input wire [4:0] id_rs0_i,
    input wire id_owner0_i,
    output wire [31:0] id_data0_o,
    input wire [4:0] id_rs1_i,
    input wire id_owner1_i,
    output wire [31:0] id_data1_o,
    input wire [4:0] id_rs2_i,
    input wire id_owner2_i,
    output wire [31:0] id_data2_o,
    input wire [4:0] id_rs3_i,
    input wire id_owner3_i,
    output wire [31:0] id_data3_o,
    input wire wb0_valid_i,
    input wire [4:0] wb0_rd_i,
    input wire [31:0] wb0_data_i,
    input wire wb1_valid_i,
    input wire [4:0] wb1_rd_i,
    input wire [31:0] wb1_data_i,
    output wire [31:1] lvt_o
);
    wire [19:0] id_rs_w;
    wire [3:0] id_owner_w;
    wire [127:0] id_data_w;
    assign id_rs_w = {id_rs3_i, id_rs2_i, id_rs1_i, id_rs0_i};
    assign id_owner_w = {id_owner3_i, id_owner2_i, id_owner1_i, id_owner0_i};
    assign {id_data3_o, id_data2_o, id_data1_o, id_data0_o} = id_data_w;
    wire wb0_write_w;
    wire wb1_write_w;
    assign wb0_write_w = wb0_valid_i && (wb0_rd_i != 5'd0);
    assign wb1_write_w = (ISSUE_WIDTH == 2) && wb1_valid_i && (wb1_rd_i != 5'd0);
    genvar regnum;
    genvar portnum;
    generate
        if (ISSUE_WIDTH == 2) begin : g_dual
            wire [31:1] lvt_w;
            assign lvt_o = lvt_w;
            for (regnum = 1; regnum < 32; regnum = regnum + 1) begin : g_lvt
                localparam [4:0] REGNUM = regnum;
                reg owner_r;
                assign lvt_w[regnum] = owner_r;
                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i)
                        owner_r <= 1'b0;
                    else if (wb1_write_w && (wb1_rd_i == REGNUM))
                        owner_r <= 1'b1;
                    else if (wb0_write_w && (wb0_rd_i == REGNUM))
                        owner_r <= 1'b0;
                end
            end
        end else begin : g_single
            assign lvt_o = 31'd0;
        end
        for (portnum = 0; portnum < 4; portnum = portnum + 1) begin : g_read
            localparam ACTIVE = (portnum < 2*ISSUE_WIDTH);
            if (ACTIVE) begin : g_active
                wire [4:0] rs_w;
                wire [31:0] bank0_data_w;
                wire [31:0] owner_data_w;
                assign rs_w = id_rs_w[5*portnum +: 5];
                edrv32_ram_cpu2_rf u_bank0 (
                    .clk_i(clk_i),
                    .wr_en_i(wb0_write_w),
                    .wr_addr_i(wb0_rd_i),
                    .wr_data_i(wb0_data_i),
                    .rd_addr_i(rs_w),
                    .rd_data_o(bank0_data_w)
                );
                if (ISSUE_WIDTH == 2) begin : g_owner
                    wire [31:0] bank1_data_w;
                    edrv32_ram_cpu2_rf u_bank1 (
                        .clk_i(clk_i),
                        .wr_en_i(wb1_write_w),
                        .wr_addr_i(wb1_rd_i),
                        .wr_data_i(wb1_data_i),
                        .rd_addr_i(rs_w),
                        .rd_data_o(bank1_data_w)
                    );
                    assign owner_data_w = id_owner_w[portnum] ? bank1_data_w : bank0_data_w;
                end else begin : g_no_owner
                    assign owner_data_w = bank0_data_w;
                end
                assign id_data_w[32*portnum +: 32] = (rs_w == 5'd0) ? 32'd0 :
                    (wb1_write_w && (wb1_rd_i == rs_w)) ? wb1_data_i :
                    (wb0_write_w && (wb0_rd_i == rs_w)) ? wb0_data_i : owner_data_w;
            end else begin : g_inactive
                assign id_data_w[32*portnum +: 32] = 32'd0;
            end
        end
    endgenerate
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused_w = ^{rst_n_i, id_rs_w, id_owner_w, wb1_valid_i, wb1_rd_i, wb1_data_i};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
