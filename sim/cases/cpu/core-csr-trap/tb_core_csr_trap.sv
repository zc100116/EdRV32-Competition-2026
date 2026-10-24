`timescale 1ns/1ps
`include "edrv32_bus.vh"
`include "edrv32_csr.vh"
`include "edrv32_uop.vh"

module tb_core_csr_trap #(parameter FRONTEND_DUAL_WINDOW=0, parameter DUAL_ISSUE=0);
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
    integer csr_validation_cycles;

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

    function automatic [31:0] enc_b;
        input [12:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin
            enc_b = {imm[12], imm[10:5], rs2, rs1, funct3,
                     imm[4:1], imm[11], 7'h63};
        end
    endfunction

    function automatic [31:0] enc_j;
        input [20:0] imm;
        input [4:0] rd;
        begin enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'h6f}; end
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
        .RESET_PC(RESET_PC), .FRONTEND_DUAL_WINDOW(FRONTEND_DUAL_WINDOW), .DUAL_ISSUE(DUAL_ISSUE),
        .MVENDORID(32'h0000_0011),
        .MARCHID  (32'h0000_0022),
        .MIMPID   (32'h0000_0033),
        .MHARTID  (32'h0000_0044)
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
        .dcache_lookup_addr_o(), .dcache_lookup_store_o(),
        .dcache_lookup_resp_valid_i(1'b0), .dcache_lookup_resp_ready_o(),
        .dcache_lookup_resp_data_i(32'd0), .dcache_lookup_resp_error_i(1'b0),
        .dcache_lookup_cancel_o(),
        .cache_perf_events_i(5'd0),
        .irq_soft_i(1'b0), .irq_timer_i(1'b0), .irq_ext_i(1'b0),
        .time_value_i(64'd0),
        .retire_o(retire), .retire_pc_o(retire_pc), .retire_instr_o(retire_instr),
        .retire_exception_o(retire_exception), .retire_cause_o(retire_cause),
        .fencei_retire_o()
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
        csr_validation_cycles = 0;
        u_mem.mem[0] = 32'h8000_0237; // lui x4,0x80000
        u_mem.mem[1] = enc_i(12'h080, 5'd4, 3'b000, 5'd1, 7'h13);
        u_mem.mem[2] = enc_csr(`EDRV32_CSR_MTVEC, 5'd1, 3'b001, 5'd0);
        u_mem.mem[3] = enc_i(12'h123, 5'd0, 3'b000, 5'd2, 7'h13);
        u_mem.mem[4] = enc_csr(`EDRV32_CSR_MSCRATCH, 5'd2, 3'b001, 5'd3);
        u_mem.mem[5] = enc_csr(`EDRV32_CSR_MSCRATCH, 5'd0, 3'b010, 5'd5);
        u_mem.mem[6] = enc_b(13'd72, 5'd2, 5'd5, 3'b001); // bne -> fail
        // Existing SoC identity parameters must reach the COMMIT-owned CSR file.
        u_mem.mem[7] = enc_i(12'h011, 5'd0, 3'b000, 5'd11, 7'h13);
        u_mem.mem[8] = enc_csr(`EDRV32_CSR_MVENDORID, 5'd0, 3'b010, 5'd12);
        u_mem.mem[9] = enc_b(13'd60, 5'd11, 5'd12, 3'b001); // bne -> fail
        u_mem.mem[10] = enc_i(12'h022, 5'd0, 3'b000, 5'd11, 7'h13);
        u_mem.mem[11] = enc_csr(`EDRV32_CSR_MARCHID, 5'd0, 3'b010, 5'd12);
        u_mem.mem[12] = enc_b(13'd48, 5'd11, 5'd12, 3'b001); // bne -> fail
        u_mem.mem[13] = enc_i(12'h033, 5'd0, 3'b000, 5'd11, 7'h13);
        u_mem.mem[14] = enc_csr(`EDRV32_CSR_MIMPID, 5'd0, 3'b010, 5'd12);
        u_mem.mem[15] = enc_b(13'd36, 5'd11, 5'd12, 3'b001); // bne -> fail
        u_mem.mem[16] = enc_i(12'h044, 5'd0, 3'b000, 5'd11, 7'h13);
        u_mem.mem[17] = enc_csr(`EDRV32_CSR_MHARTID, 5'd0, 3'b010, 5'd12);
        u_mem.mem[18] = enc_b(13'd24, 5'd11, 5'd12, 3'b001); // bne -> fail
        u_mem.mem[19] = 32'h0000_0073; // ecall
        u_mem.mem[20] = enc_i(12'd1, 5'd0, 3'b000, 5'd7, 7'h13);
        u_mem.mem[21] = enc_s(12'h104, 5'd7, 5'd4, 3'b010);
        u_mem.mem[22] = enc_j(21'd0, 5'd0);

        u_mem.mem[24] = enc_i(12'd3, 5'd0, 3'b000, 5'd7, 7'h13); // fail
        u_mem.mem[25] = enc_s(12'h104, 5'd7, 5'd4, 3'b010);
        u_mem.mem[26] = enc_j(21'd0, 5'd0);

        u_mem.mem[32] = enc_csr(`EDRV32_CSR_MCAUSE, 5'd0, 3'b010, 5'd8);
        u_mem.mem[33] = enc_i(12'd11, 5'd0, 3'b000, 5'd9, 7'h13);
        u_mem.mem[34] = enc_b(13'h1fd8, 5'd9, 5'd8, 3'b001); // -40 -> fail
        u_mem.mem[35] = enc_csr(`EDRV32_CSR_MEPC, 5'd0, 3'b010, 5'd10);
        u_mem.mem[36] = enc_i(12'd4, 5'd10, 3'b000, 5'd10, 7'h13);
        u_mem.mem[37] = enc_csr(`EDRV32_CSR_MEPC, 5'd10, 3'b001, 5'd0);
        u_mem.mem[38] = 32'h3020_0073; // mret

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;
            if (u_core.mem2_packet_valid_w &&
                (u_core.mem2_packet_op_class_w == `EDRV32_OP_CSR) &&
                !u_core.u_commit_stage.csr_snapshot_valid_r) begin
                csr_validation_cycles <= csr_validation_cycles + 1;
                if (u_core.mem2_packet_accept_w)
                    $fatal(1, "CSR escaped COMMIT before registered validation");
            end
            if (retire &&
                (u_core.mem2_packet_op_class_w == `EDRV32_OP_CSR) &&
                !u_core.u_commit_stage.csr_snapshot_valid_r)
                $fatal(1, "CSR retired without a registered snapshot");
            if (retire_exception) begin
                trap_count <= trap_count + 1;
                if (retire_cause != 32'd11)
                    $fatal(1, "wrong trap cause pc=%08x cause=%08x", retire_pc, retire_cause);
            end
            if (dmem_req_valid && dmem_req_ready && dmem_req_we &&
                (dmem_req_addr == TOHOST_ADDR)) begin
                if (dmem_req_wdata != 32'd1)
                    $fatal(1, "CSR/trap program failed tohost=%08x", dmem_req_wdata);
                if (trap_count != 1)
                    $fatal(1, "expected one precise trap, got %0d", trap_count);
                if (csr_validation_cycles < 8)
                    $fatal(1, "CSR validation stage was not exercised");
                $display("PASS: core CSR/trap/mret cycles=%0d", cycles);
                $finish;
            end
            if (cycles > 1000)
                $fatal(1, "CSR/trap timeout pc=%08x instr=%08x traps=%0d",
                       retire_pc, retire_instr, trap_count);
        end
    end
endmodule
