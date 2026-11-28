// File: old_tb.sv
// Spec: cpu-v2-testplan CV15.
// Clock: clk_sys.
// Description: Observe the unchanged competition core and its zero-miss B1 cache interfaces.
/* verilator lint_off BLKSEQ */
module old_tb;
    edrv32_cpu_b1_core_tb harness();
    bit [31:0] begin_pc;
    bit [31:0] end_pc;
    integer start_cycle;
    bit measuring;
    initial begin
        if (!$value$plusargs("PERF_BEGIN=%h", begin_pc)) $fatal(1, "missing PERF_BEGIN");
        if (!$value$plusargs("PERF_END=%h", end_pc)) $fatal(1, "missing PERF_END");
    end
    always @(posedge harness.clk) begin
        if (harness.rst_n) begin
            for (int j=0; j<2; j++) begin
                if (harness.trace_valid[j]) begin
                    if (harness.u_core.trace_pc_w[j*32 +:32] == begin_pc) begin
                        start_cycle = harness.cycles;
                        measuring = 1;
                    end
                    if (measuring && harness.u_core.trace_pc_w[j*32 +:32] == end_pc) begin
                        $display("PERF old cycles=%0d", harness.cycles-start_cycle);
                        measuring = 0;
                    end
                end
            end
        end
    end
endmodule
