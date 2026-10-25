`timescale 1ns/1ps
`include "edrv32_bus.vh"
`include "edrv32_lsu.vh"
`include "edrv32_axi4.vh"

module tb_cache_blocking #(parameter FETCH_WIDE=0);
    reg clk;
    reg rst_n;

    reg i_lookup_valid;
    wire i_lookup_ready;
    reg [31:0] i_lookup_addr;
    wire i_lookup_resp_valid;
    reg i_lookup_resp_ready;
    wire [31:0] i_lookup_resp_data;
    wire [31:0] i_lookup_resp_upper;
    reg i_lookup_cacheable=1;
    reg i_inject_error=0;
    wire i_lookup_resp_error;
    reg i_invalidate;
    wire i_fabric_req_valid;
    reg i_fabric_req_ready;
    wire [31:0] i_fabric_req_addr;
    reg i_fabric_resp_valid;
    wire i_fabric_resp_ready;
    reg [31:0] i_fabric_resp_data;
    reg i_fabric_resp_error;
    wire [`AXI_ID_W-1:0] i_axi_arid;
    wire [31:0] i_axi_araddr;
    wire [`AXI_LEN_W-1:0] i_axi_arlen;
    wire [`AXI_SIZE_W-1:0] i_axi_arsize;
    wire [`AXI_BURST_W-1:0] i_axi_arburst;
    wire i_axi_arvalid;
    wire i_axi_arready;
    wire [`AXI_ID_W-1:0] i_axi_rid;
    wire [`AXI_DATA_W-1:0] i_axi_rdata;
    wire [`AXI_RESP_W-1:0] i_axi_rresp;
    wire i_axi_rlast;
    wire i_axi_rvalid;
    wire i_axi_rready;

    reg d_lookup_valid;
    wire d_lookup_ready;
    reg [31:0] d_lookup_addr;
    reg [`EDRV32_LSU_TOKEN_W-1:0] d_lookup_token;
    reg d_lookup_store;
    wire d_lookup_resp_valid;
    reg d_lookup_resp_ready;
    wire [31:0] d_lookup_resp_data;
    wire [`EDRV32_LSU_TOKEN_W-1:0] d_lookup_resp_token;
    wire d_lookup_resp_store;
    wire d_lookup_fast_valid;
    wire [`EDRV32_LSU_TOKEN_W-1:0] d_lookup_fast_token;
    wire d_lookup_fast_store;
    wire [31:0] d_lookup_fast_data;
    wire d_lookup_resp_error;
    reg d_lookup_cancel;
    reg [1:0] d_lookup_cancel_keep_count;

    reg d_commit_valid;
    wire d_commit_ready;
    reg [31:0] d_commit_addr;
    reg d_commit_write;
    reg [`BUS_SZ_W-1:0] d_commit_size;
    reg [3:0] d_commit_wstrb;
    reg [31:0] d_commit_wdata;
    reg d_commit_cacheable;
    wire d_commit_resp_valid;
    reg d_commit_resp_ready;
    wire [31:0] d_commit_resp_data;
    wire d_commit_resp_error;

    wire d_fabric_req_valid;
    reg d_fabric_req_ready;
    wire [31:0] d_fabric_req_addr;
    wire d_fabric_req_write;
    wire [`BUS_SZ_W-1:0] d_fabric_req_size;
    wire [3:0] d_fabric_req_wstrb;
    wire [31:0] d_fabric_req_wdata;
    reg d_fabric_resp_valid;
    wire d_fabric_resp_ready;
    reg [31:0] d_fabric_resp_data;
    reg d_fabric_resp_error;
    wire [`AXI_ID_W-1:0] d_axi_awid;
    wire [31:0] d_axi_awaddr;
    wire [`AXI_LEN_W-1:0] d_axi_awlen;
    wire [`AXI_SIZE_W-1:0] d_axi_awsize;
    wire [`AXI_BURST_W-1:0] d_axi_awburst;
    wire d_axi_awvalid;
    wire d_axi_awready;
    wire [`AXI_DATA_W-1:0] d_axi_wdata;
    wire [`AXI_STRB_W-1:0] d_axi_wstrb;
    wire d_axi_wlast;
    wire d_axi_wvalid;
    wire d_axi_wready;
    wire [`AXI_ID_W-1:0] d_axi_bid;
    wire [`AXI_RESP_W-1:0] d_axi_bresp;
    wire d_axi_bvalid;
    wire d_axi_bready;
    wire [`AXI_ID_W-1:0] d_axi_arid;
    wire [31:0] d_axi_araddr;
    wire [`AXI_LEN_W-1:0] d_axi_arlen;
    wire [`AXI_SIZE_W-1:0] d_axi_arsize;
    wire [`AXI_BURST_W-1:0] d_axi_arburst;
    wire d_axi_arvalid;
    wire d_axi_arready;
    wire [`AXI_ID_W-1:0] d_axi_rid;
    wire [`AXI_DATA_W-1:0] d_axi_rdata;
    wire [`AXI_RESP_W-1:0] d_axi_rresp;
    wire d_axi_rlast;
    wire d_axi_rvalid;
    wire d_axi_rready;
    reg d_clean_all;
    wire d_clean_busy;
    wire d_clean_done;
    reg d_maint_invalidate;
    reg d_maint_clean;
    reg d_maint_clean_invalidate;
    reg [31:0] d_maint_addr;
    reg [31:0] d_maint_size;
    wire d_maint_busy;
    wire d_maint_done;

    reg [31:0] memory [0:4095];
    reg i_pending;
    reg [31:0] i_pending_addr;
    reg d_pending;
    reg [31:0] d_pending_addr;
    reg d_pending_write;
    integer i_fabric_requests;
    integer d_fabric_requests;
    integer checks;
    integer memory_index;
    integer d_request_checkpoint;
    reg i_burst_check_active;
    reg [31:0] i_burst_base;
    integer i_burst_responses;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    edrv32_icache #(.LINE_COUNT(16),.FETCH_WIDE(FETCH_WIDE)) u_icache (
        .clk_i(clk), .rst_n_i(rst_n),
        .lookup_req_valid_i(i_lookup_valid), .lookup_req_ready_o(i_lookup_ready),
        .lookup_req_addr_i(i_lookup_addr), .lookup_resp_valid_o(i_lookup_resp_valid),
        .lookup_req_cacheable_i(i_lookup_cacheable), .lookup_req_executable_i(1'b1),
        .lookup_resp_ready_i(i_lookup_resp_ready), .lookup_resp_data_o(i_lookup_resp_data),
        .lookup_resp_upper_o(i_lookup_resp_upper),
        .lookup_resp_error_o(i_lookup_resp_error), .invalidate_i(i_invalidate),
        .axi_arid_o(i_axi_arid), .axi_araddr_o(i_axi_araddr),
        .axi_arlen_o(i_axi_arlen), .axi_arsize_o(i_axi_arsize),
        .axi_arburst_o(i_axi_arburst), .axi_arvalid_o(i_axi_arvalid),
        .axi_arready_i(i_axi_arready), .axi_rid_i(i_axi_rid),
        .axi_rdata_i(i_axi_rdata), .axi_rresp_i(i_axi_rresp),
        .axi_rlast_i(i_axi_rlast), .axi_rvalid_i(i_axi_rvalid),
        .axi_rready_o(i_axi_rready), .miss_o(), .refill_busy_o()
    );

    edrv32_dcache #(.LINE_COUNT(16)) u_dcache (
        .clk_i(clk), .rst_n_i(rst_n),
        .lookup_req_valid_i(d_lookup_valid), .lookup_req_ready_o(d_lookup_ready),
        .lookup_req_token_i(d_lookup_token),
        .lookup_req_addr_i(d_lookup_addr), .lookup_req_store_i(d_lookup_store),
        .lookup_req_size_i(`BUS_SZ_WORD), .lookup_req_unsigned_i(1'b0),
        .lookup_resp_valid_o(d_lookup_resp_valid), .lookup_resp_ready_i(d_lookup_resp_ready),
        .lookup_resp_token_o(d_lookup_resp_token),
        .lookup_resp_store_o(d_lookup_resp_store),
        .lookup_fast_valid_o(d_lookup_fast_valid),
        .lookup_fast_ready_i(1'b0),
        .lookup_fast_token_o(d_lookup_fast_token),
        .lookup_fast_store_o(d_lookup_fast_store),
        .lookup_fast_data_o(d_lookup_fast_data),
        .lookup_resp_data_o(d_lookup_resp_data), .lookup_resp_error_o(d_lookup_resp_error),
        .lookup_cancel_i(d_lookup_cancel),
        .lookup_cancel_keep_count_i(d_lookup_cancel_keep_count),
        .commit_req_valid_i(d_commit_valid), .commit_req_ready_o(d_commit_ready),
        .commit_req_addr_i(d_commit_addr), .commit_req_write_i(d_commit_write),
        .commit_req_size_i(d_commit_size), .commit_req_wstrb_i(d_commit_wstrb),
        .commit_req_wdata_i(d_commit_wdata), .commit_req_cacheable_i(d_commit_cacheable),
        .commit_resp_valid_o(d_commit_resp_valid), .commit_resp_ready_i(d_commit_resp_ready),
        .commit_resp_data_o(d_commit_resp_data), .commit_resp_error_o(d_commit_resp_error),
        .clean_all_i(d_clean_all), .clean_busy_o(d_clean_busy),
        .clean_done_o(d_clean_done),
        .maint_invalidate_i(d_maint_invalidate),
        .maint_clean_i(d_maint_clean),
        .maint_clean_invalidate_i(d_maint_clean_invalidate),
        .maint_addr_i(d_maint_addr), .maint_size_i(d_maint_size),
        .maint_busy_o(d_maint_busy), .maint_done_o(d_maint_done),
        .axi_awid_o(d_axi_awid), .axi_awaddr_o(d_axi_awaddr),
        .axi_awlen_o(d_axi_awlen), .axi_awsize_o(d_axi_awsize),
        .axi_awburst_o(d_axi_awburst), .axi_awvalid_o(d_axi_awvalid),
        .axi_awready_i(d_axi_awready), .axi_wdata_o(d_axi_wdata),
        .axi_wstrb_o(d_axi_wstrb), .axi_wlast_o(d_axi_wlast),
        .axi_wvalid_o(d_axi_wvalid), .axi_wready_i(d_axi_wready),
        .axi_bid_i(d_axi_bid), .axi_bresp_i(d_axi_bresp),
        .axi_bvalid_i(d_axi_bvalid), .axi_bready_o(d_axi_bready),
        .axi_arid_o(d_axi_arid), .axi_araddr_o(d_axi_araddr),
        .axi_arlen_o(d_axi_arlen), .axi_arsize_o(d_axi_arsize),
        .axi_arburst_o(d_axi_arburst), .axi_arvalid_o(d_axi_arvalid),
        .axi_arready_i(d_axi_arready), .axi_rid_i(d_axi_rid),
        .axi_rdata_i(d_axi_rdata), .axi_rresp_i(d_axi_rresp),
        .axi_rlast_i(d_axi_rlast), .axi_rvalid_i(d_axi_rvalid),
        .axi_rready_o(d_axi_rready), .miss_o(), .writeback_o(),
        .refill_busy_o()
    );

    edrv32_axi_native_test_adapter u_icache_memory_adapter (
        .clk_i(clk), .rst_n_i(rst_n),
        .axi_awid_i({`AXI_ID_W{1'b0}}), .axi_awaddr_i(32'd0),
        .axi_awlen_i({`AXI_LEN_W{1'b0}}), .axi_awsize_i(`AXI_SIZE_4B),
        .axi_awburst_i(`AXI_BURST_INCR), .axi_awvalid_i(1'b0),
        .axi_awready_o(), .axi_wdata_i({`AXI_DATA_W{1'b0}}),
        .axi_wstrb_i({`AXI_STRB_W{1'b0}}), .axi_wlast_i(1'b1),
        .axi_wvalid_i(1'b0), .axi_wready_o(), .axi_bid_o(),
        .axi_bresp_o(), .axi_bvalid_o(), .axi_bready_i(1'b1),
        .axi_arid_i(i_axi_arid), .axi_araddr_i(i_axi_araddr),
        .axi_arlen_i(i_axi_arlen), .axi_arsize_i(i_axi_arsize),
        .axi_arburst_i(i_axi_arburst), .axi_arvalid_i(i_axi_arvalid),
        .axi_arready_o(i_axi_arready), .axi_rid_o(i_axi_rid),
        .axi_rdata_o(i_axi_rdata), .axi_rresp_o(i_axi_rresp),
        .axi_rlast_o(i_axi_rlast), .axi_rvalid_o(i_axi_rvalid),
        .axi_rready_i(i_axi_rready),
        .native_req_valid_o(i_fabric_req_valid),
        .native_req_ready_i(i_fabric_req_ready),
        .native_req_addr_o(i_fabric_req_addr),
        .native_req_write_o(), .native_req_size_o(),
        .native_req_wstrb_o(), .native_req_wdata_o(),
        .native_resp_valid_i(i_fabric_resp_valid),
        .native_resp_ready_o(i_fabric_resp_ready),
        .native_resp_rdata_i(i_fabric_resp_data),
        .native_resp_error_i(i_fabric_resp_error)
    );

    edrv32_axi_native_test_adapter u_dcache_memory_adapter (
        .clk_i(clk), .rst_n_i(rst_n),
        .axi_awid_i(d_axi_awid), .axi_awaddr_i(d_axi_awaddr),
        .axi_awlen_i(d_axi_awlen), .axi_awsize_i(d_axi_awsize),
        .axi_awburst_i(d_axi_awburst), .axi_awvalid_i(d_axi_awvalid),
        .axi_awready_o(d_axi_awready), .axi_wdata_i(d_axi_wdata),
        .axi_wstrb_i(d_axi_wstrb), .axi_wlast_i(d_axi_wlast),
        .axi_wvalid_i(d_axi_wvalid), .axi_wready_o(d_axi_wready),
        .axi_bid_o(d_axi_bid), .axi_bresp_o(d_axi_bresp),
        .axi_bvalid_o(d_axi_bvalid), .axi_bready_i(d_axi_bready),
        .axi_arid_i(d_axi_arid), .axi_araddr_i(d_axi_araddr),
        .axi_arlen_i(d_axi_arlen), .axi_arsize_i(d_axi_arsize),
        .axi_arburst_i(d_axi_arburst), .axi_arvalid_i(d_axi_arvalid),
        .axi_arready_o(d_axi_arready), .axi_rid_o(d_axi_rid),
        .axi_rdata_o(d_axi_rdata), .axi_rresp_o(d_axi_rresp),
        .axi_rlast_o(d_axi_rlast), .axi_rvalid_o(d_axi_rvalid),
        .axi_rready_i(d_axi_rready),
        .native_req_valid_o(d_fabric_req_valid),
        .native_req_ready_i(d_fabric_req_ready),
        .native_req_addr_o(d_fabric_req_addr),
        .native_req_write_o(d_fabric_req_write),
        .native_req_size_o(d_fabric_req_size),
        .native_req_wstrb_o(d_fabric_req_wstrb),
        .native_req_wdata_o(d_fabric_req_wdata),
        .native_resp_valid_i(d_fabric_resp_valid),
        .native_resp_ready_o(d_fabric_resp_ready),
        .native_resp_rdata_i(d_fabric_resp_data),
        .native_resp_error_i(d_fabric_resp_error)
    );

    task automatic check_true;
        input condition;
        input [8*120-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("FAIL: %0s", message);
                $fatal(1);
            end
        end
    endtask

    task automatic instruction_lookup;
        input [31:0] address;
        input [31:0] expected;
        begin
            @(negedge clk);
            i_lookup_addr = address;
            i_lookup_valid = 1'b1;
            #1;
            while (!i_lookup_ready) @(negedge clk);
            @(posedge clk); #1;
            i_lookup_valid = 1'b0;
            while (!i_lookup_resp_valid) @(posedge clk);
            #1;
            check_true(!i_lookup_resp_error && i_lookup_resp_data == expected,
                       "instruction lookup returns expected word");
            if(FETCH_WIDE!=0)check_true(i_lookup_resp_upper===
                ((!i_lookup_cacheable || address[3:2]==3)?32'd0:memory[address[13:2]+1]),
                "Wide I-cache returns adjacent word without crossing a line");
            @(posedge clk); #1;
        end
    endtask

    task automatic instruction_hit_burst;
        input [31:0] base_address;
        integer word_i;
        begin
            i_burst_base = base_address;
            i_burst_responses = 0;
            i_burst_check_active = 1'b1;
            for (word_i = 0; word_i < 4; word_i = word_i + 1) begin
                @(negedge clk);
                i_lookup_addr = base_address + word_i * 4;
                i_lookup_valid = 1'b1;
                #1;
                check_true(i_lookup_ready,
                           "warm I-cache accepts one hit request every cycle");
            end
            @(negedge clk);
            i_lookup_valid = 1'b0;
            while (i_burst_responses != 4) @(posedge clk);
            @(negedge clk);
            i_burst_check_active = 1'b0;
            check_true(i_burst_responses == 4,
                       "warm I-cache returns the complete ordered hit burst");
        end
    endtask

    task automatic instruction_hit_backpressure_pair;
        input [31:0] base_address;
        reg [31:0] held_data;
        reg [31:0] held_upper;
        integer hold_cycle;
        begin
            @(negedge clk);
            i_lookup_resp_ready = 1'b0;
            i_lookup_addr = base_address;
            i_lookup_valid = 1'b1;
            #1;
            check_true(i_lookup_ready,
                       "I-cache accepts first hit before response backpressure");

            @(negedge clk);
            i_lookup_addr = base_address + 32'd4;
            #1;
            check_true(i_lookup_ready,
                       "I-cache accepts second hit behind response register");

            @(negedge clk);
            i_lookup_valid = 1'b0;
            held_data = i_lookup_resp_data;
            held_upper = i_lookup_resp_upper;
            check_true(i_lookup_resp_valid &&
                       held_data == memory[base_address[13:2]] &&
                       !i_lookup_ready,
                       "I-cache backpressures lookup behind a held response");
            for (hold_cycle = 0; hold_cycle < 3;
                 hold_cycle = hold_cycle + 1) begin
                @(negedge clk);
                check_true(i_lookup_resp_valid &&
                           i_lookup_resp_data == held_data && i_lookup_resp_upper===held_upper,
                           "I-cache registered response is stable while held");
            end

            i_lookup_resp_ready = 1'b1;
            @(negedge clk);
            check_true(i_lookup_resp_valid &&
                       i_lookup_resp_data == memory[base_address[13:2] + 1],
                       "I-cache releases ordered second response after backpressure");
            @(posedge clk); #1;
        end
    endtask

    always @(posedge clk) begin
        if (i_burst_check_active && i_lookup_resp_valid &&
            i_lookup_resp_ready) begin
            if (i_lookup_resp_error ||
                (i_lookup_resp_data !=
                 memory[i_burst_base[13:2] + i_burst_responses])) begin
                $display("FAIL: pipelined I-cache response %0d out of order",
                         i_burst_responses);
                $fatal(1);
            end
            if(FETCH_WIDE!=0 && i_lookup_resp_upper!==
                ((i_burst_responses==3)?32'd0:memory[i_burst_base[13:2]+i_burst_responses+1]))
                $fatal(1,"Wide I-cache upper lane order mismatch");
            i_burst_responses = i_burst_responses + 1;
        end
    end

    task automatic data_lookup;
        input [31:0] address;
        input store_query;
        input [31:0] expected;
        begin
            @(negedge clk);
            d_lookup_addr = address;
            d_lookup_token = {`EDRV32_LSU_TOKEN_W{1'b0}};
            d_lookup_store = store_query;
            d_lookup_valid = 1'b1;
            #1;
            while (!d_lookup_ready) @(negedge clk);
            @(posedge clk); #1;
            d_lookup_valid = 1'b0;
            while (!d_lookup_resp_valid) @(posedge clk);
            #1;
            check_true(!d_lookup_resp_error &&
                       (store_query || (d_lookup_resp_data == expected)),
                       "data lookup returns expected response");
            @(posedge clk); #1;
        end
    endtask

    task automatic data_hit_recycle_pair;
        input [31:0] first_address;
        input [31:0] first_expected;
        input [31:0] second_address;
        input [31:0] second_expected;
        begin
            @(negedge clk);
            d_lookup_addr = first_address;
            d_lookup_token = 2'b01;
            d_lookup_store = 1'b0;
            d_lookup_valid = 1'b1;
            #1;
            check_true(d_lookup_ready,
                       "D-cache accepts first warm lookup");
            @(posedge clk); #1;

            @(negedge clk);
            d_lookup_addr = second_address;
            d_lookup_token = 2'b10;
            #1;
            check_true(!d_lookup_ready,
                       "D-cache performs synchronous lookup before response");
            @(negedge clk); #1;
            check_true(d_lookup_resp_valid && d_lookup_ready &&
                       d_lookup_resp_token == 2'b01 &&
                       (d_lookup_resp_data == first_expected),
                       "D-cache response keeps first token while recycling");
            @(posedge clk); #1;

            @(negedge clk);
            d_lookup_valid = 1'b0;
            @(negedge clk); #1;
            check_true(d_lookup_resp_valid &&
                       d_lookup_resp_token == 2'b10 &&
                       (d_lookup_resp_data == second_expected),
                       "recycled D-cache lookup returns second token in order");
            @(posedge clk); #1;
        end
    endtask

    task automatic commit_request;
        input [31:0] address;
        input write_request;
        input cacheable_request;
        input [3:0] write_strobe;
        input [31:0] write_data;
        input [31:0] expected_read;
        reg response_seen;
        reg response_error;
        reg [31:0] response_data;
        begin
            @(negedge clk);
            d_commit_addr = address;
            d_commit_write = write_request;
            d_commit_cacheable = cacheable_request;
            d_commit_wstrb = write_strobe;
            d_commit_wdata = write_data;
            d_commit_valid = 1'b1;
            #1;
            while (!d_commit_ready) @(negedge clk);
            #1;
            response_seen = d_commit_resp_valid;
            response_error = d_commit_resp_error;
            response_data = d_commit_resp_data;
            @(posedge clk); #1;
            d_commit_valid = 1'b0;
            if (!response_seen) begin
                while (!d_commit_resp_valid) @(posedge clk);
                #1;
                response_error = d_commit_resp_error;
                response_data = d_commit_resp_data;
            end
            check_true(!response_error &&
                       (write_request || (response_data == expected_read)),
                       "COMMIT memory request completes with expected response");
            @(posedge clk); #1;
        end
    endtask

    task automatic committed_store_turnover_load;
        input [31:0] address;
        input [3:0] write_strobe;
        input [31:0] write_data;
        input [31:0] expected_read;
        begin
            // The preceding store lookup owns a registered reservation.  Its
            // COMMIT authorization and the following load lookup must both be
            // accepted on this edge; the load then observes the buffered line
            // rather than the not-yet-written RAM contents.
            @(negedge clk);
            d_commit_addr = address;
            d_commit_write = 1'b1;
            d_commit_cacheable = 1'b1;
            d_commit_wstrb = write_strobe;
            d_commit_wdata = write_data;
            d_commit_valid = 1'b1;
            d_lookup_addr = address;
            d_lookup_store = 1'b0;
            d_lookup_valid = 1'b1;
            #1;
            check_true(d_commit_ready && d_commit_resp_valid &&
                       !d_commit_resp_error,
                       "committed store enters buffer with direct response");
            check_true(d_lookup_ready,
                       "store authorization accepts following lookup same cycle");
            @(posedge clk); #1;
            d_commit_valid = 1'b0;
            d_lookup_valid = 1'b0;
            while (!d_lookup_resp_valid) @(posedge clk);
            #1;
            check_true(!d_lookup_resp_error &&
                       (d_lookup_resp_data == expected_read),
                       "following load forwards newest committed store line");
            @(posedge clk); #1;
        end
    endtask

    task automatic committed_store_response_backpressure;
        input [31:0] address;
        input [31:0] write_data;
        begin
            @(negedge clk);
            d_commit_resp_ready = 1'b0;
            d_commit_addr = address;
            d_commit_write = 1'b1;
            d_commit_cacheable = 1'b1;
            d_commit_wstrb = 4'b1111;
            d_commit_wdata = write_data;
            d_commit_valid = 1'b1;
            #1;
            check_true(d_commit_ready && d_commit_resp_valid &&
                       !d_commit_resp_error,
                       "buffered store accepts while response is backpressured");
            @(posedge clk); #1;
            d_commit_valid = 1'b0;
            @(negedge clk); #1;
            check_true(d_commit_resp_valid && !d_commit_resp_error,
                       "buffered store response remains registered while held");
            d_commit_resp_ready = 1'b1;
            @(posedge clk); #1;
            check_true(!d_commit_resp_valid,
                       "held buffered-store response drains exactly once");
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            i_pending <= 1'b0;
            i_fabric_resp_valid <= 1'b0;
        end else begin
            if (i_fabric_resp_valid && i_fabric_resp_ready)
                i_fabric_resp_valid <= 1'b0;
            if (i_pending && !i_fabric_resp_valid) begin
                i_fabric_resp_valid <= 1'b1;
                i_fabric_resp_data <= memory[i_pending_addr[13:2]];
                i_fabric_resp_error <= i_inject_error;
                i_pending <= 1'b0;
            end
            if (i_fabric_req_valid && i_fabric_req_ready) begin
                i_pending <= 1'b1;
                i_pending_addr <= i_fabric_req_addr;
                i_fabric_requests <= i_fabric_requests + 1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            d_pending <= 1'b0;
            d_fabric_resp_valid <= 1'b0;
        end else begin
            if (d_fabric_resp_valid && d_fabric_resp_ready)
                d_fabric_resp_valid <= 1'b0;
            if (d_pending && !d_fabric_resp_valid) begin
                d_fabric_resp_valid <= 1'b1;
                d_fabric_resp_data <= memory[d_pending_addr[13:2]];
                d_fabric_resp_error <= 1'b0;
                d_pending <= 1'b0;
            end
            if (d_fabric_req_valid && d_fabric_req_ready) begin
                d_pending <= 1'b1;
                d_pending_addr <= d_fabric_req_addr;
                d_pending_write <= d_fabric_req_write;
                d_fabric_requests <= d_fabric_requests + 1;
                if (d_fabric_req_write) begin
                    if (d_fabric_req_wstrb[0]) memory[d_fabric_req_addr[13:2]][7:0] <= d_fabric_req_wdata[7:0];
                    if (d_fabric_req_wstrb[1]) memory[d_fabric_req_addr[13:2]][15:8] <= d_fabric_req_wdata[15:8];
                    if (d_fabric_req_wstrb[2]) memory[d_fabric_req_addr[13:2]][23:16] <= d_fabric_req_wdata[23:16];
                    if (d_fabric_req_wstrb[3]) memory[d_fabric_req_addr[13:2]][31:24] <= d_fabric_req_wdata[31:24];
                end
            end
        end
    end

    initial begin
        for (memory_index = 0; memory_index < 4096; memory_index = memory_index + 1)
            memory[memory_index] = 32'h6000_0000 ^ memory_index;

        checks = 0;
        i_fabric_requests = 0;
        d_fabric_requests = 0;
        i_burst_check_active = 1'b0;
        i_burst_base = 32'd0;
        i_burst_responses = 0;
        rst_n = 1'b0;
        i_lookup_valid = 1'b0;
        i_lookup_addr = 32'd0;
        i_lookup_resp_ready = 1'b1;
        i_invalidate = 1'b0;
        i_fabric_req_ready = 1'b1;
        i_fabric_resp_valid = 1'b0;
        i_fabric_resp_data = 32'd0;
        i_fabric_resp_error = 1'b0;
        d_lookup_valid = 1'b0;
        d_lookup_addr = 32'd0;
        d_lookup_token = {`EDRV32_LSU_TOKEN_W{1'b0}};
        d_lookup_store = 1'b0;
        d_lookup_resp_ready = 1'b1;
        d_lookup_cancel = 1'b0;
        d_lookup_cancel_keep_count = 2'd0;
        d_commit_valid = 1'b0;
        d_commit_addr = 32'd0;
        d_commit_write = 1'b0;
        d_commit_size = `BUS_SZ_WORD;
        d_commit_wstrb = 4'd0;
        d_commit_wdata = 32'd0;
        d_commit_cacheable = 1'b0;
        d_commit_resp_ready = 1'b1;
        d_fabric_req_ready = 1'b1;
        d_fabric_resp_valid = 1'b0;
        d_fabric_resp_data = 32'd0;
        d_fabric_resp_error = 1'b0;
        d_clean_all = 1'b0;
        d_maint_invalidate = 1'b0;
        d_maint_clean = 1'b0;
        d_maint_clean_invalidate = 1'b0;
        d_maint_addr = 32'd0;
        d_maint_size = 32'd0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        instruction_lookup(32'h8000_0108, memory[32'h0108 >> 2]);
        check_true(i_fabric_requests == 4, "cold I-cache miss refills exactly one four-word line");
        instruction_lookup(32'h8000_0100, memory[32'h0100 >> 2]);
        instruction_lookup(32'h8000_0104, memory[32'h0104 >> 2]);
        instruction_lookup(32'h8000_0108, memory[32'h0108 >> 2]);
        instruction_lookup(32'h8000_010c, memory[32'h010c >> 2]);
        check_true(i_fabric_requests == 4,
                   "all four refilled I-cache words hit without fabric requests");
        instruction_hit_burst(32'h8000_0100);
        check_true(i_fabric_requests == 4,
                   "pipelined I-cache hit burst performs no refill traffic");
        instruction_hit_backpressure_pair(32'h8000_0100);
        @(negedge clk); i_invalidate = 1'b1;
        @(posedge clk); #1; i_invalidate = 1'b0;
        instruction_lookup(32'h8000_0108, memory[32'h0108 >> 2]);
        check_true(i_fabric_requests == 8, "I-cache invalidate forces a new line refill");

        // Three lines map to one set.  Two resident lines must coexist and the
        // third line must evict only the exact-LRU way.
        instruction_lookup(32'h8000_0188, memory[32'h0188 >> 2]);
        instruction_lookup(32'h8000_0208, memory[32'h0208 >> 2]);
        check_true(i_fabric_requests == 16,
                   "two-way I-cache holds two conflicting lines before replacement");
        instruction_lookup(32'h8000_0188, memory[32'h0188 >> 2]);
        check_true(i_fabric_requests == 16,
                   "I-cache replacement preserves the most recently used way");

        data_lookup(32'h8000_0204, 1'b0, memory[32'h0204 >> 2]);
        check_true(d_fabric_requests == 4, "cold D-cache load refills four words");
        data_lookup(32'h8000_0200, 1'b0, memory[32'h0200 >> 2]);
        data_lookup(32'h8000_0204, 1'b0, memory[32'h0204 >> 2]);
        data_lookup(32'h8000_0208, 1'b0, memory[32'h0208 >> 2]);
        data_lookup(32'h8000_020c, 1'b0, memory[32'h020c >> 2]);
        check_true(d_fabric_requests == 4,
                   "all four refilled D-cache words hit without fabric requests");
        data_hit_recycle_pair(32'h8000_0200, memory[32'h0200 >> 2],
                              32'h8000_0204, memory[32'h0204 >> 2]);
        check_true(d_fabric_requests == 4,
                   "recycled D-cache hits perform no refill traffic");
        data_lookup(32'h8000_0208, 1'b1, 32'd0);
        committed_store_turnover_load(32'h8000_0208, 4'b0101,
                                      32'h00ad_00ef, 32'h60ad_00ef);
        check_true(d_fabric_requests == 4,
                   "buffered store turnover uses no fabric transaction");
        data_lookup(32'h8000_020c, 1'b1, 32'd0);
        committed_store_response_backpressure(32'h8000_020c,
                                              32'hc001_c0de);
        data_lookup(32'h8000_020c, 1'b0, 32'hc001_c0de);
        data_lookup(32'h8000_0204, 1'b1, 32'd0);
        commit_request(32'h8000_0204, 1'b1, 1'b1, 4'b0010,
                       32'h0000_aa00, 32'd0);
        check_true(d_fabric_requests == 4,
                   "write-back store hit has no immediate fabric transaction");
        data_lookup(32'h8000_0204, 1'b0, 32'h6000_aa81);
        check_true(memory[32'h0204 >> 2] == 32'h6000_0081,
                   "dirty store data remains resident before clean or eviction");

        @(negedge clk); d_clean_all = 1'b1;
        @(posedge clk); #1; d_clean_all = 1'b0;
        while (!d_clean_done) @(posedge clk);
        #1;
        check_true(d_fabric_requests == 8 &&
                   memory[32'h0204 >> 2] == 32'h6000_aa81,
                   "D-cache clean writes all four words of a dirty line");

        data_lookup(32'h8000_0304, 1'b1, 32'd0);
        check_true(d_fabric_requests == 12,
                   "store miss performs a four-word write allocation");
        commit_request(32'h8000_0304, 1'b1, 1'b1, 4'b1111,
                       32'h1234_5678, 32'd0);
        check_true(d_fabric_requests == 12 &&
                   memory[32'h0304 >> 2] != 32'h1234_5678,
                   "write-allocated store modifies data only at COMMIT and stays dirty");

        @(negedge clk); d_clean_all = 1'b1;
        @(posedge clk); #1; d_clean_all = 1'b0;
        while (!d_clean_done) @(posedge clk);
        #1;
        check_true(d_fabric_requests == 16 &&
                   memory[32'h0304 >> 2] == 32'h1234_5678,
                   "second clean publishes the write-allocated store");

        commit_request(32'h8000_0400, 1'b0, 1'b0, 4'b0000,
                       32'd0, memory[32'h0400 >> 2]);
        check_true(d_fabric_requests == 17, "uncached load bypasses the cache array");

        // Range maintenance must act on matching physical line addresses only.
        data_lookup(32'h8000_0600, 1'b0, memory[32'h0600 >> 2]);
        data_lookup(32'h8000_0610, 1'b0, memory[32'h0610 >> 2]);
        d_request_checkpoint = d_fabric_requests;
        @(negedge clk);
        d_maint_addr = 32'h8000_0600;
        d_maint_size = 32'd16;
        d_maint_invalidate = 1'b1;
        @(posedge clk); #1; d_maint_invalidate = 1'b0;
        while (!d_maint_done) @(posedge clk);
        data_lookup(32'h8000_0610, 1'b0, memory[32'h0610 >> 2]);
        check_true(d_fabric_requests == d_request_checkpoint,
                   "range invalidate preserves an adjacent resident line");
        data_lookup(32'h8000_0600, 1'b0, memory[32'h0600 >> 2]);
        check_true(d_fabric_requests == d_request_checkpoint + 4,
                   "range invalidate removes the selected resident line");

        data_lookup(32'h8000_0600, 1'b1, 32'd0);
        commit_request(32'h8000_0600, 1'b1, 1'b1, 4'b1111,
                       32'haaaa_0600, 32'd0);
        data_lookup(32'h8000_0610, 1'b1, 32'd0);
        commit_request(32'h8000_0610, 1'b1, 1'b1, 4'b1111,
                       32'hbbbb_0610, 32'd0);
        d_request_checkpoint = d_fabric_requests;
        @(negedge clk);
        d_maint_addr = 32'h8000_0610;
        d_maint_size = 32'd16;
        d_maint_clean = 1'b1;
        @(posedge clk); #1; d_maint_clean = 1'b0;
        while (!d_maint_done) @(posedge clk);
        #1;
        check_true((d_fabric_requests == d_request_checkpoint + 4) &&
                   (memory[32'h0610 >> 2] == 32'hbbbb_0610) &&
                   (memory[32'h0600 >> 2] != 32'haaaa_0600),
                   "range clean writes only the selected dirty line");

        d_request_checkpoint = d_fabric_requests;
        @(negedge clk);
        d_maint_addr = 32'h8000_0600;
        d_maint_size = 32'd16;
        d_maint_clean_invalidate = 1'b1;
        @(posedge clk); #1; d_maint_clean_invalidate = 1'b0;
        while (!d_maint_done) @(posedge clk);
        #1;
        check_true((d_fabric_requests == d_request_checkpoint + 4) &&
                   (memory[32'h0600 >> 2] == 32'haaaa_0600),
                   "range clean+invalidate publishes the selected dirty line");
        d_request_checkpoint = d_fabric_requests;
        data_lookup(32'h8000_0600, 1'b0, 32'haaaa_0600);
        check_true(d_fabric_requests == d_request_checkpoint + 4,
                   "clean+invalidate forces a later refill");

        // Keep an architecturally committed Store reservation across a
        // redirect cancellation.  The speculative queue supplies the keep
        // count before it flushes its younger entries.
        data_lookup(32'h8000_0600, 1'b1, 32'd0);
        check_true(u_dcache.reservation_count_r == 3'd1,
                   "prepared Store owns one reservation");
        @(negedge clk);
        d_lookup_cancel_keep_count = 2'd1;
        d_lookup_cancel = 1'b1;
        @(posedge clk); #1;
        d_lookup_cancel = 1'b0;
        d_lookup_cancel_keep_count = 2'd0;
        check_true(u_dcache.reservation_count_r == 3'd1 &&
                   u_dcache.store_reservation_addr_w == 32'h8000_0600,
                   "redirect preserves the committed reservation");
        commit_request(32'h8000_0600, 1'b1, 1'b1, 4'b1111,
                       32'h1234_0600, 32'd0);
        check_true(u_dcache.reservation_count_r == 3'd0,
                   "preserved reservation authorizes its committed Store");

        // Cancel after the AXI refill has begun. AXI VALID cannot be withdrawn,
        // so the full accepted line burst is drained but never installed.
        @(negedge clk);
        d_lookup_addr = 32'h8000_0500;
        d_lookup_store = 1'b0;
        d_lookup_valid = 1'b1;
        #1;
        while (!d_lookup_ready) @(negedge clk);
        @(posedge clk); #1; d_lookup_valid = 1'b0;
        d_request_checkpoint = d_fabric_requests;
        while (!(d_fabric_req_valid && d_fabric_req_ready)) @(posedge clk);
        @(negedge clk); d_lookup_cancel = 1'b1;
        @(posedge clk); #1; d_lookup_cancel = 1'b0;
        while (!d_lookup_ready) @(posedge clk);
        check_true(d_fabric_requests == d_request_checkpoint + 4,
                   "canceled AXI refill drains the accepted line burst");

        if(FETCH_WIDE!=0)begin
            i_lookup_cacheable=0;
            instruction_lookup(32'h00000024,memory[9]);
            i_lookup_cacheable=1;
            @(negedge clk);i_inject_error=1;i_lookup_valid=1;i_lookup_addr=32'h8000100c;
            while(!i_lookup_ready)@(negedge clk);
            @(posedge clk);#1;i_lookup_valid=0;
            while(!i_lookup_resp_valid)@(posedge clk);
            #1;check_true(i_lookup_resp_error && i_lookup_resp_data===0 && i_lookup_resp_upper===0,
                "Wide refill error suppresses all length-sensitive data");
            @(posedge clk);#1;i_inject_error=0;
            instruction_lookup(32'h8000100c,memory[32'h100c>>2]);
        end
        $display("PASS: pipelined-hit I$/blocking D$ contracts (%0d checks)", checks);
        $finish;
    end
endmodule

