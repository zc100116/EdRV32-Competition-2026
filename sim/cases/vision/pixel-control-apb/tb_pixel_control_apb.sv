`timescale 1ns/1ps

`include "edrv32_soc_map.vh"

module tb_pixel_control_apb;
    reg clk_r;
    reg rst_n_r;
    reg [31:0] paddr_r;
    reg psel_r;
    reg penable_r;
    reg pwrite_r;
    reg [31:0] pwdata_r;
    reg [3:0] pstrb_r;
    wire pready_w;
    wire [31:0] prdata_w;
    wire pslverr_w;

    reg cfg_ack_toggle_r;
    reg [31:0] frame_count_r;
    reg [31:0] error_count_r;
    wire cfg_req_toggle_w;
    wire cfg_enable_w;
    wire cfg_grayscale_w;
    wire cfg_threshold_enable_w;
    wire cfg_invert_w;
    wire signed [8:0] cfg_brightness_w;
    wire [8:0] cfg_contrast_w;
    wire [7:0] cfg_threshold_w;
    wire cfg_spatial_enable_w;
    wire [2:0] cfg_spatial_mode_w;
    wire [7:0] cfg_spatial_threshold_w;
    wire irq_w;

    integer checks;
    integer failures;
    reg [31:0] read_value_r;

    initial clk_r = 1'b0;
    always #5 clk_r = ~clk_r;

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

    task automatic apb_write;
        input [7:0] offset;
        input [31:0] value;
        input [3:0] strobe;
        input expect_error;
        begin
            @(negedge clk_r);
            paddr_r = {24'b0, offset};
            pwdata_r = value;
            pstrb_r = strobe;
            pwrite_r = 1'b1;
            psel_r = 1'b1;
            penable_r = 1'b0;
            @(negedge clk_r);
            penable_r = 1'b1;
            @(posedge clk_r);
            #1;
            check_true(pready_w, "PIXEL APB write completes");
            check_true(pslverr_w == expect_error,
                "PIXEL APB write error response");
            @(negedge clk_r);
            psel_r = 1'b0;
            penable_r = 1'b0;
            pwrite_r = 1'b0;
        end
    endtask

    task automatic apb_read;
        input [7:0] offset;
        output [31:0] value;
        begin
            @(negedge clk_r);
            paddr_r = {24'b0, offset};
            pwrite_r = 1'b0;
            psel_r = 1'b1;
            penable_r = 1'b0;
            @(negedge clk_r);
            penable_r = 1'b1;
            @(posedge clk_r);
            #1;
            value = prdata_w;
            check_true(pready_w && !pslverr_w,
                "PIXEL APB read completes without error");
            @(negedge clk_r);
            psel_r = 1'b0;
            penable_r = 1'b0;
        end
    endtask

    edrv32_pixel_apb u_dut (
        .clk_i(clk_r), .rst_n_i(rst_n_r),
        .paddr_i(paddr_r), .psel_i(psel_r), .penable_i(penable_r),
        .pwrite_i(pwrite_r), .pwdata_i(pwdata_r), .pstrb_i(pstrb_r),
        .pready_o(pready_w), .prdata_o(prdata_w),
        .pslverr_o(pslverr_w),
        .cfg_ack_toggle_i(cfg_ack_toggle_r),
        .frame_count_i(frame_count_r), .error_count_i(error_count_r),
        .cfg_req_toggle_o(cfg_req_toggle_w), .cfg_enable_o(cfg_enable_w),
        .cfg_grayscale_o(cfg_grayscale_w),
        .cfg_threshold_enable_o(cfg_threshold_enable_w),
        .cfg_invert_o(cfg_invert_w),
        .cfg_brightness_o(cfg_brightness_w),
        .cfg_contrast_o(cfg_contrast_w),
        .cfg_threshold_o(cfg_threshold_w),
        .cfg_spatial_enable_o(cfg_spatial_enable_w),
        .cfg_spatial_mode_o(cfg_spatial_mode_w),
        .cfg_spatial_threshold_o(cfg_spatial_threshold_w),
        .irq_o(irq_w)
    );

    initial begin
        checks = 0;
        failures = 0;
        rst_n_r = 1'b0;
        paddr_r = 32'b0;
        psel_r = 1'b0;
        penable_r = 1'b0;
        pwrite_r = 1'b0;
        pwdata_r = 32'b0;
        pstrb_r = 4'hf;
        cfg_ack_toggle_r = 1'b0;
        frame_count_r = 32'b0;
        error_count_r = 32'b0;

        repeat (4) @(posedge clk_r);
        rst_n_r = 1'b1;
        repeat (2) @(posedge clk_r);

        apb_read(`PIXEL_ID, read_value_r);
        check_true(read_value_r == 32'h5049_584c, "PIXEL ID");
        apb_read(`PIXEL_CAPABILITY, read_value_r);
        check_true(read_value_r == 32'h0000_003f, "PIXEL capabilities");

        apb_write(`PIXEL_CONTROL, 32'h0000_000f, 4'hf, 1'b0);
        apb_write(`PIXEL_BRIGHTNESS, 32'hffff_ffe0, 4'hf, 1'b0);
        apb_write(`PIXEL_CONTRAST, 32'd320, 4'hf, 1'b0);
        apb_write(`PIXEL_THRESHOLD, 32'd100, 4'h1, 1'b0);
        apb_write(`PIXEL_SPATIAL_CONTROL, 32'h0000_0007, 4'h1, 1'b0);
        apb_write(`PIXEL_SPATIAL_THRESHOLD, 32'd96, 4'h1, 1'b0);
        apb_write(`PIXEL_COMMAND, 32'h1, 4'h1, 1'b0);
        check_true(cfg_req_toggle_w, "PIXEL commit toggles request");
        check_true(cfg_enable_w && cfg_grayscale_w &&
                   cfg_threshold_enable_w && cfg_invert_w,
            "PIXEL commit latches control transfer payload");
        check_true(cfg_brightness_w == -9'sd32 &&
                   cfg_contrast_w == 9'd320 && cfg_threshold_w == 8'd100,
            "PIXEL commit latches numeric transfer payload");
        check_true(cfg_spatial_enable_w &&
                   cfg_spatial_mode_w == `PIXEL_SPATIAL_GAUSSIAN &&
                   cfg_spatial_threshold_w == 8'd96,
            "PIXEL commit latches spatial-filter payload");
        apb_read(`PIXEL_STATUS, read_value_r);
        check_true(read_value_r[`PIXEL_STATUS_PENDING],
            "PIXEL remains busy until datapath acknowledge");

        apb_write(`PIXEL_IRQ_ENABLE, 32'h7, 4'hf, 1'b0);
        @(negedge clk_r);
        cfg_ack_toggle_r = cfg_req_toggle_w;
        repeat (4) @(posedge clk_r);
        check_true(irq_w, "PIXEL commit completion raises IRQ");
        apb_read(`PIXEL_IRQ_STATUS, read_value_r);
        check_true(read_value_r[2], "PIXEL commit IRQ is sticky");
        apb_write(`PIXEL_IRQ_STATUS, 32'h4, 4'hf, 1'b0);

        @(negedge clk_r);
        frame_count_r = 32'd1;
        error_count_r = 32'd1;
        repeat (2) @(posedge clk_r);
        apb_read(`PIXEL_IRQ_STATUS, read_value_r);
        check_true(read_value_r[1:0] == 2'b11,
            "PIXEL frame and error events are sticky");
        apb_write(`PIXEL_IRQ_STATUS, 32'h3, 4'hf, 1'b0);
        check_true(!irq_w, "PIXEL W1C clears pending IRQs");

        apb_write(`PIXEL_STATUS, 32'b0, 4'hf, 1'b1);
        apb_write(8'h3c, 32'b0, 4'hf, 1'b1);

        if (failures == 0)
            $display("PIXEL_CONTROL_APB_PASS checks=%0d", checks);
        else
            $display("PIXEL_CONTROL_APB_FAIL checks=%0d failures=%0d",
                checks, failures);
        $finish;
    end

endmodule
