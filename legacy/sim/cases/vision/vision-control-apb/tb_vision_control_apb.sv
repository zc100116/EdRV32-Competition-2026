`timescale 1ns/1ps

`include "edrv32_soc_map.vh"

module tb_vision_control_apb;
    reg clk_r;
    reg rst_n_r;
    reg [31:0] paddr_r;
    reg cam_psel_r;
    reg disp_psel_r;
    reg penable_r;
    reg pwrite_r;
    reg [31:0] pwdata_r;
    reg [3:0] pstrb_r;

    reg cam0_init_done_r;
    reg cam1_init_done_r;
    reg cam_error_r;
    reg [31:0] cam0_frames_r;
    reg [31:0] cam1_frames_r;
    reg cfg_ack_toggle_r;
    reg cfg_response_error_r;
    reg [7:0] cfg_response_data_r;
    wire cam0_enable_w;
    wire cam1_enable_w;
    wire cfg_req_toggle_w;
    wire cfg_camera_w;
    wire cfg_read_w;
    wire [15:0] cfg_reg_addr_w;
    wire [7:0] cfg_write_data_w;
    wire cam_irq_w;
    wire cam_pready_w;
    wire [31:0] cam_prdata_w;
    wire cam_pslverr_w;

    reg [1:0] active_buffer_r;
    reg disp_error_r;
    reg [31:0] disp_frames_r;
    reg [31:0] underflows_r;
    wire disp_enable_w;
    wire disp_irq_w;
    wire disp_pready_w;
    wire [31:0] disp_prdata_w;
    wire disp_pslverr_w;

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

    task automatic apb_write_cam;
        input [7:0] offset;
        input [31:0] value;
        input expect_error;
        begin
            @(negedge clk_r);
            paddr_r = {24'b0, offset};
            pwdata_r = value;
            pstrb_r = 4'hf;
            pwrite_r = 1'b1;
            cam_psel_r = 1'b1;
            penable_r = 1'b0;
            @(negedge clk_r);
            penable_r = 1'b1;
            @(posedge clk_r);
            #1;
            check_true(cam_pready_w, "CAM APB write completes");
            check_true(cam_pslverr_w == expect_error,
                "CAM APB write error response");
            @(negedge clk_r);
            cam_psel_r = 1'b0;
            penable_r = 1'b0;
            pwrite_r = 1'b0;
        end
    endtask

    task automatic apb_read_cam;
        input [7:0] offset;
        output [31:0] value;
        begin
            @(negedge clk_r);
            paddr_r = {24'b0, offset};
            pwrite_r = 1'b0;
            cam_psel_r = 1'b1;
            penable_r = 1'b0;
            @(negedge clk_r);
            penable_r = 1'b1;
            @(posedge clk_r);
            #1;
            value = cam_prdata_w;
            check_true(cam_pready_w && !cam_pslverr_w,
                "CAM APB read completes without error");
            @(negedge clk_r);
            cam_psel_r = 1'b0;
            penable_r = 1'b0;
        end
    endtask

    task automatic apb_write_disp;
        input [7:0] offset;
        input [31:0] value;
        input expect_error;
        begin
            @(negedge clk_r);
            paddr_r = {24'b0, offset};
            pwdata_r = value;
            pstrb_r = 4'hf;
            pwrite_r = 1'b1;
            disp_psel_r = 1'b1;
            penable_r = 1'b0;
            @(negedge clk_r);
            penable_r = 1'b1;
            @(posedge clk_r);
            #1;
            check_true(disp_pready_w, "DISP APB write completes");
            check_true(disp_pslverr_w == expect_error,
                "DISP APB write error response");
            @(negedge clk_r);
            disp_psel_r = 1'b0;
            penable_r = 1'b0;
            pwrite_r = 1'b0;
        end
    endtask

    task automatic apb_read_disp;
        input [7:0] offset;
        output [31:0] value;
        begin
            @(negedge clk_r);
            paddr_r = {24'b0, offset};
            pwrite_r = 1'b0;
            disp_psel_r = 1'b1;
            penable_r = 1'b0;
            @(negedge clk_r);
            penable_r = 1'b1;
            @(posedge clk_r);
            #1;
            value = disp_prdata_w;
            check_true(disp_pready_w && !disp_pslverr_w,
                "DISP APB read completes without error");
            @(negedge clk_r);
            disp_psel_r = 1'b0;
            penable_r = 1'b0;
        end
    endtask

    edrv32_cam_apb u_cam (
        .clk_i(clk_r), .rst_n_i(rst_n_r),
        .paddr_i(paddr_r), .psel_i(cam_psel_r), .penable_i(penable_r),
        .pwrite_i(pwrite_r), .pwdata_i(pwdata_r), .pstrb_i(pstrb_r),
        .pready_o(cam_pready_w), .prdata_o(cam_prdata_w),
        .pslverr_o(cam_pslverr_w),
        .cam0_init_done_i(cam0_init_done_r),
        .cam1_init_done_i(cam1_init_done_r),
        .error_i(cam_error_r),
        .cam0_frame_count_i(cam0_frames_r),
        .cam1_frame_count_i(cam1_frames_r),
        .cfg_ack_toggle_i(cfg_ack_toggle_r),
        .cfg_response_error_i(cfg_response_error_r),
        .cfg_response_data_i(cfg_response_data_r),
        .cam0_enable_o(cam0_enable_w), .cam1_enable_o(cam1_enable_w),
        .cfg_req_toggle_o(cfg_req_toggle_w),
        .cfg_camera_o(cfg_camera_w),
        .cfg_read_o(cfg_read_w),
        .cfg_reg_addr_o(cfg_reg_addr_w),
        .cfg_write_data_o(cfg_write_data_w),
        .irq_o(cam_irq_w)
    );

    edrv32_disp_apb u_disp (
        .clk_i(clk_r), .rst_n_i(rst_n_r),
        .paddr_i(paddr_r), .psel_i(disp_psel_r), .penable_i(penable_r),
        .pwrite_i(pwrite_r), .pwdata_i(pwdata_r), .pstrb_i(pstrb_r),
        .pready_o(disp_pready_w), .prdata_o(disp_prdata_w),
        .pslverr_o(disp_pslverr_w), .active_buffer_i(active_buffer_r),
        .error_i(disp_error_r), .frame_count_i(disp_frames_r),
        .underflow_count_i(underflows_r),
        .scanout_frame_count_i(32'd7),
        .debug_status_i(7'h7f),
        .buffer0_base_i(32'h0180_0000),
        .buffer1_base_i(32'h01a0_0000),
        .buffer2_base_i(32'h01c0_0000),
        .enable_o(disp_enable_w), .irq_o(disp_irq_w)
    );

    initial begin
        checks = 0;
        failures = 0;
        rst_n_r = 1'b0;
        paddr_r = 32'b0;
        cam_psel_r = 1'b0;
        disp_psel_r = 1'b0;
        penable_r = 1'b0;
        pwrite_r = 1'b0;
        pwdata_r = 32'b0;
        pstrb_r = 4'hf;
        cam0_init_done_r = 1'b0;
        cam1_init_done_r = 1'b0;
        cam_error_r = 1'b0;
        cam0_frames_r = 32'b0;
        cam1_frames_r = 32'b0;
        cfg_ack_toggle_r = 1'b0;
        cfg_response_error_r = 1'b0;
        cfg_response_data_r = 8'b0;
        active_buffer_r = 2'b0;
        disp_error_r = 1'b0;
        disp_frames_r = 32'b0;
        underflows_r = 32'b0;

        repeat (4) @(posedge clk_r);
        rst_n_r = 1'b1;
        repeat (2) @(posedge clk_r);

        check_true(cam0_enable_w && cam1_enable_w,
            "both cameras enabled after reset");
        apb_read_cam(`CAM_ID, read_value_r);
        check_true(read_value_r == 32'h4341_4d30, "CAM ID");
        apb_write_cam(`CAM_CONTROL, 32'h0000_0002, 1'b0);
        check_true(!cam0_enable_w && cam1_enable_w,
            "CAM channel enable outputs");

        apb_write_cam(`CAM_IRQ_ENABLE, 32'h1f, 1'b0);
        cam0_frames_r = 32'd1;
        @(posedge clk_r);
        #1;
        check_true(cam_irq_w, "CAM frame event raises IRQ");
        apb_read_cam(`CAM_IRQ_STATUS, read_value_r);
        check_true(read_value_r[0], "CAM frame0 pending is sticky");
        apb_write_cam(`CAM_IRQ_STATUS, 32'h1, 1'b0);
        check_true(!cam_irq_w, "CAM W1C clears IRQ");
        apb_write_cam(`CAM_STATUS, 32'h0, 1'b1);

        apb_write_cam(`CAM_SCCB_TARGET, 32'h1, 1'b0);
        apb_write_cam(`CAM_SCCB_REG_ADDR, 32'h0000_3821, 1'b0);
        apb_write_cam(`CAM_SCCB_WRITE_DATA, 32'h0000_0006, 1'b0);
        apb_write_cam(`CAM_SCCB_COMMAND, 32'h1, 1'b0);
        apb_read_cam(`CAM_IRQ_STATUS, read_value_r);
        check_true(read_value_r[`CAM_IRQ_SCCB_ERROR],
            "SCCB submit before initialization reports error");
        apb_write_cam(`CAM_IRQ_STATUS, 32'h1f, 1'b0);

        cam0_init_done_r = 1'b1;
        cam1_init_done_r = 1'b1;
        repeat (2) @(posedge clk_r);
        apb_write_cam(`CAM_SCCB_COMMAND, 32'h1, 1'b0);
        check_true(cfg_req_toggle_w, "SCCB accepted request toggles token");
        check_true(cfg_camera_w && cfg_reg_addr_w == 16'h3821 &&
                   cfg_write_data_w == 8'h06,
            "SCCB accepted request holds bundled payload");
        apb_read_cam(`CAM_SCCB_STATUS, read_value_r);
        check_true(read_value_r[`CAM_SCCB_STATUS_BUSY],
            "SCCB request remains busy until acknowledgement");
        apb_write_cam(`CAM_SCCB_COMMAND, 32'h1, 1'b0);
        cfg_ack_toggle_r = cfg_req_toggle_w;
        repeat (4) @(posedge clk_r);
        apb_read_cam(`CAM_SCCB_STATUS, read_value_r);
        check_true(!read_value_r[`CAM_SCCB_STATUS_BUSY] &&
                   read_value_r[`CAM_SCCB_STATUS_DONE] &&
                   read_value_r[`CAM_SCCB_STATUS_READY],
            "SCCB acknowledgement completes request");
        apb_read_cam(`CAM_IRQ_STATUS, read_value_r);
        check_true(read_value_r[`CAM_IRQ_SCCB_DONE] &&
                   read_value_r[`CAM_IRQ_SCCB_ERROR],
            "SCCB completion and rejected-busy events are sticky");
        apb_write_cam(`CAM_IRQ_STATUS, 32'h18, 1'b0);

        apb_write_cam(`CAM_SCCB_TARGET, 32'h0, 1'b0);
        apb_write_cam(`CAM_SCCB_REG_ADDR, 32'h0000_300a, 1'b0);
        apb_write_cam(`CAM_SCCB_COMMAND, 32'h3, 1'b0);
        check_true(cfg_read_w && !cfg_camera_w &&
                   cfg_reg_addr_w == 16'h300a,
            "SCCB read command holds operation and address");
        cfg_response_data_r = 8'h56;
        cfg_ack_toggle_r = cfg_req_toggle_w;
        repeat (4) @(posedge clk_r);
        apb_read_cam(`CAM_SCCB_READ_DATA, read_value_r);
        check_true(read_value_r[7:0] == 8'h56,
            "SCCB read response crosses into APB domain");
        apb_write_cam(`CAM_IRQ_STATUS, 32'h18, 1'b0);

        apb_write_cam(`CAM_SCCB_COMMAND, 32'h1, 1'b0);
        cfg_response_error_r = 1'b1;
        cfg_ack_toggle_r = cfg_req_toggle_w;
        repeat (4) @(posedge clk_r);
        apb_read_cam(`CAM_SCCB_STATUS, read_value_r);
        check_true(read_value_r[`CAM_SCCB_STATUS_ERROR],
            "SCCB bus-error response raises sticky error");
        cfg_response_error_r = 1'b0;
        apb_write_cam(`CAM_IRQ_STATUS, 32'h18, 1'b0);

        check_true(disp_enable_w, "display enabled after reset");
        apb_read_disp(`DISP_BUFFER2_BASE, read_value_r);
        check_true(read_value_r == 32'h01c0_0000,
            "DISP buffer2 address");
        apb_read_disp(`DISP_SCANOUT_FRAME_COUNT, read_value_r);
        check_true(read_value_r == 32'd7, "DISP scanout frame counter");
        apb_read_disp(`DISP_DEBUG_STATUS, read_value_r);
        check_true(read_value_r[6:0] == 7'h7f,
            "DISP clock/reset/FIFO debug status");
        apb_write_disp(`DISP_IRQ_ENABLE, 32'h7, 1'b0);
        underflows_r = 32'd1;
        @(posedge clk_r);
        #1;
        check_true(disp_irq_w, "DISP underflow raises IRQ");
        apb_read_disp(`DISP_IRQ_STATUS, read_value_r);
        check_true(read_value_r[1], "DISP underflow pending is sticky");
        apb_write_disp(`DISP_IRQ_STATUS, 32'h2, 1'b0);
        check_true(!disp_irq_w, "DISP W1C clears IRQ");
        apb_write_disp(`DISP_CONTROL, 32'h0, 1'b0);
        check_true(!disp_enable_w, "DISP control disables scanout");
        apb_write_disp(`DISP_BUFFER0_BASE, 32'h0, 1'b1);

        if (failures == 0)
            $display("VISION_CONTROL_APB_PASS checks=%0d", checks);
        else
            $display("VISION_CONTROL_APB_FAIL checks=%0d failures=%0d",
                checks, failures);
        $finish;
    end

endmodule
