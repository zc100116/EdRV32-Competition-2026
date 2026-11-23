// File: edrv32_gpu_scenario.sv
// Spec: gpu-soc-testplan ST-09; gpu-soc-spec 6.1.
// Description: Inject module-boundary interrupt levels requested by the CPU mailbox.
//              Software checks pending, claim and complete through the real system bus.
// Clock domain: clk_mem injection; clk_sys PLIC and software.
`timescale 1ns/1ps
module edrv32_gpu_scenario (
    output bit checks_complete_o = 0,
    output wire [1:0] model_sda_oe_o
);
    assign model_sda_oe_o = 2'b00;
    int active_source = 0;
    int request_source;
    int partial;
    int injected = 0;
    localparam bit [31:0] MAILBOX = 32'h003ff000;
    function automatic int request();
        return { $root.edrv32_gpu_soc_tb.u_ddr.peek(MAILBOX+3),
            $root.edrv32_gpu_soc_tb.u_ddr.peek(MAILBOX+2),
            $root.edrv32_gpu_soc_tb.u_ddr.peek(MAILBOX+1),
            $root.edrv32_gpu_soc_tb.u_ddr.peek(MAILBOX) };
    endfunction
    task automatic acknowledge(input int source);
        for (int index = 0; index < 4; index++)
            $root.edrv32_gpu_soc_tb.u_ddr.poke(MAILBOX+4+32'(index),
                8'(source >> (8*index)));
    endtask
    initial begin
        if (!$value$plusargs("GPU_PARTIAL=%d", partial)) $fatal(1, "missing GPU_PARTIAL");
        wait ($root.edrv32_gpu_soc_tb.rst_n_i);
        forever begin
            repeat (100) @(negedge $root.edrv32_gpu_soc_tb.clk_mem_i);
            request_source = request();
            if (request_source != active_source) begin
                case (active_source)
                    0: begin end
                    8: release $root.edrv32_gpu_soc_tb.u_dut.u_aud.irq_o;
                    12: release $root.edrv32_gpu_soc_tb.u_dut.u_disp.irq_o;
                    13: release $root.edrv32_gpu_soc_tb.u_dut.u_gpu.irq_o;
                    14: release $root.edrv32_gpu_soc_tb.u_dut.u_eth.irq_o;
                    15: release $root.edrv32_gpu_soc_tb.u_dut.u_mem.irq_mem_xbar_o;
                    default: $fatal(1, "invalid active PLIC source=%0d", active_source);
                endcase
                case (request_source)
                    0: begin end
                    8: force $root.edrv32_gpu_soc_tb.u_dut.u_aud.irq_o = 1;
                    12: force $root.edrv32_gpu_soc_tb.u_dut.u_disp.irq_o = 1;
                    13: begin
                        if (partial != 0) $fatal(1, "GPU source requested with placeholder");
                        force $root.edrv32_gpu_soc_tb.u_dut.u_gpu.irq_o = 1;
                    end
                    14: force $root.edrv32_gpu_soc_tb.u_dut.u_eth.irq_o = 1;
                    15: force $root.edrv32_gpu_soc_tb.u_dut.u_mem.irq_mem_xbar_o = 1;
                    default: $fatal(1, "invalid requested PLIC source=%0d", request_source);
                endcase
                if (request_source != 0) injected++;
                active_source = request_source;
                // Allow the existing X3 synchronizer to see deassertion before completion.
                repeat (10) @(negedge $root.edrv32_gpu_soc_tb.clk_sys_i);
                acknowledge(active_source);
                if (active_source == 0 && injected == (partial != 0 ? 4 : 5))
                    checks_complete_o = 1;
            end
        end
    end
endmodule
