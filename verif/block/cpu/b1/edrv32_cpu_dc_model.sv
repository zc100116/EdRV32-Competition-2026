// File: edrv32_cpu_dc_model.sv
// Spec: cpu-spec 3.3, 4.7; cpu-testplan 2.3
// Description: Blocking D$ interface, commit-only writes/devices and one-entry buffer.
// Clock: clk_sys.
module edrv32_cpu_dc_model (
    input logic clk_i,
    input logic rst_n_i,
    input logic dc_req_valid_i,
    input logic [31:0] dc_req_addr_i,
    input logic dc_req_store_i,
    input logic [1:0] dc_req_size_i,
    output logic dc_req_ready_o,
    output logic dc_resp_valid_o,
    output logic [31:0] dc_resp_data_o,
    output logic dc_resp_err_o,
    output logic dc_resp_device_o,
    input logic dc_kill_i,
    input logic dc_commit_i,
    input logic [31:0] dc_store_data_i,
    input logic dc_fence_i,
    input logic dc_clean_all_i,
    output logic dc_fence_done_o,
    output logic dc_wb_event_o,
    output logic miss_o,
    output logic device_execute_o,
    output logic write_buffer_valid_o
);
    import edrv32_cpu_memory::*;
    int miss_pct = 0;
    int delay_min = 5;
    int delay_max = 40;
    int ready_low_pct = 0;
    int wb_event_cycle = -1;
    int cycle_r;
    int wb_event_count = 0;
    bit resp_valid_r;
    bit resp_err_r;
    logic [31:0] error_addr;
    bit error_enabled;
    int delay_r;
    bit active_r;
    bit ready_r;
    bit responded_r;
    bit committed_r;
    bit store_r;
    bit device_r;
    bit error_r;
    logic [31:0] addr_r;
    logic [1:0] size_r;
    logic [31:0] store_data_r;
    bit buffer_valid_r;
    logic [31:0] buffer_addr_r;
    logic [1:0] buffer_size_r;
    logic [31:0] buffer_data_r;
    logic [31:0] tohost_addr;
    bit tohost_enabled;

    initial begin
        void'($value$plusargs("DC_MISS_PCT=%d", miss_pct));
        void'($value$plusargs("DC_DELAY_MIN=%d", delay_min));
        void'($value$plusargs("DC_DELAY_MAX=%d", delay_max));
        void'($value$plusargs("DC_READY_LOW_PCT=%d", ready_low_pct));
        void'($value$plusargs("DC_WB_EVENT_CYCLE=%d", wb_event_cycle));
        error_enabled = $value$plusargs("DC_ERROR_ADDR=%h", error_addr);
        tohost_enabled = $value$plusargs("TOHOST_ADDR=%h", tohost_addr);
    end

    assign dc_req_ready_o = rst_n_i && ready_r && !dc_fence_i && !dc_clean_all_i
        && (!active_r || (!device_r && responded_r && dc_commit_i && !dc_kill_i));
    assign dc_resp_device_o = (active_r || resp_valid_r) && device_r;
    assign dc_resp_valid_o = resp_valid_r && !dc_kill_i;
    assign dc_resp_err_o = resp_err_r && dc_resp_valid_o;
    assign miss_o = active_r && !device_r && delay_r != 0;
    assign write_buffer_valid_o = buffer_valid_r;

    function automatic logic [31:0] forwarded(input logic [31:0] addr,
                                               input logic [1:0] size);
        logic [31:0] value;
        value = read_data(addr, size);
        // spec 4.7: merge only byte lanes covered by the pending store.
        for (int lane = 0; lane < (1 << size); lane++) begin
            for (int stored = 0; stored < (1 << buffer_size_r); stored++) begin
                if (buffer_valid_r && physical(addr + 32'(lane))
                    == physical(buffer_addr_r + 32'(stored)))
                    value[lane*8 +: 8] = buffer_data_r[stored*8 +: 8];
            end
            // A request accepted together with the older store's commit must see it too.
            for (int stored = 0; stored < (1 << size_r); stored++) begin
                if (active_r && dc_commit_i && store_r && !device_r && !error_r
                    && physical(addr + 32'(lane)) == physical(addr_r + 32'(stored)))
                    value[lane*8 +: 8] = dc_store_data_i[stored*8 +: 8];
            end
        end
        return value;
    endfunction

    task automatic report_result(input logic [31:0] addr,
                                  input logic [1:0] size,
                                  input bit error);
        resp_valid_r <= 1;
        resp_err_r <= error;
        dc_resp_data_o <= forwarded(addr, size);
        responded_r <= 1;
    endtask

    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            cycle_r <= 0;
            wb_event_count <= 0;
            active_r <= 0;
            ready_r <= 1;
            delay_r <= 0;
            responded_r <= 0;
            committed_r <= 0;
            buffer_valid_r <= 0;
            resp_valid_r <= 0;
            resp_err_r <= 0;
            dc_fence_done_o <= 0;
            dc_wb_event_o <= 0;
            device_execute_o <= 0;
        end else begin
            cycle_r <= cycle_r + 1;
            dc_wb_event_o <= cycle_r == wb_event_cycle;
            if (cycle_r == wb_event_cycle)
                wb_event_count <= wb_event_count + 1;
            ready_r <= int'($urandom_range(0, 99)) >= ready_low_pct;
            resp_valid_r <= 0;
            resp_err_r <= 0;
            device_execute_o <= 0;
            dc_fence_done_o <= (dc_fence_i || dc_clean_all_i)
                && !buffer_valid_r && !active_r;
            // Old buffer drains while the next committed store can replace it.
            if (buffer_valid_r) begin
                write_data(buffer_addr_r, buffer_size_r, buffer_data_r);
                if (tohost_enabled && buffer_addr_r == tohost_addr) begin
                    tohost_valid <= 1;
                    tohost_value <= buffer_data_r;
                end
            end
            buffer_valid_r <= 0;
            if (active_r) begin
                if (dc_kill_i) begin
                    active_r <= 0;
                    delay_r <= 0;
                end else begin
                    if (dc_commit_i) begin
                        committed_r <= 1;
                        store_data_r <= dc_store_data_i;
                        if (device_r) begin
                            delay_r <= int'($urandom_range(32'(delay_min), 32'(delay_max)));
                        end else begin
                            active_r <= 0;
                            if (store_r && !error_r) begin
                                buffer_valid_r <= 1;
                                buffer_addr_r <= addr_r;
                                buffer_size_r <= size_r;
                                buffer_data_r <= dc_store_data_i;
                            end
                        end
                    end
                    if (delay_r != 0) begin
                        delay_r <= delay_r - 1;
                        if (delay_r == 1) begin
                            if (device_r && committed_r) begin
                                resp_valid_r <= 1;
                                resp_err_r <= error_r;
                                if (!error_r) begin
                                    dc_resp_data_o <= access_device(addr_r, store_r,
                                        size_r, store_data_r);
                                    device_execute_o <= 1;
                                    if (store_r && tohost_enabled && addr_r == tohost_addr) begin
                                        tohost_valid <= 1;
                                        tohost_value <= store_data_r;
                                    end
                                end
                                active_r <= 0;
                                responded_r <= 1;
                            end else if (!device_r) begin
                                report_result(addr_r, size_r, error_r);
                            end
                        end
                    end
                end
            end
            if (dc_req_valid_i && dc_req_ready_o) begin
                active_r <= 1;
                addr_r <= dc_req_addr_i;
                size_r <= dc_req_size_i;
                store_r <= dc_req_store_i;
                device_r <= device(dc_req_addr_i);
                error_r <= error_enabled && dc_req_addr_i == error_addr;
                committed_r <= 0;
                responded_r <= 0;
                delay_r <= 0;
                if (!device(dc_req_addr_i)) begin
                    if (int'($urandom_range(0, 99)) < miss_pct)
                        delay_r <= int'($urandom_range(32'(delay_min), 32'(delay_max))) - 1;
                    else
                        report_result(dc_req_addr_i, dc_req_size_i,
                            error_enabled && dc_req_addr_i == error_addr);
                end
            end
        end
    end
endmodule
