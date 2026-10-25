`timescale 1ns/1ps

module tb_geometry_frame_scheduler;
    reg clk;
    reg rst_n;
    reg [4:0] mode;
    reg source_valid;
    reg [1:0] source_buffer;
    reg [31:0] source_base;
    wire source_release_valid;
    wire [1:0] source_release_buffer;
    reg target_release_valid;
    reg [1:0] target_release_buffer;
    wire display_valid;
    wire [1:0] display_buffer;
    wire [31:0] display_base;
    reg geometry_ready;
    wire geometry_start;
    wire [31:0] geometry_source_base;
    wire [31:0] geometry_target_base;
    wire [4:0] geometry_mode;
    reg geometry_done;
    reg geometry_error;
    wire overflow_error;

    integer checks;
    integer failures;

    always #5 clk = ~clk;

    edrv32_geometry_frame_scheduler u_scheduler (
        .clk_i(clk), .rst_n_i(rst_n), .mode_i(mode),
        .source_valid_i(source_valid), .source_buffer_i(source_buffer),
        .source_base_i(source_base),
        .source_release_valid_o(source_release_valid),
        .source_release_buffer_o(source_release_buffer),
        .target_release_valid_i(target_release_valid),
        .target_release_buffer_i(target_release_buffer),
        .display_valid_o(display_valid), .display_buffer_o(display_buffer),
        .display_base_o(display_base), .geometry_ready_i(geometry_ready),
        .geometry_start_o(geometry_start),
        .geometry_source_base_o(geometry_source_base),
        .geometry_target_base_o(geometry_target_base),
        .geometry_mode_o(geometry_mode), .geometry_done_i(geometry_done),
        .geometry_error_i(geometry_error),
        .overflow_error_o(overflow_error)
    );

    task automatic check_true;
        input condition;
        input [8*120-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                failures = failures + 1;
                $display("CHECK_FAIL time=%0t %0s", $time, message);
            end
        end
    endtask

    task automatic send_source;
        input [1:0] buffer_i;
        input [31:0] base_i;
        begin
            @(negedge clk);
            source_buffer = buffer_i;
            source_base = base_i;
            source_valid = 1'b1;
            @(negedge clk);
            source_valid = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        mode = 5'd9;
        source_valid = 1'b0;
        source_buffer = 2'b0;
        source_base = 32'b0;
        target_release_valid = 1'b0;
        target_release_buffer = 2'b0;
        geometry_ready = 1'b1;
        geometry_done = 1'b0;
        geometry_error = 1'b0;
        checks = 0;
        failures = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        send_source(2'd0, 32'h0180_0000);
        @(negedge clk);
        check_true(geometry_start, "first source starts geometry");
        check_true(geometry_source_base == 32'h0180_0000,
                   "active source is the first frame");
        check_true(geometry_target_base == 32'h0200_0000,
                   "first target buffer is selected");
        check_true(geometry_mode == 5'd9, "mode is latched at frame start");

        send_source(2'd1, 32'h01a0_0000);
        send_source(2'd2, 32'h01c0_0000);
        check_true(source_release_valid && source_release_buffer == 2'd1,
                   "newest source replaces and releases stale pending frame");

        // Complete active frame while another newest source replaces pending.
        @(negedge clk);
        source_valid = 1'b1;
        source_buffer = 2'd1;
        source_base = 32'h01a0_0000;
        geometry_done = 1'b1;
        @(negedge clk);
        source_valid = 1'b0;
        geometry_done = 1'b0;
        check_true(source_release_valid && source_release_buffer == 2'd0,
                   "active source release has priority on completion");
        check_true(display_valid && display_buffer == 2'd0 &&
                   display_base == 32'h0200_0000,
                   "completed target is offered to display");

        @(negedge clk);
        check_true(source_release_valid && source_release_buffer == 2'd2,
                   "simultaneous stale release is deferred without loss");
        check_true(geometry_start &&
                   geometry_source_base == 32'h01a0_0000,
                   "only the newest pending frame starts next");
        check_true(!overflow_error, "normal latest-frame replacement is safe");

        if (failures == 0)
            $display("GEOMETRY_FRAME_SCHEDULER_PASS checks=%0d", checks);
        else
            $fatal(1, "GEOMETRY_FRAME_SCHEDULER_FAIL checks=%0d failures=%0d",
                   checks, failures);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Geometry frame scheduler timeout");
    end
endmodule
