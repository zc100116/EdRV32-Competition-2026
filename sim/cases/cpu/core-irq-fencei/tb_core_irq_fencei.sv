`timescale 1ns/1ps
`include "edrv32_bus.vh"
`include "edrv32_csr.vh"
`include "edrv32_pair.vh"

module tb_core_irq_fencei #(parameter FRONTEND_DUAL_WINDOW=0, parameter DUAL_ISSUE=0, parameter PAIR_IRQ=0);
    localparam [31:0] RESET_PC = 32'h8000_0000;
    localparam [31:0] TOHOST_ADDR = 32'h8000_0104;
    reg clk;
    reg rst_n;
    reg irq_ext;
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
    wire trap;
    wire [31:0] trap_cause;
    integer cycles;
    reg pair_irq_sent=0;
    integer pair_traps=0,pair_replays=0;
    integer trap_count;
    integer fencei_retire_count;
    reg [31:0] interrupted_pc;
    reg interrupted_pc_replayed;

    function automatic [31:0] enc_i;
        input [11:0] imm; input [4:0] rs1; input [2:0] funct3;
        input [4:0] rd; input [6:0] opcode;
        begin enc_i = {imm, rs1, funct3, rd, opcode}; end
    endfunction
    function automatic [31:0] enc_s;
        input [11:0] imm; input [4:0] rs2; input [4:0] rs1; input [2:0] funct3;
        begin enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'h23}; end
    endfunction
    function automatic [31:0] enc_j;
        input [20:0] imm; input [4:0] rd;
        begin enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'h6f}; end
    endfunction
    function automatic [31:0] enc_csr;
        input [11:0] csr; input [4:0] rs1; input [2:0] funct3; input [4:0] rd;
        begin enc_csr = {csr, rs1, funct3, rd, 7'h73}; end
    endfunction

    initial clk = 1'b0;
    always #5 clk = ~clk;

    edrv32_core #(.RESET_PC(RESET_PC), .FRONTEND_DUAL_WINDOW(FRONTEND_DUAL_WINDOW), .DUAL_ISSUE(DUAL_ISSUE)) u_core (
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
        .irq_soft_i(1'b0), .irq_timer_i(1'b0), .irq_ext_i(irq_ext),
        .time_value_i(64'd0),
        .retire_o(retire), .retire_pc_o(retire_pc), .retire_instr_o(retire_instr),
        .retire_exception_o(trap), .retire_cause_o(trap_cause),
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
        irq_ext = 1'b0;
        cycles = 0;
        trap_count = 0;
        fencei_retire_count = 0;
        interrupted_pc = 32'd0;
        interrupted_pc_replayed = 1'b0;
        u_mem.mem[0] = 32'h8000_0237; // lui x4,0x80000
        u_mem.mem[1] = enc_i(12'h080, 5'd4, 3'b000, 5'd1, 7'h13);
        u_mem.mem[2] = enc_i(12'd1, 5'd1, 3'b000, 5'd1, 7'h13); // vectored mode
        u_mem.mem[3] = enc_csr(`EDRV32_CSR_MTVEC, 5'd1, 3'b001, 5'd0);
        u_mem.mem[4] = 32'h0000_1137; // lui x2,0x1
        u_mem.mem[5] = enc_i(12'h800, 5'd2, 3'b000, 5'd2, 7'h13); // x2=0x800
        u_mem.mem[6] = enc_csr(`EDRV32_CSR_MIE, 5'd2, 3'b001, 5'd0);
        u_mem.mem[7] = enc_i(12'd8, 5'd0, 3'b000, 5'd2, 7'h13);
        u_mem.mem[8] = enc_csr(`EDRV32_CSR_MSTATUS, 5'd2, 3'b001, 5'd0);
        u_mem.mem[9] = enc_i(12'd6, 5'd0, 3'b000, 5'd6, 7'h13);
        if(PAIR_IRQ!=0)u_mem.mem[9]={16'h4385,16'h4319}; // c.li x6,6; c.li x7,1
        u_mem.mem[10] = enc_i(12'd1, 5'd0, 3'b000, 5'd7, 7'h13);
        u_mem.mem[11] = 32'h0000_100f; // fence.i
        u_mem.mem[12] = enc_s(12'h104, 5'd7, 5'd4, 3'b010);
        u_mem.mem[13] = enc_j(21'd0, 5'd0);

        // mtvec base 0x80, machine external interrupt vector = base + 4*11.
        u_mem.mem[43] = enc_csr(`EDRV32_CSR_MCAUSE, 5'd0, 3'b010, 5'd8);
        u_mem.mem[44] = enc_s(12'h108, 5'd8, 5'd4, 3'b010);
        u_mem.mem[45] = enc_csr(`EDRV32_CSR_MEPC, 5'd0, 3'b010, 5'd9);
        u_mem.mem[46] = enc_s(12'h10c, 5'd9, 5'd4, 3'b010);
        u_mem.mem[47] = 32'h3020_0073;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;
            if (PAIR_IRQ==0 && retire && (retire_instr == enc_csr(`EDRV32_CSR_MSTATUS,
                                                   5'd2, 3'b001, 5'd0)))
                irq_ext <= 1'b1;
            if(PAIR_IRQ!=0 && !pair_irq_sent && u_core.decode_valid_w &&
                u_core.decode_pc_w==RESET_PC+36 && u_core.decode_second_w[`EDRV32_PAIR_DECODE_W-1])begin
                irq_ext<=1;pair_irq_sent<=1;
            end
            if(u_core.second_retire_o && u_core.retire_pc_o==RESET_PC+36 && trap_count!=0)
                pair_replays<=pair_replays+1;
            if (trap) begin
                if(PAIR_IRQ!=0 && u_core.commit_second_w[`EDRV32_PAIR_RESULT_W-1])begin
                    pair_traps<=pair_traps+1;
                    if(u_core.commit_gpr_write_w||u_core.commit_second_write_w||u_core.retire_count_o!=0)
                        $fatal(1,"interrupted pair wrote architectural state");
                end
                trap_count <= trap_count + 1;
                interrupted_pc <= retire_pc;
                irq_ext <= 1'b0;
                if (trap_cause != `EDRV32_CAUSE_INT_M_EXT)
                    $fatal(1, "wrong interrupt cause=%08x", trap_cause);
            end
            if (retire && (retire_pc == interrupted_pc) && (trap_count != 0))
                interrupted_pc_replayed <= 1'b1;
            if (retire && (retire_instr == 32'h0000_100f))
                fencei_retire_count <= fencei_retire_count + 1;

            if (dmem_req_valid && dmem_req_ready && dmem_req_we &&
                (dmem_req_addr == TOHOST_ADDR)) begin
                if (dmem_req_wdata != 32'd1 || trap_count != 1)
                    $fatal(1, "IRQ/fencei result data=%08x traps=%0d",
                           dmem_req_wdata, trap_count);
                if (u_mem.mem[66] != `EDRV32_CAUSE_INT_M_EXT)
                    $fatal(1, "handler saw wrong mcause=%08x", u_mem.mem[66]);
                if (u_mem.mem[67] != interrupted_pc || !interrupted_pc_replayed)
                    $fatal(1, "mepc/replay mismatch saved=%08x trap_pc=%08x replay=%b",
                           u_mem.mem[67], interrupted_pc, interrupted_pc_replayed);
                if (fencei_retire_count != 1)
                    $fatal(1, "fence.i retirement count=%0d", fencei_retire_count);
                if(PAIR_IRQ!=0 && (!pair_irq_sent || pair_traps!=1 || pair_replays!=1 || interrupted_pc!=RESET_PC+36))
                    $fatal(1,"paired interrupt not exercised sent=%0d traps=%0d replays=%0d pc=%08x",pair_irq_sent,pair_traps,pair_replays,interrupted_pc);
                $display("PASS: core IRQ/vectored-mtvec/fence.i cycles=%0d", cycles);
                $finish;
            end
            if (cycles > 1400)
                $fatal(1, "IRQ/fencei timeout pc=%08x instr=%08x traps=%0d",
                       retire_pc, retire_instr, trap_count);
        end
    end
endmodule
