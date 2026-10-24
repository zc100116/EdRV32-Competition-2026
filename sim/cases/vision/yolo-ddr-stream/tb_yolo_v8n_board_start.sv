`timescale 1ns/1ps

module tb_yolo_v8n_board_start;
    reg clk_27m_i = 1'b0;
    reg ref_clk_p_i = 1'b0;
    reg reset_n_i = 1'b0;
    always #18.518 clk_27m_i = !clk_27m_i;
    always #4 ref_clk_p_i = !ref_clk_p_i;
    wire ref_clk_n_i = !ref_clk_p_i;
    wire uart_tx_w;
    wire [7:0] led_w;
    wire mem_rst_n_w, mem_ck_w, mem_ck_n_w, mem_cke_w, mem_cs_n_w;
    wire mem_ras_n_w, mem_cas_n_w, mem_we_n_w, mem_odt_w;
    wire [14:0] mem_a_w;
    wire [2:0] mem_ba_w;
    wire [3:0] mem_dqs_w, mem_dqs_n_w, mem_dm_w;
    wire [31:0] mem_dq_w;
    reg [7:0] reply_r [0:30];
    integer received_r = 0;
    integer bit_no;
    integer print_index;

    edrv32_pango_200h_yolo_v8n_top #(.UART_BAUD(15000000)) dut (
        .clk_27m_i(clk_27m_i),
        .ref_clk_p_i(ref_clk_p_i), .ref_clk_n_i(ref_clk_n_i),
        .reset_n_i(reset_n_i), .uart_rx_i(1'b1),
        .uart_tx_o(uart_tx_w), .led_o(led_w),
        .mem_rst_n_o(mem_rst_n_w),
        .mem_ck_o(mem_ck_w), .mem_ck_n_o(mem_ck_n_w),
        .mem_cke_o(mem_cke_w), .mem_cs_n_o(mem_cs_n_w),
        .mem_ras_n_o(mem_ras_n_w), .mem_cas_n_o(mem_cas_n_w),
        .mem_we_n_o(mem_we_n_w), .mem_odt_o(mem_odt_w),
        .mem_a_o(mem_a_w), .mem_ba_o(mem_ba_w),
        .mem_dqs_io(mem_dqs_w), .mem_dqs_n_io(mem_dqs_n_w),
        .mem_dq_io(mem_dq_w), .mem_dm_o(mem_dm_w)
    );

    initial forever begin
        @(negedge uart_tx_w);
        #33.333;
        if (uart_tx_w !== 1'b0)
            $fatal(1, "status start bit invalid");
        for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
            #66.667;
            if (received_r < 31)
                reply_r[received_r][bit_no] = uart_tx_w;
        end
        #66.667;
        if (uart_tx_w !== 1'b1)
            $fatal(1, "status stop bit invalid");
        received_r = received_r + 1;
    end

    initial begin
        repeat (8) @(negedge ref_clk_p_i);
        reset_n_i = 1'b1;
        wait (dut.ddr_ready_sync_r);
        if (dut.run_owner_r || dut.core_busy_w)
            $fatal(1, "core started before model and image");
        force dut.model_base_w = 32'h0010_0000;
        force dut.model_size_w = 32'd3358720;
        force dut.model_crc_w = 32'h7739_8e67;
        force dut.model_ready_w = 1'b1;
        repeat (3) @(negedge dut.yolo_clk_w);
        if (!dut.model_seen_r || dut.image_seen_r)
            $fatal(1, "model completion not recognized");
        force dut.model_ready_w = 1'b0;
        repeat (3) @(negedge dut.yolo_clk_w);
        force dut.model_base_w = 32'h0215_2000;
        force dut.model_size_w = 32'd3932160;
        force dut.model_ready_w = 1'b1;
        wait (dut.run_owner_r);
        if (!dut.image_seen_r || !dut.core_busy_w)
            $fatal(1, "core did not start after image completion");
        force dut.core_step_w = 7'd73;
        force dut.core_done_w = 1'b1;
        repeat (2) @(negedge dut.yolo_clk_w);
        force dut.core_done_w = 1'b0;
        wait (dut.post_owner_r);
        if (!dut.core_finished_r || !dut.post_busy_w)
            $fatal(1, "postprocessor did not start after core completion");
        force dut.post_done_w = 1'b1;
        repeat (2) @(negedge dut.yolo_clk_w);
        force dut.post_done_w = 1'b0;
        wait (received_r == 31);
        if (reply_r[0] !== "Y" || reply_r[1] !== "V" ||
            reply_r[2] !== "8" || reply_r[4] !== "P" ||
            reply_r[5] !== "A" || reply_r[6] !== "S" ||
            reply_r[7] !== "S" || reply_r[9] !== "S" ||
            reply_r[10] !== "T" || reply_r[13] !== "=" ||
            reply_r[17] !== "C" || reply_r[20] !== "=" ||
            reply_r[29] !== 8'h0d || reply_r[30] !== 8'h0a ||
            !dut.run_done_r || dut.run_error_r)
            $fatal(1, "full-network status failed");
        for (print_index = 0; print_index < 31; print_index = print_index + 1)
            $write("%c", reply_r[print_index]);
        $display("tb_yolo_v8n_board_start PASS");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "full-network board start timeout ddr=%0d model=%0d image=%0d owner=%0d busy=%0d done=%0d status=%0d rx=%0d",
               dut.ddr_ready_sync_r, dut.model_seen_r, dut.image_seen_r,
               dut.run_owner_r, dut.core_busy_w, dut.run_done_r,
               dut.u_reporter.index_r, received_r);
    end
endmodule
