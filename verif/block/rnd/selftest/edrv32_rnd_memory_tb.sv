// File: edrv32_rnd_memory_tb.sv
// Spec: rnd-testplan 2; SoC 4.2; Task R-T1 independent environment acceptance.
// Description: Exercise the memory BFM with held responses, burst strobes, latency,
//              random stalls and one-shot transaction error injection.
// Clock domain: clk_mem.
`timescale 1ns/1ps
module edrv32_rnd_memory_tb;
    logic clk_mem = 0;
    logic rst_mem_n = 0;
    edrv32_axi256_if axi();
    int checker_errors;
    int random_seed = 32'h12345678;

    always #4 clk_mem = ~clk_mem;

    edrv32_rnd_memory u_memory (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(axi)
    );

    edrv32_axi256_checker u_checker (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(axi),
        .errors_o(checker_errors)
    );

    task automatic equal(input string what_i,
        input logic [31:0] wanted_i,
        input logic [31:0] actual_i);
        if (wanted_i !== actual_i)
            $fatal(1, "FAIL memory %s desc=0 coord=(-1,-1) expected=%h actual=%h time=%0t",
                what_i, wanted_i, actual_i, $time);
    endtask

    task automatic read_burst(input int address_i,
        input int beats_i,
        input bit error_i,
        input bit fixed_latency_i);
        time accepted;
        @(negedge clk_mem);
        axi.araddr = 32'(address_i);
        axi.arlen = 4'(beats_i - 1);
        axi.arvalid = 1;
        do @(posedge clk_mem); while (!axi.arready);
        accepted = $time;
        @(negedge clk_mem);
        axi.arvalid = 0;
        for (int beat = 0; beat < beats_i; beat++) begin
            do @(posedge clk_mem); while (!axi.rvalid);
            if (beat == 0 && fixed_latency_i)
                equal("fixed latency=40", 40, 32'(($time - accepted) / 8));
            equal("RRESP", error_i ? 2 : 0, 32'(axi.rresp));
            equal("RLAST", 32'(beat == beats_i - 1), 32'(axi.rlast));
            for (int lane = 0; lane < 32; lane++)
                equal("read data", 32'(u_memory.mem[address_i + beat * 32 + lane]),
                    32'(axi.rdata[lane*8+:8]));
            // Hold each payload for three clock cycles; shared checker checks stability.
            repeat (3) @(negedge clk_mem);
            axi.rready = 1;
            @(posedge clk_mem);
            @(negedge clk_mem);
            axi.rready = 0;
        end
    endtask

    task automatic write_burst(input int address_i,
        input int beats_i,
        input bit error_i);
        byte unsigned before_bytes[512];
        for (int i = 0; i < beats_i * 32; i++) before_bytes[i] = u_memory.mem[address_i + i];
        @(negedge clk_mem);
        axi.awaddr = 32'(address_i);
        axi.awlen = 4'(beats_i - 1);
        axi.awvalid = 1;
        do @(posedge clk_mem); while (!axi.awready);
        @(negedge clk_mem);
        axi.awvalid = 0;
        for (int beat = 0; beat < beats_i; beat++) begin
            axi.wvalid = 1;
            axi.wlast = beat == beats_i - 1;
            axi.wstrb = beat == 0 ? 32'hffffffe0 : 32'h00ffffff;
            for (int lane = 0; lane < 32; lane++) axi.wdata[lane*8+:8] = 8'(beat * 32 + lane);
            do @(posedge clk_mem); while (!axi.wready);
            @(negedge clk_mem);
        end
        axi.wvalid = 0;
        do @(posedge clk_mem); while (!axi.bvalid);
        equal("BRESP", error_i ? 2 : 0, 32'(axi.bresp));
        repeat (3) @(negedge clk_mem);
        axi.bready = 1;
        @(posedge clk_mem);
        @(negedge clk_mem);
        axi.bready = 0;
        for (int beat = 0; beat < beats_i; beat++) begin
            for (int lane = 0; lane < 32; lane++) begin
                if ((beat == 0 && lane >= 5) || (beat != 0 && lane < 24))
                    equal("WSTRB written", 32'((beat * 32 + lane) & 255),
                        32'(u_memory.mem[address_i + beat * 32 + lane]));
                else equal("WSTRB unchanged", 32'(before_bytes[beat * 32 + lane]),
                    32'(u_memory.mem[address_i + beat * 32 + lane]));
            end
        end
    endtask

    initial begin
        axi.awid = 0;
        axi.awaddr = 0;
        axi.awlen = 0;
        axi.awvalid = 0;
        axi.wdata = 0;
        axi.wstrb = 0;
        axi.wlast = 0;
        axi.wvalid = 0;
        axi.bready = 0;
        axi.arid = 0;
        axi.araddr = 0;
        axi.arlen = 0;
        axi.arvalid = 0;
        axi.rready = 0;
        u_memory.memory_size = 32'h80000;
        u_memory.random_percent = 0;
        u_memory.read_latency = 40;
        u_memory.b_delay = 7;
        for (int i = 0; i < 32'h80000; i++) u_memory.mem[i] = 8'(i * 37 + 11);
        repeat (5) @(negedge clk_mem);
        rst_mem_n = 1;
        read_burst(32'h20000, 16, 0, 1);
        for (int kind = 1; kind <= 4; kind++) begin
            @(negedge clk_mem);
            u_memory.error_kind = kind;
            u_memory.injected = 0;
            case (kind)
                1: read_burst(32'h1000, 2, 1, 1);
                2: read_burst(32'h20000, 3, 1, 1);
                3: read_burst(32'h10000, 5, 1, 1);
                4: read_burst(32'h50000, 1, 1, 1);
                default: $fatal(1, "FAIL invalid memory selftest kind");
            endcase
            begin
                equal("one injection", 1, 32'(u_memory.injected));
            end
            read_burst(32'h20000, 1, 0, 1);
        end
        @(negedge clk_mem);
        u_memory.error_kind = 6;
        u_memory.injected = 0;
        read_burst(32'h48000, 4, 1, 1);
        read_burst(32'h48000, 2, 0, 1);
        equal("parameter AR count", 2, 32'(u_memory.parameter_ar_count));
        equal("parameter read beats", 6, 32'(u_memory.parameter_beats));
        @(negedge clk_mem);
        u_memory.error_kind = 5;
        u_memory.injected = 0;
        write_burst(32'h30000, 16, 1);
        write_burst(32'h30000, 3, 0);
        @(negedge clk_mem);
        u_memory.error_kind = 0;
        u_memory.random_percent = 55;
        for (int i = 0; i < 20; i++) begin
            random_seed = (random_seed << 1) ^ (random_seed < 0 ? 32'h04c11db7 : 0);
            write_burst(32'h30000 + i * 512, 1 + (random_seed & 15), 0);
            read_burst(32'h30000 + i * 512, 1 + (random_seed & 15), 0, 0);
        end
        equal("all AW/B returned", 32'(u_memory.aw_count), 32'(u_memory.b_count));
        equal("all AR/R returned", 32'(u_memory.ar_count), 32'(u_memory.r_count));
        equal("checker errors", 0, 32'(checker_errors));
        equal("read queue drained", 0, 32'(u_memory.reads.size()));
        equal("write queue drained", 0, 32'(u_memory.writes.size()));
        equal("response queue drained", 0, 32'(u_memory.responses.size()));
        $display(string'({"PASS RND memory model: strobes, 1..16 beats, ",
            "stalls, latency40, SLVERR kinds1..6"}));
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "FAIL memory selftest timeout");
    end
endmodule
