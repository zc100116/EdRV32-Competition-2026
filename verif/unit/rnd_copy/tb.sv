// File: tb.sv
// Spec: rnd-spec 2.6 COPY, 5.2, 5.3; T-SLIM1-MEDIA M2.
// Description: Byte snapshot oracle checks all relative alignments, overlap and full RAM rows.
// Clock domain: clk_mem model.
module tb;
    bit clk = 0;
    always #4 clk = ~clk;
    bit rst_n = 0;
    bit start = 0;
    bit cancel = 0;
    logic [511:0] command = 0;
    wire done;
    wire [4:0] pixels;
    wire rd_valid;
    wire [31:0] rd_addr;
    wire [15:0] rd_bytes;
    bit rd_data_valid = 0;
    logic [255:0] rd_data = 0;
    bit rd_done = 0;
    wire wr_valid;
    wire [31:0] wr_addr;
    wire [15:0] wr_bytes;
    wire wr_data_valid;
    wire [255:0] wr_data;
    wire [31:0] wr_strb;
    bit wr_ready = 1;
    bit wr_done = 0;
    byte unsigned memory [0:131071];
    byte unsigned expected [0:131071];
    byte unsigned snapshot [0:65535];
    int read_left = 0;
    int read_addr = 0;
    int write_left = 0;
    int write_addr = 0;
    int cycle = 0;
    bit stalls = 0;
    int count = 0;
    bit streaming = 0;
    edrv32_rnd_copy dut (
        .clk_i(clk), .rst_n_i(rst_n), .start_i(start), .cancel_i(cancel),
        .command_i(command), .done_o(done), .pixel_count_o(pixels),
        .rd_valid_o(rd_valid), .rd_ready_i(1'b1), .rd_addr_o(rd_addr),
        .rd_bytes_o(rd_bytes), .rd_data_valid_i(rd_data_valid), .rd_data_i(rd_data),
        .rd_done_i(rd_done), .wr_valid_o(wr_valid), .wr_ready_i(1'b1),
        .wr_addr_o(wr_addr), .wr_bytes_o(wr_bytes), .wr_data_valid_o(wr_data_valid),
        .wr_data_ready_i(wr_ready), .wr_data_o(wr_data), .wr_strb_o(wr_strb),
        .wr_done_i(wr_done)
    );
    always @(posedge clk) begin
        if (streaming && write_left > 0 && !stalls && !cancel && !wr_data_valid)
            $fatal(1,"FAIL COPY bubble during continuous output");
        if (wr_valid && !cancel) begin
            streaming = 0;
            write_addr = int'(wr_addr);
            write_left = (int'(wr_bytes)+31)/32;
        end
        if (wr_data_valid && wr_ready) begin
            streaming = 1;
            if (write_left == 0) $fatal(1,"FAIL write without descriptor");
            for (int b = 0; b < 32; b++)
                if (wr_strb[b]) memory[write_addr+b] = wr_data[b*8 +: 8];
            write_addr += 32;
            write_left--;
            count += int'(pixels);
        end
    end
    always @(negedge clk) begin
        cycle++;
        wr_ready = !stalls || cycle%7 < 4;
        rd_done = rd_data_valid && read_left == 0;
        rd_data_valid = 0;
        wr_done = write_left == 0 && !wr_valid;
        if (rd_valid && !cancel && read_left == 0) begin
            read_addr = int'(rd_addr);
            read_left = (int'(rd_bytes)+31)/32;
        end else if (read_left != 0 && (!stalls || cycle%5 != 0)) begin
            for (int b = 0; b < 32; b++) rd_data[b*8 +: 8] = memory[read_addr+b];
            read_addr += 32;
            read_left--;
            rd_data_valid = 1;
        end
    end
    task automatic run_copy(input int source, target, width, height, stride,
                            input bit backpressure, input int abort_phase = 0);
        for (int b = 0; b < 131072; b++) begin
            memory[b] = 8'((b*173+(b>>7)*59)^cycle);
            expected[b] = memory[b];
        end
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width*4; x++)
                snapshot[y*width*4+x] = memory[source+y*stride+x];
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width*4; x++)
                expected[target+y*stride+x] = snapshot[y*width*4+x];
        @(negedge clk); #1;
        command = 0;
        command[31:0] = 32'h1105;
        command[63:32] = 32'(target);
        command[79:64] = 16'(stride);
        command[139:128] = 12'(width-1);
        command[155:144] = 12'(height-1);
        command[207:192] = 16'(width-1);
        command[223:208] = 16'(height-1);
        command[287:256] = 32'(source);
        command[303:288] = 16'(stride);
        stalls = backpressure;
        count = 0;
        start = 1;
        @(negedge clk); #1; start = 0;
        if (abort_phase != 0) begin
            if (abort_phase == 1) wait(rd_data_valid);
            else wait(wr_data_valid && wr_ready);
            @(negedge clk); #1; cancel = 1;
            @(negedge clk); #1; cancel = 0;
            // The parent drains accepted DMA traffic after cancelling this engine.
            wait(read_left == 0);
            repeat (3) @(negedge clk);
            write_left = 0;
            streaming = 0;
        end else begin
            wait(done);
            @(negedge clk); #1;
            // All offsets exercise the aligner; pixel accounting uses legal ARGB bases.
            if (target%4 == 0 && count != width*height)
                $fatal(1,"FAIL COPY pixels %0d",count);
            for (int b = 0; b < 131072; b++)
                if (memory[b] !== expected[b])
                    $fatal(1,"FAIL COPY src=%0d dst=%0d at=%0d got=%h want=%h",
                           source,target,b,memory[b],expected[b]);
        end
        repeat (2) @(negedge clk);
    endtask
    initial begin
        repeat (3) @(negedge clk); rst_n = 1;
        for (int s = 0; s < 32; s++)
            for (int d = 0; d < 32; d++)
                run_copy(4096+s,65536+d,35,1,256,(s+d)%2 != 0);
        for (int s = 0; s < 32; s++) begin
            run_copy(4096+s,65536,4096,1,16384,1);
            run_copy(4096+s,65536+28,4096,1,16384,0);
        end
        run_copy(8195,8454,35,4,256,1);
        run_copy(8455,8192,35,4,256,1);
        run_copy(8193,8196,35,4,256,1);
        run_copy(4095,65536,70,2,512,1);
        run_copy(4097,65540,35,1,256,1,1);
        run_copy(4097,65540,35,1,256,1,2);
        run_copy(4097,65540,35,1,256,0);
        $display("PASS COPY 1024 offsets, 64 maximum rows, overlap, 4KiB and cancel/restart");
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1,"FAIL COPY timeout");
    end
endmodule
