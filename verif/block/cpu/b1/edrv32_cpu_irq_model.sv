// File: edrv32_cpu_irq_model.sv
// Spec: cpu-spec 3.1; cpu-testplan 2.3
// Description: Each interrupt starts at a configured cycle or retired PC match.
// Clock: clk_sys; mtime advances once per active clock.
module edrv32_cpu_irq_model (
    input logic clk_i,
    input logic rst_n_i,
    input logic [1:0] trace_valid_i,
    input logic [63:0] trace_pc_i,
    output logic irq_meip_o,
    output logic irq_msip_o,
    output logic irq_mtip_o,
    output logic [63:0] mtime_o
);
    int cycle_r;
    int start_cycle[3];
    int duration[3];
    int remaining_r[3];
    bit fired_r[3];
    bit pc_enabled[3];
    logic [31:0] start_pc[3];
    logic [2:0] irq_r;
    string names[3] = '{"MEIP", "MSIP", "MTIP"};

    integer parsed_cycle;
    integer parsed_duration;
    initial begin
        for (int index = 0; index < 3; index++) begin
            // Scalar temporaries preserve absent-plusarg defaults in Verilator 5.020.
            parsed_cycle = -1;
            parsed_duration = 1;
            void'($value$plusargs({names[index], "_CYCLE=%d"}, parsed_cycle));
            void'($value$plusargs({names[index], "_DURATION=%d"}, parsed_duration));
            start_cycle[index] = parsed_cycle;
            duration[index] = parsed_duration;
            pc_enabled[index] = $value$plusargs({names[index], "_PC=%h"}, start_pc[index]);
        end
    end

    assign irq_meip_o = irq_r[0];
    assign irq_msip_o = irq_r[1];
    assign irq_mtip_o = irq_r[2];

    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            cycle_r <= 0;
            mtime_o <= 0;
            irq_r <= 0;
            for (int index = 0; index < 3; index++) begin
                fired_r[index] <= 0;
                remaining_r[index] <= 0;
            end
        end else begin
            cycle_r <= cycle_r + 1;
            mtime_o <= mtime_o + 1;
            for (int index = 0; index < 3; index++) begin
                if (remaining_r[index] > 0) begin
                    remaining_r[index] <= remaining_r[index] - 1;
                    if (remaining_r[index] == 1)
                        irq_r[index] <= 0;
                end
                if (!fired_r[index] && (cycle_r == start_cycle[index]
                    || (pc_enabled[index]
                        && ((trace_valid_i[0] && trace_pc_i[31:0] == start_pc[index])
                        || (trace_valid_i[1] && trace_pc_i[63:32] == start_pc[index]))))) begin
                    fired_r[index] <= 1;
                    remaining_r[index] <= duration[index];
                    irq_r[index] <= 1;
                end
            end
        end
    end
endmodule
