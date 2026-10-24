`timescale 1ns/1ps

module tb_ov5640_sccb;
    localparam [7:0] READ_VALUE = 8'ha5;

    reg clk_r;
    reg rst_n_r;
    reg start_r;
    reg read_r;
    reg [15:0] reg_addr_r;
    reg [7:0] write_data_r;
    reg dc_response_low_r;
    reg force_bus_low_r;
    wire sda_i_w;
    wire busy_w;
    wire done_w;
    wire bus_error_w;
    wire [7:0] read_data_w;
    wire scl_w;
    wire sda_drive_low_w;

    integer checks;
    integer failures;
    integer timeout_cycles;

    initial clk_r = 1'b0;
    always #5 clk_r = ~clk_r;

    wire dont_care_state_w = u_dut.state_r == 4'd3;
    wire read_state_w = u_dut.state_r == 4'd5;
    wire modeled_read_bit_w = READ_VALUE[u_dut.bit_index_r];
    assign sda_i_w = force_bus_low_r ? 1'b0 :
        (dont_care_state_w && dc_response_low_r ? 1'b0 :
        (read_state_w ? modeled_read_bit_w : 1'b1));

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

    task automatic launch;
        input is_read;
        input [15:0] address;
        input [7:0] data;
        begin
            @(negedge clk_r);
            read_r = is_read;
            reg_addr_r = address;
            write_data_r = data;
            start_r = 1'b1;
            @(negedge clk_r);
            start_r = 1'b0;
        end
    endtask

    task automatic wait_done;
        begin
            timeout_cycles = 0;
            while (!done_w && timeout_cycles < 10000) begin
                @(posedge clk_r);
                timeout_cycles = timeout_cycles + 1;
            end
            check_true(done_w, "SCCB transaction completes");
            @(posedge clk_r);
        end
    endtask

    edrv32_ov5640_sccb #(
        .CLK_HZ(8000000), .SCCB_HZ(1000000), .DIVIDER(8)
    ) u_dut (
        .clk_i(clk_r), .rst_n_i(rst_n_r), .start_i(start_r),
        .read_i(read_r), .reg_addr_i(reg_addr_r),
        .write_data_i(write_data_r), .sda_i(sda_i_w),
        .busy_o(busy_w), .done_o(done_w), .bus_error_o(bus_error_w),
        .read_data_o(read_data_w), .scl_o(scl_w),
        .sda_drive_low_o(sda_drive_low_w)
    );

    initial begin
        checks = 0;
        failures = 0;
        rst_n_r = 1'b0;
        start_r = 1'b0;
        read_r = 1'b0;
        reg_addr_r = 16'b0;
        write_data_r = 8'b0;
        dc_response_low_r = 1'b1;
        force_bus_low_r = 1'b0;

        repeat (4) @(posedge clk_r);
        rst_n_r = 1'b1;
        repeat (2) @(posedge clk_r);

        launch(1'b0, 16'h503d, 8'h80);
        wait_done();
        check_true(!bus_error_w,
            "write accepts a slave-driven-low Don't-Care bit");
        check_true(!busy_w && !sda_drive_low_w && scl_w,
            "write returns bus to released idle state");

        dc_response_low_r = 1'b0;
        launch(1'b0, 16'h3821, 8'h07);
        wait_done();
        check_true(!bus_error_w,
            "floating-high Don't-Care bit is not treated as NACK");

        force_bus_low_r = 1'b1;
        launch(1'b0, 16'h3821, 8'h01);
        wait_done();
        check_true(bus_error_w, "stuck-low SDA is reported as a bus error");
        force_bus_low_r = 1'b0;
        dc_response_low_r = 1'b1;

        launch(1'b1, 16'h300a, 8'h00);
        wait_done();
        check_true(!bus_error_w, "read completes without a bus error");
        check_true(read_data_w == READ_VALUE,
            "read samples eight sensor data bits");

        if (failures == 0)
            $display("OV5640_SCCB_PASS checks=%0d", checks);
        else
            $display("OV5640_SCCB_FAIL checks=%0d failures=%0d",
                checks, failures);
        $finish;
    end

endmodule
