// File: edrv32_cpu2_id_agu.v
// Spec: cpu-v2-spec 5.2, 5.5, 7.
// Description: Registered candidate owner parallels RF read; qualified ID address and local load capture.
// Clock domain: clk_sys.
module edrv32_cpu2_id_agu (
    // Clock and control.
    input wire clk_i,
    input wire rst_n_i,
    // Fixed ID head fields; owner bits [2:0] are {bank1 owner, unused, bank0 owner}.
    input wire id_valid_i,
    input wire id_load_i,
    input wire id_store_i,
    input wire [4:0] id_rs1_i,
    input wire [4:0] id_candidates_i,
    input wire [31:0] id_imm_i,
    // Completed WB values, increasing age order.
    input wire [1:0] wb_valid_i,
    input wire [9:0] wb_rd_i,
    input wire [63:0] wb_data_i,
    // Uncommitted producers which exclude early address generation.
    input wire older_valid_i,
    input wire [4:0] older_rd_i,
    input wire [1:0] ex_valid_i,
    input wire [9:0] ex_rd_i,
    input wire [1:0] mem_valid_i,
    input wire [9:0] mem_rd_i,
    input wire [1:0] wb_mul_pending_i,
    input wire [9:0] wb_mul_rd_i,
    // D$ probe initialization port, one word per cycle.
    input wire fill_valid_i,
    input wire fill_way_i,
    input wire [31:0] fill_addr_i,
    input wire [31:0] fill_data_i,
    input wire fill_line_valid_i,
    output wire id_eligible_o,
    output wire [31:0] id_addr_o,
    output wire ex_valid_o,
    output wire [31:0] ex_addr_o,
    output wire operand_valid_o,
    output wire operand_hit_o,
    output wire [31:0] operand_data_o
);
    wire [31:0] bank0_data_w;
    wire [31:0] bank1_data_w;
    wire owner_w;
    wire [31:0] owner_data_w;
    wire [31:0] source_w;
    wire dependency_w;
    wire [31:0] id_addr_w;
    wire unused_w;
    assign unused_w = ^{id_candidates_i[3], id_candidates_i[1], fill_addr_i[1:0]};
    edrv32_ram_cpu2_rf u_rf_bank0 (
        .clk_i(clk_i),
        .wr_en_i(wb_valid_i[0] && (wb_rd_i[4:0] != 5'd0)),
        .wr_addr_i(wb_rd_i[4:0]),
        .wr_data_i(wb_data_i[31:0]),
        .rd_addr_i(id_rs1_i),
        .rd_data_o(bank0_data_w)
    );
    edrv32_ram_cpu2_rf u_rf_bank1 (
        .clk_i(clk_i),
        .wr_en_i(wb_valid_i[1] && (wb_rd_i[9:5] != 5'd0)),
        .wr_addr_i(wb_rd_i[9:5]),
        .wr_data_i(wb_data_i[63:32]),
        .rd_addr_i(id_rs1_i),
        .rd_data_o(bank1_data_w)
    );
    assign owner_w = id_candidates_i[4] ? id_candidates_i[2] : id_candidates_i[0];
    assign owner_data_w = owner_w ? bank1_data_w : bank0_data_w;
    assign source_w = (id_rs1_i == 5'd0) ? 32'd0 :
        (wb_valid_i[1] && (wb_rd_i[9:5] == id_rs1_i)) ? wb_data_i[63:32] :
        (wb_valid_i[0] && (wb_rd_i[4:0] == id_rs1_i)) ? wb_data_i[31:0] : owner_data_w;
    assign dependency_w = (id_rs1_i != 5'd0) && (
        (older_valid_i && (older_rd_i == id_rs1_i)) ||
        (ex_valid_i[0] && (ex_rd_i[4:0] == id_rs1_i)) ||
        (ex_valid_i[1] && (ex_rd_i[9:5] == id_rs1_i)) ||
        (mem_valid_i[0] && (mem_rd_i[4:0] == id_rs1_i)) ||
        (mem_valid_i[1] && (mem_rd_i[9:5] == id_rs1_i)) ||
        (wb_mul_pending_i[0] && (wb_mul_rd_i[4:0] == id_rs1_i)) ||
        (wb_mul_pending_i[1] && (wb_mul_rd_i[9:5] == id_rs1_i)));
    assign id_eligible_o = id_valid_i && id_load_i && !id_store_i && !dependency_w;
    assign id_addr_w = source_w + id_imm_i;
    assign id_addr_o = id_addr_w;
    reg ex_valid_r;
    reg [31:0] ex_addr_r;
    reg load_valid_r;
    reg [31:0] load_addr_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ex_valid_r <= 1'b0;
            load_valid_r <= 1'b0;
        end else begin
            ex_valid_r <= id_eligible_o;
            load_valid_r <= ex_valid_r;
        end
    end
    always @(posedge clk_i) begin
        ex_addr_r <= id_addr_w;
        load_addr_r <= ex_addr_r;
    end
    assign ex_valid_o = ex_valid_r;
    assign ex_addr_o = ex_addr_r;
    wire [31:0] way_data_w [0:1];
    wire [1:0] way_hit_w;
    genvar way;
    genvar bank;
    generate
        for (way = 0; way < 2; way = way + 1) begin : g_way
            localparam WAY = (way != 0);
            wire [63:0] data_w;
            wire [18:0] tag_w;
            for (bank = 0; bank < 2; bank = bank + 1) begin : g_bank
                localparam BANK = (bank != 0);
                edrv32_ram_cpu2_cache_data u_data (
                    .clk_i(clk_i),
                    .wr_en_i(fill_valid_i && (fill_way_i == WAY) && (fill_addr_i[2] == BANK)),
                    .wr_addr_i(fill_addr_i[13:3]),
                    .wr_data_i(fill_data_i),
                    .rd_en_i(ex_valid_r),
                    .rd_addr_i(ex_addr_r[13:3]),
                    .rd_data_o(data_w[32*bank +: 32])
                );
            end
            edrv32_ram_cpu2_cache_tag u_tag (
                .clk_i(clk_i),
                .wr_en_i(fill_valid_i && (fill_way_i == WAY)),
                .wr_addr_i(fill_addr_i[13:5]),
                .wr_data_i({fill_line_valid_i, fill_addr_i[31:14]}),
                .rd_en_i(ex_valid_r),
                .rd_addr_i(ex_addr_r[13:5]),
                .rd_data_o(tag_w)
            );
            assign way_data_w[way] = load_addr_r[2] ? data_w[63:32] : data_w[31:0];
            assign way_hit_w[way] = tag_w[18] && (tag_w[17:0] == load_addr_r[31:14]);
        end
    endgenerate
    reg operand_valid_r;
    reg operand_hit_r;
    reg [31:0] operand_data_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            operand_valid_r <= 1'b0;
        else
            operand_valid_r <= load_valid_r;
    end
    always @(posedge clk_i) begin
        operand_data_r <= way_hit_w[1] ? way_data_w[1] : way_data_w[0];
        operand_hit_r <= |way_hit_w;
    end
    assign operand_valid_o = operand_valid_r;
    assign operand_hit_o = operand_hit_r;
    assign operand_data_o = operand_data_r;
    wire unused_addr_w;
    assign unused_addr_w = ^load_addr_r[13:3] ^ ^load_addr_r[1:0];
endmodule
