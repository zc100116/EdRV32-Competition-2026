`timescale 1ns/1ps
`include "edrv32_bus.vh"
`include "edrv32_csr.vh"

module tb_core_pma_trap;
    localparam [31:0] RESET_PC = 32'h8000_0000;
    localparam [31:0] TOHOST_ADDR = 32'h8000_0104;
    reg clk;
    reg rst_n;
    wire imem_req_valid, imem_req_ready;
    wire [31:0] imem_req_addr;
    wire imem_resp_valid, imem_resp_ready;
    wire [31:0] imem_resp_rdata;
    wire imem_resp_error;
    wire dmem_req_valid, dmem_req_ready;
    wire [31:0] dmem_req_addr;
    wire dmem_req_we;
    wire [`BUS_SZ_W-1:0] dmem_req_size;
    wire [3:0] dmem_req_wstrb;
    wire [31:0] dmem_req_wdata;
    wire dmem_resp_valid, dmem_resp_ready;
    wire [31:0] dmem_resp_rdata;
    wire dmem_resp_error;
    wire retire;
    wire [31:0] retire_pc;
    wire [31:0] retire_instr;
    wire retire_exception;
    wire [31:0] retire_cause;
    integer cycles;
    integer trap_count;
    integer unexpected_dmem_requests;

    function automatic [31:0] enc_i;
        input [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin enc_i = {imm, rs1, funct3, rd, opcode}; end
    endfunction

    function automatic [31:0] enc_s;
        input [11:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'h23}; end
    endfunction

    function automatic [31:0] enc_csr;
        input [11:0] csr;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        begin enc_csr = {csr, rs1, funct3, rd, 7'h73}; end
    endfunction

    initial clk = 1'b0;
    always #5 clk = ~clk;

    edrv32_core #(
        .RESET_PC(RESET_PC), .TCM_ENABLE(0)
    ) u_core (
        .clk_i(clk), .rst_n_i(rst_n),
        .imem_req_valid_o(imem_req_valid), .imem_req_ready_i(imem_req_ready),
        .imem_req_addr_o(imem_req_addr), .imem_resp_valid_i(imem_resp_valid),
        .imem_resp_ready_o(imem_resp_ready), .imem_resp_rdata_i(imem_resp_rdata),
        .imem_resp_error_i(imem_resp_error),
        .dmem_req_valid_o(dmem_req_valid), .dmem_req_ready_i(dmem_req_ready),
        .dmem_req_addr_o(dmem_req_addr), .dmem_req_we_o(dmem_req_we),
        .dmem_req_size_o(dmem_req_size), .dmem_req_wstrb_o(dmem_req_wstrb),
        .dmem_req_wdata_o(dmem_req_wdata), .dmem_req_cacheable_o(),
        .dmem_resp_valid_i(dmem_resp_valid),
        .dmem_resp_ready_o(dmem_resp_ready), .dmem_resp_rdata_i(dmem_resp_rdata),
        .dmem_resp_error_i(dmem_resp_error),
        .dcache_lookup_valid_o(), .dcache_lookup_ready_i(1'b0),
        .dcache_lookup_addr_o(), .dcache_lookup_token_o(),
        .dcache_lookup_store_o(), .dcache_lookup_size_o(),
        .dcache_lookup_unsigned_o(),
        .dcache_lookup_resp_valid_i(1'b0), .dcache_lookup_resp_ready_o(),
        .dcache_lookup_resp_data_i(32'd0), .dcache_lookup_resp_error_i(1'b0),
        .dcache_lookup_resp_token_i(3'd0),
        .dcache_lookup_resp_store_i(1'b0),
        .dcache_lookup_fast_valid_i(1'b0),
        .dcache_lookup_fast_ready_o(), .dcache_lookup_fast_token_i(3'd0),
        .dcache_lookup_fast_store_i(1'b0),
        .dcache_lookup_fast_data_i(32'd0),
        .dcache_lookup_cancel_o(), .dcache_reservation_keep_count_o(),
        .cache_perf_events_i(5'd0),
        .irq_soft_i(1'b0), .irq_timer_i(1'b0), .irq_ext_i(1'b0),
        .time_value_i(64'd0),
        .retire_o(retire), .retire_pc_o(retire_pc),
        .retire_instr_o(retire_instr), .retire_exception_o(retire_exception),
        .retire_cause_o(retire_cause), .fence_retire_o(),
        .fencei_retire_o(), .core_sleep_o(),
        .debug_decode_pc_o(), .debug_decode_instr_o()
    );

    edrv32_mem_model #(
        .MEM_DEPTH_WORDS(1024), .BASE_ADDR(RESET_PC), .IMEM_LAT(1), .DMEM_LAT(1)
    ) u_mem (
        .clk(clk), .rst_n(rst_n),
        .imem_req_valid_i(imem_req_valid), .imem_req_ready_o(imem_req_ready),
        .imem_req_addr_i(imem_req_addr), .imem_resp_valid_o(imem_resp_valid),
        .imem_resp_ready_i(imem_resp_ready), .imem_resp_rdata_o(imem_resp_rdata),
        .imem_resp_error_o(imem_resp_error),
        .dmem_req_valid_i(dmem_req_valid), .dmem_req_ready_o(dmem_req_ready),
        .dmem_req_addr_i(dmem_req_addr), .dmem_req_we_i(dmem_req_we),
        .dmem_req_size_i(dmem_req_size), .dmem_req_wstrb_i(dmem_req_wstrb),
        .dmem_req_wdata_i(dmem_req_wdata), .dmem_resp_valid_o(dmem_resp_valid),
        .dmem_resp_ready_i(dmem_resp_ready), .dmem_resp_rdata_o(dmem_resp_rdata),
        .dmem_resp_error_o(dmem_resp_error),
        .imem_req_stall_i(1'b0), .dmem_req_stall_i(1'b0)
    );

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        trap_count = 0;
        unexpected_dmem_requests = 0;

        u_mem.mem[0] = 32'h8000_0237; // lui x4,0x80000
        u_mem.mem[1] = enc_i(12'h100, 5'd4, 3'b000, 5'd1, 7'h13);
        u_mem.mem[2] = enc_csr(`EDRV32_CSR_MTVEC, 5'd1, 3'b001, 5'd0);
        u_mem.mem[3] = enc_i(12'h055, 5'd0, 3'b000, 5'd3, 7'h13);
        u_mem.mem[4] = enc_s(12'd0, 5'd3, 5'd0, 3'b010); // ROM store fault
        u_mem.mem[5] = 32'h5000_02b7;                    // lui x5,0x50000
        u_mem.mem[6] = enc_i(12'd0, 5'd5, 3'b010, 5'd6, 7'h03); // hole load
        u_mem.mem[7] = 32'h0200_02b7;                    // lui x5,0x02000
        u_mem.mem[8] = enc_s(12'd0, 5'd3, 5'd5, 3'b010); // disabled DTCM store
        u_mem.mem[9] = 32'h0100_02b7;                    // lui x5,0x01000
        u_mem.mem[10] = enc_i(12'd0, 5'd5, 3'b010, 5'd6, 7'h03); // ITCM data load
        u_mem.mem[11] = enc_i(12'd1, 5'd0, 3'b000, 5'd7, 7'h13);
        u_mem.mem[12] = enc_s(12'h104, 5'd7, 5'd4, 3'b010); // PASS
        u_mem.mem[13] = 32'h0000_006f;

        // Common precise-trap handler: advance mepc past the faulting memory op.
        u_mem.mem[64] = enc_csr(`EDRV32_CSR_MEPC, 5'd0, 3'b010, 5'd9);
        u_mem.mem[65] = enc_i(12'd4, 5'd9, 3'b000, 5'd9, 7'h13);
        u_mem.mem[66] = enc_csr(`EDRV32_CSR_MEPC, 5'd9, 3'b001, 5'd0);
        u_mem.mem[67] = 32'h3020_0073; // mret

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;
            if (retire_exception) begin
                case (trap_count)
                    0: if ((retire_pc != RESET_PC + 32'd16) ||
                           (retire_cause != 32'd7))
                        $fatal(1, "ROM store trap mismatch pc=%08x cause=%0d",
                               retire_pc, retire_cause);
                    1: if ((retire_pc != RESET_PC + 32'd24) ||
                           (retire_cause != 32'd5))
                        $fatal(1, "hole load trap mismatch pc=%08x cause=%0d",
                               retire_pc, retire_cause);
                    2: if ((retire_pc != RESET_PC + 32'd32) ||
                           (retire_cause != 32'd7))
                        $fatal(1, "DTCM store trap mismatch pc=%08x cause=%0d",
                               retire_pc, retire_cause);
                    3: if ((retire_pc != RESET_PC + 32'd40) ||
                           (retire_cause != 32'd5))
                        $fatal(1, "ITCM load trap mismatch pc=%08x cause=%0d",
                               retire_pc, retire_cause);
                    default: $fatal(1, "unexpected extra PMA trap");
                endcase
                trap_count <= trap_count + 1;
            end

            if (dmem_req_valid && dmem_req_ready) begin
                if (dmem_req_addr == TOHOST_ADDR) begin
                    if (!dmem_req_we || (dmem_req_wdata != 32'd1) ||
                        (trap_count != 4) || (unexpected_dmem_requests != 0))
                        $fatal(1, "PMA integration failed traps=%0d bad_req=%0d data=%08x",
                               trap_count, unexpected_dmem_requests, dmem_req_wdata);
                    $display("PASS: core PMA precise faults/no-request cycles=%0d", cycles);
                    $finish;
                end else begin
                    unexpected_dmem_requests <= unexpected_dmem_requests + 1;
                    $fatal(1, "PMA fault leaked dmem request addr=%08x we=%b",
                           dmem_req_addr, dmem_req_we);
                end
            end
            if (cycles > 1500)
                $fatal(1, "PMA integration timeout pc=%08x traps=%0d",
                       retire_pc, trap_count);
        end
    end
endmodule
