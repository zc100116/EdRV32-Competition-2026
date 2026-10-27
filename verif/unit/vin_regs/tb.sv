// File: tb.sv
// Spec: vin 4, 6; SoC 7.1.
// Description: APB oracle checks masks, reserved CH2, RW1C precedence and performance events.
// Clock domain: clk_mem.
module tb;
    bit clk = 0;
    always #4 clk = ~clk;
    bit rst_n = 0;
    bit [11:0] addr = 0;
    bit sel = 0;
    bit access = 0;
    bit write = 0;
    bit [31:0] wdata = 0;
    wire ready;
    wire [31:0] rdata;
    wire slverr;
    wire enable;
    wire abort_request;
    wire soft_rst;
    wire [31:0] cam0_size;
    wire [31:0] cam1_size;
    wire [31:0] msrc_base;
    wire [15:0] msrc_stride;
    wire [31:0] msrc_size;
    wire msrc_start;
    wire [15:0] ch_ctrl;
    wire [31:0] ch_stride;
    wire [255:0] ch_bases;
    wire [7:0] ch_slot_busy;
    bit busy = 0;
    bit [31:0] irq_set = 0;
    bit [3:0] error_code = 0;
    bit [15:0] perf_event = 0;
    bit [3:0] cfg_errors = 0;
    wire irq;
    edrv32_vin_regs u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .apb_paddr_i(addr),
        .apb_psel_i(sel),
        .apb_penable_i(access),
        .apb_pwrite_i(write),
        .apb_pwdata_i(wdata),
        .apb_pstrb_i(4'b0000),
        .apb_pready_o(ready),
        .apb_prdata_o(rdata),
        .apb_pslverr_o(slverr),
        .enable_o(enable),
        .abort_o(abort_request),
        .soft_rst_o(soft_rst),
        .cam0_size_o(cam0_size),
        .cam1_size_o(cam1_size),
        .msrc_base_o(msrc_base),
        .msrc_stride_o(msrc_stride),
        .msrc_size_o(msrc_size),
        .msrc_start_o(msrc_start),
        .ch_ctrl_o(ch_ctrl),
        .ch_stride_o(ch_stride),
        .ch_bases_o(ch_bases),
        .ch_slot_busy_o(ch_slot_busy),
        .busy_i(busy),
        .msrc_busy_i(busy),
        .ch_done_info_i(12'h123),
        .ch_done_frame_id_i(64'h11223344_aabbccdd),
        .ch_wr_stat_i(6'h2d),
        .irq_set_i(irq_set),
        .error_code_i(error_code),
        .perf_event_i(perf_event),
        .cfg_errors_i(cfg_errors),
        .irq_o(irq)
    );

    task automatic put(input bit [11:0] a, input bit [31:0] d);
        @(negedge clk);
        addr = a;
        sel = 1;
        access = 0;
        write = 1;
        wdata = d;
        @(negedge clk);
        access = 1;
        @(negedge clk);
        sel = 0;
        access = 0;
        write = 0;
    endtask
    task automatic get(input bit [11:0] a, input bit [31:0] want);
        @(negedge clk);
        addr = a;
        sel = 1;
        access = 0;
        write = 0;
        @(negedge clk);
        access = 1;
        #1;
        if (!ready || slverr || rdata !== want)
            $fatal(1,"FAIL APB addr=%h want=%h got=%h t=%0t",a,want,rdata,$time);
        @(negedge clk);
        sel = 0;
        access = 0;
    endtask
    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        get('h000,'h00010001);
        get('h008,2);
        get('h100,'h02d00500);
        get('h104,'h02d00500);
        get('h114,'ha00);
        get('h200,'h30);
        get('h280,'h30);
        put('h100,'hffffffff);
        get('h100,'h0fff07fe);
        put('h110,'h12345fff);
        get('h110,'h12345000);
        put('h114,'hffffabcd);
        get('h114,'habc0);
        put('h200,'hffffffff);
        get('h200,'h77);
        put('h208,'hfedcbfff);
        get('h208,'hfedcb000);
        put('h218,'hffffffff);
        get('h218,15);
        for (int a = 'h300; a < 'h380; a += 4) begin
            put(12'(a),'hffffffff);
            get(12'(a),0);
        end
        get('h220,'h23);
        get('h224,'haabbccdd);
        get('h2a0,4);
        get('h2a4,'h11223344);
        put('h00c,'hffffffff);
        get('h00c,'h107);
        @(negedge clk);
        irq_set = 'h106;
        error_code = 9;
        perf_event = 16'h1459;
        cfg_errors = 5;
        @(negedge clk);
        irq_set = 0;
        error_code = 0;
        perf_event = 0;
        cfg_errors = 0;
        get('h010,'h106);
        get('h014,9);
        get('h008,6);
        get('h02c,1);
        get('h054,0); // CH2 PERF5.
        get('h060,0); // CH2 PERF8.
        get('h06c,0); // CH2 PERF11.
        get('h07c,5);
        if (!irq) $fatal(1,"FAIL IRQ enable");
        put('h010,2);
        get('h010,'h104);
        get('h014,0);
        put('h010,'h104);
        if (irq) $fatal(1,"FAIL IRQ clear");
        put('h004,1);
        get('h004,1);
        rst_n = 0;
        repeat (2) @(negedge clk);
        rst_n = 1;
        get('h004,0);
        get('h07c,0);
        get('h200,'h30);
        $display("PASS vin_regs");
        $finish;
    end
    initial begin #1000000; $fatal(1,"FAIL timeout"); end
endmodule
