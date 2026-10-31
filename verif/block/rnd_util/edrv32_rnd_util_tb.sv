// File: edrv32_rnd_util_tb.sv
// Spec: rnd 2.6, 5.2, 7; T-RNDMEAS.
// Description: Replay real LVGL batches; compare target bytes and observe lane use.
// Clock domain: clk_mem, 125 MHz.
`timescale 1ns/1ps
module edrv32_rnd_util_tb;
    logic clk_mem = 0;
    logic rst_mem_n = 0;
    logic irq;
    edrv32_apb_if apb();
    edrv32_axi256_if axi();
    byte unsigned file_buffer[0:16*1024*1024-1];
    longint unsigned cycles = 0;
    longint unsigned two = 0;
    longint unsigned one = 0;
    longint unsigned zero = 0;
    longint unsigned accepted = 0;
    longint unsigned stall = 0;
    longint unsigned extra = 0;
    longint unsigned rd_wait = 0;
    longint unsigned wr_wait = 0;

    task automatic equal(input string what_i,
        input logic [31:0] expected_i,
        input logic [31:0] actual_i);
        if (actual_i !== expected_i)
            $fatal(1, "FAIL %s expected=%08h actual=%08h time=%0t",
                what_i, expected_i, actual_i, $time);
    endtask

    always @(posedge clk_mem) begin
        if (rst_mem_n && u_rnd.busy_w) begin
            cycles++;
            if (u_rnd.u_alpha.out_valid_o && u_rnd.u_alpha.out_ready_i) begin
                if (u_rnd.blend_tag_w[29]) two++;
                else one++;
            end else zero++;
            if (u_rnd.u_draw.geometry_w) begin
                if (u_rnd.u_draw.geometry_valid_w && u_rnd.u_draw.pipeline_step_w)
                    accepted++;
                if (u_rnd.u_draw.render_state_r == u_rnd.u_draw.S_RENDER_STREAM &&
                    u_rnd.u_draw.pipeline_step_w && !u_rnd.u_draw.geometry_ready_w)
                    stall++;
                if (u_rnd.u_draw.u_geometry.request_i &&
                    u_rnd.u_draw.u_geometry.pair_i)
                    extra += u_rnd.u_draw.u_geometry.aa_w ? 4 : 1;
            end
            if (u_rnd.u_regs.read_wait_i) rd_wait++;
            if (u_rnd.u_regs.write_wait_i) wr_wait++;
        end
    end

    always #4 clk_mem = ~clk_mem;

    assign apb.prdata[127:0] = 0;
    assign apb.prdata[511:160] = 0;
    assign apb.pready[3:0] = 0;
    assign apb.pready[15:5] = 0;
    assign apb.pslverr[3:0] = 0;
    assign apb.pslverr[15:5] = 0;

    edrv32_rnd_util_memory u_memory (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(axi)
    );

    edrv32_rnd u_rnd (
        .clk_mem_i(clk_mem),
        .rst_mem_n_i(rst_mem_n),

        .apb_paddr_i(apb.paddr),
        .apb_psel_i(apb.psel[4]),
        .apb_penable_i(apb.penable),
        .apb_pwrite_i(apb.pwrite),
        .apb_pwdata_i(apb.pwdata),
        .apb_pstrb_i(apb.pstrb),
        .apb_pready_o(apb.pready[4]),
        .apb_prdata_o(apb.prdata[159:128]),
        .apb_pslverr_o(apb.pslverr[4]),

        .p4_awid_o(axi.awid),
        .p4_awaddr_o(axi.awaddr),
        .p4_awlen_o(axi.awlen),
        .p4_awvalid_o(axi.awvalid),
        .p4_awready_i(axi.awready),
        .p4_wdata_o(axi.wdata),
        .p4_wstrb_o(axi.wstrb),
        .p4_wlast_o(axi.wlast),
        .p4_wvalid_o(axi.wvalid),
        .p4_wready_i(axi.wready),
        .p4_bid_i(axi.bid),
        .p4_bresp_i(axi.bresp),
        .p4_bvalid_i(axi.bvalid),
        .p4_bready_o(axi.bready),

        .p4_arid_o(axi.arid),
        .p4_araddr_o(axi.araddr),
        .p4_arlen_o(axi.arlen),
        .p4_arvalid_o(axi.arvalid),
        .p4_arready_i(axi.arready),
        .p4_rid_i(axi.rid),
        .p4_rdata_i(axi.rdata),
        .p4_rresp_i(axi.rresp),
        .p4_rlast_i(axi.rlast),
        .p4_rvalid_i(axi.rvalid),
        .p4_rready_o(axi.rready),

        .irq_o(irq)
    );

    task automatic apb_access(input bit write_i,
        input logic [11:0] address_i,
        input logic [31:0] data_i,
        output logic [31:0] data_o);
        @(negedge clk_mem);
        apb.paddr = address_i;
        apb.pwrite = write_i;
        apb.pwdata = data_i;
        // rnd 4: all writes are full-word regardless of PSTRB, including zero.
        apb.pstrb = address_i[3:0];
        apb.psel = 16'h0010;
        apb.penable = 0;
        @(negedge clk_mem);
        apb.penable = 1;
        @(posedge clk_mem);
        equal("APB PREADY", 1, 32'(apb.pready[4]));
        equal("APB PSLVERR", 0, 32'(apb.pslverr[4]));
        data_o = apb.prdata[159:128];
        @(negedge clk_mem);
        apb.psel = 0;
        apb.penable = 0;
    endtask

    task automatic write_reg(input logic [11:0] address_i,
        input logic [31:0] data_i);
        logic [31:0] unused_data;
        apb_access(1, address_i, data_i, unused_data);
    endtask

    task automatic read_reg(input logic [11:0] address_i,
        output logic [31:0] data_o);
        apb_access(0, address_i, 0, data_o);
    endtask

    initial begin : stimulus
        string path;
        int fd;
        int count;
        int batches;
        int descriptors;
        int pages;
        logic [19:0] page;
        int targets;
        int size;
        int latency;
        logic [31:0] address;
        logic [31:0] status;
        logic [31:0] perf;
        longint unsigned start_cycles;
        longint unsigned start_read;
        longint unsigned start_write;
        apb.paddr = 0;
        apb.psel = 0;
        apb.penable = 0;
        apb.pwrite = 0;
        apb.pwdata = 0;
        apb.pstrb = 0;
        if (!$value$plusargs("INPUT=%s", path)) $fatal(1, "FAIL INPUT is required");
        if (!$value$plusargs("LATENCY=%d", latency)) $fatal(1, "FAIL LATENCY is required");
        fd = $fopen(path, "rb");
        if (fd == 0) $fatal(1, "FAIL cannot open %s", path);
        count = $fread(batches, fd);
        equal("batch header bytes", 4, 32'(count));
        u_memory.read_latency = latency;
        repeat (5) @(negedge clk_mem);
        rst_mem_n = 1;
        repeat (2) @(negedge clk_mem);
        for (int batch = 0; batch < batches; batch++) begin
            count = $fread(descriptors, fd);
            equal("descriptor header bytes", 4, 32'(count));
            count = $fread(pages, fd);
            equal("page header bytes", 4, 32'(count));
            for (int index = 0; index < pages; index++) begin
                count = $fread(address, fd);
                page = address[19:0];
                equal("page number bytes", 4, 32'(count));
                u_memory.page_index[page[19:0]] = index;
                count = $fread(file_buffer, fd, 0, 4096);
                equal("page bytes", 4096, 32'(count));
                for (int k = 0; k < 4096; k++)
                    u_memory.mem[index * 4096 + k] = file_buffer[k];
            end
            write_reg(12'h010, 3);
            write_reg(12'h00c, 3);
            write_reg(12'h020, 32'h1000);
            write_reg(12'h024, 32'(descriptors));
            start_cycles = cycles;
            start_read = rd_wait;
            start_write = wr_wait;
            write_reg(12'h028, 1);
            wait (irq);
            @(negedge clk_mem);
            read_reg(12'h014, status);
            equal("ERR_CODE", 0, status);
            read_reg(12'h040, perf);
            equal("PERF0", perf, 32'(cycles - start_cycles));
            read_reg(12'h050, perf);
            equal("PERF4", perf, 32'(rd_wait - start_read));
            read_reg(12'h054, perf);
            equal("PERF5", perf, 32'(wr_wait - start_write));
            count = $fread(targets, fd);
            equal("target count bytes", 4, 32'(count));
            for (int target = 0; target < targets; target++) begin
                count = $fread(address, fd);
                equal("target address bytes", 4, 32'(count));
                count = $fread(size, fd);
                equal("target size bytes", 4, 32'(count));
                count = $fread(file_buffer, fd, 0, size);
                equal("expected target bytes", 32'(size), 32'(count));
                for (int k = 0; k < size; k++) begin
                    if (u_memory.mem[u_memory.offset(address + 32'(k))] !== file_buffer[k])
                        $fatal(1, "FAIL batch=%0d addr=%08h expected=%02h actual=%02h",
                            batch, address + 32'(k), file_buffer[k],
                            u_memory.mem[u_memory.offset(address + 32'(k))]);
                end
            end
        end
        $fclose(fd);
        $display("UTIL %0d %0d %0d %0d %0d %0d %0d %0d %0d",
            cycles, two, one, zero, accepted, stall, extra, rd_wait, wr_wait);
        $display("PASS real LVGL replay batches=%0d latency=%0d", batches, latency);
        $finish;
    end
endmodule
