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
    input wire push_one_i,
    input wire push_two_i,
    input wire [7:0] push_one_copy_i,
    input wire [7:0] push_two_copy_i,
    input wire [357:0] push_data_i,
    input wire [43:0] push_predecode_i,
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
    (* keep = "true", syn_preserve = 1 *) reg [69:0] predecode_r [0:DEPTH-1];
    wire [69:0] push_predecode_w [0:1];
    reg [2:0] index_hi_r [0:DEPTH-1];
    reg [11:0] tournament_r [0:DEPTH-1];
    reg [1:0] read_ptr_r;
    reg [1:0] write_ptr_r;
    reg [2:0] count_r;
    wire [1:0] read_next_w;
    wire [1:0] write_next_w;
    assign write_next_w = push_two_i ? write_ptr_r + 2'd2 :
        push_one_i ? write_ptr_r + 2'd1 : write_ptr_r;
    wire [1:0] keep_count_w;
    assign keep_count_w = keep_pair_i ? 2'd2 : 2'd1;
    assign read_next_w = read_ptr_r + keep_count_w;
    // Each output slice owns its read-select FFs; all copies take the same next pointer.
    genvar read_slot;
    genvar read_slice;
    genvar write_entry;
    genvar operand_slice;
    genvar decode_slot;
    genvar decode_slice;
    genvar write_slice;
    generate
        for (decode_slot = 0; decode_slot < 2;
            decode_slot = decode_slot + 1) begin : g_predecode
            localparam SLOT = decode_slot;
            wire [31:0] instr_w;
            wire unused_opcode_w;
            assign unused_opcode_w = &{1'b0, instr_w[6:0]};
            wire [21:0] stored_w;
            wire [31:0] immediate_w;
            wire format_u_w;
            wire format_i_w;
            assign instr_w = push_data_i[decode_slot*RECORD_BITS+32 +: 32];
            assign stored_w = push_predecode_i[decode_slot*22 +: 22];
            assign format_u_w = stored_w[19];
            assign format_i_w = !(|stored_w[21:18]);
            // One-hot immediate formats select raw instruction fragments in parallel.
            assign immediate_w =
                ({32{format_i_w}} & {{20{instr_w[31]}}, instr_w[31:20]}) |
                ({32{format_u_w}} & {instr_w[31:12], 12'b0}) |
                ({32{stored_w[21]}} &
                    {{20{instr_w[31]}}, instr_w[31:25], instr_w[11:7]}) |
                ({32{stored_w[20]}} & {{19{instr_w[31]}}, instr_w[31], instr_w[7],
                    instr_w[30:25], instr_w[11:8], 1'b0}) |
                ({32{stored_w[18]}} & {{11{instr_w[31]}}, instr_w[31], instr_w[19:12],
                    instr_w[20], instr_w[30:21], 1'b0});
            assign push_predecode_w[decode_slot] = {
                stored_w[18:17], stored_w[2] && instr_w[11:7] != 0, stored_w[16:11],
                immediate_w, stored_w[6], instr_w[14:12], stored_w[10:7], stored_w[5:0],
                instr_w[11:7], instr_w[24:20], instr_w[19:15]};
            for (decode_slice = 0; decode_slice < 5;
                decode_slice = decode_slice + 1) begin : g_read
                localparam SLICE_BITS = decode_slice == 4 ? 6 : 16;
                (* keep = "true", syn_preserve = 1 *) reg [3:0] read_select_copy1_r;
                wire [1:0] next_ptr_w;
                assign next_ptr_w = read_ptr_r + pop_count_i + SLOT[1:0];
                assign predecode_o[decode_slot*70 + decode_slice*16 +: SLICE_BITS] =
                    ({SLICE_BITS{read_select_copy1_r[0]}} &
                        predecode_r[0][decode_slice*16 +: SLICE_BITS]) |
                    ({SLICE_BITS{read_select_copy1_r[1]}} &
                        predecode_r[1][decode_slice*16 +: SLICE_BITS]) |
                    ({SLICE_BITS{read_select_copy1_r[2]}} &
                        predecode_r[2][decode_slice*16 +: SLICE_BITS]) |
                    ({SLICE_BITS{read_select_copy1_r[3]}} &
                        predecode_r[3][decode_slice*16 +: SLICE_BITS]);
                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i)
                        read_select_copy1_r <= 4'b1 << SLOT;
                    else if (flush_i)
                        read_select_copy1_r <= keep_head_i ? read_select_copy1_r : 4'b1 << SLOT;
                    else
                        read_select_copy1_r <= 4'b1 << next_ptr_w;
                end
            end
        end
        for (read_slot = 0; read_slot < 2; read_slot = read_slot + 1) begin : g_read_slot
            localparam SLOT = read_slot;
            assign tournament_o[read_slot*12 +: 12] =
                tournament_r[read_ptr_r + SLOT[1:0]];
            assign index_hi_o[read_slot*3 +: 3] =
                index_hi_r[read_ptr_r + SLOT[1:0]];
            for (read_slice = 0; read_slice < 12;
                read_slice = read_slice + 1) begin : g_read_slice
                localparam SLICE_BITS = read_slice == 11 ? 3 : 16;
                reg [3:0] read_select_copy_r /* synthesis syn_preserve=1 */;
                wire [1:0] next_ptr_w;
                assign next_ptr_w = read_ptr_r + pop_count_i + SLOT[1:0];
                assign data_o[read_slot*RECORD_BITS + read_slice*16 +: SLICE_BITS] =
                    ({SLICE_BITS{read_select_copy_r[0]}} &
                        entries_r[0][read_slice*16 +: SLICE_BITS]) |
                    ({SLICE_BITS{read_select_copy_r[1]}} &
                        entries_r[1][read_slice*16 +: SLICE_BITS]) |
                    ({SLICE_BITS{read_select_copy_r[2]}} &
                        entries_r[2][read_slice*16 +: SLICE_BITS]) |
                    ({SLICE_BITS{read_select_copy_r[3]}} &
                        entries_r[3][read_slice*16 +: SLICE_BITS]);
                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i)
                        read_select_copy_r <= 4'b1 << SLOT;
                    else if (flush_i)
                        read_select_copy_r <= keep_head_i ? read_select_copy_r : 4'b1 << SLOT;
                    else
                        read_select_copy_r <= 4'b1 << next_ptr_w;
                end
            end
        end
        for (operand_slice = 0; operand_slice < 8;
            operand_slice = operand_slice + 1) begin : g_operand_read
            localparam SLOT = operand_slice % 2;
            localparam SLICE = operand_slice / 2;
            reg [3:0] read_select_copy_r /* synthesis syn_preserve=1 */;
            wire [1:0] next_ptr_w;
            assign next_ptr_w = read_ptr_r + pop_count_i + SLOT[1:0];
            // Record[56:47] is {instruction.rs2, instruction.rs1}.
            assign operand_addr_o[SLICE*20 + SLOT*10 +: 10] =
                ({10{read_select_copy_r[0]}} & entries_r[0][56:47]) |
                ({10{read_select_copy_r[1]}} & entries_r[1][56:47]) |
                ({10{read_select_copy_r[2]}} & entries_r[2][56:47]) |
                ({10{read_select_copy_r[3]}} & entries_r[3][56:47]);
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    read_select_copy_r <= 4'b1 << SLOT;
                else if (flush_i)
                    read_select_copy_r <= keep_head_i ? read_select_copy_r : 4'b1 << SLOT;
                else
                    read_select_copy_r <= 4'b1 << next_ptr_w;
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
                    write_ptr_r_copy <= write_next_w;
            end
            always @(posedge clk_i) begin
                if (!flush_i) begin
                    if (push_one_i && write_ptr_r_copy == write_entry[1:0])
                        index_hi_r[write_entry] <= push_index_hi_i[2:0];
                    if (push_one_i && write_ptr_r_copy == write_entry[1:0])
                        tournament_r[write_entry] <= push_tournament_i[11:0];
                    if (push_two_i && write_next_w_copy == write_entry[1:0])
                        index_hi_r[write_entry] <= push_index_hi_i[5:3];
                    if (push_two_i && write_next_w_copy == write_entry[1:0])
                        tournament_r[write_entry] <= push_tournament_i[23:12];
                end
            end
            // Wide record slices own both pointer and late-response enable copies.
            // A response event never drives a whole 249-bit slot-selection cone.
            for (write_slice = 0; write_slice < 17;
                write_slice = write_slice + 1) begin : g_slice
                localparam GROUP = (write_entry*17 + write_slice) % 8;
                localparam WIDTH = write_slice == 11 ? 3 : write_slice == 16 ? 6 : 16;
                (* keep = "true", syn_preserve = 1 *) reg [1:0] write_ptr_copy1_r;
                wire write0_w;
                wire write1_w;
                assign write0_w = !flush_i && push_one_copy_i[GROUP] &&
                    write_ptr_copy1_r == write_entry[1:0];
                assign write1_w = !flush_i && push_two_copy_i[GROUP] &&
                    (write_ptr_copy1_r + 2'd1) == write_entry[1:0];
                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i)
                        write_ptr_copy1_r <= 0;
                    else if (flush_i)
                        write_ptr_copy1_r <= keep_head_i ? read_next_w : 2'd0;
                    else
                        write_ptr_copy1_r <= write_next_w;
                end
                if (write_slice < 12) begin : g_record
                    always @(posedge clk_i) begin
                        if (write0_w || write1_w)
                            entries_r[write_entry][write_slice*16 +: WIDTH] <=
                                ({WIDTH{write0_w}} & push_data_i[write_slice*16 +: WIDTH]) |
                                ({WIDTH{write1_w}} & push_data_i[179+write_slice*16 +: WIDTH]);
                    end
                end else begin : g_controls
                    localparam OFFSET = (write_slice-12)*16;
                    always @(posedge clk_i) begin
                        if (write0_w || write1_w)
                            predecode_r[write_entry][OFFSET +: WIDTH] <=
                                ({WIDTH{write0_w}} & push_predecode_w[0][OFFSET +: WIDTH]) |
                                ({WIDTH{write1_w}} & push_predecode_w[1][OFFSET +: WIDTH]);
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
            write_ptr_r <= write_next_w;
            count_r <= count_r + {1'b0, push_count_i} - {1'b0, pop_count_i};
        end
    end
endmodule
