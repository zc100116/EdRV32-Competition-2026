// File: edrv32_cpu_core.sv
// Spec: cpu-spec 3.1-3.4; C-V2 environment self-test
// Description: Fixed instruction/transaction table; no instruction execution model.
// Clock: clk_sys. This stub is never compiled with the real core.
module edrv32_cpu_core (
    // Clock and reset.
    input logic clk_i,
    input logic rst_n_i,
    input logic rst_sys_csr_n_i,
    input logic [9:0] rst_sys_counter_n_i,


    // I$ interface.
    output logic ic_req_valid_o,
    output logic [31:0] ic_req_addr_o,
    output logic ic_kill_o,
    output logic ic_inv_o,
    input logic ic_req_ready_i,
    input logic ic_resp_valid_i,
    input logic [7:0] ic_resp_valid_copy_i,
    input logic [63:0] ic_resp_data_i,
    input logic ic_resp_err_i,
    input logic ic_inv_done_i,

    // D$ interface.
    output logic dc_req_valid_o,
    output logic [31:0] dc_req_addr_o,
    output logic dc_req_store_o,
    output logic [1:0] dc_req_size_o,
    output logic dc_kill_o,
    output logic dc_commit_o,
    output logic [31:0] dc_store_data_o,
    output logic dc_fence_o,
    output logic dc_clean_all_o,
    input logic dc_req_ready_i,
    input logic dc_resp_valid_i,
    input logic [63:0] dc_resp_way_data_i,
    input logic [1:0] dc_resp_way_hit_i,
    input logic dc_resp_err_i,
    input logic dc_resp_device_i,
    input logic dc_fence_done_i,
    input logic dc_wb_event_i,

    // Control and status.
    output logic [63:0] debug_o,

    // Interrupts and timer.
    input logic irq_meip_i,
    input logic irq_msip_i,
    input logic irq_mtip_i,
    input logic [63:0] mtime_i
);
    wire [31:0] dc_resp_data_i =
        ({32{dc_resp_way_hit_i[0]}} & dc_resp_way_data_i[31:0]) |
        ({32{dc_resp_way_hit_i[1]}} & dc_resp_way_data_i[63:32]);
    // The fixed-table stub does not implement CSR or HPM state.
    wire unused_reset_w = &{1'b0, rst_sys_csr_n_i, rst_sys_counter_n_i,
        ic_resp_valid_copy_i};

    logic done_w;
    logic [1:0] trace_valid_w = 0;
    logic [63:0] trace_pc_w = 0;
    logic [63:0] trace_instr_w = 0;
    logic [9:0] trace_rd_w = 0;
    logic [63:0] trace_rd_data_w = 0;
    logic trace_trap_w = 0;
    logic [31:0] trace_cause_w = 0;
    // Spec v0.6 3.4: this transaction stub has no pipeline bypass or stalls.
    wire [11:0] trace_bypass_w = 0;
    wire [1:0] trace_redirect_cause_w = 0;
    wire [2:0] trace_stall_cause_w = 0;
    logic m_enter_w;
    int violation = 0;
    int retired = 0;
    logic [31:0] result;
    bit expect_ic_error;
    bit expect_dc_error;
    logic [31:0] dc_error_addr;
    logic [31:0] ic_error_addr;
    bit dc_error_enabled;
    bit ic_error_enabled;

    assign m_enter_w = dc_req_valid_o && dc_req_ready_i;
    // Expose counters/debug hooks for C-V5, without attempting coverage statistics here.
    assign debug_o = {trace_pc_w[31:0], 11'b0, trace_valid_w, 19'b0};

    task automatic retire_pair;
        trace_valid_w = 2'b11;
        trace_pc_w = {32'h4, 32'h0};
        trace_instr_w = {32'h00200113, 32'h00100093};
        trace_rd_w = {5'd2, 5'd1};
        trace_rd_data_w = {32'd2, 32'd1};
        retired += 2;
        @(negedge clk_i);
        trace_valid_w = 0;
    endtask

    task automatic fetch(input logic [31:0] addr, input bit cancel);
        expect_ic_error = ic_error_enabled && ic_error_addr == addr;
        ic_req_addr_o = addr;
        ic_req_valid_o = 1;
        do @(posedge clk_i); while (!ic_req_ready_i);
        @(negedge clk_i);
        ic_req_valid_o = 0;
        if (cancel) begin
            ic_kill_o = 1;
            @(negedge clk_i);
            ic_kill_o = 0;
        end else begin
            while (!ic_resp_valid_i) @(negedge clk_i);
            if (ic_resp_err_i != expect_ic_error)
                $fatal(1, "FAIL stub fetch error expected %b got %b", expect_ic_error,
                    ic_resp_err_i);
            if (!ic_resp_err_i && addr == 0 && ic_resp_data_i != 64'h0020011300100093)
                $fatal(1, "FAIL fetch data expected 0020011300100093 got %016x",
                    ic_resp_data_i);
            @(negedge clk_i);
        end
    endtask

    task automatic access_data(input logic [31:0] addr, input bit store,
                                input logic [1:0] size, input logic [31:0] data,
                                input bit cancel);
        expect_dc_error = dc_error_enabled && dc_error_addr == addr;
        dc_req_addr_o = addr;
        dc_req_size_o = size;
        dc_req_store_o = store;
        dc_req_valid_o = 1;
        do @(posedge clk_i); while (!dc_req_ready_i);
        @(negedge clk_i);
        dc_req_valid_o = 0;
        if (cancel) begin
            dc_kill_o = 1;
            @(negedge clk_i);
            dc_kill_o = 0;
        end else begin
            if (!dc_resp_device_i)
                while (!dc_resp_valid_i) @(negedge clk_i);
            if (!dc_resp_device_i && dc_resp_err_i != expect_dc_error)
                $fatal(1, "FAIL cached error expected %b got %b", expect_dc_error, dc_resp_err_i);
            if (!dc_resp_device_i && dc_resp_err_i) begin
                if (!expect_dc_error)
                    $fatal(1, "FAIL unexpected cached access error");
                dc_kill_o = 1;
                @(negedge clk_i);
                dc_kill_o = 0;
                return;
            end
            result = dc_resp_data_i;
            dc_store_data_o = data;
            dc_commit_o = 1;
            @(negedge clk_i);
            dc_commit_o = 0;
            if (addr >= 32'h20000000 && addr < 32'h80000000) begin
                while (!dc_resp_valid_i) @(negedge clk_i);
                result = dc_resp_data_i;
                if (dc_resp_err_i != expect_dc_error)
                    $fatal(1, "FAIL device error expected %b got %b",
                        expect_dc_error, dc_resp_err_i);
            end
        end
    endtask

    task automatic overlapping_store_load;
        dc_req_addr_o = 32'h10000002;
        dc_req_size_o = 1;
        dc_req_store_o = 1;
        dc_req_valid_o = 1;
        do @(posedge clk_i); while (!dc_req_ready_i);
        @(negedge clk_i);
        dc_req_valid_o = 0;
        while (!dc_resp_valid_i) @(negedge clk_i);
        dc_commit_o = 1;
        dc_store_data_o = 32'hbbcc;
        dc_req_addr_o = 32'h10000000;
        dc_req_size_o = 2;
        dc_req_store_o = 0;
        dc_req_valid_o = 1;
        @(posedge clk_i);
        if (!dc_req_ready_i) begin
            @(negedge clk_i);
            dc_commit_o = 0;
            do @(posedge clk_i); while (!dc_req_ready_i);
        end
        @(negedge clk_i);
        dc_commit_o = 0;
        dc_req_valid_o = 0;
        while (!dc_resp_valid_i) @(negedge clk_i);
        if (dc_resp_data_i != 32'hbbccaa44)
            $fatal(1, "FAIL write-buffer merge expected bbccaa44 got %08x", dc_resp_data_i);
        dc_commit_o = 1;
        @(negedge clk_i);
        dc_commit_o = 0;
    endtask

    initial begin
        ic_req_valid_o = 0;
        ic_req_addr_o = 0;
        ic_kill_o = 0;
        ic_inv_o = 0;
        dc_req_valid_o = 0;
        dc_req_addr_o = 0;
        dc_req_store_o = 0;
        dc_req_size_o = 2;
        dc_kill_o = 0;
        dc_commit_o = 0;
        dc_store_data_o = 0;
        dc_fence_o = 0;
        dc_clean_all_o = 0;
        done_w = 0;
        void'($value$plusargs("VIOLATION=%d", violation));
        ic_error_enabled = $value$plusargs("IC_ERROR_ADDR=%h", ic_error_addr);
        dc_error_enabled = $value$plusargs("DC_ERROR_ADDR=%h", dc_error_addr);
        wait (rst_n_i);
        @(negedge clk_i);
        if (violation == 1) begin
            ic_req_addr_o = 2;
            ic_req_valid_o = 1;
            repeat (2) @(negedge clk_i);
            $fatal(1, "FAIL checker failed to reject unaligned fetch");
        end
        fetch(0, 0);
        retire_pair();
        fetch(8, 1);
        // A replacement fetch must survive completion of the canceled fill.
        fetch(16, 0);
        trace_valid_w = 1;
        trace_pc_w = 16;
        trace_instr_w = 64'h0000000000000013;
        trace_rd_w = 0;
        trace_rd_data_w = 64'h00000000deadbeef;
        retired++;
        @(negedge clk_i);
        trace_valid_w = 0;
        access_data(32'h10000000, 1, 2, 32'h11223344, 0);
        access_data(32'h10000001, 1, 0, 32'haa, 0);
        access_data(32'h10000000, 0, 2, 0, 0);
        if (!dc_error_enabled && result != 32'h1122aa44)
            $fatal(1, "FAIL load expected 1122aa44 got %08x", result);
        access_data(32'h10000000, 1, 2, 32'hdeadbeef, 1);
        access_data(32'h10000000, 0, 2, 0, 0);
        if (!dc_error_enabled && result != 32'h1122aa44)
            $fatal(1, "FAIL killed store changed memory: %08x", result);
        if (!dc_error_enabled)
            overlapping_store_load();
        access_data(32'h40007000, 1, 2, 32'hdeadbeef, 1);
        access_data(32'h40007000, 1, 2, 32'h55667788, 0);
        access_data(32'h40007000, 0, 2, 0, 0);
        if (!dc_error_enabled && result != 32'h55667788)
            $fatal(1, "FAIL device expected 55667788 got %08x", result);
        access_data(32'h10001000, 1, 2, 1, 0);
        dc_fence_o = 1;
        while (!dc_fence_done_i) @(negedge clk_i);
        dc_fence_o = 0;
        @(negedge clk_i);
        dc_clean_all_o = 1;
        while (!dc_fence_done_i) @(negedge clk_i);
        dc_clean_all_o = 0;
        ic_inv_o = 1;
        while (!ic_inv_done_i) @(negedge clk_i);
        ic_inv_o = 0;
        if (mtime_i == 0)
            $fatal(1, "FAIL mtime did not advance");
        // Interrupt inputs are stimulated externally; the stub only reports observation.
        trace_trap_w = 1;
        trace_cause_w = 32'h8000000b;
        @(negedge clk_i);
        trace_trap_w = 0;
        done_w = 1;
    end
    // These interface inputs are observed by the TB through their own checks.
    wire unused_w = &{1'b0, irq_meip_i, irq_msip_i, irq_mtip_i, dc_wb_event_i};
endmodule
