`timescale 1ns/1ps
`include "edrv32_uop.vh"
`include "edrv32_bus.vh"
`include "edrv32_exception.vh"
`include "edrv32_lsu.vh"

module tb_mem_req_flow;
    reg clk, rst_n;
    reg in_valid;
    wire in_ready;
    reg [31:0] in_pc, in_instr, in_result, in_mem_addr, in_store_data;
    reg in_is_compressed, in_rd_write, in_result_ready, in_mem_unsigned;
    reg [4:0] in_rd;
    reg [`EDRV32_EPOCH_W-1:0] in_epoch;
    reg [`EDRV32_OP_CLASS_W-1:0] in_op_class;
    reg [`BUS_SZ_W-1:0] in_mem_size;
    reg in_mdu_token;
    reg [`EDRV32_CSR_OP_W-1:0] in_csr_op;
    reg [11:0] in_csr_addr;
    reg [31:0] in_csr_src;
    reg in_fence, in_fencei, in_mret, in_wfi, in_exception_valid;
    reg [`EDRV32_EXC_CAUSE_W-1:0] in_exception_cause;
    reg [31:0] in_exception_tval;
    wire candidate_valid, candidate_ready;
    wire [31:0] candidate_pc, candidate_instr, candidate_result;
    wire [31:0] candidate_mem_addr, candidate_store_data;
    wire candidate_is_compressed, candidate_rd_write;
    wire candidate_result_ready, candidate_mem_unsigned;
    wire [4:0] candidate_rd;
    wire [`EDRV32_EPOCH_W-1:0] candidate_epoch;
    wire [`EDRV32_OP_CLASS_W-1:0] candidate_op_class;
    wire [`BUS_SZ_W-1:0] candidate_mem_size;
    wire candidate_mem_cacheable, candidate_mem_tcm, candidate_mem_mmio;
    wire candidate_mdu_token;
    wire [`EDRV32_CSR_OP_W-1:0] candidate_csr_op;
    wire [11:0] candidate_csr_addr;
    wire [31:0] candidate_csr_src;
    wire candidate_fence, candidate_fencei, candidate_mret, candidate_wfi;
    wire candidate_exception_valid;
    wire [`EDRV32_EXC_CAUSE_W-1:0] candidate_exception_cause;
    wire [31:0] candidate_exception_tval;
    wire out_valid;
    reg out_accept;
    wire [31:0] out_pc, out_instr, out_result, out_mem_addr, out_store_data;
    wire out_is_compressed, out_rd_write, out_result_ready, out_mem_unsigned;
    wire [4:0] out_rd;
    wire [`EDRV32_EPOCH_W-1:0] out_epoch;
    wire [`EDRV32_OP_CLASS_W-1:0] out_op_class;
    wire [`BUS_SZ_W-1:0] out_mem_size;
    wire out_mem_cacheable, out_mem_tcm, out_mem_mmio, out_mdu_token;
    wire [`EDRV32_CSR_OP_W-1:0] out_csr_op;
    wire [11:0] out_csr_addr;
    wire [31:0] out_csr_src;
    wire out_fence, out_fencei, out_mret, out_wfi, out_exception_valid;
    wire [`EDRV32_EXC_CAUSE_W-1:0] out_exception_cause;
    wire [31:0] out_exception_tval;
    wire queue_full;
    reg kill;
    integer checks;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic check_true;
        input condition;
        input [8*96-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("FAIL: %0s", message);
                $fatal(1);
            end
        end
    endtask

    task automatic set_packet;
        input [31:0] pc_i;
        input [4:0] rd_i;
        input [31:0] value_i;
        begin
            in_pc = pc_i;
            in_instr = {20'h12345, rd_i, 7'h13};
            in_rd = rd_i;
            in_result = value_i;
            in_mem_addr = 32'h8000_1000 + {25'd0, rd_i, 2'b00};
            in_store_data = value_i ^ 32'h55aa_55aa;
        end
    endtask

    edrv32_mem1_stage dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .valid_i(in_valid),
        .ready_o(in_ready),
        .pc_i(in_pc),
        .instr_i(in_instr),
        .is_compressed_i(in_is_compressed),
        .epoch_i(in_epoch),
        .rd_i(in_rd),
        .rd_write_i(in_rd_write),
        .op_class_i(in_op_class),
        .result_i(in_result),
        .result_ready_i(in_result_ready),
        .mem_addr_i(in_mem_addr),
        .mem_size_i(in_mem_size),
        .mem_unsigned_i(in_mem_unsigned),
        .store_data_i(in_store_data),
        .mdu_token_i(in_mdu_token),
        .csr_op_i(in_csr_op),
        .csr_addr_i(in_csr_addr),
        .csr_src_i(in_csr_src),
        .fence_i(in_fence),
        .fencei_i(in_fencei),
        .mret_i(in_mret),
        .wfi_i(in_wfi),
        .exception_valid_i(in_exception_valid),
        .exception_cause_i(in_exception_cause),
        .exception_tval_i(in_exception_tval),
        .memory_sequence_i({`EDRV32_LSU_SEQUENCE_W{1'b0}}),
        .packet_valid_o(out_valid),
        .packet_ready_i(out_accept),
        .packet_pc_o(out_pc),
        .packet_instr_o(out_instr),
        .packet_is_compressed_o(out_is_compressed),
        .packet_epoch_o(out_epoch),
        .packet_rd_o(out_rd),
        .packet_rd_write_o(out_rd_write),
        .packet_op_class_o(out_op_class),
        .packet_result_o(out_result),
        .packet_result_ready_o(out_result_ready),
        .packet_mem_addr_o(out_mem_addr),
        .packet_mem_size_o(out_mem_size),
        .packet_mem_unsigned_o(out_mem_unsigned),
        .packet_store_data_o(out_store_data),
        .packet_mem_cacheable_o(out_mem_cacheable),
        .packet_mem_tcm_o(out_mem_tcm),
        .packet_mem_mmio_o(out_mem_mmio),
        .packet_lsu_token_valid_o(),
        .packet_lsu_token_o(),
        .packet_mdu_token_o(out_mdu_token),
        .packet_csr_op_o(out_csr_op),
        .packet_csr_addr_o(out_csr_addr),
        .packet_csr_src_o(out_csr_src),
        .packet_fence_o(out_fence),
        .packet_fencei_o(out_fencei),
        .packet_mret_o(out_mret),
        .packet_wfi_o(out_wfi),
        .packet_exception_valid_o(out_exception_valid),
        .packet_exception_cause_o(out_exception_cause),
        .packet_exception_tval_o(out_exception_tval),
        .full_o(queue_full),
        .load_alloc_valid_o(),
        .load_alloc_ready_i(1'b1),
        .load_alloc_token_i({`EDRV32_LSU_TOKEN_W{1'b0}}),
        .load_alloc_pc_o(), .load_alloc_rd_o(), .load_alloc_addr_o(),
        .load_alloc_size_o(), .load_alloc_unsigned_o(),
        .load_alloc_epoch_o(), .load_alloc_sequence_o(),
        .store_alloc_valid_o(), .store_alloc_ready_i(1'b1),
        .store_alloc_token_i({`EDRV32_LSU_TOKEN_W{1'b0}}), .store_alloc_pc_o(),
        .store_alloc_addr_o(), .store_alloc_wstrb_o(),
        .store_alloc_wdata_o(), .store_alloc_epoch_o(),
        .store_alloc_sequence_o(),
        .kill_i(kill)
    );

    initial begin
        checks = 0;
        rst_n = 1'b0;
        in_valid = 1'b0;
        in_pc = 32'd0; in_instr = 32'd0; in_is_compressed = 1'b0;
        in_epoch = 2'd1; in_rd = 5'd0; in_rd_write = 1'b1;
        // Use a real load packet when checking PMA sideband propagation;
        // non-memory uops intentionally carry no effective PMA attributes.
        in_op_class = `EDRV32_OP_LOAD; in_result = 32'd0;
        in_result_ready = 1'b1; in_mem_addr = 32'h8000_1000;
        in_mem_size = `BUS_SZ_WORD; in_mem_unsigned = 1'b0;
        in_store_data = 32'd0; in_mdu_token = 1'b0;
        in_csr_op = {`EDRV32_CSR_OP_W{1'b0}}; in_csr_addr = 12'd0;
        in_csr_src = 32'd0; in_fence = 1'b0; in_fencei = 1'b0;
        in_mret = 1'b0; in_wfi = 1'b0; in_exception_valid = 1'b0;
        in_exception_cause = {`EDRV32_EXC_CAUSE_W{1'b0}};
        in_exception_tval = 32'd0; out_accept = 1'b0; kill = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        #1;
        check_true(in_ready && !out_valid && !queue_full,
                   "Empty MEM1-to-MEM2 boundary accepts input");

        set_packet(32'h8000_0100, 5'd1, 32'h1111_1111);
        in_valid = 1'b1;
        @(posedge clk); #1;
        check_true(out_valid && out_pc == 32'h8000_0100 && out_rd == 5'd1 &&
                   out_result == 32'h1111_1111 && out_mem_cacheable,
                   "First packet occupies and classifies the head");

        set_packet(32'h8000_0104, 5'd2, 32'h2222_2222);
        @(posedge clk); #1;
        check_true(queue_full && !in_ready && out_pc == 32'h8000_0100,
                   "Second packet fills tail without replacing head");

        set_packet(32'h8000_0108, 5'd3, 32'h3333_3333);
        repeat (3) begin
            #1;
            check_true(!in_ready && out_pc == 32'h8000_0100 &&
                       out_result == 32'h1111_1111,
                       "Full elastic queue holds head under backpressure");
            @(posedge clk);
        end

        // r47 T2-b contract: at full capacity the upstream may push in the
        // same cycle the head pops.  The old head leaves, the promoted tail
        // payload becomes the new head, and the incoming packet lands in the
        // tail slot, keeping the occupancy at two.
        out_accept = 1'b1;
        #1;
        check_true(in_ready, "Full queue accepts input when the head pops");
        @(posedge clk); #1;
        check_true(queue_full && in_ready && out_pc == 32'h8000_0104 &&
                   out_rd == 5'd2 && out_result == 32'h2222_2222,
                   "Pop+push promotes tail payload exactly once");

        // A second pop+push pair must present the previously captured packet
        // as head and keep sustaining one packet per cycle.
        set_packet(32'h8000_010c, 5'd4, 32'h4444_4444);
        @(posedge clk); #1;
        check_true(out_valid && out_pc == 32'h8000_0108 && out_rd == 5'd3 &&
                   out_result == 32'h3333_3333 && queue_full,
                   "Pop+push preserves FIFO order under full occupancy");
        @(posedge clk); #1;
        check_true(out_valid && out_pc == 32'h8000_010c && out_rd == 5'd4 &&
                   out_result == 32'h4444_4444 && queue_full,
                   "Second pop+push delivers the tail-written packet");

        // Stop capturing while the downstream keeps popping: occupancy must
        // drain exactly one entry per pop without duplicating or dropping.
        in_valid = 1'b0;
        @(posedge clk); #1;
        check_true(!queue_full && in_ready && out_valid &&
                   out_pc == 32'h8000_010c,
                   "Full queue drains one entry per pop");
        @(posedge clk); #1;
        check_true(!queue_full && in_ready && !out_valid,
                   "Drained queue reports empty without residue");
        out_accept = 1'b0;

        kill = 1'b1;
        @(posedge clk); #1;
        kill = 1'b0;
        #1;
        check_true(!out_valid && in_ready, "Age-qualified kill clears both queue slots");

        $display("PASS: MEM1-to-MEM2 elastic flow with full-state pop+push (%0d checks)", checks);
        $finish;
    end
endmodule
