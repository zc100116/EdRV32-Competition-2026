`timescale 1ns/1ps

module tb_hdmi_reset_cdc;
    reg pixel_clk_r;
    reg serial_clk_r;
    reg arst_n_r;
    wire pixel_rst_n_w;
    wire serial_rst_n_w;
    wire tmds_clk_p_w;
    wire tmds_clk_n_w;
    wire [2:0] tmds_data_p_w;
    wire [2:0] tmds_data_n_w;

    integer checks;
    integer failures;
    integer cycle;

    initial pixel_clk_r = 1'b0;
    always #7 pixel_clk_r = ~pixel_clk_r;
    initial serial_clk_r = 1'b0;
    always #1.4 serial_clk_r = ~serial_clk_r;

    task automatic check_true;
        input condition;
        input [8*120-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                failures = failures + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    reset_sync #(.STAGES(2)) u_pixel_reset_sync (
        .clk(pixel_clk_r), .arst_n_i(arst_n_r),
        .rst_n_o(pixel_rst_n_w)
    );

    reset_sync #(.STAGES(2)) u_serial_reset_sync (
        .clk(serial_clk_r), .arst_n_i(arst_n_r),
        .rst_n_o(serial_rst_n_w)
    );

    edrv32_tmds_tx u_tmds_tx (
        .pixel_clk_i(pixel_clk_r), .serial_clk_i(serial_clk_r),
        .pixel_rst_n_i(pixel_rst_n_w),
        .serial_rst_n_i(serial_rst_n_w),
        .rgb_i(24'h12_34_56), .hs_i(1'b0), .vs_i(1'b0), .de_i(1'b1),
        .tmds_clk_p_o(tmds_clk_p_w), .tmds_clk_n_o(tmds_clk_n_w),
        .tmds_data_p_o(tmds_data_p_w), .tmds_data_n_o(tmds_data_n_w)
    );

    initial begin
        checks = 0;
        failures = 0;
        arst_n_r = 1'b0;
        #3;
        check_true(!pixel_rst_n_w && !serial_rst_n_w,
            "both resets assert asynchronously");

        #2.3 arst_n_r = 1'b1;
        fork
            begin
                @(posedge serial_clk_r);
                #0.1;
                check_true(!serial_rst_n_w,
                    "serial reset remains active for synchronizer latency");
            end
            begin
                @(posedge pixel_clk_r);
                #0.1;
                check_true(!pixel_rst_n_w,
                    "pixel reset remains active for synchronizer latency");
            end
        join
        repeat (3) @(posedge pixel_clk_r);
        #0.1;
        check_true(pixel_rst_n_w, "pixel reset releases in pixel domain");
        check_true(serial_rst_n_w, "serial reset releases in serial domain");
        check_true(u_tmds_tx.u_clock_serializer.local_reset_pipe_r == 2'b11 &&
                   u_tmds_tx.u_red_serializer.local_reset_pipe_r == 2'b11 &&
                   u_tmds_tx.u_green_serializer.local_reset_pipe_r == 2'b11 &&
                   u_tmds_tx.u_blue_serializer.local_reset_pipe_r == 2'b11,
            "all four serializer-local reset chains release cleanly");

        for (cycle = 0; cycle < 20; cycle = cycle + 1) begin
            @(posedge pixel_clk_r);
            #0.1;
            check_true((^{tmds_clk_p_w, tmds_clk_n_w,
                tmds_data_p_w, tmds_data_n_w}) !== 1'bx,
                "TMDS outputs contain no unknown values after release");
            check_true(tmds_clk_p_w != tmds_clk_n_w,
                "TMDS clock differential outputs are complementary");
        end

        #2.1 arst_n_r = 1'b0;
        #0.1;
        check_true(!pixel_rst_n_w && !serial_rst_n_w,
            "mid-cycle reset asserts in both domains without a clock edge");
        check_true(u_tmds_tx.u_clock_serializer.local_reset_pipe_r == 2'b00 &&
                   u_tmds_tx.u_red_serializer.local_reset_pipe_r == 2'b00 &&
                   u_tmds_tx.u_green_serializer.local_reset_pipe_r == 2'b00 &&
                   u_tmds_tx.u_blue_serializer.local_reset_pipe_r == 2'b00,
            "all serializer-local reset chains assert asynchronously");
        #3.7 arst_n_r = 1'b1;
        repeat (3) @(posedge pixel_clk_r);
        #0.1;
        check_true(pixel_rst_n_w && serial_rst_n_w,
            "both domains recover after a second asynchronous reset");
        check_true(u_tmds_tx.u_clock_serializer.local_reset_pipe_r == 2'b11 &&
                   u_tmds_tx.u_red_serializer.local_reset_pipe_r == 2'b11 &&
                   u_tmds_tx.u_green_serializer.local_reset_pipe_r == 2'b11 &&
                   u_tmds_tx.u_blue_serializer.local_reset_pipe_r == 2'b11,
            "all serializer-local reset chains recover after reset");

        if (failures == 0)
            $display("HDMI_RESET_CDC_PASS checks=%0d", checks);
        else
            $display("HDMI_RESET_CDC_FAIL checks=%0d failures=%0d",
                checks, failures);
        $finish;
    end

endmodule
