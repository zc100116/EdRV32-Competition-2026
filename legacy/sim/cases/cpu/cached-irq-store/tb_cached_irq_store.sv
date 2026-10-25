`timescale 1ns/1ps
`include "edrv32_bus.vh"
`include "edrv32_lsu.vh"

// Warm-cache, straight-line LSU throughput probe. CASEID selects the body:
// 0 ALU, 1 loads, 2 stores, 3 load/use, 4 store/unrelated load,
// 5 store/full-forward load, 6 repeated byte-store/partial word load,
// 7 one partial-overlap pair followed by unrelated ALU instructions.
module tb_cached_irq_store;
reg irq=0; integer traps=0; integer wait_cycles=0; reg armed=0;
    localparam [31:0] RESET_PC = 32'h8000_0000;
    localparam integer BODY_START = 3;
    localparam integer BODY_LENGTH = 64;
    localparam integer BODY_END = BODY_START + BODY_LENGTH - 1;
    localparam integer LOOP_INDEX = BODY_END + 1;
    localparam integer SAMPLE_FIRST = BODY_START + 8;
    localparam integer SAMPLE_LAST = BODY_END - 8;

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

    integer caseid;
    integer i;
    integer cycle;
    integer pass;
    integer first_cycle;
    integer last_cycle;
    integer sampled_retires;
    integer lookup_fires;
    integer lookup_wait_lookup;
    integer lookup_wait_store;
    integer lookup_wait_other;
    integer load_full_cycles;
    integer store_full_cycles;
    integer ex_load_wait_cycles;
    integer commit_wait_cycles;
    integer decode_dep_cycles;
    integer decode_resident_cycles;
    integer decode_load_cycles;
    integer pair_first_cycle;
    integer pair_gap_sum;
    integer pair_count;
    integer last_lookup_cycle;
    integer lookup_gap_sum;
    integer lookup_gap_count;
    integer trace_enable;
    integer cold_first_request_cycle;
    integer cold_first_completion_cycle;
    integer cold_misses;
    integer warm_dcache_misses;
    integer warm_icache_misses;
    reg [`EDRV32_LSU_TOKEN_W-1:0] warm_sample_token;
    integer warm_sample_request_cycle;
    integer warm_sample_completion_cycle;
    integer partial_store_retire_cycle;
    integer partial_load_retire_cycle;

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
    function automatic [31:0] enc_j;
        input [20:0] imm;
        input [4:0] rd;
        begin enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'h6f}; end
    endfunction

    initial clk = 1'b0;
    always #5 clk = ~clk;

    edrv32_cached_core_native_harness #(
        .RESET_PC(RESET_PC), .ICACHE_LINE_COUNT(256),
        .DCACHE_LINE_COUNT(256)
    ) u_core (
        .clk_i(clk), .rst_n_i(rst_n),
        .imem_req_valid_o(imem_req_valid), .imem_req_ready_i(imem_req_ready),
        .imem_req_addr_o(imem_req_addr),
        .imem_resp_valid_i(imem_resp_valid), .imem_resp_ready_o(imem_resp_ready),
        .imem_resp_rdata_i(imem_resp_rdata), .imem_resp_error_i(imem_resp_error),
        .dmem_req_valid_o(dmem_req_valid), .dmem_req_ready_i(dmem_req_ready),
        .dmem_req_addr_o(dmem_req_addr), .dmem_req_we_o(dmem_req_we),
        .dmem_req_size_o(dmem_req_size), .dmem_req_wstrb_o(dmem_req_wstrb),
        .dmem_req_wdata_o(dmem_req_wdata),
        .dmem_resp_valid_i(dmem_resp_valid), .dmem_resp_ready_o(dmem_resp_ready),
        .dmem_resp_rdata_i(dmem_resp_rdata), .dmem_resp_error_i(dmem_resp_error),
        .itcm_req_valid_o(), .itcm_req_ready_i(1'b0), .itcm_req_addr_o(),
        .itcm_resp_valid_i(1'b0), .itcm_resp_ready_o(),
        .itcm_resp_rdata_i(32'd0), .itcm_resp_error_i(1'b0),
        .dtcm_req_valid_o(), .dtcm_req_ready_i(1'b0), .dtcm_req_addr_o(),
        .dtcm_req_we_o(), .dtcm_req_size_o(), .dtcm_req_wstrb_o(),
        .dtcm_req_wdata_o(), .dtcm_resp_valid_i(1'b0),
        .dtcm_resp_ready_o(), .dtcm_resp_rdata_i(32'd0),
        .dtcm_resp_error_i(1'b0),
        .irq_soft_i(1'b0), .irq_timer_i(1'b0), .irq_ext_i(irq),
        .time_value_i(64'd0),
        .retire_o(retire), .retire_pc_o(retire_pc),
        .retire_instr_o(retire_instr), .retire_exception_o(retire_exception),
        .retire_cause_o(retire_cause),
        .debug_decode_instr_o(), .debug_decode_pc_o(), .core_sleep_o()
    );

    edrv32_mem_model #(
        .MEM_DEPTH_WORDS(4096), .BASE_ADDR(RESET_PC),
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
        .dmem_req_wdata_i(dmem_req_wdata),
        .dmem_resp_valid_o(dmem_resp_valid), .dmem_resp_ready_i(dmem_resp_ready),
        .dmem_resp_rdata_o(dmem_resp_rdata), .dmem_resp_error_o(dmem_resp_error),
        .imem_req_stall_i(1'b0), .dmem_req_stall_i(1'b0)
    );


function automatic [31:0] enc_csr;
 input [11:0] csr; input [4:0] rs1;
 begin enc_csr={csr,rs1,3'b001,5'd0,7'h73}; end
endfunction
initial begin
 rst_n=0;
 for(i=0;i<4096;i=i+1) u_mem.mem[i]=32'h00000013;
 u_mem.mem[0]={20'h80001,5'd10,7'h37};
 u_mem.mem[1]=enc_i(12'h055,0,0,5,7'h13);
 u_mem.mem[2]=enc_i(0,10,2,6,7'h03);
 u_mem.mem[3]={20'h80000,5'd1,7'h37};
 u_mem.mem[4]=enc_i(12'h100,1,0,1,7'h13);
 u_mem.mem[5]=enc_csr(12'h305,1);
 u_mem.mem[6]={20'h1,5'd2,7'h37};
 u_mem.mem[7]=enc_i(12'h800,2,0,2,7'h13);
 u_mem.mem[8]=enc_csr(12'h304,2);
 u_mem.mem[9]=enc_i(8,0,0,2,7'h13);
 u_mem.mem[10]=enc_csr(12'h300,2);
 u_mem.mem[32]=enc_s(0,5,10,2);
 u_mem.mem[33]=enc_j(0,0);
 u_mem.mem[64]=32'h0000000f; // handler fences outstanding memory
 u_mem.mem[65]=enc_j(0,0);
 u_mem.mem[1024]=32'h11223344;
 repeat(4) @(negedge clk); rst_n=1;
end
always @(negedge clk) if(rst_n) begin
 if(!armed && u_core.u_cached_core.u_core.mem1_packet_valid_w && u_core.u_cached_core.u_core.mem1_packet_pc_w==32'h80000080) begin irq=1;armed=1;end
 if(traps>0) irq=0;
end
always @(posedge clk) if(rst_n) begin
 if(retire_exception) begin
  traps=traps+1;
  if(retire || u_core.u_cached_core.u_core.store_commit_fire_w)
   $fatal(1,"interrupt event retired or committed the interrupted Store");
 end
 if(traps>0) begin
  wait_cycles=wait_cycles+1;
  if(retire && retire_pc==32'h80000100) begin
   if(u_core.u_cached_core.u_core.u_store_queue.committed_count_r!=0 ||
      u_core.u_cached_core.u_dcache.reservation_count_r!=0)
    $fatal(1,"killed Store left queue or D-cache reservation state");
   $display("PASS: IRQ flush removes speculative Store and handler FENCE retires cycles=%0d",wait_cycles);
   $finish;
  end
  if(wait_cycles==100)
   $fatal(1,"handler FENCE did not make progress after IRQ flush");
 end
end
initial begin #20000;$fatal(1,"timeout");end
endmodule

