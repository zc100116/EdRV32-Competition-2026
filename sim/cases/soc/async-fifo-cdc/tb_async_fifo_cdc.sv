// ============================================================================
// File        : tb_async_fifo_cdc.sv
// Description : Directed asynchronous FIFO CDC, backpressure and reset test.
// ============================================================================

`timescale 1ns/1ps

module tb_async_fifo_cdc;

    localparam integer DATA_W = 32;
    localparam integer ADDR_W = 3;

    reg wr_clk_r;
    reg rd_clk_r;
    reg wr_rst_n_r;
    reg rd_rst_n_r;
    reg [DATA_W-1:0] wr_data_r;
    reg wr_valid_r;
    wire wr_ready_w;
    wire [DATA_W-1:0] rd_data_w;
    wire rd_valid_w;
    reg rd_ready_r;

    integer sent_r;
    integer received_r;
    integer target_r;
    integer full_stalls_r;
    integer empty_waits_r;
    integer checks_r;
    integer failures_r;
    reg [31:0] phase_base_r;
    reg [31:0] held_data_r;
    reg held_valid_r;

    always #3.5 wr_clk_r = ~wr_clk_r;
    always #5.5 rd_clk_r = ~rd_clk_r;

    function [31:0] expected_word;
        input [31:0] phase_base;
        input integer index;
        begin
            expected_word = phase_base ^
                            (32'h9e37_79b9 * (index + 1));
        end
    endfunction

    task automatic check_true;
        input condition;
        input [8*120-1:0] message;
        begin
            checks_r = checks_r + 1;
            if (!condition) begin
                failures_r = failures_r + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    task automatic send_phase;
        input integer word_count;
        integer timeout;
        reg write_fire;
        begin
            target_r = word_count;
            timeout = 0;
            while ((sent_r < word_count) && (timeout < 20000)) begin
                @(negedge wr_clk_r);
                if (($urandom % 5) != 0) begin
                    wr_valid_r = 1'b1;
                    wr_data_r = expected_word(phase_base_r, sent_r);
                end else begin
                    wr_valid_r = 1'b0;
                end
                write_fire = wr_valid_r && wr_ready_w;
                @(posedge wr_clk_r);
                if (write_fire)
                    sent_r = sent_r + 1;
                else if (wr_valid_r)
                    full_stalls_r = full_stalls_r + 1;
                timeout = timeout + 1;
            end
            @(negedge wr_clk_r);
            wr_valid_r = 1'b0;
            check_true(sent_r == word_count,
                       "writer did not complete before timeout");

            timeout = 0;
            while ((received_r < word_count) && (timeout < 20000)) begin
                @(posedge rd_clk_r);
                timeout = timeout + 1;
            end
            check_true(received_r == word_count,
                       "reader did not drain before timeout");
        end
    endtask

    edrv32_async_fifo #(
        .DATA_W (DATA_W),
        .ADDR_W (ADDR_W)
    ) dut (
        .wr_clk_i   (wr_clk_r),
        .wr_rst_n_i (wr_rst_n_r),
        .wr_data_i  (wr_data_r),
        .wr_valid_i (wr_valid_r),
        .wr_ready_o (wr_ready_w),
        .rd_clk_i   (rd_clk_r),
        .rd_rst_n_i (rd_rst_n_r),
        .rd_data_o  (rd_data_w),
        .rd_valid_o (rd_valid_w),
        .rd_ready_i (rd_ready_r)
    );

    always @(negedge rd_clk_r or negedge rd_rst_n_r) begin
        if (!rd_rst_n_r)
            rd_ready_r <= 1'b0;
        else
            rd_ready_r <= (($urandom % 4) != 0);
    end

    always @(posedge rd_clk_r or negedge rd_rst_n_r) begin
        if (!rd_rst_n_r) begin
            held_data_r <= 32'b0;
            held_valid_r <= 1'b0;
        end else begin
            if (rd_valid_w && rd_ready_r) begin
                check_true(rd_data_w ===
                           expected_word(phase_base_r, received_r),
                           "FIFO data changed, duplicated or reordered");
                received_r = received_r + 1;
                held_valid_r <= 1'b0;
            end else if (rd_valid_w) begin
                if (held_valid_r)
                    check_true(rd_data_w === held_data_r,
                               "read payload was not stable under backpressure");
                held_data_r <= rd_data_w;
                held_valid_r <= 1'b1;
            end else begin
                held_valid_r <= 1'b0;
                if (rd_ready_r)
                    empty_waits_r = empty_waits_r + 1;
            end
        end
    end

    initial begin
        wr_clk_r = 1'b0;
        rd_clk_r = 1'b0;
        wr_rst_n_r = 1'b0;
        rd_rst_n_r = 1'b0;
        wr_data_r = 32'b0;
        wr_valid_r = 1'b0;
        rd_ready_r = 1'b0;
        sent_r = 0;
        received_r = 0;
        target_r = 0;
        full_stalls_r = 0;
        empty_waits_r = 0;
        checks_r = 0;
        failures_r = 0;
        phase_base_r = 32'h1000_0000;
        held_data_r = 32'b0;
        held_valid_r = 1'b0;

        // The write side starts first. It must safely fill and backpressure
        // while the read-side pointer synchronizer remains in reset.
        #19 wr_rst_n_r = 1'b1;
        fork
            begin
                send_phase(300);
            end
            begin
                #73 rd_rst_n_r = 1'b1;
            end
        join

        check_true(full_stalls_r > 0,
                   "FIFO never applied full backpressure");
        check_true(empty_waits_r > 0,
                   "FIFO never exercised its empty state");

        // Reset only after the FIFO has drained. Assertion is deliberately
        // asynchronous; deassertion is staggered again for both domains.
        #3 wr_rst_n_r = 1'b0;
        rd_rst_n_r = 1'b0;
        wr_valid_r = 1'b0;
        sent_r = 0;
        received_r = 0;
        phase_base_r = 32'h2000_0000;
        #17 rd_rst_n_r = 1'b1;
        #29 wr_rst_n_r = 1'b1;
        send_phase(500);

        repeat (8) @(posedge rd_clk_r);
        if (failures_r == 0)
            $display("ASYNC_FIFO_CDC_PASS checks=%0d full_stalls=%0d empty_waits=%0d",
                     checks_r, full_stalls_r, empty_waits_r);
        else
            $fatal(1, "ASYNC_FIFO_CDC_FAIL checks=%0d failures=%0d",
                   checks_r, failures_r);
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "ASYNC_FIFO_CDC_TIMEOUT");
    end

endmodule
