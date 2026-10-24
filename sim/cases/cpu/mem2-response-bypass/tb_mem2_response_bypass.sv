`timescale 1ns/1ps
`include "edrv32_uop.vh"
`include "edrv32_bus.vh"
`include "edrv32_exception.vh"
`include "edrv32_lsu.vh"

// The queued LSU owns Cache completion; MEM2 transports its token and keeps
// the registered COMMIT boundary at one packet per cycle.
module tb_mem2_response_bypass;
    reg clk;
    reg rst_n;
    reg valid;
    wire ready;
    reg kill;
    reg packet_ready;
    reg [31:0] pc;
    reg [4:0] rd;
    reg rd_write;
    reg [`EDRV32_OP_CLASS_W-1:0] op_class;
    reg [31:0] result;
    reg result_ready;
    reg lsu_token_valid;
    reg [`EDRV32_LSU_TOKEN_W-1:0] lsu_token;
    wire hazard_valid;
    wire hazard_ready;
    wire hazard_late_load;
    wire hazard_lsu_token_valid;
    wire [`EDRV32_LSU_TOKEN_W-1:0] hazard_lsu_token;
    wire packet_valid;
    wire [31:0] packet_pc;
    wire [4:0] packet_rd;
    wire [`EDRV32_OP_CLASS_W-1:0] packet_op_class;
    wire [31:0] packet_result;
    wire packet_result_ready;
    wire packet_lsu_token_valid;
    wire [`EDRV32_LSU_TOKEN_W-1:0] packet_lsu_token;
    integer checks;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    edrv32_mem2_stage dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .valid_i(valid), .ready_o(ready),
        .pc_i(pc), .instr_i(32'd0), .is_compressed_i(1'b0),
        .epoch_i({`EDRV32_EPOCH_W{1'b0}}),
        .rd_i(rd), .rd_write_i(rd_write), .op_class_i(op_class),
        .result_i(result), .result_ready_i(result_ready),
        .mem_addr_i(32'h8000_1000), .mem_size_i(`BUS_SZ_WORD),
        .mem_unsigned_i(1'b0), .store_data_i(32'd0),
        .mem_cacheable_i(1'b1), .mem_tcm_i(1'b0),
        .mem_mmio_i(1'b0), .lsu_token_valid_i(lsu_token_valid),
        .lsu_token_i(lsu_token), .mdu_token_i(1'b0),
        .csr_op_i({`EDRV32_CSR_OP_W{1'b0}}),
        .csr_addr_i(12'd0), .csr_src_i(32'd0),
        .fence_i(1'b0), .fencei_i(1'b0),
        .mret_i(1'b0), .wfi_i(1'b0),
        .exception_valid_i(1'b0),
        .exception_cause_i({`EDRV32_EXC_CAUSE_W{1'b0}}),
        .exception_tval_i(32'd0),
        .hazard_valid_o(hazard_valid), .hazard_write_o(),
        .hazard_ready_o(hazard_ready), .hazard_rd_o(),
        .hazard_value_o(), .hazard_pc_o(),
        .hazard_op_class_o(), .hazard_late_load_o(hazard_late_load),
        .hazard_lsu_token_valid_o(hazard_lsu_token_valid),
        .hazard_lsu_token_o(hazard_lsu_token),
        .packet_valid_o(packet_valid), .packet_ready_i(packet_ready),
        .packet_pc_o(packet_pc), .packet_instr_o(),
        .packet_is_compressed_o(), .packet_epoch_o(),
        .packet_rd_o(packet_rd), .packet_rd_write_o(),
        .packet_op_class_o(packet_op_class),
        .packet_result_o(packet_result),
        .packet_result_ready_o(packet_result_ready),
        .packet_mem_addr_o(), .packet_mem_size_o(),
        .packet_mem_unsigned_o(), .packet_store_data_o(),
        .packet_mem_cacheable_o(), .packet_mem_tcm_o(),
        .packet_mem_mmio_o(),
        .packet_lsu_token_valid_o(packet_lsu_token_valid),
        .packet_lsu_token_o(packet_lsu_token),
        .packet_mdu_token_o(), .packet_csr_op_o(),
        .packet_csr_addr_o(), .packet_csr_src_o(),
        .packet_fence_o(), .packet_fencei_o(),
        .packet_mret_o(), .packet_wfi_o(),
        .packet_exception_valid_o(),
        .packet_exception_cause_o(), .packet_exception_tval_o(),
        .kill_i(kill)
    );

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

    initial begin
        checks = 0;
        rst_n = 1'b0;
        valid = 1'b0;
        kill = 1'b0;
        packet_ready = 1'b1;
        pc = 32'h8000_0100;
        rd = 5'd5;
        rd_write = 1'b1;
        op_class = `EDRV32_OP_LOAD;
        result = 32'd0;
        result_ready = 1'b0;
        lsu_token_valid = 1'b1;
        lsu_token = 3'd5;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        valid = 1'b1;
        #1;
        check_true(ready, "queued Load enters MEM2");
        @(posedge clk); #1;
        check_true(hazard_valid && !hazard_ready && hazard_late_load &&
                   hazard_lsu_token_valid && hazard_lsu_token == 3'd5,
                   "MEM2 exposes the queued Load producer token");

        @(negedge clk);
        pc = 32'h8000_0104;
        rd = 5'd6;
        op_class = `EDRV32_OP_ALU;
        result = 32'd42;
        result_ready = 1'b1;
        lsu_token_valid = 1'b0;
        #1;
        check_true(ready, "next packet enters while Load transfers");
        @(posedge clk); #1;
        check_true(packet_valid && packet_pc == 32'h8000_0100 &&
                   packet_op_class == `EDRV32_OP_LOAD &&
                   packet_lsu_token_valid && packet_lsu_token == 3'd5 &&
                   !packet_result_ready,
                   "Load token reaches COMMIT without fabricated data");

        @(negedge clk);
        valid = 1'b0;
        @(posedge clk); #1;
        check_true(packet_valid && packet_pc == 32'h8000_0104 &&
                   packet_rd == 5'd6 && packet_result == 32'd42 &&
                   packet_result_ready && !packet_lsu_token_valid,
                   "ALU packet follows on the next cycle");
        @(posedge clk); #1;
        check_true(!packet_valid, "pipeline drains exactly once");

        @(negedge clk);
        packet_ready = 1'b0;
        valid = 1'b1;
        pc = 32'h8000_0108;
        @(posedge clk); #1;
        valid = 1'b0;
        kill = 1'b1;
        @(posedge clk); #1;
        check_true(!packet_valid && !hazard_valid,
                   "kill removes the speculative resident packet");

        $display("PASS: MEM2 queued-token boundary (%0d checks)", checks);
        $finish;
    end
endmodule
