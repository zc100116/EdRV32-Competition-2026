// File: edrv32_cpu2_fetch.v
// Spec: cpu-v2-spec 5.2, 5.5, 7.
// Description: Dual physical banks, parallel F2 owner decode and fixed-head IB.
// Clock domain: clk_sys.
module edrv32_cpu2_fetch (
    // Clock and control.
    input wire clk_i,
    input wire rst_n_i,
    // F1 request and physical-bank direction results.
    input wire f1_valid_i,
    input wire [31:0] f1_pc_i,
    input wire [1:0] f1_direction_i,
    // Probe cache fill port; one word, one way at a time.
    input wire fill_valid_i,
    input wire fill_way_i,
    input wire [31:0] fill_addr_i,
    input wire [31:0] fill_instr_i,
    input wire fill_line_valid_i,
    // BTB training; position is the PC word parity.
    input wire btb_write_i,
    input wire [31:0] btb_pc_i,
    input wire [31:0] btb_target_i,
    input wire [2:0] btb_type_i,
    // Owner snoop in increasing age order.
    input wire [31:1] lvt_i,
    input wire [1:0] wb_valid_i,
    input wire [9:0] wb_rd_i,
    // Second local WB tag copy, captured on the same upstream WB edge.
    input wire [1:0] wb_valid_copy_i,
    input wire [9:0] wb_rd_copy_i,
    // IB enqueue permission and registered consumer decision.
    input wire ib_accept_i,
    input wire [1:0] ib_remove_i,
    output wire ib_ready_o,
    output wire [3:0] ib_count_o,
    output wire [1:0] id_valid_o,
    output wire [63:0] id_instr_o,
    output wire [9:0] id_candidates_o,
    // F2 results, including independent cross-line hit status.
    output wire f2_valid_o,
    output wire [1:0] f2_hit_o,
    output wire [63:0] f2_instr_o,
    output wire [1:0] f2_taken_o,
    output wire [31:0] f2_target_o,
    output wire [5:0] f2_type_o
);
    wire [31:0] f1_next_pc_w;
    wire [31:0] physical_pc_w [0:1];
    wire [31:0] physical_instr_w [0:1];
    wire [1:0] physical_hit_w;
    wire [3:0] physical_owner_w;
    wire [7:0] physical_wb_w;
    wire [1:0] btb_hit_w;
    wire [31:0] btb_target_w [0:1];
    wire [2:0] btb_type_w [0:1];
    wire unused_w;
    assign unused_w = ^{fill_addr_i[1:0], btb_pc_i[1:0]};
    reg f2_valid_r;
    reg f2_parity_r;
    reg [31:0] f2_pc_r [0:1];
    reg [1:0] f2_taken_r;
    reg [31:0] f2_target_r [0:1];
    reg [2:0] f2_type_r [0:1];
    assign f1_next_pc_w = f1_pc_i + 32'd4;
    assign physical_pc_w[0] = f1_pc_i[2] ? f1_next_pc_w : f1_pc_i;
    assign physical_pc_w[1] = f1_pc_i[2] ? f1_pc_i : f1_next_pc_w;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            f2_valid_r <= 1'b0;
        else
            f2_valid_r <= f1_valid_i;
    end
    always @(posedge clk_i) begin
        f2_parity_r <= f1_pc_i[2];
        f2_pc_r[0] <= physical_pc_w[0];
        f2_pc_r[1] <= physical_pc_w[1];
        f2_taken_r <= btb_hit_w & f1_direction_i;
        f2_target_r[0] <= btb_target_w[0];
        f2_target_r[1] <= btb_target_w[1];
        f2_type_r[0] <= btb_type_w[0];
        f2_type_r[1] <= btb_type_w[1];
    end
    genvar bank;
    genvar way;
    generate
        for (bank = 0; bank < 2; bank = bank + 1) begin : g_bank
            localparam BANK = (bank != 0);
            wire [31:0] bank_pc_w;
            wire [31:0] bank_f2_pc_w;
            wire [63:0] way_instr_w;
            wire [1:0] way_hit_w;
            wire [58:0] btb_data_w;
            (* keep = "true", syn_keep = 1 *) wire [3:0] way_owner_w;
            (* keep = "true", syn_keep = 1 *) wire [7:0] way_wb_w;
            wire unused_bank_w;
            assign unused_bank_w = ^{bank_pc_w[2:0], bank_f2_pc_w[13:0]};
            wire [1:0] bank_wb_valid_w;
            wire [9:0] bank_wb_rd_w;
            if (bank == 0) begin : g_wb_region0
                assign bank_wb_valid_w = wb_valid_i;
                assign bank_wb_rd_w = wb_rd_i;
            end else begin : g_wb_region1
                assign bank_wb_valid_w = wb_valid_copy_i;
                assign bank_wb_rd_w = wb_rd_copy_i;
            end
            reg [63:0] btb_valid_r;
            assign bank_pc_w = physical_pc_w[bank];
            assign bank_f2_pc_w = f2_pc_r[bank];
            for (way = 0; way < 2; way = way + 1) begin : g_way
                localparam WAY = (way != 0);
                wire fill_w;
                wire [18:0] tag_w;
                wire [31:0] instr_w;
                wire [4:0] rs1_w;
                wire [4:0] rs2_w;
                wire unused_instr_w;
                assign instr_w = way_instr_w[32*way +: 32];
                assign unused_instr_w = ^{instr_w[31:25], instr_w[14:0]};
                assign rs1_w = instr_w[19:15];
                assign rs2_w = instr_w[24:20];
                // Four parallel LVT reads and WB compares per bank, before tag selection.
                assign way_owner_w[2*way] = (rs1_w != 5'd0) && lvt_i[rs1_w];
                assign way_owner_w[2*way+1] = (rs2_w != 5'd0) && lvt_i[rs2_w];
                assign way_wb_w[4*way +: 4] = {
                    (rs2_w != 5'd0) && bank_wb_valid_w[1] && (bank_wb_rd_w[9:5] == rs2_w),
                    (rs1_w != 5'd0) && bank_wb_valid_w[1] && (bank_wb_rd_w[9:5] == rs1_w),
                    (rs2_w == 5'd0) || (bank_wb_valid_w[0] && (bank_wb_rd_w[4:0] == rs2_w)),
                    (rs1_w == 5'd0) || (bank_wb_valid_w[0] && (bank_wb_rd_w[4:0] == rs1_w))};
                assign fill_w = fill_valid_i && (fill_way_i == WAY) &&
                    (fill_addr_i[2] == BANK);
                edrv32_ram_cpu2_cache_data u_data (
                    .clk_i(clk_i),
                    .wr_en_i(fill_w),
                    .wr_addr_i(fill_addr_i[13:3]),
                    .wr_data_i(fill_instr_i),
                    .rd_en_i(f1_valid_i),
                    .rd_addr_i(bank_pc_w[13:3]),
                    .rd_data_o(way_instr_w[32*way +: 32])
                );
                // Each physical bank has its own tag read for cross-line requests.
                edrv32_ram_cpu2_cache_tag u_tag (
                    .clk_i(clk_i),
                    .wr_en_i(fill_valid_i && (fill_way_i == WAY)),
                    .wr_addr_i(fill_addr_i[13:5]),
                    .wr_data_i({fill_line_valid_i, fill_addr_i[31:14]}),
                    .rd_en_i(f1_valid_i),
                    .rd_addr_i(bank_pc_w[13:5]),
                    .rd_data_o(tag_w)
                );
                assign way_hit_w[way] = tag_w[18] && (tag_w[17:0] == bank_f2_pc_w[31:14]);
            end
            assign physical_instr_w[bank] = way_hit_w[1] ? way_instr_w[63:32] :
                way_instr_w[31:0];
            assign physical_hit_w[bank] = |way_hit_w;
            assign physical_owner_w[2*bank +: 2] = way_hit_w[1] ?
                way_owner_w[3:2] : way_owner_w[1:0];
            assign physical_wb_w[4*bank +: 4] = way_hit_w[1] ?
                way_wb_w[7:4] : way_wb_w[3:0];
            edrv32_ram_cpu2_btb u_btb (
                .clk_i(clk_i),
                .wr_en_i(btb_write_i && (btb_pc_i[2] == BANK)),
                .wr_addr_i(btb_pc_i[8:3]),
                .wr_data_i({1'b1, btb_pc_i[31:9], btb_type_i, btb_target_i}),
                .rd_addr_i(bank_pc_w[8:3]),
                .rd_data_o(btb_data_w)
            );
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    btb_valid_r <= 64'd0;
                else if (btb_write_i && (btb_pc_i[2] == BANK))
                    btb_valid_r[btb_pc_i[8:3]] <= 1'b1;
            end
            assign btb_hit_w[bank] = btb_data_w[58] && btb_valid_r[bank_pc_w[8:3]] &&
                (btb_data_w[57:35] == bank_pc_w[31:9]);
            assign btb_type_w[bank] = btb_data_w[34:32];
            assign btb_target_w[bank] = btb_data_w[31:0];
        end
    endgenerate
    wire [31:0] aligned_instr_w [0:1];
    wire [4:0] enqueue_candidates_w [0:1];
    wire [1:0] aligned_taken_w;
    wire enqueue0_w;
    wire enqueue1_w;
    wire [1:0] enqueue_count_w;
    reg [3:0] ib_count_r;
    wire [3:0] retained_count_w;
    reg [12:0] ib_credit_r;
    wire [12:0] retained_credit_w;
    assign retained_credit_w = ib_credit_r >> ib_remove_i;
    // spec 5.5: registered one-hot occupancy supplies every IB insertion position.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            ib_credit_r <= 13'd1;
        else
            ib_credit_r <= enqueue1_w ? (retained_credit_w << 2) :
                enqueue0_w ? (retained_credit_w << 1) : retained_credit_w;
    end
    assign aligned_instr_w[0] = f2_parity_r ? physical_instr_w[1] : physical_instr_w[0];
    assign aligned_instr_w[1] = f2_parity_r ? physical_instr_w[0] : physical_instr_w[1];
    assign aligned_taken_w = f2_parity_r ? {f2_taken_r[0], f2_taken_r[1]} : f2_taken_r;
    assign f2_valid_o = f2_valid_r;
    assign f2_instr_o = {aligned_instr_w[1], aligned_instr_w[0]};
    assign f2_hit_o = f2_parity_r ? {physical_hit_w[0], physical_hit_w[1]} : physical_hit_w;
    assign f2_taken_o = {aligned_taken_w[1] && !aligned_taken_w[0], aligned_taken_w[0]};
    assign f2_target_o = (aligned_taken_w[0] ^ f2_parity_r) ?
        f2_target_r[0] : f2_target_r[1];
    assign f2_type_o = f2_parity_r ? {f2_type_r[0], f2_type_r[1]} :
        {f2_type_r[1], f2_type_r[0]};
    assign ib_ready_o = ib_count_r <= 4'd10;
    assign ib_count_o = ib_count_r;
    assign enqueue0_w = ib_accept_i && ib_ready_o && f2_valid_r && f2_hit_o[0];
    assign enqueue1_w = enqueue0_w && f2_hit_o[1] && !aligned_taken_w[0];
    assign enqueue_count_w = {1'b0, enqueue0_w} + {1'b0, enqueue1_w};
    assign retained_count_w = ib_count_r - {2'b0, ib_remove_i};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            ib_count_r <= 4'd0;
        else
            ib_count_r <= retained_count_w + {2'b0, enqueue_count_w};
    end
    wire [383:0] ib_instr_flat_w;
    wire [9:0] ib_candidates_flat_w;
    wire [31:0] shifted_instr_w [0:11];
    wire [4:0] shifted_candidates_w [0:11];
    wire [59:0] corrected_candidates_flat_w;
    genvar slot;
    generate
        for (slot = 0; slot < 2; slot = slot + 1) begin : g_enqueue
            wire bank_w;
            wire [3:0] wb_w;
            wire [1:0] owner0_w;
            wire [1:0] owner1_w;
            assign bank_w = f2_parity_r ^ (slot != 0);
            assign wb_w = bank_w ? physical_wb_w[7:4] : physical_wb_w[3:0];
            assign owner0_w = (physical_owner_w[1:0] & ~wb_w[1:0]) | wb_w[3:2];
            assign owner1_w = (physical_owner_w[3:2] & ~wb_w[1:0]) | wb_w[3:2];
            assign enqueue_candidates_w[slot] = {bank_w, owner1_w, owner0_w};
        end
        for (slot = 0; slot < 12; slot = slot + 1) begin : g_ib
            reg [4:0] ib_candidates_r;
            if (slot < 2) begin : g_id
                assign ib_candidates_flat_w[5*slot +: 5] = ib_candidates_r;
            end
            reg [31:0] ib_instr_r;
            assign ib_instr_flat_w[32*slot +: 32] = ib_instr_r;
            wire [1:0] wb_valid_w;
            wire [9:0] wb_rd_w;
            // Each WB region covers six entries and one bank of two ways (16 operands).
            if (slot < 6) begin : g_wb_region0
                assign wb_valid_w = wb_valid_i;
                assign wb_rd_w = wb_rd_i;
            end else begin : g_wb_region1
                assign wb_valid_w = wb_valid_copy_i;
                assign wb_rd_w = wb_rd_copy_i;
            end
            wire [31:0] next1_instr_w;
            wire [31:0] next2_instr_w;
            wire [4:0] next1_candidates_w;
            wire [4:0] next2_candidates_w;
            wire insert0_w;
            wire insert1_w;
            wire [31:0] next_instr_w;
            wire [4:0] selected_candidates_w;
            wire [4:0] next_rs1_w;
            wire [4:0] next_rs2_w;
            wire [1:0] next_owner1_w;
            wire [1:0] next_owner2_w;
            if (slot < 11) begin : g_next1
                assign next1_instr_w = ib_instr_flat_w[32*(slot+1) +: 32];
                assign next1_candidates_w = corrected_candidates_flat_w[5*(slot+1) +: 5];
            end else begin : g_end1
                assign next1_instr_w = 32'd0;
                assign next1_candidates_w = 5'd0;
            end
            if (slot < 10) begin : g_next2
                assign next2_instr_w = ib_instr_flat_w[32*(slot+2) +: 32];
                assign next2_candidates_w = corrected_candidates_flat_w[5*(slot+2) +: 5];
            end else begin : g_end2
                assign next2_instr_w = 32'd0;
                assign next2_candidates_w = 5'd0;
            end
            assign shifted_instr_w[slot] = (ib_remove_i == 2'd2) ? next2_instr_w :
                (ib_remove_i == 2'd1) ? next1_instr_w : ib_instr_flat_w[32*slot +: 32];
            assign shifted_candidates_w[slot] = (ib_remove_i == 2'd2) ? next2_candidates_w :
                (ib_remove_i == 2'd1) ? next1_candidates_w :
                corrected_candidates_flat_w[5*slot +: 5];
            assign insert0_w = enqueue0_w && retained_credit_w[slot];
            if (slot == 0) begin : g_first_position
                assign insert1_w = 1'b0;
            end else begin : g_second_position
                assign insert1_w = enqueue1_w && retained_credit_w[slot-1];
            end
            assign next_instr_w = insert0_w ? aligned_instr_w[0] :
                insert1_w ? aligned_instr_w[1] : shifted_instr_w[slot];
            assign selected_candidates_w = insert0_w ? enqueue_candidates_w[0] :
                insert1_w ? enqueue_candidates_w[1] : shifted_candidates_w[slot];
            wire [9:0] current_rs_w;
            assign current_rs_w = ib_instr_flat_w[32*slot+15 +: 10];
            assign next_rs1_w = current_rs_w[4:0];
            assign next_rs2_w = current_rs_w[9:5];
            // Repair each resident entry before movement; incoming words are repaired in parallel.
            assign next_owner1_w = (next_rs1_w == 5'd0) ? 2'b00 :
                (wb_valid_w[1] && (wb_rd_w[9:5] == next_rs1_w)) ? 2'b11 :
                (wb_valid_w[0] && (wb_rd_w[4:0] == next_rs1_w)) ? 2'b00 :
                {ib_candidates_r[2], ib_candidates_r[0]};
            assign next_owner2_w = (next_rs2_w == 5'd0) ? 2'b00 :
                (wb_valid_w[1] && (wb_rd_w[9:5] == next_rs2_w)) ? 2'b11 :
                (wb_valid_w[0] && (wb_rd_w[4:0] == next_rs2_w)) ? 2'b00 :
                {ib_candidates_r[3], ib_candidates_r[1]};
            assign corrected_candidates_flat_w[5*slot +: 5] = {ib_candidates_r[4],
                next_owner2_w[1], next_owner1_w[1], next_owner2_w[0], next_owner1_w[0]};
            always @(posedge clk_i) begin
                ib_instr_r <= next_instr_w;
                ib_candidates_r <= selected_candidates_w;
            end
        end
    endgenerate
    assign id_valid_o = {ib_count_r >= 4'd2, ib_count_r != 4'd0};
    assign id_instr_o = ib_instr_flat_w[63:0];
    assign id_candidates_o = ib_candidates_flat_w[9:0];
endmodule
