// File: edrv32_cpu_trace.sv
// Spec: cpu-spec 3.4; C-V1/C-V2 coordinator trace agreement
// Description: Emit ordered four-column hex retirement records and trap records.
// Clock: clk_sys; caller connects signals with hierarchical references to u_core.
module edrv32_cpu_trace (
    input logic clk_i,
    input logic rst_n_i,
    input logic [1:0] trace_valid_i,
    input logic [63:0] trace_pc_i,
    input logic [63:0] trace_instr_i,
    input logic [9:0] trace_rd_i,
    input logic [63:0] trace_rd_data_i,
    input logic trace_trap_i,
    input logic [31:0] trace_cause_i
);
    string path = "build/cpu-rtl.trace";
    integer descriptor;
    initial begin
        void'($value$plusargs("TRACE_FILE=%s", path));
        descriptor = $fopen(path, "w");
        if (descriptor == 0)
            $fatal(1, "FAIL cannot open trace file %s", path);
    end
    always @(posedge clk_i) begin
        if (rst_n_i) begin
            for (int slot = 0; slot < 2; slot++) begin
                if (trace_valid_i[slot])
                    $fdisplay(descriptor, "%08x %08x %02x %08x", trace_pc_i[slot*32 +: 32],
                        trace_instr_i[slot*32 +: 32], trace_rd_i[slot*5 +: 5],
                        trace_rd_i[slot*5 +: 5] == 0 ? 32'b0 : trace_rd_data_i[slot*32 +: 32]);
            end
            if (trace_trap_i)
                $fdisplay(descriptor, "trap %08x", trace_cause_i);
            $fflush(descriptor);
        end
    end
    final $fclose(descriptor);
endmodule
