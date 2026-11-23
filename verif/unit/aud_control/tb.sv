// File: tb.sv
// Spec: aud-spec 4, 6; gpu-soc-spec 5.2 X11.
// Description: Disable and rapid re-enable during an outstanding read must drain
//              the transaction and FIFO before restarting from ring offset zero.
// Clock domain: unrelated clk_mem and clk_aud test clocks.
module tb;
    reg clk_mem_i = 0;
    reg clk_aud_i = 0;
    always #5 clk_mem_i = ~clk_mem_i;
    always #41 clk_aud_i = ~clk_aud_i;
    reg rst_mem_n_i = 0;
    reg rst_aud_n_i = 0;
    reg [11:0] s_apb_paddr_i = 0;
    reg s_apb_psel_i = 0;
    reg s_apb_penable_i = 0;
    reg s_apb_pwrite_i = 0;
    reg [31:0] s_apb_pwdata_i = 0;
    reg [3:0] s_apb_pstrb_i = 0;
    wire s_apb_pready_o;
    wire [31:0] s_apb_prdata_o;
    wire s_apb_pslverr_o;
    wire m_axi_arvalid_o;
    reg m_axi_arready_i = 0;
    wire [31:0] m_axi_araddr_o;
    wire [3:0] m_axi_arlen_o;
    wire m_axi_arid_o;
    reg m_axi_rvalid_i = 0;
    wire m_axi_rready_o;
    reg [255:0] m_axi_rdata_i = 0;
    reg [1:0] m_axi_rresp_i = 0;
    reg m_axi_rlast_i = 0;
    reg m_axi_rid_i = 0;
    wire urgent_o;
    wire irq_o;
    wire aud_bclk_o;
    wire aud_lrck_o;
    wire aud_sdata_o;
    edrv32_aud u_dut (
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_i),
        .clk_aud_i(clk_aud_i),
        .rst_aud_n_i(rst_aud_n_i),
        .s_apb_paddr_i(s_apb_paddr_i),
        .s_apb_psel_i(s_apb_psel_i),
        .s_apb_penable_i(s_apb_penable_i),
        .s_apb_pwrite_i(s_apb_pwrite_i),
        .s_apb_pwdata_i(s_apb_pwdata_i),
        .s_apb_pstrb_i(s_apb_pstrb_i),
        .s_apb_pready_o(s_apb_pready_o),
        .s_apb_prdata_o(s_apb_prdata_o),
        .s_apb_pslverr_o(s_apb_pslverr_o),
        .m_axi_arvalid_o(m_axi_arvalid_o),
        .m_axi_arready_i(m_axi_arready_i),
        .m_axi_araddr_o(m_axi_araddr_o),
        .m_axi_arlen_o(m_axi_arlen_o),
        .m_axi_arid_o(m_axi_arid_o),
        .m_axi_rvalid_i(m_axi_rvalid_i),
        .m_axi_rready_o(m_axi_rready_o),
        .m_axi_rdata_i(m_axi_rdata_i),
        .m_axi_rresp_i(m_axi_rresp_i),
        .m_axi_rlast_i(m_axi_rlast_i),
        .m_axi_rid_i(m_axi_rid_i),
        .urgent_o(urgent_o),
        .irq_o(irq_o),
        .aud_bclk_o(aud_bclk_o),
        .aud_lrck_o(aud_lrck_o),
        .aud_sdata_o(aud_sdata_o)
    );
    task write_reg(input [11:0] addr, input [31:0] data_in);
        begin
            @(negedge clk_mem_i);
            s_apb_psel_i = 1;
            s_apb_paddr_i = addr;
            s_apb_pwrite_i = 1;
            s_apb_pwdata_i = data_in;
            s_apb_pstrb_i = 15;
            @(negedge clk_mem_i);
            s_apb_penable_i = 1;
            @(negedge clk_mem_i);
            if (!s_apb_pready_o || s_apb_pslverr_o) $fatal(1, "FAIL APB response");
            s_apb_psel_i = 0;
            s_apb_penable_i = 0;
        end
    endtask
    task read_reg(input [11:0] addr, input [31:0] expected);
        begin
            @(negedge clk_mem_i);
            s_apb_psel_i = 1;
            s_apb_paddr_i = addr;
            s_apb_pwrite_i = 0;
            @(negedge clk_mem_i);
            s_apb_penable_i = 1;
            #1;
            if (s_apb_prdata_o !== expected)
                $fatal(1, "FAIL register %h expected=%h actual=%h", addr, expected,
                    s_apb_prdata_o);
            @(negedge clk_mem_i);
            s_apb_psel_i = 0;
            s_apb_penable_i = 0;
        end
    endtask
    task response(input reg last_beat);
        begin
            @(negedge clk_mem_i);
            m_axi_rvalid_i = 1;
            m_axi_rlast_i = last_beat;
            m_axi_rdata_i = {8{32'h76543210}};
            do @(posedge clk_mem_i); while (!m_axi_rready_o);
            @(negedge clk_mem_i);
            m_axi_rvalid_i = 0;
        end
    endtask
    initial begin
        repeat (5) @(negedge clk_mem_i);
        rst_mem_n_i = 1;
        @(negedge clk_aud_i);
        rst_aud_n_i = 1;
        write_reg('h100, 'h80000000);
        write_reg('h104, 512);
        write_reg('h108, 96);
        write_reg('h004, 1);
        wait (m_axi_arvalid_o);
        @(negedge clk_mem_i);
        if (m_axi_araddr_o != 'h80000000 || m_axi_arlen_o != 2)
            $fatal(1, "FAIL initial burst");
        m_axi_arready_i = 1;
        @(negedge clk_mem_i);
        m_axi_arready_i = 0;
        response(0);
        write_reg('h004, 0);
        write_reg('h004, 1);
        repeat (30) @(negedge clk_mem_i);
        if (m_axi_arvalid_o) $fatal(1, "FAIL new AR before drain");
        response(0);
        response(1);
        wait (m_axi_arvalid_o);
        @(negedge clk_mem_i);
        if (m_axi_araddr_o != 'h80000000 || m_axi_arlen_o != 2)
            $fatal(1, "FAIL restart expected ring base, actual=%h", m_axi_araddr_o);
        m_axi_arready_i = 1;
        @(negedge clk_mem_i);
        m_axi_arready_i = 0;
        response(0);
        response(0);
        response(1);
        repeat (20) @(negedge clk_mem_i);
        write_reg('h004, 0);
        // Allow 24 queued samples plus FIFO/Gray synchronization to drain.
        repeat (400) @(negedge clk_mem_i);
        read_reg('h10c, 0);
        read_reg('h008, 2);
        if (urgent_o || aud_sdata_o) $fatal(1, "FAIL disabled outputs");
        $display("PASS control: in-flight disable, rapid re-enable, FIFO drain and RD reset");
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "FAIL timeout");
    end
endmodule
