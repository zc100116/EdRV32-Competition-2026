// File: edrv32_cpu_coverage_tb.sv
// Spec: cpu-spec 3.4, 7.1-7.2; cpu-testplan 4 (C-V5)
// Description: Feed documented observations to the collector, including held IRQs
//              and simultaneous independent IRQ arrivals. This is not a CPU test.
// Clock: synthetic clk_sys.
module edrv32_cpu_coverage_tb;
    logic clk = 0;
    logic rst_n = 0;
    logic [63:0] debug = 0;
    logic [1:0] valid = 0;
    logic [63:0] instr = 0;
    logic trap = 0;
    logic [31:0] cause = 0;
    logic [11:0] bypass = 0;
    logic [1:0] redirect = 0;
    logic [2:0] stall = 0;
    logic [2:0] irq = 0;
    int causes[9] = '{0, 1, 2, 3, 4, 5, 6, 7, 11};

    edrv32_cpu_coverage u_coverage (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .debug_i(debug),
        .irq_arrival_debug_i(debug),
        .trace_valid_i(valid),
        .trace_instr_i(instr),
        .trace_trap_i(trap),
        .trace_cause_i(cause),
        .trace_bypass_i(bypass),
        .trace_redirect_cause_i(redirect),
        .trace_stall_cause_i(stall),
        .irq_meip_i(irq[0]),
        .irq_msip_i(irq[1]),
        .irq_mtip_i(irq[2])
    );
    initial forever #5 clk = !clk;

    task automatic tick;
        @(negedge clk);
    endtask

    initial begin
        tick();
        rst_n = 1;
        valid = 3;
        instr = {32'h00000013, 32'h00000013};
        tick();
        valid = 0;
        for (int reason = 1; reason <= 4; reason++) begin
            debug[23:21] = 3'(reason);
            tick();
        end
        debug = 0;
        // Each field must decode independently for all six source encodings.
        for (int source_idx = 1; source_idx <= 6; source_idx++) begin
            for (int field_idx = 0; field_idx < 4; field_idx++) begin
                bypass = 0;
                bypass[field_idx*3 +: 3] = 3'(source_idx);
                tick();
            end
        end
        bypass = 0;
        trap = 1;
        foreach (causes[index]) begin
            cause = 32'(causes[index]);
            tick();
        end
        cause = 32'h8000000b;
        tick();
        trap = 0;
        debug[16] = 1;
        redirect = 1;
        tick();
        redirect = 2;
        tick();
        // The third E redirect cause is not direction or target misprediction.
        redirect = 3;
        tick();
        redirect = 0;
        debug = 64'h00020000;
        tick();
        debug = 0;
        valid = 1;
        instr = 64'h30200073;
        tick();
        instr = 64'h0000100f;
        tick();
        valid = 0;
        debug[24] = 1;
        stall = 1;
        tick();
        debug = 0;
        stall = 2;
        tick();
        stall = 3;
        tick();
        stall = 4;
        tick();
        stall = 0;
        debug[15] = 1;
        tick();
        debug = 0;
        // Ordinary execution: a three-cycle asserted IRQ is one arrival.
        debug[7] = 1;
        irq = 1;
        repeat (3) tick();
        irq = 0;
        debug = 0;
        tick();
        // Two interrupt sources rising together count as two arrivals.
        debug[25] = 1;
        irq = 3;
        tick();
        irq = 0;
        debug = 0;
        tick();
        debug[26] = 1;
        irq = 4;
        tick();
        irq = 0;
        debug = 0;
        tick();
        debug[14] = 1;
        debug[28] = 1;
        irq = 1;
        tick();
        irq = 0;
        debug = 0;
        tick();
        debug[16] = 1;
        redirect = 1;
        irq = 1;
        tick();
        $display("PASS coverage observations");
        $finish;
    end
endmodule
