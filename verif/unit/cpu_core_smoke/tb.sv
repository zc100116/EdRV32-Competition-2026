// File: cpu_core_smoke/tb.sv
// Spec: cpu-plan C-R3; cpu-spec 3.1-3.4
// Description: Execute the BSP-linked software with ideal one-cycle caches.
//              Check architectural traps and the common tohost completion convention.
// Clock: clk_sys.
`timescale 1ns/1ps
module tb #(parameter RVC_EN=1);
    // The generated map also declares constants for other SoC clients.
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    /* verilator lint_on UNUSEDPARAM */
    reg clk_i=0;
    always #5 clk_i=~clk_i;
    reg rst_n_i=0;
    wire ic_req_valid_o;
    wire [31:0] ic_req_addr_o;
    reg ic_req_ready_i=0;
    reg ic_resp_valid_i=0;
    reg [63:0] ic_resp_data_i=0;
    reg ic_resp_err_i=0;
    wire ic_kill_o;
    wire ic_inv_o;
    reg ic_inv_done_i=0;
    wire dc_req_valid_o;
    wire [31:0] dc_req_addr_o;
    wire dc_req_store_o;
    wire [1:0] dc_req_size_o;
    reg dc_req_ready_i=0;
    reg dc_resp_valid_i=0;
    reg [31:0] dc_resp_data_i=0;
    reg dc_resp_err_i=0;
    reg dc_resp_device_i=0;
    wire dc_kill_o;
    wire dc_commit_o;
    wire [31:0] dc_store_data_o;
    wire dc_fence_o;
    wire dc_clean_all_o;
    reg dc_fence_done_i=0;
    reg dc_wb_event_i=0;
    reg irq_meip_i=0;
    reg irq_msip_i=0;
    reg irq_mtip_i=0;
    reg [63:0] mtime_i=0;
    wire [63:0] debug_o;
    reg [7:0] rom[0:16383];
    reg [7:0] sram[0:EDRV32_SRAM_SIZE-1];
    string rom_path;
    string sram_path;
    reg [31:0] store_addr_r;
    reg [1:0] store_size_r;
    reg store_pending_r=0;
    integer i;
    integer cycles=0;
    integer retired=0;
    integer pairs=0;
    integer multiply_seen=0;
    integer divide_seen=0;
    integer csr_seen=0;
    integer fence_i_seen=0;
    integer e1_recover_seen=0;
    integer write_byte;
    integer trace_lane;
    function automatic [7:0] byte_at(input reg [31:0] address);
        begin
            if(address<16384)byte_at=rom[address];
            else if(address>=EDRV32_SRAM_BASE && address<EDRV32_SRAM_BASE+EDRV32_SRAM_SIZE)
                byte_at=sram[address-32'h10000000];
            else begin
                $fatal(1,"FAIL smoke unmapped address %h",address);
                byte_at=0;
            end
        end
    endfunction
    edrv32_cpu_core #(.RVC_EN(RVC_EN)) dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .ic_req_valid_o(ic_req_valid_o),
        .ic_req_addr_o(ic_req_addr_o),
        .ic_req_ready_i(ic_req_ready_i),
        .ic_resp_valid_i(ic_resp_valid_i),
        .ic_resp_data_i(ic_resp_data_i),
        .ic_resp_err_i(ic_resp_err_i),
        .ic_kill_o(ic_kill_o),
        .ic_inv_o(ic_inv_o),
        .ic_inv_done_i(ic_inv_done_i),
        .dc_req_valid_o(dc_req_valid_o),
        .dc_req_addr_o(dc_req_addr_o),
        .dc_req_store_o(dc_req_store_o),
        .dc_req_size_o(dc_req_size_o),
        .dc_req_ready_i(dc_req_ready_i),
        .dc_resp_valid_i(dc_resp_valid_i),
        .dc_resp_data_i(dc_resp_data_i),
        .dc_resp_err_i(dc_resp_err_i),
        .dc_resp_device_i(dc_resp_device_i),
        .dc_kill_o(dc_kill_o),
        .dc_commit_o(dc_commit_o),
        .dc_store_data_o(dc_store_data_o),
        .dc_fence_o(dc_fence_o),
        .dc_clean_all_o(dc_clean_all_o),
        .dc_fence_done_i(dc_fence_done_i),
        .dc_wb_event_i(dc_wb_event_i),
        .irq_meip_i(irq_meip_i),
        .irq_msip_i(irq_msip_i),
        .irq_mtip_i(irq_mtip_i),
        .mtime_i(mtime_i),
        .debug_o(debug_o)
    );
    always @(posedge clk_i) begin
        if(!rst_n_i)begin
            ic_resp_valid_i<=0;dc_resp_valid_i<=0;
            dc_fence_done_i<=0;ic_inv_done_i<=0;store_pending_r<=0;
        end else begin
            cycles=cycles+1;mtime_i<=mtime_i+1'b1;
            if(dc_commit_o && store_pending_r)begin
                for(write_byte=0;write_byte<4;write_byte=write_byte+1)
                    if(write_byte<(1<<store_size_r))
                        sram[store_addr_r-32'h10000000+32'(write_byte)]=
                            dc_store_data_o[write_byte*8+:8];
                // This BSP image has no initialized globals; nm reports tohost at SRAM+0x40.
                if(store_addr_r==32'h10000040 && dc_store_data_o!=0)begin
                    if(dc_store_data_o!=1)
                        $fatal(1,"FAIL smoke software status=%h",dc_store_data_o);
                    if(multiply_seen==0 || divide_seen==0 || csr_seen==0 || fence_i_seen==0 || pairs==0 || e1_recover_seen==0)
                        $fatal(1,"FAIL smoke missing functional coverage");
                    $display("PASS cpu_core_smoke RVC=%0d cycles=%0d instructions=%0d pairs=%0d",
                        RVC_EN,cycles,retired,pairs);$finish;
                end
            end
            ic_resp_valid_i<=ic_req_valid_o && ic_req_ready_i && !ic_kill_o;
            if(ic_req_valid_o && ic_req_ready_i)
                for(i=0;i<8;i=i+1)ic_resp_data_i[i*8+:8]<=byte_at(ic_req_addr_o+32'(i));
            dc_resp_valid_i<=dc_req_valid_o && dc_req_ready_i && !dc_kill_o;
            if(dc_req_valid_o && dc_req_ready_i)begin
                store_addr_r<=dc_req_addr_o;store_size_r<=dc_req_size_o;
                store_pending_r<=dc_req_store_o;
                dc_resp_data_i<=0;
                for(i=0;i<4;i=i+1)
                    if(i<(1<<dc_req_size_o))
                        dc_resp_data_i[i*8+:8]<=byte_at(dc_req_addr_o+32'(i));
            end else if(dc_commit_o || dc_kill_o)store_pending_r<=0;
            dc_fence_done_i<=dc_fence_o || dc_clean_all_o;
            ic_inv_done_i<=ic_inv_o;
            if(dut.trace_trap_w)
                $fatal(1,"FAIL smoke trap cause=%h pc=%h value=%h time=%t",
                    dut.trace_cause_w,dut.m_trap_pc_w,dut.m_trap_value_w,$time);
            if(dut.e_redirect1_w)e1_recover_seen=e1_recover_seen+1;
            if(dut.trace_valid_w==3)pairs=pairs+1;
            for(trace_lane=0;trace_lane<2;trace_lane=trace_lane+1)
                if(dut.trace_valid_w[trace_lane])begin
                    retired=retired+1;
                    if($test$plusargs("TRACE"))
                        $display("retire pc=%h instr=%h rd=%d data=%h",
                            dut.trace_pc_w[trace_lane*32+:32],dut.trace_instr_w[trace_lane*32+:32],
                            dut.trace_rd_w[trace_lane*5+:5],dut.trace_rd_data_w[trace_lane*32+:32]);
                    if(dut.trace_instr_w[trace_lane*32+:7]==7'h33 &&
                        dut.trace_instr_w[trace_lane*32+25+:7]==1)begin
                        if(dut.trace_instr_w[trace_lane*32+14])divide_seen=divide_seen+1;
                        else multiply_seen=multiply_seen+1;
                    end
                    if(dut.trace_instr_w[trace_lane*32+:7]==7'h73)csr_seen=csr_seen+1;
                    if(dut.trace_instr_w[trace_lane*32+:32]==32'h0000100f)
                        fence_i_seen=fence_i_seen+1;
                end
            if(cycles>10000)$fatal(1,"FAIL smoke timeout debug=%h",debug_o);
        end
    end
    initial begin
        for(i=0;i<16384;i=i+1)rom[i]=0;
        for(i=0;i<EDRV32_SRAM_SIZE;i=i+1)sram[i]=0;
        if(!$value$plusargs("ROM_HEX=%s",rom_path))$fatal(1,"FAIL missing ROM_HEX");
        if(!$value$plusargs("SRAM_HEX=%s",sram_path))$fatal(1,"FAIL missing SRAM_HEX");
        $readmemh(rom_path,rom);$readmemh(sram_path,sram);
        ic_req_ready_i=1;dc_req_ready_i=1;
        repeat(4)@(negedge clk_i);rst_n_i=1;
    end
endmodule
