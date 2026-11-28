// File: tb.sv
// Spec: fpu-spec 2.1-2.4, 3.1, 5.2-5.4; FV02/04-07/09/11/16.
// Description: Exact-reference scoreboarding, completion stalls, inclusive cancellation
// and tag wraparound; expected values depend only on external input vectors.
// Clock domain: simulation clk_sys.
module tb;
    import edrv32_fpu_vectors_pkg::*;
    parameter [31:0] FPU_FORMAT = "F";
    localparam B = FPU_FORMAT == "FD" ? 64 : 32;
    localparam T = FPU_FORMAT == "FD" ? 4 : 3;
    localparam N = 1 << T;
    reg clk;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    reg rst_n;
    reg req_valid;
    wire req_ready;
    reg [31:0] instr;
    reg [B-1:0] src1;
    reg [B-1:0] src2;
    reg [B-1:0] src3;
    reg [31:0] int_src;
    reg [2:0] rm;
    reg [T-1:0] req_tag;
    wire resp_valid;
    reg resp_ready;
    wire [T-1:0] resp_tag;
    wire [B-1:0] resp_data;
    wire [4:0] resp_flags;
    wire resp_int_dest;
    reg [T-1:0] age_head;
    reg cancel_valid;
    reg [T-1:0] cancel_tag;
    edrv32_cpu2_fpu_short #(.FPU_FORMAT(FPU_FORMAT)) u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .unit_req_valid_i(req_valid),
        .unit_req_ready_o(req_ready),
        .unit_req_instr_i(instr),
        .unit_req_tag_i(req_tag),
        .unit_req_src1_i(src1),
        .unit_req_src2_i(src2),
        .unit_resp_valid_o(resp_valid),
        .unit_resp_ready_i(resp_ready),
        .unit_resp_tag_o(resp_tag),
        .unit_resp_data_o(resp_data),
        .unit_resp_flags_o(resp_flags),
        .unit_resp_int_dest_o(resp_int_dest),
        .age_head_i(age_head),
        .cancel_valid_i(cancel_valid),
        .cancel_tag_i(cancel_tag)
    );
    reg [B-1:0] expected [0:N-1];
    reg [4:0] expected_flags [0:N-1];
    reg expected_dest [0:N-1];
    reg [31:0] expected_instr [0:N-1];
    reg allocated [0:N-1];
    reg completed [0:N-1];
    integer accepted_cycle [0:N-1];
    integer head_seq;
    integer tail_seq;
    integer cycle;
    integer accepted;
    integer checked;
    integer cancelled;
    integer fd;
    integer fields;
    integer cutoff;
    integer latency;
    reg [B-1:0] reference_data;
    reg [4:0] reference_flags;
    reg reference_dest;
    reg have_vector;
    reg eof;
    reg held;
    reg [T-1:0] held_tag;
    reg [B-1:0] held_data;
    reg [4:0] held_flags;
    reg held_dest;
    reg [31:0] random_r;
    bit softfloat_mode;
    bit stress_mode;
    bit vector_available;
    fpu_vector_t vector_w;
    fpu_vector_t saved_vector [0:N-1];
    string vector_path;
    initial begin
        rst_n = 0;
        req_valid = 0;
        resp_ready = 1;
        age_head = 0;
        cancel_valid = 0;
        cancel_tag = 0;
        head_seq = 0;
        tail_seq = 0;
        cycle = 0;
        accepted = 0;
        checked = 0;
        cancelled = 0;
        have_vector = 0;
        eof = 0;
        held = 0;
        random_r = 32'hf02a51;
        if (!$value$plusargs("VECTORS=%s", vector_path)) $fatal(1, "Missing VECTORS");
        softfloat_mode = $test$plusargs("SOFTFLOAT");
        stress_mode = $test$plusargs("STRESS");
        fd = $fopen(vector_path, "r");
        if (fd == 0) $fatal(1, "Cannot open vectors");
        for (integer j = 0; j < N; j = j+1) begin
            allocated[j] = 0;
            completed[j] = 0;
        end
        repeat (3) @(negedge clk);
        rst_n = 1;
        while (!eof || have_vector || tail_seq != head_seq) begin
            @(negedge clk);
            cycle = cycle + 1;
            random_r = {random_r[30:0], random_r[31]^random_r[21]^random_r[1]^random_r[0]};
            if (!have_vector && !eof) begin
                if (softfloat_mode) begin
                    read_vector(fd, vector_w, vector_available);
                    fields = vector_available ? 9 : -1;
                    instr = vector_w.instr;
                    rm = vector_w.rm;
                    src1 = B'(vector_w.src1);
                    src2 = B'(vector_w.src2);
                    src3 = B'(vector_w.src3);
                    int_src = vector_w.int_src;
                    reference_data = B'(vector_w.result);
                    reference_flags = vector_w.flags;
                    reference_dest = vector_w.int_dest;
                    // Emulate the top's specified boxing boundary before an S unit.
                    // FMV.X.W keeps raw low bits; integer-source operations ignore FP.
                    if (FPU_FORMAT == "FD" && !instr[25]) begin
                        if (vector_w.src1[63:32] != 32'hffffffff) src1 = B'(64'hffffffff7fc00000);
                        if (vector_w.src2[63:32] != 32'hffffffff) src2 = B'(64'hffffffff7fc00000);
                    end
                end else begin
                fields = $fscanf(fd, "%h %h %h %h %h %h %h %h %h\n",
                    instr, src1, src2, src3, int_src, rm,
                    reference_data, reference_flags, reference_dest);
                    if (FPU_FORMAT == "FD" && !reference_dest)
                        reference_data = B'(64'hffffffff00000000 | 64'(reference_data));
                    vector_w.instr = instr;
                    vector_w.rm = rm;
                    vector_w.src1 = 64'(src1);
                    vector_w.src2 = 64'(src2);
                    vector_w.src3 = 64'(src3);
                    vector_w.int_src = int_src;
                    vector_w.result = 64'(reference_data);
                    vector_w.flags = reference_flags;
                    vector_w.int_dest = reference_dest;
                end
                if (fields == 9) have_vector = 1;
                else if (fields == -1 || fields == 0) eof = 1;
                else $fatal(1, "Malformed vector fields=%0d", fields);
            end
            // First 32 transactions run alone for latency checks. Thereafter
            // stalls include long full-skid intervals, bubbles and same-edge flushes.
            req_valid = have_vector && (tail_seq-head_seq < N)
                && (accepted >= 32 || tail_seq == head_seq);
            req_tag = T'(tail_seq % N);
            age_head = T'(head_seq % N);
            resp_ready = !stress_mode || accepted < 32 || ((cycle % 97 < 69) && (random_r[3:0] != 0));
            cancel_valid = stress_mode && accepted >= 32 && cycle % 127 == 33 && tail_seq != head_seq;
            cutoff = head_seq + ((tail_seq-head_seq)/2);
            cancel_tag = T'(cutoff % N);
            @(posedge clk);
            if (held && !cancel_valid) begin
                if (!resp_valid || {resp_tag,resp_data,resp_flags,resp_int_dest}
                    !== {held_tag,held_data,held_flags,held_dest}) begin
                    $fatal(1, "Response changed under backpressure cycle=%0d",cycle);
                end
            end
            held = resp_valid && !resp_ready && !cancel_valid;
            held_tag = resp_tag;
            held_data = resp_data;
            held_flags = resp_flags;
            held_dest = resp_int_dest;
            if (resp_valid && resp_ready) begin
                if (!allocated[resp_tag] || completed[resp_tag]) begin
                    $fatal(1, "Unexpected/duplicate result tag=%0d cycle=%0d",resp_tag,cycle);
                end
                if (softfloat_mode) begin
                    if ({resp_data,resp_flags,resp_int_dest}
                        !== {expected[resp_tag],expected_flags[resp_tag],expected_dest[resp_tag]}) begin
                        $display("tag=%0d cycle=%0d protocol_seed=f02a51",resp_tag,cycle);
                    end
                    compare_response(saved_vector[resp_tag],64'(resp_data),
                        resp_flags,resp_int_dest);
                end
                if ({resp_data,resp_flags,resp_int_dest}
                    !== {expected[resp_tag],expected_flags[resp_tag],expected_dest[resp_tag]}) begin
                    $display("a=%h b=%h c=%h int=%h rm=%h cycle=%0d seed=f02a51",
                        saved_vector[resp_tag].src1,saved_vector[resp_tag].src2,
                        saved_vector[resp_tag].src3,saved_vector[resp_tag].int_src,
                        saved_vector[resp_tag].rm,cycle);
                    $fatal(1, "tag=%0d instr=%08h expected=%08h/%02h/%0d actual=%08h/%02h/%0d",
                        resp_tag,expected_instr[resp_tag],expected[resp_tag],
                        expected_flags[resp_tag],expected_dest[resp_tag],
                        resp_data,resp_flags,resp_int_dest);
                end
                latency = cycle - accepted_cycle[resp_tag];
                if (accepted < 32) begin
                    if (latency != (expected_instr[resp_tag][31:26] == 6'b001000 ? 1 : 2)) begin
                        $fatal(1, "Latency mismatch instr=%08h cycles=%0d",
                            expected_instr[resp_tag],latency);
                    end
                    $display("LATENCY instr=%08h cycles=%0d",expected_instr[resp_tag],latency);
                end
                completed[resp_tag] = 1;
                checked = checked + 1;
            end
            if (req_valid && req_ready) begin
                if (allocated[req_tag]) $fatal(1, "Tag reuse while live");
                saved_vector[req_tag] = vector_w;
                expected[req_tag] = reference_data;
                expected_flags[req_tag] = reference_flags;
                expected_dest[req_tag] = reference_dest;
                expected_instr[req_tag] = instr;
                accepted_cycle[req_tag] = cycle;
                allocated[req_tag] = 1;
                completed[req_tag] = 0;
                tail_seq = tail_seq + 1;
                accepted = accepted + 1;
                have_vector = 0;
            end
            if (cancel_valid) begin
                for (integer seq = cutoff; seq < tail_seq; seq = seq+1) begin
                    allocated[seq % N] = 0;
                    completed[seq % N] = 0;
                    cancelled = cancelled + 1;
                end
                tail_seq = cutoff;
            end
            while (head_seq != tail_seq && completed[head_seq % N]) begin
                allocated[head_seq % N] = 0;
                completed[head_seq % N] = 0;
                head_seq = head_seq + 1;
            end
            #1;
            if (cycle > 50000000) $fatal(1, "Test timeout");
        end
        req_valid = 0;
        cancel_valid = 0;
        repeat (16) begin
            @(posedge clk);
            if (resp_valid) $fatal(1, "Late result after drain");
        end
        $display("PASS accepted=%0d checked=%0d cancelled=%0d cycles=%0d format=%s",
            accepted,checked,cancelled,cycle,FPU_FORMAT);
        $finish;
    end
    wire unused_inputs = ^{src2,src3,int_src,rm};
endmodule
