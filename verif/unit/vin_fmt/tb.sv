// File: tb.sv
// Spec: vin 2.2, 5.2, 6.
// Description: Independent normalized-word oracle for short/long lines and frames.
// Clock domain: clk_mem.
module tb;
    bit clk = 0;
    always #4 clk = ~clk;
    bit rst_n = 0;
    bit enable = 0;
    bit in_valid = 0;
    wire in_ready;
    bit [35:0] item;
    wire out_valid;
    bit out_ready = 1;
    wire [31:0] data;
    wire sof;
    wire eol;
    wire eof;
    wire [31:0] id;
    wire [10:0] out_width;
    wire [11:0] out_height;
    wire incomplete;
    bit [10:0] width = 6;
    bit [11:0] height = 3;
    wire frame;
    wire incomplete_frame;
    wire cfg_error;
    typedef struct packed {
        bit [31:0] data;
        bit sof;
        bit eol;
        bit eof;
        bit incomplete;
        bit [31:0] id;
    } word_t;
    word_t expected[$];
    int frames;
    int incomplete_frames;
    int errors;
    int cycles;
    edrv32_vin_fmt u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .item_valid_i(in_valid),
        .item_ready_o(in_ready),
        .item_data_i(item),
        .valid_o(out_valid),
        .ready_i(out_ready),
        .data_o(data),
        .sof_o(sof),
        .eol_o(eol),
        .eof_o(eof),
        .frame_id_o(id),
        .width_o(out_width),
        .height_o(out_height),
        .incomplete_o(incomplete),
        .enable_i(enable),
        .width_i(width),
        .height_i(height),
        .frame_o(frame),
        .incomplete_frame_o(incomplete_frame),
        .cfg_error_o(cfg_error)
    );
    always @(negedge clk) begin
        cycles++;
        out_ready = cycles % 7 != 0 && cycles % 7 != 1;
    end
    always @(posedge clk) begin
        word_t want;
        if (rst_n) begin
            if (frame) frames++;
            if (incomplete_frame) incomplete_frames++;
            if (cfg_error) errors++;
            if (out_valid && out_ready) begin
                if (expected.size() == 0) $fatal(1, "FAIL unexpected normalized word");
                want = expected.pop_front();
                if ({data, sof, eol, eof, id} !==
                    {want.data, want.sof, want.eol, want.eof, want.id})
                    $fatal(1, "FAIL word want=%h got=%h markers=%b%b%b id=%0d t=%0t",
                        want.data, data, sof, eol, eof, id, $time);
                if (eof && incomplete !== want.incomplete)
                    $fatal(1, "FAIL incomplete want=%b got=%b", want.incomplete, incomplete);
            end
        end
    end
    task automatic send(input int typ, input bit last, input int d = 0, input bit lost = 0);
        @(negedge clk);
        in_valid = 1;
        item = {2'(typ), last, lost, 32'(d)};
        do @(posedge clk); while (!in_ready);
        @(negedge clk);
        in_valid = 0;
    endtask
    task automatic discard_frame;
        send(2, 0);
        send(0, 1, 32'hdeadbeef);
        send(3, 0);
    endtask
    task automatic expect_frame(input int w, input int h, input int fid, input bit bad,
                               input bit [31:0] words[]);
        word_t entry;
        for (int n = 0; n < w*h; n++) begin
            entry.data = words[n];
            entry.sof = n == 0;
            entry.eol = n % w == w-1;
            entry.eof = n == w*h-1;
            entry.incomplete = bad;
            entry.id = fid;
            expected.push_back(entry);
        end
    endtask
    task automatic settle;
        repeat (200) @(negedge clk);
        if (expected.size() != 0) $fatal(1, "FAIL missing %0d words", expected.size());
    endtask
    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        discard_frame(); // Disabled input is drained.
        enable = 1;
        repeat (3) @(negedge clk);
        width = 0; // Config validation also occurs on enabled discarded frame starts.
        discard_frame();
        width = 6;
        discard_frame();
        expect_frame(3, 3, 0, 1, '{32'ha1, 0, 0, 32'hb1, 32'hb2, 32'hb3, 0, 0, 0});
        send(2, 0);
        send(0, 1, 32'ha1); // Short line.
        send(0, 0, 32'hb1);
        send(0, 0, 32'hb2);
        send(0, 0, 32'hb3);
        send(0, 1, 32'hb4); // Long line; missing final configured row.
        send(3, 0, 0, 1);
        settle();
        width = 2;
        height = 1;
        expect_frame(1, 1, 1, 0, '{32'h12345678});
        send(2, 0);
        width = 8; // Dimensions are captured only at SOF.
        height = 5;
        send(0, 1, 32'h12345678);
        send(3, 0);
        settle();
        width = 2;
        height = 1;
        expect_frame(1, 1, 2, 1, '{32'h11223344});
        send(2, 0);
        send(0, 1, 32'h11223344);
        send(0, 1, 32'h55667788); // Too many rows.
        send(3, 0);
        settle();
        width = 0;
        send(2, 0);
        send(3, 0);
        settle();
        if (errors != 2 || frames != 3 || incomplete_frames != 2)
            $fatal(1, "FAIL counts cfg=%0d frames=%0d incomplete=%0d",
                errors, frames, incomplete_frames);
        enable = 0;
        repeat (3) @(negedge clk);
        enable = 1;
        width = 2;
        discard_frame();
        discard_frame();
        expect_frame(1, 1, 3, 0, '{32'hcafef00d});
        send(2, 0);
        send(0, 1, 32'hcafef00d);
        send(3, 0);
        settle();
        // Generate the expected image before sending raw lines; never inspect DUT state.
        for (int fid = 4; fid < 104; fid++) begin
            bit [31:0] normalized[];
            int raw_words[];
            int words_per_line;
            int lines;
            int raw_lines;
            bit bad;
            bit lost;
            words_per_line = $urandom_range(1,16);
            lines = $urandom_range(1,5);
            raw_lines = $urandom_range(0,lines+2);
            raw_words = new[raw_lines];
            normalized = new[words_per_line*lines];
            lost = $urandom_range(0,7) == 0;
            bad = raw_lines != lines || lost;
            for (int y = 0; y < raw_lines; y++) begin
                raw_words[y] = $urandom_range(0,words_per_line+3);
                if (raw_words[y] != words_per_line) bad = 1;
                for (int x = 0; x < raw_words[y]; x++)
                    if (x < words_per_line && y < lines)
                        normalized[y*words_per_line+x] = 32'((fid<<16)|(y<<8)|x);
            end
            width = 11'(words_per_line*2);
            height = 12'(lines);
            expect_frame(words_per_line,lines,fid,bad,normalized);
            send(2,0);
            for (int y = 0; y < raw_lines; y++) begin
                if (raw_words[y] == 0) send(1,0);
                for (int x = 0; x < raw_words[y]; x++)
                    send(0,x==raw_words[y]-1,(fid<<16)|(y<<8)|x);
            end
            send(3,0,0,lost);
            settle();
        end
        $display("PASS vin_fmt");
        $finish;
    end
    initial begin #1000000; $fatal(1, "FAIL timeout"); end
endmodule
