// File: edrv32_cpu_dc_model.sv
// Spec: cpu-spec 3.3, 4.7; cpu-testplan 2.3
// Description: Blocking D$ interface, commit-only writes/devices and one-entry buffer.
// Clock: clk_sys.
module edrv32_cpu_dc_model (
    input logic clk_i,
    input logic rst_n_i,
    // cpu-spec 3.3/4.10: speculative, synchronous query, without a handshake.
    input logic dc_early_valid_i,
    input logic [31:0] dc_early_addr_i,
    output wire [1:0] dc_early_way_hit_o,
    output wire [63:0] dc_early_way_data_o,

    input logic dc_req_valid_i,
    input logic [31:0] dc_req_addr_i,
    input logic dc_req_store_i,
    input logic [1:0] dc_req_size_i,
    output logic dc_req_ready_o,
    output logic dc_resp_valid_o,
    output wire [1:0] dc_resp_way_hit_o,
    output wire [63:0] dc_resp_way_data_o,
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
    logic early_hit_r;
    logic [31:0] early_data_r;
    logic [31:0] resp_data_r;
    bit early_way_r;
    bit resp_way_r;
    assign dc_early_way_hit_o = early_hit_r && early_failure_r==0 ? (early_way_r ? 2'b10 : 2'b01) : 2'b00;
    assign dc_early_way_data_o = early_way_r ? {early_data_r,32'b0} : {32'b0,early_data_r};
    assign dc_resp_way_hit_o = dc_resp_valid_o ? (resp_way_r ? 2'b10 : 2'b01) : 2'b00;
    assign dc_resp_way_data_o = resp_way_r ? {resp_data_r,32'b0} : {32'b0,resp_data_r};
    int early_fail_pct = 0;
    logic [31:0] early_addr_r;
    wire [2:0] early_failure_r;
    logic [2:0] early_query_failure_r;
    assign early_failure_r = early_query_failure_r != 0 ? early_query_failure_r :
        buffer_valid_r && (physical(early_addr_r)>>2)==(physical(buffer_addr_r)>>2) ? 3'd4 :
        active_r && store_r && (physical(early_addr_r)>>2)==(physical(addr_r)>>2) ? 3'd5 :
        dc_clean_all_i ? 3'd6 : 3'd0;
    logic [31:0] early_miss_addr;
    bit early_miss_enabled;
    logic [31:0] early_block_addr;
    bit early_block_enabled;
    logic early_reuse_w;
    logic [2:0] early_failure_w;
    int early_random_r;
    int early_miss_random_r;
    int miss_pct = 0;
    int delay_min = 5;
    int delay_max = 40;
    int ready_low_pct = 0;
    bit forced_ready_low = 0;
    int wb_event_cycle = -1;
    int cycle_r;
    int clean_delay = 1;
    int maintenance_count_r;
    bit maintenance_active_r;
    int buffer_hold_cycles = 0;
    int buffer_hold_r;
    int wb_event_count = 0;
    bit resp_valid_r;
    bit resp_err_r;
    logic [31:0] error_addr;
    bit error_enabled;
    int delay_r;
    int device_delay_r;
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
        void'($value$plusargs("DC_EARLY_FAIL_PCT=%d", early_fail_pct));
        early_miss_enabled = $value$plusargs("DC_EARLY_MISS_ADDR=%h", early_miss_addr);
        early_block_enabled = $value$plusargs("DC_EARLY_BLOCK_ADDR=%h", early_block_addr);
        void'($value$plusargs("DC_CLEAN_ALL_DELAY=%d", clean_delay));
        void'($value$plusargs("WB_HOLD_CYCLES=%d", buffer_hold_cycles));
        void'($value$plusargs("DC_MISS_PCT=%d", miss_pct));
        void'($value$plusargs("DC_DELAY_MIN=%d", delay_min));
        void'($value$plusargs("DC_DELAY_MAX=%d", delay_max));
        void'($value$plusargs("DC_READY_LOW_PCT=%d", ready_low_pct));
        void'($value$plusargs("DC_WB_EVENT_CYCLE=%d", wb_event_cycle));
        error_enabled = $value$plusargs("DC_ERROR_ADDR=%h", error_addr);
        tohost_enabled = $value$plusargs("TOHOST_ADDR=%h", tohost_addr);
    end

    assign dc_req_ready_o = rst_n_i && ready_r && !forced_ready_low &&
        !dc_fence_i && !dc_clean_all_i
        && (!active_r || (!device_r && responded_r && dc_commit_i && !dc_kill_i));
    assign dc_resp_device_o = (active_r || resp_valid_r) && device_r;
    assign dc_resp_valid_o = resp_valid_r;
    assign dc_resp_err_o = resp_err_r && dc_resp_valid_o;
    assign miss_o = active_r && !device_r && delay_r != 0;
    assign write_buffer_valid_o = buffer_valid_r;

    assign early_reuse_w = (|dc_early_way_hit_o) && dc_req_valid_i &&
        !dc_req_store_i && dc_req_addr_i == early_addr_r;
    // The replica read is independent of ordinary request readiness and RAM usage.
    // Failure reasons are observations for cpu-testplan A-02 coverage, not DUT ports.
    always_comb begin
        early_failure_w = 0;
        if (early_random_r < early_fail_pct ||
            (early_block_enabled && dc_early_addr_i == early_block_addr))
            early_failure_w = 1;
        if (early_miss_random_r < miss_pct ||
            (early_miss_enabled && dc_early_addr_i == early_miss_addr))
            early_failure_w = 2;
        if (device(dc_early_addr_i))
            early_failure_w = 3;
        if (buffer_valid_r && (physical(dc_early_addr_i) >> 2) ==
            (physical(buffer_addr_r) >> 2))
            early_failure_w = 4;
        if (active_r && store_r && (physical(dc_early_addr_i) >> 2) ==
            (physical(addr_r) >> 2))
            early_failure_w = 5;
        if (dc_clean_all_i) early_failure_w = 6;
    end
    // The query updates only response registers. It never starts a transaction,
    // allocates a fill, touches memory, drains a buffer or executes a device.
    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            early_hit_r <= 0;
            early_data_r <= 0;
            early_addr_r <= 0;
            early_query_failure_r <= 0;
            early_random_r <= 100;
            early_miss_random_r <= 100;
        end else begin
            early_random_r <= int'($urandom_range(0, 99));
            early_miss_random_r <= int'($urandom_range(0, 99));
            early_hit_r <= dc_early_valid_i && early_failure_w == 0;
            early_query_failure_r <= dc_early_valid_i ? early_failure_w : 0;
            if (dc_early_valid_i) begin
                early_way_r <= 1'($urandom_range(0,1));
                early_addr_r <= dc_early_addr_i;
                early_data_r <= read_data(dc_early_addr_i, 2);
            end
        end
    end

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
                                    input bit error, input bit fill_return);
        resp_valid_r <= 1;
        resp_err_r <= error;
        resp_way_r <= error || fill_return ? 1'b0 : 1'($urandom_range(0,1));
        resp_data_r <= forwarded(addr, size);
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
            buffer_hold_r <= 0;
            maintenance_active_r <= 0;
            maintenance_count_r <= 0;
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
            dc_fence_done_o <= 0;
            if ((!dc_fence_i && !dc_clean_all_i) || dc_fence_done_o)
                maintenance_active_r <= 0;
            else if (!maintenance_active_r && !buffer_valid_r && !active_r) begin
                maintenance_active_r <= 1;
                maintenance_count_r <= dc_clean_all_i ? clean_delay - 1 : 0;
                if (!dc_clean_all_i || clean_delay == 1)
                    dc_fence_done_o <= 1;
            end
            if (maintenance_active_r && maintenance_count_r > 0) begin
                maintenance_count_r <= maintenance_count_r - 1;
                if (maintenance_count_r == 1)
                    dc_fence_done_o <= 1;
            end
            // Old buffer drains while the next committed store can replace it.
            if (buffer_hold_r > 0)
                buffer_hold_r <= buffer_hold_r - 1;
            if (buffer_valid_r && buffer_hold_r == 0) begin
                write_data(buffer_addr_r, buffer_size_r, buffer_data_r);
                if (tohost_enabled && buffer_addr_r == tohost_addr) begin
                    tohost_valid <= 1;
                    tohost_value <= buffer_data_r;
                end
            end
            if (buffer_hold_r == 0)
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
                            delay_r <= device_delay_r;
                        end else begin
                            active_r <= 0;
                            if (store_r && !error_r) begin
                                buffer_valid_r <= 1;
                                buffer_hold_r <= buffer_hold_cycles;
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
                                    resp_way_r <= 0;
                                    resp_data_r <= access_device(addr_r, store_r,
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
                                report_result(addr_r, size_r, error_r, 1'b1);
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
                device_delay_r <= int'($urandom_range(32'(delay_min), 32'(delay_max)));
                error_r <= error_enabled && dc_req_addr_i == error_addr;
                committed_r <= 0;
                responded_r <= 0;
                delay_r <= 0;
                if (!device(dc_req_addr_i)) begin
                    if (early_reuse_w) begin
                        resp_valid_r <= 1;
                        resp_err_r <= error_enabled && dc_req_addr_i == error_addr;
                        resp_data_r <= early_data_r;
                        resp_way_r <= error_enabled && dc_req_addr_i == error_addr ?
                            1'b0 : early_way_r;
                        responded_r <= 1;
                    end else if ((early_miss_enabled && dc_req_addr_i == early_miss_addr) ||
                        int'($urandom_range(0, 99)) < miss_pct)
                        delay_r <= int'($urandom_range(32'(delay_min), 32'(delay_max))) - 1;
                    else
                        report_result(dc_req_addr_i, dc_req_size_i,
                            error_enabled && dc_req_addr_i == error_addr, 1'b0);
                end
            end
        end
    end
endmodule
