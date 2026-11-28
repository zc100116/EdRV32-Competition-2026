// File: tb.sv
// Spec: cpu-v2-testplan CV12; cache-spec 4, 6.
// Description: APB register, command snapshot, byte enable and error priority test.
// Clock domain: clk_sys.
module tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [11:0] addr = 0;
    reg sel = 0;
    reg enable = 0;
    reg write = 0;
    reg [31:0] data = 0;
    reg [3:0] strb = 0;
    wire ready;
    wire [31:0] rdata;
    wire error;
    wire req;
    reg req_ready = 0;
    wire [2:0] cmd;
    wire [31:0] op_addr;
    wire [31:0] op_size;
    reg busy = 0;
    reg wb_err = 0;
    reg [31:0] wb_addr = 0;
    wire irq;
    edrv32_cpu2_cache_ctrl dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .apb_paddr_i(addr),
        .apb_psel_i(sel),
        .apb_penable_i(enable),
        .apb_pwrite_i(write),
        .apb_pwdata_i(data),
        .apb_pstrb_i(strb),
        .apb_pready_o(ready),
        .apb_prdata_o(rdata),
        .apb_pslverr_o(error),
        .maint_req_valid_o(req),
        .maint_req_ready_i(req_ready),
        .maint_cmd_o(cmd),
        .maint_addr_o(op_addr),
        .maint_size_o(op_size),
        .maint_busy_i(busy),
        .wb_err_i(wb_err),
        .wb_err_addr_i(wb_addr),
        .cache_irq_o(irq)
    );
    task automatic wr(input [11:0] a, input [31:0] d, input [3:0] s);
        @(negedge clk);
        addr = a;
        data = d;
        strb = s;
        sel = 1;
        write = 1;
        enable = 0;
        @(negedge clk);
        enable = 1;
        @(negedge clk);
        sel = 0;
        enable = 0;
        write = 0;
    endtask
    task automatic rd(input [11:0] a, input [31:0] expected);
        @(negedge clk);
        addr = a;
        sel = 1;
        enable = 1;
        #1;
        if (!ready || error || rdata !== expected)
            $fatal(1, "read %h expected %h got %h at %t", a, expected, rdata, $time);
        @(negedge clk);
        sel = 0;
        enable = 0;
    endtask
    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1;
        rd(12'h000, 32'h00050001);
        rd(12'h008, 0);
        rd(12'h00c, 0);
        rd(12'h010, 0);
        rd(12'h014, 0);
        rd(12'h020, 0);
        rd(12'h024, 0);
        rd(12'h028, 0);
        wr(12'h020, 32'h11223344, 4'hf);
        wr(12'h020, 32'haabbccdd, 4'h5);
        rd(12'h020, 32'h11bb33dd);
        wr(12'h024, 32'h12345678, 4'hf);
        wr(12'h024, 32'habcd0000, 4'hc);
        rd(12'h024, 32'habcd5678);
        for (int c = 1; c <= 4; c++) begin
            wr(12'h028, 32'(c), 4'h0);
            if (req) $fatal(1, "command without strobe");
            wr(12'h028, 32'(c), 4'h1);
            if (!req || cmd != 3'(c) || op_addr != 32'h11bb33dd ||
                op_size != 32'habcd5678) $fatal(1, "command snapshot");
            rd(12'h008, 1);
            wr(12'h028, 32'd4, 4'hf);
            if (cmd != 3'(c)) $fatal(1, "pending command overwritten");
            @(negedge clk);
            busy = 1;
            req_ready = 1;
            @(negedge clk);
            req_ready = 0;
            if (req) $fatal(1, "request not consumed");
            wr(12'h028, 1, 4'hf);
            if (req) $fatal(1, "busy command accepted");
            busy = 0;
        end
        wr(12'h028, 0, 4'hf);
        wr(12'h028, 5, 4'hf);
        wr(12'h028, 32'h10000001, 4'hf);
        if (req) $fatal(1, "invalid command accepted");
        wr(12'h00c, 32'hffffffff, 4'hf);
        rd(12'h00c, 2);
        @(negedge clk);
        wb_err = 1;
        wb_addr = 32'h80000120;
        @(negedge clk);
        wb_err = 0;
        if (!irq) $fatal(1, "missing irq");
        rd(12'h010, 2);
        rd(12'h014, 32'h80000120);
        wr(12'h010, 2, 4'h0);
        rd(12'h010, 2);
        fork
            wr(12'h010, 2, 4'h1);
            begin
                repeat (2) @(negedge clk);
                wb_err = 1;
                wb_addr = 32'h1000ffe0;
                @(negedge clk);
                wb_err = 0;
            end
        join
        rd(12'h010, 2);
        rd(12'h014, 32'h1000ffe0);
        wr(12'h010, 2, 4'h1);
        rd(12'h010, 0);
        if (irq) $fatal(1, "irq not cleared");
        wr(12'h004, 32'hffffffff, 4'hf);
        rd(12'h004, 0);
        wr(12'h000, 0, 4'hf);
        rd(12'h000, 32'h00050001);
        $display("PASS cpu2_cache_ctrl CV12");
        $finish;
    end
endmodule
