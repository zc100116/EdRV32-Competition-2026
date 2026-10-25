`timescale 1ns/1ps
`include "edrv32_bus.vh"

module tb_core_smoke #(parameter FRONTEND_DUAL_WINDOW=0);
    localparam [31:0] RESET_PC = 32'h8000_0000;
    localparam [31:0] DATA_ADDR = 32'h8000_0100;
    localparam [31:0] TOHOST_ADDR = 32'h8000_0104;
    localparam [31:0] LINK_ADDR = 32'h8000_0108;

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
    integer retires;
    integer load_retire_cycle;
    integer load_consumer_retire_cycle;

    function automatic [31:0] enc_i;
        input [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin enc_i = {imm, rs1, funct3, rd, opcode}; end
    endfunction

    function automatic [31:0] enc_r;
        input [6:0] funct7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin enc_r = {funct7, rs2, rs1, funct3, rd, opcode}; end
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

    initial clk = 1'b0;
    always #5 clk = ~clk;

`ifdef EDRV32_CACHED_TEST
    edrv32_cached_core_native_harness #(
        .RESET_PC(RESET_PC), .ICACHE_LINE_COUNT(16), .DCACHE_LINE_COUNT(16)
    ) u_core (
        .clk_i(clk), .rst_n_i(rst_n),
        .imem_req_valid_o(imem_req_valid), .imem_req_ready_i(imem_req_ready),
        .imem_req_addr_o(imem_req_addr), .imem_resp_valid_i(imem_resp_valid),
        .imem_resp_ready_o(imem_resp_ready), .imem_resp_rdata_i(imem_resp_rdata),
        .imem_resp_error_i(imem_resp_error),
        .dmem_req_valid_o(dmem_req_valid), .dmem_req_ready_i(dmem_req_ready),
        .dmem_req_addr_o(dmem_req_addr), .dmem_req_we_o(dmem_req_we),
        .dmem_req_size_o(dmem_req_size), .dmem_req_wstrb_o(dmem_req_wstrb),
        .dmem_req_wdata_o(dmem_req_wdata), .dmem_resp_valid_i(dmem_resp_valid),
        .dmem_resp_ready_o(dmem_resp_ready), .dmem_resp_rdata_i(dmem_resp_rdata),
        .dmem_resp_error_i(dmem_resp_error),
        .itcm_req_valid_o(), .itcm_req_ready_i(1'b0), .itcm_req_addr_o(),
        .itcm_resp_valid_i(1'b0), .itcm_resp_ready_o(),
        .itcm_resp_rdata_i(32'd0), .itcm_resp_error_i(1'b0),
        .dtcm_req_valid_o(), .dtcm_req_ready_i(1'b0), .dtcm_req_addr_o(),
        .dtcm_req_we_o(), .dtcm_req_size_o(), .dtcm_req_wstrb_o(),
        .dtcm_req_wdata_o(), .dtcm_resp_valid_i(1'b0),
        .dtcm_resp_ready_o(), .dtcm_resp_rdata_i(32'd0),
        .dtcm_resp_error_i(1'b0),
        .irq_soft_i(1'b0), .irq_timer_i(1'b0), .irq_ext_i(1'b0),
        .time_value_i(64'd0),
        .retire_o(retire), .retire_pc_o(retire_pc), .retire_instr_o(retire_instr),
        .retire_exception_o(retire_exception), .retire_cause_o(retire_cause),
        .debug_decode_instr_o(), .debug_decode_pc_o(), .core_sleep_o()
    );
`else
    edrv32_core #(.RESET_PC(RESET_PC), .FRONTEND_DUAL_WINDOW(FRONTEND_DUAL_WINDOW)) u_core (
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
`endif

    edrv32_mem_model #(
        .MEM_DEPTH_WORDS(1024), .BASE_ADDR(RESET_PC),
        .IMEM_LAT(1), .DMEM_LAT(2)
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
        retires = 0;
        load_retire_cycle = -1;
        load_consumer_retire_cycle = -1;
        u_mem.mem[0]  = enc_i(12'd5, 5'd0, 3'b000, 5'd1, 7'h13); // x1=5
        u_mem.mem[1]  = enc_i(12'd7, 5'd1, 3'b000, 5'd2, 7'h13); // x2=12
        u_mem.mem[2]  = enc_r(7'd0, 5'd2, 5'd1, 3'b000, 5'd3, 7'h33); // x3=17
        u_mem.mem[3]  = 32'h8000_0237; // lui x4,0x80000
        u_mem.mem[4]  = enc_s(12'h100, 5'd3, 5'd4, 3'b010); // sw x3,0x100(x4)
        u_mem.mem[5]  = enc_i(12'h100, 5'd4, 3'b010, 5'd5, 7'h03); // lw x5
        u_mem.mem[6]  = enc_i(12'd1, 5'd5, 3'b000, 5'd6, 7'h13); // x6=18
        u_mem.mem[7]  = enc_j(21'd8, 5'd8); // jal x8,+8; link=0x80000020
        u_mem.mem[8]  = enc_i(12'd3, 5'd0, 3'b000, 5'd7, 7'h13); // killed
        u_mem.mem[9]  = enc_i(12'd1, 5'd0, 3'b000, 5'd7, 7'h13); // x7=1
        u_mem.mem[10] = enc_s(12'h108, 5'd8, 5'd4, 3'b010); // preserve JAL link
        u_mem.mem[11] = enc_s(12'h104, 5'd7, 5'd4, 3'b010); // tohost=1
        u_mem.mem[12] = enc_j(21'd0, 5'd0); // loop

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;
            if (retire) retires <= retires + 1;
            if (retire && (retire_pc == RESET_PC + 32'h0000_0014))
                load_retire_cycle <= cycles;
            if (retire && (retire_pc == RESET_PC + 32'h0000_0018))
                load_consumer_retire_cycle <= cycles;
            if (retire_exception) begin
                $fatal(1, "unexpected exception pc=%08x cause=%08x", retire_pc, retire_cause);
            end
`ifdef EDRV32_CACHED_TEST
            // A write-back cache retires this cacheable store after updating
            // its resident line and dirty state; no fabric write is required
            // until eviction or an explicit clean operation.
            if (retire && (retire_pc == RESET_PC + 32'h0000_002c)) begin
                if (u_core.u_cached_core.u_core.u_decode_stage.u_regfile.regs_r[6]
                    !== 32'd18)
                    $fatal(1, "cached load RAW consumer used stale x6=%08x",
                           u_core.u_cached_core.u_core.u_decode_stage.u_regfile.regs_r[6]);
                if (u_core.u_cached_core.u_core.u_decode_stage.u_regfile.regs_r[7]
                    !== 32'd1)
                    $fatal(1, "cached tohost store source is wrong x7=%08x",
                           u_core.u_cached_core.u_core.u_decode_stage.u_regfile.regs_r[7]);
                if (u_core.u_cached_core.u_core.u_decode_stage.u_regfile.regs_r[8] !==
                    32'h8000_0020)
                    $fatal(1, "cached redirect corrupted JAL link x8=%08x",
                           u_core.u_cached_core.u_core.u_decode_stage.u_regfile.regs_r[8]);
                if ((load_retire_cycle < 0) ||
                    (load_consumer_retire_cycle < 0))
                    $fatal(1, "cached load-use retirement markers missing");
                // The AXI-to-native test harness serializes the two 32-bit
                // words that form each 64-bit beat, so its absolute refill
                // latency is not a CPU performance contract. Keep the useful
                // architectural check: the dependent instruction must retire
                // within the bounded load-use recovery window.
                if ((load_consumer_retire_cycle - load_retire_cycle) > 4)
                    $fatal(1, "cached load-use retirement gap regressed to %0d",
                           load_consumer_retire_cycle - load_retire_cycle);
                $display("PASS: eight-stage cached core smoke cycles=%0d retires=%0d",
                         cycles, retires);
                $display("PASS: cached load/consumer retire cycles=%0d/%0d gap=%0d",
                         load_retire_cycle, load_consumer_retire_cycle,
                         load_consumer_retire_cycle - load_retire_cycle);
                $finish;
            end
`else
            if (dmem_req_valid && dmem_req_ready && dmem_req_we &&
                (dmem_req_addr == TOHOST_ADDR)) begin
                if (dmem_req_wdata != 32'd1 || dmem_req_wstrb != 4'b1111)
                    $fatal(1, "bad tohost write data=%08x strb=%x", dmem_req_wdata,
                           dmem_req_wstrb);
                if (u_mem.mem[64] != 32'd17)
                    $fatal(1, "store/load path corrupted data word=%08x", u_mem.mem[64]);
                if (u_mem.mem[66] != 32'h8000_0020)
                    $fatal(1, "redirect killed/corrupted JAL link=%08x", u_mem.mem[66]);
                if (u_core.u_decode_stage.u_regfile.regs_r[6] !== 32'd18)
                    $fatal(1, "load RAW consumer used stale x6=%08x",
                           u_core.u_decode_stage.u_regfile.regs_r[6]);
                $display("PASS: eight-stage core smoke cycles=%0d retires=%0d", cycles, retires);
                $finish;
            end
`endif
            if (cycles > 600) begin
                $fatal(1, "core smoke timeout retires=%0d last_pc=%08x instr=%08x",
                       retires, retire_pc, retire_instr);
            end
        end
    end

endmodule
