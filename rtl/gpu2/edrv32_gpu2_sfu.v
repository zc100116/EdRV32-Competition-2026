// File: edrv32_gpu2_sfu.v
// Spec: gpu-v2-spec 2.4; M-6 II4 reservation, M-7 synchronous scratch; GP-A2.
// Description: Two eleven-edge arithmetic engines, one dual-read seed DRM and fixed modulo slots.
// Clock domain: clk_gpu. Independent engine returns allow coincident RSQ/LOG completions.
module edrv32_gpu2_sfu (
    // Clock and control reset.
    input wire clk_i,
    input wire rst_n_i,

    // One scalar request each fourth clock; op 0 RCP, 1 RSQ, 2 LOG2, 3 EXP2.
    input wire req_valid_i,
    output reg req_ready_o,
    input wire [1:0] req_op_i,
    input wire [31:0] req_data_i,
    input wire [4:0] req_tag_i,

    // Two independently backpressured completion ports; RF arbitration is external.
    output wire resp0_valid_o,
    input wire resp0_ready_i,
    output wire [31:0] resp0_data_o,
    output wire [4:0] resp0_tag_o,
    output wire resp1_valid_o,
    input wire resp1_ready_i,
    output wire [31:0] resp1_data_o,
    output wire [4:0] resp1_tag_o,

    // Setup owns the independent RCP seed read port; one-cycle enabled read.
    input wire setup_en_i,
    input wire [5:0] setup_index_i,
    output wire [31:0] setup_seed_o
);
    wire accept_w;
    wire [1:0] response_pop_w;
    reg [1:0] phase_r;
    reg [5:0] outstanding_r;
    wire [5:0] outstanding_next_w;
    reg [4:0] allocate_r;
    reg [86:0] valid_r;
    reg [4:0] id_r [0:86];
    reg [1:0] op_r [0:86];
    reg [4:0] tag_r [0:4];
    // Same-edge roots separate eight field-bank writes from the two metadata copies.
    (* keep = "true", syn_preserve = 1 *) reg [1:0] front_commit_r;
    (* keep = "true", syn_preserve = 1 *) reg [9:0] front_id_r;
    (* keep = "true", syn_preserve = 1 *) reg [3:0] meta_write_r;
    assign accept_w = req_valid_i && req_ready_o;
    assign response_pop_w = {resp1_valid_o && resp1_ready_i, resp0_valid_o && resp0_ready_i};
    assign outstanding_next_w = outstanding_r + {5'b0, accept_w}
        - {5'b0, response_pop_w[0]} - {5'b0, response_pop_w[1]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            phase_r <= 2'b0;
            outstanding_r <= 6'b0;
            req_ready_o <= 1'b1;
            allocate_r <= 5'b0;
            valid_r <= 87'b0;
            front_commit_r <= 2'b0;
            meta_write_r <= 4'b0;
        end else begin
            phase_r <= phase_r + 2'd1;
            outstanding_r <= outstanding_next_w;
            req_ready_o <= phase_r == 2'd3 && outstanding_next_w < 6'd32;
            allocate_r <= allocate_r + {4'b0, accept_w};
            valid_r <= {valid_r[85:0], accept_w};
            front_commit_r <= {2{valid_r[3]}};
            meta_write_r <= {4{valid_r[3]}};
        end
    end
    always @(posedge clk_i) begin
        id_r[0] <= allocate_r;
        op_r[0] <= req_op_i;
        tag_r[0] <= req_tag_i;
        id_r[1] <= id_r[0];
        op_r[1] <= op_r[0];
        id_r[2] <= id_r[1];
        op_r[2] <= op_r[1];
        id_r[3] <= id_r[2];
        op_r[3] <= op_r[2];
        id_r[4] <= id_r[3];
        op_r[4] <= op_r[3];
        id_r[5] <= id_r[4];
        op_r[5] <= op_r[4];
        id_r[6] <= id_r[5];
        op_r[6] <= op_r[5];
        id_r[7] <= id_r[6];
        op_r[7] <= op_r[6];
        id_r[8] <= id_r[7];
        op_r[8] <= op_r[7];
        id_r[9] <= id_r[8];
        op_r[9] <= op_r[8];
        id_r[10] <= id_r[9];
        op_r[10] <= op_r[9];
        id_r[11] <= id_r[10];
        op_r[11] <= op_r[10];
        id_r[12] <= id_r[11];
        op_r[12] <= op_r[11];
        id_r[13] <= id_r[12];
        op_r[13] <= op_r[12];
        id_r[14] <= id_r[13];
        op_r[14] <= op_r[13];
        id_r[15] <= id_r[14];
        op_r[15] <= op_r[14];
        id_r[16] <= id_r[15];
        op_r[16] <= op_r[15];
        id_r[17] <= id_r[16];
        op_r[17] <= op_r[16];
        id_r[18] <= id_r[17];
        op_r[18] <= op_r[17];
        id_r[19] <= id_r[18];
        op_r[19] <= op_r[18];
        id_r[20] <= id_r[19];
        op_r[20] <= op_r[19];
        id_r[21] <= id_r[20];
        op_r[21] <= op_r[20];
        id_r[22] <= id_r[21];
        op_r[22] <= op_r[21];
        id_r[23] <= id_r[22];
        op_r[23] <= op_r[22];
        id_r[24] <= id_r[23];
        op_r[24] <= op_r[23];
        id_r[25] <= id_r[24];
        op_r[25] <= op_r[24];
        id_r[26] <= id_r[25];
        op_r[26] <= op_r[25];
        id_r[27] <= id_r[26];
        op_r[27] <= op_r[26];
        id_r[28] <= id_r[27];
        op_r[28] <= op_r[27];
        id_r[29] <= id_r[28];
        op_r[29] <= op_r[28];
        id_r[30] <= id_r[29];
        op_r[30] <= op_r[29];
        id_r[31] <= id_r[30];
        op_r[31] <= op_r[30];
        id_r[32] <= id_r[31];
        op_r[32] <= op_r[31];
        id_r[33] <= id_r[32];
        op_r[33] <= op_r[32];
        id_r[34] <= id_r[33];
        op_r[34] <= op_r[33];
        id_r[35] <= id_r[34];
        op_r[35] <= op_r[34];
        id_r[36] <= id_r[35];
        op_r[36] <= op_r[35];
        id_r[37] <= id_r[36];
        op_r[37] <= op_r[36];
        id_r[38] <= id_r[37];
        op_r[38] <= op_r[37];
        id_r[39] <= id_r[38];
        op_r[39] <= op_r[38];
        id_r[40] <= id_r[39];
        op_r[40] <= op_r[39];
        id_r[41] <= id_r[40];
        op_r[41] <= op_r[40];
        id_r[42] <= id_r[41];
        op_r[42] <= op_r[41];
        id_r[43] <= id_r[42];
        op_r[43] <= op_r[42];
        id_r[44] <= id_r[43];
        op_r[44] <= op_r[43];
        id_r[45] <= id_r[44];
        op_r[45] <= op_r[44];
        id_r[46] <= id_r[45];
        op_r[46] <= op_r[45];
        id_r[47] <= id_r[46];
        op_r[47] <= op_r[46];
        id_r[48] <= id_r[47];
        op_r[48] <= op_r[47];
        id_r[49] <= id_r[48];
        op_r[49] <= op_r[48];
        id_r[50] <= id_r[49];
        op_r[50] <= op_r[49];
        id_r[51] <= id_r[50];
        op_r[51] <= op_r[50];
        id_r[52] <= id_r[51];
        op_r[52] <= op_r[51];
        id_r[53] <= id_r[52];
        op_r[53] <= op_r[52];
        id_r[54] <= id_r[53];
        op_r[54] <= op_r[53];
        id_r[55] <= id_r[54];
        op_r[55] <= op_r[54];
        id_r[56] <= id_r[55];
        op_r[56] <= op_r[55];
        id_r[57] <= id_r[56];
        op_r[57] <= op_r[56];
        id_r[58] <= id_r[57];
        op_r[58] <= op_r[57];
        id_r[59] <= id_r[58];
        op_r[59] <= op_r[58];
        id_r[60] <= id_r[59];
        op_r[60] <= op_r[59];
        id_r[61] <= id_r[60];
        op_r[61] <= op_r[60];
        id_r[62] <= id_r[61];
        op_r[62] <= op_r[61];
        id_r[63] <= id_r[62];
        op_r[63] <= op_r[62];
        id_r[64] <= id_r[63];
        op_r[64] <= op_r[63];
        id_r[65] <= id_r[64];
        op_r[65] <= op_r[64];
        id_r[66] <= id_r[65];
        op_r[66] <= op_r[65];
        id_r[67] <= id_r[66];
        op_r[67] <= op_r[66];
        id_r[68] <= id_r[67];
        op_r[68] <= op_r[67];
        id_r[69] <= id_r[68];
        op_r[69] <= op_r[68];
        id_r[70] <= id_r[69];
        op_r[70] <= op_r[69];
        id_r[71] <= id_r[70];
        op_r[71] <= op_r[70];
        id_r[72] <= id_r[71];
        op_r[72] <= op_r[71];
        id_r[73] <= id_r[72];
        op_r[73] <= op_r[72];
        id_r[74] <= id_r[73];
        op_r[74] <= op_r[73];
        id_r[75] <= id_r[74];
        op_r[75] <= op_r[74];
        id_r[76] <= id_r[75];
        op_r[76] <= op_r[75];
        id_r[77] <= id_r[76];
        op_r[77] <= op_r[76];
        id_r[78] <= id_r[77];
        op_r[78] <= op_r[77];
        id_r[79] <= id_r[78];
        op_r[79] <= op_r[78];
        id_r[80] <= id_r[79];
        op_r[80] <= op_r[79];
        id_r[81] <= id_r[80];
        op_r[81] <= op_r[80];
        id_r[82] <= id_r[81];
        op_r[82] <= op_r[81];
        id_r[83] <= id_r[82];
        op_r[83] <= op_r[82];
        id_r[84] <= id_r[83];
        op_r[84] <= op_r[83];
        id_r[85] <= id_r[84];
        op_r[85] <= op_r[84];
        id_r[86] <= id_r[85];
        op_r[86] <= op_r[85];
        tag_r[1] <= tag_r[0];
        tag_r[2] <= tag_r[1];
        tag_r[3] <= tag_r[2];
        tag_r[4] <= tag_r[3];
        front_id_r <= {id_r[3], id_r[3]};
    end
    wire [5:0] table_index_w;
    wire [31:0] front0_w;
    wire [31:0] front3_w;
    wire signed [9:0] front_scale_w;
    wire front_sign_w;
    wire front_exp_fma_w;
    wire front_special_w;
    wire [31:0] unused_front_special_data_w;
    edrv32_gpu2_sfu_prepare u_prepare (
        .clk_i(clk_i),
        .op_i(req_op_i),
        .x_i(req_data_i),
        .index_o(table_index_w),
        .field0_o(front0_w),
        .field3_o(front3_w),
        .scale_o(front_scale_w),
        .sign_o(front_sign_w),
        .exp_fma_o(front_exp_fma_w),
        .special_o(front_special_w),
        .special_data_o(unused_front_special_data_w)
    );
    reg [5:0] table_index_r;
    wire [9:0] table_addr_w;
    wire [31:0] table_data_w;
    // Two registered read-enable leaves per 32-bit capture, sixteen FF sinks each.
    (* keep = "true", syn_preserve = 1 *) reg [1:0] first_read_valid_r;
    (* keep = "true", syn_preserve = 1 *) reg [1:0] second_read_valid_r;
    reg [31:0] first_seed_r;
    reg [31:0] second_seed_r;
    wire second_read_w;
    assign second_read_w = valid_r[2] && op_r[2] == 2'd2;
    assign table_addr_w = second_read_w ? 10'd177 + {4'b0, table_index_r}
        : op_r[1] == 2'd0 ? {4'b0, table_index_w}
        : op_r[1] == 2'd1 ? 10'd64 + {4'b0, table_index_w}
        : op_r[1] == 2'd2 ? 10'd128 + {4'b0, table_index_w}
        : 10'd226 + {4'b0, table_index_w};
    edrv32_rom_gpu2_sfu u_seed_rom (
        .clk_i(clk_i),
        .a_en_i(valid_r[1] || second_read_w),
        .a_addr_i(table_addr_w),
        .a_data_o(table_data_w),
        .b_en_i(setup_en_i),
        .b_addr_i(setup_index_i),
        .b_data_o(setup_seed_o)
    );
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            first_read_valid_r <= 2'b0;
            second_read_valid_r <= 2'b0;
        end else begin
            first_read_valid_r <= {2{valid_r[1]}};
            second_read_valid_r <= {2{second_read_w}};
        end
    end
    always @(posedge clk_i) begin
        table_index_r <= table_index_w;
        if (first_read_valid_r[0]) first_seed_r[15:0] <= table_data_w[15:0];
        if (first_read_valid_r[1]) first_seed_r[31:16] <= table_data_w[31:16];
        if (second_read_valid_r[0]) second_seed_r[15:0] <= table_data_w[15:0];
        if (second_read_valid_r[1]) second_seed_r[31:16] <= table_data_w[31:16];
    end
    wire [31:0] front1_w;
    wire [31:0] front2_w;
    wire [2:0] front_class_w;
    wire [20:0] front_meta_w;
    assign front1_w = op_r[4] == 2'd2 ? second_seed_r : first_seed_r;
    assign front2_w = first_seed_r;
    assign front_class_w = unused_front_special_data_w[22] ? 3'd4
        : {1'b0, unused_front_special_data_w[30], unused_front_special_data_w[31]};
    assign front_meta_w = {tag_r[4], front_class_w, front_special_w,
        front_exp_fma_w, front_sign_w, front_scale_w};
    wire [1:0] unused_issue_valid_w;
    wire [9:0] unused_issue_id_w;
    wire [1:0] complete_valid_w;
    wire [5:0] complete_slot_w;
    wire [9:0] complete_id_w;
    wire [3:0] complete_op_w;
    wire [63:0] arithmetic_data_w;
    wire [1:0] ahead_valid_w;
    wire [5:0] ahead_slot_w;
    wire [9:0] ahead_id_w;
    wire [9:0] prefetch_id_w;
    wire [3:0] prefetch_op_w;
    wire [5:0] prefetch_slot_w;
    wire [1:0] prefetch_valid_w;
    wire [255:0] field_data_w;
    wire [223:0] result_data_w;
    wire [41:0] meta_data_w;
    reg [255:0] field_capture_r;
    reg [223:0] result_capture_r;
    // Card112 DRM->arithmetic was10 levels; capture after only forwarding muxes.
    always @(posedge clk_i) begin
        field_capture_r <= field_data_w;
        result_capture_r <= result_data_w;
    end
    // Eleven-edge engines: distinct modulo-four phases and scratch write phases.
    // Prefetch offsets5/18/29/40/52/63/75/86 retain II4 for every opcode mix.
    wire [3:0] engine0_events_w;
    assign engine0_events_w[0] = valid_r[5];
    assign engine0_events_w[1] = valid_r[18];
    assign engine0_events_w[2] = valid_r[52] && op_r[52] != 2'd0;
    assign engine0_events_w[3] = valid_r[63] && op_r[63] != 2'd0;
    reg [4:0] prefetch0_id_w;
    reg [1:0] prefetch0_op_w;
    reg [2:0] prefetch0_slot_w;
    always @(*) begin
        prefetch0_id_w = 5'b0;
        prefetch0_op_w = 2'b0;
        prefetch0_slot_w = 3'b0;
        case (engine0_events_w)
            4'b0001: begin
                prefetch0_id_w = id_r[5];
                prefetch0_op_w = op_r[5];
                prefetch0_slot_w = 3'd0;
            end
            4'b0010: begin
                prefetch0_id_w = id_r[18];
                prefetch0_op_w = op_r[18];
                prefetch0_slot_w = 3'd1;
            end
            4'b0100: begin
                prefetch0_id_w = id_r[52];
                prefetch0_op_w = op_r[52];
                prefetch0_slot_w = 3'd4;
            end
            4'b1000: begin
                prefetch0_id_w = id_r[63];
                prefetch0_op_w = op_r[63];
                prefetch0_slot_w = 3'd5;
            end
            default: begin
                prefetch0_id_w = 5'b0;
            end
        endcase
    end
    assign prefetch_id_w[0 +: 5] = prefetch0_id_w;
    assign prefetch_op_w[0 +: 2] = prefetch0_op_w;
    assign prefetch_slot_w[0 +: 3] = prefetch0_slot_w;
    assign prefetch_valid_w[0] = |engine0_events_w;
    wire [3:0] engine1_events_w;
    assign engine1_events_w[0] = valid_r[29];
    assign engine1_events_w[1] = valid_r[40];
    assign engine1_events_w[2] = valid_r[75] && op_r[75][1];
    assign engine1_events_w[3] = valid_r[86] && op_r[86] == 2'd2;
    reg [4:0] prefetch1_id_w;
    reg [1:0] prefetch1_op_w;
    reg [2:0] prefetch1_slot_w;
    always @(*) begin
        prefetch1_id_w = 5'b0;
        prefetch1_op_w = 2'b0;
        prefetch1_slot_w = 3'b0;
        case (engine1_events_w)
            4'b0001: begin
                prefetch1_id_w = id_r[29];
                prefetch1_op_w = op_r[29];
                prefetch1_slot_w = 3'd2;
            end
            4'b0010: begin
                prefetch1_id_w = id_r[40];
                prefetch1_op_w = op_r[40];
                prefetch1_slot_w = 3'd3;
            end
            4'b0100: begin
                prefetch1_id_w = id_r[75];
                prefetch1_op_w = op_r[75];
                prefetch1_slot_w = 3'd6;
            end
            4'b1000: begin
                prefetch1_id_w = id_r[86];
                prefetch1_op_w = op_r[86];
                prefetch1_slot_w = 3'd7;
            end
            default: begin
                prefetch1_id_w = 5'b0;
            end
        endcase
    end
    assign prefetch_id_w[5 +: 5] = prefetch1_id_w;
    assign prefetch_op_w[2 +: 2] = prefetch1_op_w;
    assign prefetch_slot_w[3 +: 3] = prefetch1_slot_w;
    assign prefetch_valid_w[1] = |engine1_events_w;
    wire field1_update0_w;
    wire field1_update1_w;
    wire field3_update_w;
    assign field1_update0_w = complete_valid_w[0] && complete_slot_w[2:0] == 3'd1
        && complete_op_w[1:0] == 2'd0;
    assign field1_update1_w = complete_valid_w[1] && complete_slot_w[5:3] == 3'd2
        && complete_op_w[3:2] == 2'd1;
    assign field3_update_w = complete_valid_w[0] && complete_slot_w[2:0] == 3'd0
        && complete_op_w[1];
    genvar field_bank;
    generate
        for (field_bank = 0; field_bank < 8; field_bank = field_bank + 1) begin : g_field
            localparam FIELD = field_bank % 4;
            localparam ENGINE = field_bank / 4;
            if (FIELD == 2 && ENGINE == 0) begin : g_unread
                // LOG's base-table add is issued only by engine1.
                assign field_data_w[field_bank*32 +: 32] = 32'b0;
            end else begin : g_active
                wire wr_en_w;
                wire [4:0] wr_id_w;
                wire [31:0] wr_data_w;
                assign wr_en_w = front_commit_r[0]
                    || (FIELD == 1 && (field1_update0_w || field1_update1_w))
                    || (FIELD == 3 && field3_update_w);
                assign wr_id_w = front_commit_r[0] ? front_id_r[4:0]
                    : FIELD == 1 && field1_update1_w ? complete_id_w[9:5] : complete_id_w[4:0];
                assign wr_data_w = front_commit_r[0]
                    ? (FIELD == 0 ? front0_w : FIELD == 1 ? front1_w
                        : FIELD == 2 ? front2_w : front3_w)
                    : FIELD == 1 && field1_update1_w ? arithmetic_data_w[63:32]
                        : arithmetic_data_w[31:0];
                edrv32_ram_gpu2_sfu_scratch u_field (
                    .clk_i(clk_i),
                    .wr_en_i(wr_en_w),
                    .wr_addr_i(wr_id_w),
                    .wr_data_i(wr_data_w),
                    .rd_addr_i(prefetch_id_w[ENGINE*5 +: 5]),
                    .rd_data_o(field_data_w[field_bank*32 +: 32])
                );
            end
        end
    endgenerate
    genvar result_bank;
    generate
        // Slot7 is terminal for LOG and never read: seven result banks suffice.
        for (result_bank = 0; result_bank < 7; result_bank = result_bank + 1) begin : g_result
            localparam WR = result_bank == 0 || result_bank == 1
                || result_bank == 4 || result_bank == 5 ? 0 : 1;
            localparam RD = result_bank == 0 || result_bank == 3 || result_bank == 4 ? 0 : 1;
            localparam [2:0] SLOT = result_bank;
            wire [31:0] bank_data_w;
            (* keep = "true", syn_preserve = 1 *) reg [1:0] forward_r;
            // Predict the next core return at prefetch, avoiding a RAM dependency bubble.
            always @(posedge clk_i) begin
                forward_r <= {2{ahead_valid_w[WR] && ahead_slot_w[WR*3 +: 3] == SLOT
                    && ahead_id_w[WR*5 +: 5] == prefetch_id_w[RD*5 +: 5]}};
            end
            edrv32_ram_gpu2_sfu_scratch u_result (
                .clk_i(clk_i),
                .wr_en_i(complete_valid_w[WR] && complete_slot_w[WR*3 +: 3] == SLOT),
                .wr_addr_i(complete_id_w[WR*5 +: 5]),
                .wr_data_i(arithmetic_data_w[WR*32 +: 32]),
                .rd_addr_i(prefetch_id_w[RD*5 +: 5]),
                .rd_data_o(bank_data_w)
            );
            assign result_data_w[result_bank*32 +: 16] = forward_r[0]
                ? arithmetic_data_w[WR*32 +: 16] : bank_data_w[15:0];
            assign result_data_w[result_bank*32+16 +: 16] = forward_r[1]
                ? arithmetic_data_w[WR*32+16 +: 16] : bank_data_w[31:16];
        end
    endgenerate
    genvar engine;
    generate
        for (engine = 0; engine < 2; engine = engine + 1) begin : g_engine
            wire [20:0] meta_read_w;
            assign meta_read_w = meta_data_w[engine*21 +: 21];
            edrv32_ram_gpu2_sfu_meta u_meta (
                .clk_i(clk_i),
                .wr_en_i(meta_write_r[engine*2 +: 2]),
                .wr_addr_i(front_id_r[9:5]),
                .wr_data_i(front_meta_w),
                .rd_addr_i(prefetch_id_w[engine*5 +: 5]),
                .rd_data_o(meta_data_w[engine*21 +: 21])
            );
            reg issue_valid_r;
            reg [4:0] issue_id_r;
            reg [1:0] issue_op_r;
            reg [2:0] issue_slot_r;
            reg [20:0] issue_meta_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) issue_valid_r <= 1'b0;
                else issue_valid_r <= prefetch_valid_w[engine];
            end
            always @(posedge clk_i) begin
                issue_id_r <= prefetch_id_w[engine*5 +: 5];
                issue_op_r <= prefetch_op_w[engine*2 +: 2];
                issue_slot_r <= prefetch_slot_w[engine*3 +: 3];
                issue_meta_r <= front_commit_r[1]
                    && front_id_r[9:5] == prefetch_id_w[engine*5 +: 5]
                    ? front_meta_w : meta_read_w;
            end
            assign unused_issue_valid_w[engine] = issue_valid_r;
            assign unused_issue_id_w[engine*5 +: 5] = issue_id_r;
            wire [31:0] field0_w;
            wire [31:0] field1_w;
            wire [31:0] field2_w;
            wire [31:0] field3_w;
            assign field0_w = field_capture_r[engine*128 +: 32];
            assign field1_w = field_capture_r[engine*128+32 +: 32];
            assign field2_w = field_capture_r[engine*128+64 +: 32];
            assign field3_w = field_capture_r[engine*128+96 +: 32];
            wire [31:0] a_w;
            reg [5:0] a_select_w;
            (* keep = "true", syn_preserve = 1 *) reg [11:0] a_select_r;
            wire [31:0] b_w;
            reg [11:0] b_select_w;
            (* keep = "true", syn_preserve = 1 *) reg [23:0] b_select_r;
            wire [31:0] c_w;
            reg [11:0] c_select_w;
            (* keep = "true", syn_preserve = 1 *) reg [23:0] c_select_r;
            reg mul_w;
            reg mul_r;
            always @(*) begin
                a_select_w = 6'b0;
                b_select_w = 12'b0;
                c_select_w = 12'b0;
                mul_w = 1'b0;
                case (issue_slot_r)
                    3'd0: begin
                        case (issue_op_r)
                            2'd0: begin
                                a_select_w = 6'h1;
                                b_select_w = 12'h1;
                                c_select_w = 12'h1;
                                mul_w = 1'b0;
                            end
                            2'd1: begin
                                a_select_w = 6'h2;
                                b_select_w = 12'h1;
                                c_select_w = 12'b0;
                                mul_w = 1'b1;
                            end
                            2'd2: begin
                                a_select_w = 6'h4;
                                b_select_w = 12'h1;
                                c_select_w = 12'b0;
                                mul_w = 1'b1;
                            end
                            2'd3: begin
                                a_select_w = 6'h4;
                                b_select_w = 12'h2;
                                c_select_w = issue_meta_r[11] ? 12'h2 : 12'b0;
                                mul_w = !issue_meta_r[11];
                            end
                            default: begin
                                a_select_w = 6'b0;
                            end
                        endcase
                    end
                    3'd1: begin
                        case (issue_op_r)
                            2'd0: begin
                                a_select_w = 6'h2;
                                b_select_w = 12'h4;
                                c_select_w = 12'h4;
                                mul_w = 1'b0;
                            end
                            2'd1: begin
                                a_select_w = 6'h1;
                                b_select_w = 12'h4;
                                c_select_w = 12'h8;
                                mul_w = 1'b0;
                            end
                            2'd2: begin
                                a_select_w = 6'h8;
                                b_select_w = 12'h8;
                                c_select_w = 12'h10;
                                mul_w = 1'b0;
                            end
                            2'd3: begin
                                a_select_w = 6'h8;
                                b_select_w = 12'h10;
                                c_select_w = 12'h20;
                                mul_w = 1'b0;
                            end
                            default: begin
                                a_select_w = 6'b0;
                            end
                        endcase
                    end
                    3'd2: begin
                        case (issue_op_r)
                            2'd0: begin
                                a_select_w = 6'h1;
                                b_select_w = 12'h20;
                                c_select_w = 12'h1;
                                mul_w = 1'b0;
                            end
                            2'd1: begin
                                a_select_w = 6'h2;
                                b_select_w = 12'h20;
                                c_select_w = 12'b0;
                                mul_w = 1'b1;
                            end
                            2'd2: begin
                                a_select_w = 6'h4;
                                b_select_w = 12'h20;
                                c_select_w = 12'h40;
                                mul_w = 1'b0;
                            end
                            2'd3: begin
                                a_select_w = 6'h4;
                                b_select_w = 12'h20;
                                c_select_w = 12'h80;
                                mul_w = 1'b0;
                            end
                            default: begin
                                a_select_w = 6'b0;
                            end
                        endcase
                    end
                    3'd3: begin
                        case (issue_op_r)
                            2'd0: begin
                                a_select_w = 6'h2;
                                b_select_w = 12'h40;
                                c_select_w = 12'h4;
                                mul_w = 1'b0;
                            end
                            2'd1: begin
                                a_select_w = 6'h10;
                                b_select_w = 12'h40;
                                c_select_w = 12'b0;
                                mul_w = 1'b1;
                            end
                            2'd2: begin
                                a_select_w = 6'h4;
                                b_select_w = 12'h40;
                                c_select_w = 12'h100;
                                mul_w = 1'b0;
                            end
                            2'd3: begin
                                a_select_w = 6'h4;
                                b_select_w = 12'h40;
                                c_select_w = 12'h200;
                                mul_w = 1'b0;
                            end
                            default: begin
                                a_select_w = 6'b0;
                            end
                        endcase
                    end
                    3'd4: begin
                        case (issue_op_r)
                            2'd1: begin
                                a_select_w = 6'h1;
                                b_select_w = 12'h80;
                                c_select_w = 12'h8;
                                mul_w = 1'b0;
                            end
                            2'd2: begin
                                a_select_w = 6'h4;
                                b_select_w = 12'h80;
                                c_select_w = 12'h1;
                                mul_w = 1'b0;
                            end
                            2'd3: begin
                                a_select_w = 6'h4;
                                b_select_w = 12'h80;
                                c_select_w = 12'h1;
                                mul_w = 1'b0;
                            end
                            default: begin
                                a_select_w = 6'b0;
                            end
                        endcase
                    end
                    3'd5: begin
                        case (issue_op_r)
                            2'd1: begin
                                a_select_w = 6'h2;
                                b_select_w = 12'h100;
                                c_select_w = 12'b0;
                                mul_w = 1'b1;
                            end
                            2'd2: begin
                                a_select_w = 6'h4;
                                b_select_w = 12'h100;
                                c_select_w = 12'b0;
                                mul_w = 1'b1;
                            end
                            2'd3: begin
                                a_select_w = 6'h4;
                                b_select_w = 12'h100;
                                c_select_w = 12'h1;
                                mul_w = 1'b0;
                            end
                            default: begin
                                a_select_w = 6'b0;
                            end
                        endcase
                    end
                    3'd6: begin
                        case (issue_op_r)
                            2'd2: begin
                                a_select_w = 6'h1;
                                b_select_w = 12'h200;
                                c_select_w = 12'h400;
                                mul_w = 1'b0;
                            end
                            2'd3: begin
                                a_select_w = 6'h2;
                                b_select_w = 12'h400;
                                c_select_w = 12'b0;
                                mul_w = 1'b1;
                            end
                            default: begin
                                a_select_w = 6'b0;
                            end
                        endcase
                    end
                    3'd7: begin
                        case (issue_op_r)
                            2'd2: begin
                                a_select_w = 6'h20;
                                b_select_w = 12'h800;
                                c_select_w = 12'h800;
                                mul_w = 1'b0;
                            end
                            default: begin
                                a_select_w = 6'b0;
                            end
                        endcase
                    end
                    default: begin
                        a_select_w = 6'b0;
                    end
                endcase
            end
            always @(posedge clk_i) begin
                a_select_r <= {2{a_select_w}};
                b_select_r <= {2{b_select_w}};
                c_select_r <= {2{c_select_w}};
                mul_r <= mul_w;
            end
            assign a_w = ({{16{a_select_r[6]}}, {16{a_select_r[0]}}} & field0_w)
                | ({{16{a_select_r[7]}}, {16{a_select_r[1]}}} & field1_w)
                | ({{16{a_select_r[8]}}, {16{a_select_r[2]}}} & field3_w)
                | ({{16{a_select_r[9]}}, {16{a_select_r[3]}}} & result_capture_r[0 +: 32])
                | ({{16{a_select_r[10]}}, {16{a_select_r[4]}}} & result_capture_r[64 +: 32])
                | ({{16{a_select_r[11]}}, {16{a_select_r[5]}}} & result_capture_r[160 +: 32]);
            assign b_w = ({{16{b_select_r[12]}}, {16{b_select_r[0]}}} & field1_w)
                | ({{16{b_select_r[13]}}, {16{b_select_r[1]}}} & 32'h3f317218)
                | ({{16{b_select_r[14]}}, {16{b_select_r[2]}}} & result_capture_r[0 +: 32])
                | ({{16{b_select_r[15]}}, {16{b_select_r[3]}}} & 32'h3e4ccccd)
                | ({{16{b_select_r[16]}}, {16{b_select_r[4]}}} & 32'h3c088889)
                | ({{16{b_select_r[17]}}, {16{b_select_r[5]}}} & result_capture_r[32 +: 32])
                | ({{16{b_select_r[18]}}, {16{b_select_r[6]}}} & result_capture_r[64 +: 32])
                | ({{16{b_select_r[19]}}, {16{b_select_r[7]}}} & result_capture_r[96 +: 32])
                | ({{16{b_select_r[20]}}, {16{b_select_r[8]}}} & result_capture_r[128 +: 32])
                | ({{16{b_select_r[21]}}, {16{b_select_r[9]}}} & 32'h3f800000)
                | ({{16{b_select_r[22]}}, {16{b_select_r[10]}}} & result_capture_r[160 +: 32])
                | ({{16{b_select_r[23]}}, {16{b_select_r[11]}}} & 32'h3fb8aa3b);
            assign c_w = ({{16{c_select_r[12]}}, {16{c_select_r[0]}}} & 32'h3f800000)
                | ({{16{c_select_r[13]}}, {16{c_select_r[1]}}} & 32'h3c317218)
                | ({{16{c_select_r[14]}}, {16{c_select_r[2]}}} & field1_w)
                | ({{16{c_select_r[15]}}, {16{c_select_r[3]}}} & 32'h3fc00000)
                | ({{16{c_select_r[16]}}, {16{c_select_r[4]}}} & 32'hbe800000)
                | ({{16{c_select_r[17]}}, {16{c_select_r[5]}}} & 32'h3d2aaaab)
                | ({{16{c_select_r[18]}}, {16{c_select_r[6]}}} & 32'h3eaaaaab)
                | ({{16{c_select_r[19]}}, {16{c_select_r[7]}}} & 32'h3e2aaaab)
                | ({{16{c_select_r[20]}}, {16{c_select_r[8]}}} & 32'hbf000000)
                | ({{16{c_select_r[21]}}, {16{c_select_r[9]}}} & 32'h3f000000)
                | ({{16{c_select_r[22]}}, {16{c_select_r[10]}}} & field2_w)
                | ({{16{c_select_r[23]}}, {16{c_select_r[11]}}} & result_capture_r[192 +: 32]);
            wire [31:0] arithmetic_w;
            edrv32_gpu2_sfu_arithmetic u_arithmetic (
                .clk_i(clk_i),
                .mul_i(mul_r),
                .a_i(a_w),
                .b_i(b_w),
                .c_i(c_w),
                .result_o(arithmetic_w)
            );
            reg [10:0] complete_valid_r;
            reg [54:0] complete_id_r;
            reg [32:0] complete_slot_r;
            reg [21:0] complete_op_r;
            reg [219:0] complete_meta_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) complete_valid_r <= 11'b0;
                else complete_valid_r <= {complete_valid_r[9:0], issue_valid_r};
            end
            always @(posedge clk_i) begin
                complete_id_r <= {complete_id_r[49:0], issue_id_r};
                complete_slot_r <= {complete_slot_r[29:0], issue_slot_r};
                complete_op_r <= {complete_op_r[19:0], issue_op_r};
                complete_meta_r <= {complete_meta_r[199:0],
                    issue_meta_r[20:12], issue_meta_r[10:0]};
            end
            assign complete_valid_w[engine] = complete_valid_r[10];
            assign complete_id_w[engine*5 +: 5] = complete_id_r[54:50];
            assign complete_slot_w[engine*3 +: 3] = complete_slot_r[32:30];
            assign complete_op_w[engine*2 +: 2] = complete_op_r[21:20];
            assign arithmetic_data_w[engine*32 +: 32] = arithmetic_w;
            assign ahead_valid_w[engine] = complete_valid_r[9];
            assign ahead_id_w[engine*5 +: 5] = complete_id_r[49:45];
            assign ahead_slot_w[engine*3 +: 3] = complete_slot_r[29:27];
            wire [19:0] return_meta_w;
            wire [2:0] return_class_w;
            wire [31:0] special_data_w;
            wire terminal_w;
            assign return_meta_w = complete_meta_r[219:200];
            assign return_class_w = return_meta_w[14:12];
            assign special_data_w = return_class_w[2] ? 32'h7fc00000
                : {return_class_w[0], return_class_w[1] ? 8'hff : 8'b0, 23'b0};
            assign terminal_w = complete_valid_r[10]
                && (complete_op_r[21:20] == 2'd0 ? complete_slot_r[32:30] == 3'd3
                    : complete_op_r[21:20] == 2'd1 ? complete_slot_r[32:30] == 3'd5
                    : complete_op_r[21:20] == 2'd2 ? complete_slot_r[32:30] == 3'd7
                    : complete_slot_r[32:30] == 3'd6);
            wire [31:0] scaled_w;
            edrv32_gpu2_sfu_scale u_scale (
                .clk_i(clk_i),
                .data_i(arithmetic_w),
                .scale_i(return_meta_w[9:0]),
                .sign_i(return_meta_w[10]),
                .special_i(return_meta_w[11]),
                .special_data_i(special_data_w),
                .data_o(scaled_w)
            );
            reg [1:0] scale_valid_r;
            (* keep = "true", syn_preserve = 1 *) reg [2:0] queue_write_r;
            reg [9:0] scale_tag_r;
            reg [5:0] count_r;
            reg [4:0] wr_r;
            reg [4:0] rd_r;
            wire pop_w;
            wire push_w;
            wire [36:0] queue_w;
            wire queue_valid_w;
            assign queue_valid_w = count_r != 0;
            assign pop_w = response_pop_w[engine];
            assign push_w = scale_valid_r[1];
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    scale_valid_r <= 2'b0;
                    queue_write_r <= 3'b0;
                    count_r <= 6'b0;
                    wr_r <= 5'b0;
                    rd_r <= 5'b0;
                end else begin
                    scale_valid_r <= {scale_valid_r[0], terminal_w};
                    queue_write_r <= {3{scale_valid_r[0]}};
                    count_r <= count_r + {5'b0, push_w} - {5'b0, pop_w};
                    wr_r <= wr_r + {4'b0, push_w};
                    rd_r <= rd_r + {4'b0, pop_w};
                end
            end
            always @(posedge clk_i) begin
                scale_tag_r <= {scale_tag_r[4:0], return_meta_w[19:15]};
            end
            edrv32_ram_gpu2_sfu_queue u_queue (
                .clk_i(clk_i),
                .wr_en_i(queue_write_r),
                .wr_addr_i(wr_r),
                .wr_data_i({scale_tag_r[9:5], scaled_w}),
                .rd_addr_i(rd_r),
                .rd_data_o(queue_w)
            );
            if (engine == 0) begin : g_resp0
                assign resp0_valid_o = queue_valid_w;
                assign resp0_data_o = queue_w[31:0];
                assign resp0_tag_o = queue_w[36:32];
            end else begin : g_resp1
                assign resp1_valid_o = queue_valid_w;
                assign resp1_data_o = queue_w[31:0];
                assign resp1_tag_o = queue_w[36:32];
            end
        end
    endgenerate
endmodule
