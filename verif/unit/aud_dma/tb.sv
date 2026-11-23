// File: tb.sv
// Spec: aud-spec 2.2-2.3, 4, 6, 8.2/8.4.
// Description: Ring/page burst splitting, AXI stalls, unpacking and error drain.
// Clock domain: clk_mem test clock.
module tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg enable = 0;
    reg restart = 0;
    reg clear_error = 0;
    reg [23:0] wr_ptr = 0;
    wire [23:0] rd_ptr;
    wire [23:0] avail;
    wire busy;
    wire error_event;
    reg [9:0] free_space = 512;
    wire sample_valid;
    reg sample_ready = 1;
    wire [31:0] sample_data;
    wire arvalid;
    reg arready = 0;
    wire [31:0] araddr;
    wire [3:0] arlen;
    wire arid;
    reg rvalid = 0;
    wire rready;
    reg [255:0] rdata = 0;
    reg [1:0] rresp = 0;
    reg rlast = 0;
    integer samples = 0;
    integer errors = 0;
    integer bursts = 0;
    reg [31:0] expected [0:2047];
    integer queued = 0;
    integer tick = 0;
    edrv32_aud_dma dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .enable_i(enable),
        .restart_i(restart),
        .clear_error_i(clear_error),
        .ring_base_i(32'h00000e00),
        .ring_size_i(24'd1536),
        .wr_ptr_i(wr_ptr),
        .rd_ptr_o(rd_ptr),
        .avail_o(avail),
        .busy_o(busy),
        .error_o(error_event),
        .free_i(free_space),
        .sample_valid_o(sample_valid),
        .sample_ready_i(sample_ready),
        .sample_data_o(sample_data),
        .m_axi_arvalid_o(arvalid),
        .m_axi_arready_i(arready),
        .m_axi_araddr_o(araddr),
        .m_axi_arlen_o(arlen),
        .m_axi_arid_o(arid),
        .m_axi_rvalid_i(rvalid),
        .m_axi_rready_o(rready),
        .m_axi_rdata_i(rdata),
        .m_axi_rresp_i(rresp),
        .m_axi_rlast_i(rlast),
        .m_axi_rid_i(1'b0)
    );
    always @(posedge clk) begin
        if (rst_n) begin
            tick <= tick + 1;
            if (error_event) errors = errors + 1;
            if (sample_valid && sample_ready) begin
                if (samples >= queued || sample_data !== expected[samples])
                    $fatal(1, "FAIL sample %0d expected=%h actual=%h", samples,
                        expected[samples], sample_data);
                samples = samples + 1;
            end
        end
    end
    always @(negedge clk) sample_ready = (tick % 5 != 2);
    task burst(input [31:0] address, input integer beats, input integer bad_beat);
        integer n;
        integer j;
        begin
            wait (arvalid);
            @(negedge clk);
            if (araddr !== address || int'(arlen) != beats-1 || arid !== 0)
                $fatal(1, "FAIL burst expected=%h/%0d actual=%h/%0d", address, beats,
                    araddr, int'(arlen)+1);
            repeat (3) begin
                @(negedge clk);
                if (!arvalid || araddr !== address || int'(arlen) != beats-1)
                    $fatal(1, "FAIL stalled address changed");
            end
            arready = 1;
            @(negedge clk);
            arready = 0;
            bursts = bursts + 1;
            for (n = 0; n < beats; n = n + 1) begin
                repeat (2) @(negedge clk);
                for (j = 0; j < 8; j = j + 1) begin
                    rdata[j*32 +: 32] = address + 32'(n*32+j*4);
                    if (n != bad_beat) begin
                        expected[queued] = rdata[j*32 +: 32];
                        queued = queued + 1;
                    end
                end
                rresp = n == bad_beat ? 2'b10 : 2'b00;
                rlast = (n == beats-1);
                rvalid = 1;
                do @(posedge clk); while (!rready);
                @(negedge clk);
                rvalid = 0;
            end
            wait (!busy);
            @(negedge clk);
        end
    endtask
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        enable = 1;
        restart = 1;
        @(negedge clk);
        restart = 0;
        free_space = 100;
        wr_ptr = 448;
        repeat (10) @(negedge clk);
        if (arvalid) $fatal(1, "FAIL insufficient FIFO credit");
        free_space = 512;
        burst('he00, 14, -1);
        wr_ptr = 1024;
        burst('hfc0, 2, -1);
        burst('h1000, 16, -1);
        wr_ptr = 1408;
        burst('h1200, 12, -1);
        wr_ptr = 256;
        burst('h1380, 4, -1);
        if (rd_ptr != 0) $fatal(1, "FAIL ring wrap rd=%0d", rd_ptr);
        burst('he00, 8, -1);
        repeat (20) @(negedge clk);
        if (arvalid || avail != 0) $fatal(1, "FAIL empty ring");
        wr_ptr = 768;
        burst('hf00, 8, 2);
        // A page split leaves data available, but the error must stop new ARs.
        repeat (20) @(negedge clk);
        if (arvalid || errors != 1 || rd_ptr != 512)
            $fatal(1, "FAIL error halt errors=%0d rd=%0d", errors, rd_ptr);
        clear_error = 1;
        @(negedge clk);
        clear_error = 0;
        burst('h1000, 8, -1);
        if (samples != queued || errors != 1 || bursts != 8)
            $fatal(1, "FAIL final samples=%0d queued=%0d bursts=%0d", samples, queued,
                bursts);
        $display("PASS DMA %0d bursts, %0d ordered samples, 1 drained error", bursts, samples);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "FAIL timeout");
    end
endmodule
