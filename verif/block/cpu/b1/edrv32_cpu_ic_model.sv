// File: edrv32_cpu_ic_model.sv
// Spec: cpu-spec 3.2; cpu-testplan 2.3
// Description: Synchronous hit responses, delayed misses and canceled fill responses.
// Clock: clk_sys.
module edrv32_cpu_ic_model (
    input logic clk_i,
    input logic rst_n_i,
    input logic ic_req_valid_i,
    input logic [31:0] ic_req_addr_i,
    output logic ic_req_ready_o,
    output logic ic_resp_valid_o,
    output logic [63:0] ic_resp_data_o,
    output logic ic_resp_err_o,
    input logic ic_kill_i,
    input logic ic_inv_i,
    output logic ic_inv_done_o,
    output logic miss_o,
    output logic killed_fill_o
);
    import edrv32_cpu_memory::*;
    int miss_pct = 0;
    int delay_min = 5;
    int delay_max = 40;
    int ready_low_pct = 0;
    logic [31:0] error_addr;
    bit error_enabled;
    int delay_r;
    logic [31:0] addr_r;
    bit canceled_r;
    bit ready_r;
    bit resp_valid_r;
    bit resp_err_r;

    initial begin
        void'($value$plusargs("IC_MISS_PCT=%d", miss_pct));
        void'($value$plusargs("IC_DELAY_MIN=%d", delay_min));
        void'($value$plusargs("IC_DELAY_MAX=%d", delay_max));
        void'($value$plusargs("IC_READY_LOW_PCT=%d", ready_low_pct));
        error_enabled = $value$plusargs("IC_ERROR_ADDR=%h", error_addr);
    end

    assign ic_req_ready_o = rst_n_i && ready_r && delay_r == 0 && !ic_inv_i;
    assign ic_resp_valid_o = resp_valid_r && !ic_kill_i;
    assign ic_resp_err_o = resp_err_r && ic_resp_valid_o;
    assign miss_o = delay_r != 0;

    task automatic respond(input logic [31:0] addr);
        ic_resp_data_o <= {read_data(addr + 4, 2), read_data(addr, 2)};
        resp_err_r <= error_enabled && addr == error_addr;
        resp_valid_r <= 1;
    endtask

    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            delay_r <= 0;
            canceled_r <= 0;
            ready_r <= 1;
            resp_valid_r <= 0;
            resp_err_r <= 0;
            ic_inv_done_o <= 0;
            killed_fill_o <= 0;
        end else begin
            ready_r <= int'($urandom_range(0, 99)) >= ready_low_pct;
            resp_valid_r <= 0;
            resp_err_r <= 0;
            ic_inv_done_o <= ic_inv_i;
            killed_fill_o <= 0;
            if (ic_kill_i && delay_r != 0)
                canceled_r <= 1;
            if (delay_r != 0) begin
                delay_r <= delay_r - 1;
                if (delay_r == 1) begin
                    if (!canceled_r && !ic_kill_i)
                        respond(addr_r);
                    else
                        killed_fill_o <= 1;
                end
            end
            if (ic_req_valid_i && ic_req_ready_o) begin
                addr_r <= ic_req_addr_i;
                canceled_r <= ic_kill_i;
                if (int'($urandom_range(0, 99)) < miss_pct)
                    delay_r <= int'($urandom_range(32'(delay_min), 32'(delay_max))) - 1;
                else if (!ic_kill_i)
                    respond(ic_req_addr_i);
            end
        end
    end
endmodule
