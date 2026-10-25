`timescale 1ns/1ps
`include "edrv32_bus.vh"
`include "edrv32_hpm.vh"

module tb_core_mdu;
    localparam [31:0] RESET_PC = 32'h8000_0000;
    localparam [31:0] DATA_ADDR = 32'h8000_0100;
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
    wire trap;
    wire [31:0] trap_cause;
    integer cycles;
    integer divide_retire_cycle;
    integer independent_store_cycle;
    integer qualified_mdu_raw_cycles;
    integer completed_mdu_bypass_cycles;

    function automatic [31:0] enc_i;
        input [11:0] imm; input [4:0] rs1; input [2:0] funct3;
        input [4:0] rd; input [6:0] opcode;
        begin enc_i = {imm, rs1, funct3, rd, opcode}; end
    endfunction
    function automatic [31:0] enc_r;
        input [6:0] funct7; input [4:0] rs2; input [4:0] rs1;
        input [2:0] funct3; input [4:0] rd;
        begin enc_r = {funct7, rs2, rs1, funct3, rd, 7'h33}; end
    endfunction
    function automatic [31:0] enc_s;
        input [11:0] imm; input [4:0] rs2; input [4:0] rs1; input [2:0] funct3;
        begin enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'h23}; end
    endfunction
    function automatic [31:0] enc_b;
        input [12:0] imm; input [4:0] rs2; input [4:0] rs1; input [2:0] funct3;
        begin enc_b = {imm[12], imm[10:5], rs2, rs1, funct3,
                       imm[4:1], imm[11], 7'h63}; end
    endfunction
    function automatic [31:0] enc_j;
        input [20:0] imm; input [4:0] rd;
        begin enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'h6f}; end
    endfunction

    initial clk = 1'b0;
    always #5 clk = ~clk;

    edrv32_core #(.RESET_PC(RESET_PC)) u_core (
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
        .retire_exception_o(trap), .retire_cause_o(trap_cause),
        .fencei_retire_o()
    );

    edrv32_mem_model #(.MEM_DEPTH_WORDS(1024), .BASE_ADDR(RESET_PC),
                       .IMEM_LAT(1), .DMEM_LAT(1)) u_mem (
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
        divide_retire_cycle = -1;
        independent_store_cycle = -1;
        qualified_mdu_raw_cycles = 0;
        completed_mdu_bypass_cycles = 0;
        u_mem.mem[0] = 32'h8000_0537; // lui x10,0x80000
        u_mem.mem[1] = enc_i(12'hff9, 5'd0, 3'b000, 5'd1, 7'h13); // -7
        u_mem.mem[2] = enc_i(12'd3, 5'd0, 3'b000, 5'd2, 7'h13);
        u_mem.mem[3] = enc_r(7'h01, 5'd2, 5'd1, 3'b100, 5'd3); // div x3,x1,x2
        u_mem.mem[4] = enc_i(12'd9, 5'd0, 3'b000, 5'd4, 7'h13);
        u_mem.mem[5] = enc_s(12'h100, 5'd4, 5'd10, 3'b010);
        u_mem.mem[6] = enc_i(12'd2, 5'd3, 3'b000, 5'd5, 7'h13); // waits; x5=0
        u_mem.mem[7] = enc_r(7'h01, 5'd4, 5'd2, 3'b000, 5'd6); // mul=27
        u_mem.mem[8] = enc_i(12'd27, 5'd0, 3'b000, 5'd7, 7'h13);
        u_mem.mem[9] = enc_b(13'd28, 5'd7, 5'd6, 3'b001); // fail index16
        u_mem.mem[10] = enc_b(13'd24, 5'd0, 5'd5, 3'b001); // fail index16
        u_mem.mem[11] = enc_i(12'd1, 5'd0, 3'b000, 5'd8, 7'h13);
        u_mem.mem[12] = enc_s(12'h104, 5'd8, 5'd10, 3'b010);
        u_mem.mem[13] = enc_j(21'd0, 5'd0);
        u_mem.mem[16] = enc_i(12'd3, 5'd0, 3'b000, 5'd8, 7'h13);
        u_mem.mem[17] = enc_s(12'h104, 5'd8, 5'd10, 3'b010);
        u_mem.mem[18] = enc_j(21'd0, 5'd0);
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;
            if (u_core.hpm_events_w[`EDRV32_HPM_MDU_RAW_HAZARD-1]) begin
                qualified_mdu_raw_cycles <= qualified_mdu_raw_cycles + 1;
                if (!(u_core.decode_dependency_stall_w && u_core.mdu_raw_hazard_w) &&
                    !u_core.ex_late_mdu_stall_w)
                    $fatal(1, "MDU RAW HPM event lacks a valid dependency stall");
            end
            if ((u_core.align_valid_w && u_core.align_accept_w &&
                 u_core.mdu_raw_hazard_w && u_core.mdu_result_complete_w) ||
                (u_core.decode_valid_w && u_core.decode_accept_w &&
                 (u_core.decode_late_mdu_rs1_w || u_core.decode_late_mdu_rs2_w)))
                completed_mdu_bypass_cycles <= completed_mdu_bypass_cycles + 1;
            if (u_core.hpm_events_w[`EDRV32_HPM_MDU_WAW_HAZARD-1] &&
                (!u_core.decode_dependency_stall_w ||
                 !u_core.mdu_waw_hazard_w))
                $fatal(1, "MDU WAW HPM event lacks a valid dependency stall");
            if (trap) $fatal(1, "unexpected MDU test trap cause=%08x", trap_cause);
            if (u_core.mdu_authorize_w && u_core.mdu_result_complete_w &&
                (!u_core.mdu_writeback_fire_w || !u_core.commit_gpr_write_w ||
                 (u_core.commit_gpr_rd_w != u_core.mdu_result_rd_w) ||
                 (u_core.commit_gpr_value_w != u_core.mdu_result_data_w)))
                $fatal(1, "completed MDU did not write on its retirement edge");
            if (retire && (retire_pc == RESET_PC + 32'd12))
                divide_retire_cycle <= cycles;
            if (dmem_req_valid && dmem_req_ready && dmem_req_we &&
                (dmem_req_addr == DATA_ADDR))
                independent_store_cycle <= cycles;
            if (dmem_req_valid && dmem_req_ready && dmem_req_we &&
                (dmem_req_addr == TOHOST_ADDR)) begin
                if (dmem_req_wdata != 32'd1)
                    $fatal(1, "MDU program failed tohost=%08x", dmem_req_wdata);
                if (u_mem.mem[64] != 32'd9 || divide_retire_cycle < 0 ||
                    qualified_mdu_raw_cycles == 0 ||
                    completed_mdu_bypass_cycles == 0 ||
                    independent_store_cycle <= divide_retire_cycle)
                    $fatal(1, "independent progress/MDU bypass missing data=%08x div=%0d store=%0d raw=%0d bypass=%0d",
                           u_mem.mem[64], divide_retire_cycle,
                           independent_store_cycle, qualified_mdu_raw_cycles,
                           completed_mdu_bypass_cycles);
                $display("PASS: core MDU/scoreboard cycles=%0d raw=%0d bypass=%0d",
                         cycles, qualified_mdu_raw_cycles,
                         completed_mdu_bypass_cycles);
                $finish;
            end
            if (cycles > 1600)
                $fatal(1, "core MDU timeout pc=%08x instr=%08x", retire_pc, retire_instr);
        end
    end
endmodule
