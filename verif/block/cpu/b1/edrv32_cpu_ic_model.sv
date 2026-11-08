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
    logic [31:0] delay_addr;
    int address_delay = 0;
    bit delay_enabled;
    int inv_delay = 1;
    int inv_count_r;
    bit inv_active_r;
    logic [31:0] addr_r;
    bit canceled_r;
    bit ready_r;
    bit resp_valid_r;
    bit resp_err_r;
    bit lookup_miss_r;
    bit busy_r;
    bit return_r;

    initial begin
        void'($value$plusargs("IC_MISS_PCT=%d", miss_pct));
        void'($value$plusargs("IC_DELAY_MIN=%d", delay_min));
        void'($value$plusargs("IC_DELAY_MAX=%d", delay_max));
        void'($value$plusargs("IC_READY_LOW_PCT=%d", ready_low_pct));
        delay_enabled = $value$plusargs("IC_DELAY_ADDR=%h", delay_addr);
        void'($value$plusargs("IC_DELAY_CYCLES=%d", address_delay));
        void'($value$plusargs("IC_INV_DELAY=%d", inv_delay));
        error_enabled = $value$plusargs("IC_ERROR_ADDR=%h", error_addr);
    end

    assign ic_req_ready_o = rst_n_i && ready_r && !busy_r && !return_r;
    assign ic_resp_valid_o = resp_valid_r;
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
            lookup_miss_r <= 0;
            busy_r <= 0;
            return_r <= 0;
            canceled_r <= 0;
            ready_r <= 1;
            resp_valid_r <= 0;
            resp_err_r <= 0;
            ic_inv_done_o <= 0;
            inv_count_r <= 0;
            inv_active_r <= 0;
            killed_fill_o <= 0;
        end else begin
            ready_r <= int'($urandom_range(0, 99)) >= ready_low_pct;
            lookup_miss_r <= 0;
            return_r <= 0;
            if (lookup_miss_r)
                busy_r <= 1;
            resp_valid_r <= 0;
            resp_err_r <= 0;
            ic_inv_done_o <= 0;
            if (!ic_inv_i)
                inv_active_r <= 0;
            else if (!inv_active_r) begin
                inv_active_r <= 1;
                inv_count_r <= inv_delay - 1;
                if (inv_delay == 1)
                    ic_inv_done_o <= 1;
            end
            if (inv_active_r && inv_count_r > 0) begin
                inv_count_r <= inv_count_r - 1;
                if (inv_count_r == 1)
                    ic_inv_done_o <= 1;
            end
            killed_fill_o <= 0;
            if (ic_kill_i && delay_r != 0)
                canceled_r <= 1;
            if (delay_r != 0) begin
                delay_r <= delay_r - 1;
                if (delay_r == 1) begin
                    busy_r <= 0;
                    return_r <= 1;
                    if (!canceled_r && !ic_kill_i)
                        respond(addr_r);
                    else
                        killed_fill_o <= 1;
                end
            end
            // cache-spec v0.11: ready remains high while discovering the miss;
            // accept the handshake but discard this successor without a response.
            if (ic_req_valid_i && ic_req_ready_o && !lookup_miss_r) begin
                addr_r <= ic_req_addr_i;
                canceled_r <= ic_kill_i;
                if (delay_enabled && ic_req_addr_i == delay_addr) begin
                    delay_r <= address_delay - 1;
                    lookup_miss_r <= 1;
                end else if (int'($urandom_range(0, 99)) < miss_pct) begin
                    delay_r <= int'($urandom_range(32'(delay_min), 32'(delay_max))) - 1;
                    lookup_miss_r <= 1;
                end
                else if (!ic_kill_i)
                    respond(ic_req_addr_i);
            end
        end
    end
endmodule
