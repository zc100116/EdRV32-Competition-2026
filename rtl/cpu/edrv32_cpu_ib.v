// File: edrv32_cpu_ib.v
// Spec: cpu-spec 4.1, 4.2
// Description: Queue instruction records between F2 and D in program order.
// Accept up to two records and retire up to two queue entries per clock.
// Clock domain: clk_sys.
module edrv32_cpu_ib (
    // Clock and queue control reset.
    input wire clk_i,
    input wire rst_n_i,
    // F2 input: each 179-bit record is described in rtl/cpu/README.md.
    input wire [1:0] push_count_i,
    input wire [357:0] push_data_i,
    input wire [5:0] push_index_hi_i,
    output wire [5:0] index_hi_o,
    input wire [23:0] push_tournament_i,
    output wire [23:0] tournament_o,
    // D observes the oldest two records and consumes 0, 1 or 2.
    input wire [1:0] pop_count_i,
    output wire [357:0] data_o,
    // Per-slot predecode: {jal,slow,dest,serial,memory,control,csr,mul,load,
    // immediate[31:0],ALU[3:0],class[3:0],pipe1,illegal,imm,write,use2,use1,rd,rs2,rs1}.
    output wire [139:0] predecode_o,
    // Four 8-bit register-file slices each get their own four source-register addresses.
    output wire [79:0] operand_addr_o,
    output wire [1:0] valid_count_o,
    // A stalled D redirect retains its head; older redirects discard the whole queue.
    input wire flush_i,
    input wire keep_head_i,
    input wire keep_pair_i,
    output wire [2:0] count_o
);
    localparam RECORD_BITS = 179;
    localparam [2:0] DEPTH = 3'd4;
    reg [RECORD_BITS-1:0] entries_r [0:DEPTH-1];
    wire [69:0] push_predecode_w [0:1];
    reg [2:0] index_hi_r [0:DEPTH-1];
    reg [11:0] tournament_r [0:DEPTH-1];
    reg [1:0] read_ptr_r;
    reg [1:0] write_ptr_r;
    reg [2:0] count_r;
    wire [1:0] read_next_w;
    wire [1:0] keep_count_w;
    assign keep_count_w = keep_pair_i ? 2'd2 : 2'd1;
    assign read_next_w = read_ptr_r + keep_count_w;
    // Each output slice owns its read-select FFs; all copies take the same next pointer.
    genvar read_slot;
    genvar read_slice;
    genvar write_entry;
    genvar operand_slice;
    genvar decode_slot;
    generate
        for (decode_slot = 0; decode_slot < 2;
            decode_slot = decode_slot + 1) begin : g_predecode
            wire [31:0] instr_w;
            wire [4:0] rs1_w;
            wire [4:0] rs2_w;
            wire [4:0] rd_w;
            wire use1_w;
            wire use2_w;
            wire write_w;
            wire [31:0] immediate_w;
            wire [3:0] class_w;
            wire [3:0] operation_w;
            wire operand_imm_w;
            wire illegal_w;
            wire pipe1_w;
            assign instr_w = data_o[decode_slot*RECORD_BITS+32 +: 32];
            edrv32_cpu_decode u_decode (
                .instr_i(instr_w),
                .rs1_o(rs1_w),
                .rs2_o(rs2_w),
                .rd_o(rd_w),
                .rs1_used_o(use1_w),
                .rs2_used_o(use2_w),
                .rd_write_o(write_w),
                .imm_o(immediate_w),
                .class_o(class_w),
                .alu_operation_o(operation_w),
                .operand_imm_o(operand_imm_w),
                .illegal_o(illegal_w)
            );
            // Capability follows opcode families, including their illegal encodings.
            assign pipe1_w = instr_w[6:0] == 7'h13 || instr_w[6:0] == 7'h37 ||
                instr_w[6:0] == 7'h17 ||
                (instr_w[6:0] == 7'h33 && instr_w[31:25] != 1) ||
                instr_w[6:0] == 7'h63 || instr_w[6:0] == 7'h6f;
            assign push_predecode_w[decode_slot] = {
                class_w == 4'd3,
                class_w == 4'd6 || class_w == 4'd8 || class_w == 4'd10,
                write_w && rd_w != 0,
                class_w >= 4'd10,
                class_w == 4'd6 || class_w == 4'd7,
                class_w >= 4'd3 && class_w <= 4'd5,
                class_w == 4'd10,
                class_w == 4'd8,
                class_w == 4'd6,
                immediate_w, operation_w, class_w, pipe1_w, illegal_w, operand_imm_w,
                write_w, use2_w, use1_w, rd_w, rs2_w, rs1_w};
            // cpu-spec v0.21: decode belongs to D1, after the IB read mux.
            assign predecode_o[decode_slot*70 +: 70] = push_predecode_w[decode_slot];
        end
        for (read_slot = 0; read_slot < 2; read_slot = read_slot + 1) begin : g_read_slot
            localparam SLOT = read_slot;
            assign tournament_o[read_slot*12 +: 12] =
                tournament_r[read_ptr_r + SLOT[1:0]];
            assign index_hi_o[read_slot*3 +: 3] =
                index_hi_r[read_ptr_r + SLOT[1:0]];
            for (read_slice = 0; read_slice < 6;
                read_slice = read_slice + 1) begin : g_read_slice
                localparam SLICE_BITS = read_slice == 5 ? 19 : 32;
                reg [1:0] read_ptr_copy_r /* synthesis syn_preserve=1 */;
                wire [1:0] slot_w;
                assign slot_w = read_ptr_copy_r + SLOT[1:0];
                assign data_o[read_slot*RECORD_BITS + read_slice*32 +: SLICE_BITS] =
                    entries_r[slot_w][read_slice*32 +: SLICE_BITS];
                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i)
                        read_ptr_copy_r <= 0;
                    else if (flush_i)
                        read_ptr_copy_r <= keep_head_i ? read_ptr_r : 2'd0;
                    else
                        read_ptr_copy_r <= read_ptr_r + pop_count_i;
                end
            end
        end
        for (operand_slice = 0; operand_slice < 8;
            operand_slice = operand_slice + 1) begin : g_operand_read
            localparam SLOT = operand_slice % 2;
            localparam SLICE = operand_slice / 2;
            reg [1:0] read_ptr_copy_r /* synthesis syn_preserve=1 */;
            wire [1:0] slot_w;
            assign slot_w = read_ptr_copy_r + SLOT[1:0];
            // Record[56:47] is {instruction.rs2, instruction.rs1}.
            assign operand_addr_o[SLICE*20 + SLOT*10 +: 10] = entries_r[slot_w][56:47];
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    read_ptr_copy_r <= 0;
                else if (flush_i)
                    read_ptr_copy_r <= keep_head_i ? read_ptr_r : 2'd0;
                else
                    read_ptr_copy_r <= read_ptr_r + pop_count_i;
            end
        end
        // Decode each destination locally instead of a dynamic 716-bit write mux.
        for (write_entry = 0; write_entry < 4;
            write_entry = write_entry + 1) begin : g_write_entry
            reg [1:0] write_ptr_r_copy /* synthesis syn_preserve=1 */;
            wire [1:0] write_next_w_copy;
            assign write_next_w_copy = write_ptr_r_copy + 1'b1;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    write_ptr_r_copy <= 0;
                else if (flush_i)
                    write_ptr_r_copy <= keep_head_i ? read_next_w : 2'd0;
                else
                    write_ptr_r_copy <= write_ptr_r + push_count_i;
            end
            always @(posedge clk_i) begin
                if (!flush_i) begin
                    if (push_count_i != 0 && write_ptr_r_copy == write_entry[1:0])
                        index_hi_r[write_entry] <= push_index_hi_i[2:0];
                    if (push_count_i != 0 && write_ptr_r_copy == write_entry[1:0])
                        tournament_r[write_entry] <= push_tournament_i[11:0];
                    if (push_count_i == 2 && write_next_w_copy == write_entry[1:0])
                        index_hi_r[write_entry] <= push_index_hi_i[5:3];
                    if (push_count_i == 2 && write_next_w_copy == write_entry[1:0])
                        tournament_r[write_entry] <= push_tournament_i[23:12];
                    if (push_count_i != 0 && write_ptr_r_copy == write_entry[1:0]) begin
                        entries_r[write_entry] <= push_data_i[178:0];
                    end
                    if (push_count_i == 2 && write_next_w_copy == write_entry[1:0]) begin
                        entries_r[write_entry] <= push_data_i[357:179];
                    end
                end
            end
        end
    endgenerate
    assign valid_count_o = count_r >= 2 ? 2'd2 : count_r[1:0];
    assign count_o = count_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            read_ptr_r <= 0;
            write_ptr_r <= 0;
            count_r <= 0;
        end else if (flush_i) begin
            read_ptr_r <= keep_head_i ? read_ptr_r : 2'd0;
            write_ptr_r <= keep_head_i ? read_next_w : 2'd0;
            count_r <= keep_head_i ? {1'b0, keep_count_w} : 3'd0;
        end else begin
            read_ptr_r <= read_ptr_r + pop_count_i;
            write_ptr_r <= write_ptr_r + push_count_i;
            count_r <= count_r + {1'b0, push_count_i} - {1'b0, pop_count_i};
        end
    end
endmodule
