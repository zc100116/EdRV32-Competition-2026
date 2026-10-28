// File: dut_connections.svh
// Spec: PIX 3; SoC 4.3, 4.5.
// Description: Public PIX port mapping, shared by real and explicit stub tops.
// Clock domain: clk_mem.
        // Clock and reset.
        .clk_mem_i(clk_mem),
        .rst_mem_n_i(rst_mem_n),

        // Upstream pixel stream.
        .pix_in_valid_i(in_valid),
        .pix_in_ready_o(in_ready),
        .pix_in_data_i(in_data),
        .pix_in_sof_i(in_sof),
        .pix_in_eol_i(in_eol),
        .pix_in_eof_i(in_eof),

        // Downstream pixel stream.
        .pix_out_valid_o(out_valid),
        .pix_out_ready_i(out_ready),
        .pix_out_data_o(out_data),
        .pix_out_sof_o(out_sof),
        .pix_out_eol_o(out_eol),
        .pix_out_eof_o(out_eof),

        // APB control and status (media slot 2).
        .apb_paddr_i(apb.paddr),
        .apb_psel_i(apb.psel[2]),
        .apb_penable_i(apb.penable),
        .apb_pwrite_i(apb.pwrite),
        .apb_pwdata_i(apb.pwdata),
        .apb_pstrb_i(apb.pstrb),
        .apb_prdata_o(apb.prdata[95:64]),
        .apb_pready_o(apb.pready[2]),
        .apb_pslverr_o(apb.pslverr[2]),

        // Interrupt.
        .irq_o(irq)
