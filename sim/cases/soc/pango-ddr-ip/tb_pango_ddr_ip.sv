// ============================================================================
// File        : tb_pango_ddr_ip.sv
// Description : Direct UI test for the generated Pango DDR controller and the
//               Micron DDR3 component model.  No project AXI RTL is present.
// ============================================================================

`timescale 1ns/1ps

module tb_pango_ddr_ip;

    localparam integer MAX_BEATS = 16;

    reg ref_clk_r;
    reg resetn_r;
    wire core_clk_w;
    wire init_done_w;
    wire init_error_w;

    reg [27:0] awaddr_r;
    reg [3:0] awid_r;
    reg [3:0] awlen_r;
    reg awvalid_r;
    wire awready_w;
    reg [255:0] wdata_r;
    reg [31:0] wstrb_r;
    wire wready_w;
    wire [3:0] wid_w;
    wire wlast_w;

    reg [27:0] araddr_r;
    reg [3:0] arid_r;
    reg [3:0] arlen_r;
    reg arvalid_r;
    wire arready_w;
    wire [255:0] rdata_w;
    wire [3:0] rid_w;
    wire rlast_w;
    wire rvalid_w;

    reg [255:0] expected_r [0:MAX_BEATS-1];
    integer checks_r;
    integer failures_r;
    integer beat_i;
    integer start_cycle_r;
    integer end_cycle_r;
    integer cycle_r;

    always #4 ref_clk_r = ~ref_clk_r;

    // Pango primitive models resolve this exact root-level instance name.
    GTP_GRS GRS_INST (
        .GRS_N(resetn_r)
    );

    always @(posedge core_clk_w)
        cycle_r <= cycle_r + 1;

    function [255:0] pattern;
        input [31:0] tag;
        input integer index;
        integer lane;
        begin
            for (lane = 0; lane < 8; lane = lane + 1)
                pattern[lane*32 +: 32] = tag ^ index ^ (lane * 32'h1020_4081);
        end
    endfunction

    task check_true;
        input condition;
        input [8*120-1:0] message;
        begin
            checks_r = checks_r + 1;
            if (!condition) begin
                failures_r = failures_r + 1;
                $display("CHECK_FAIL %0s", message);
            end
        end
    endtask

    task ui_write;
        input [27:0] word_addr;
        input [3:0] id;
        input integer beats;
        input [31:0] tag;
        integer index;
        begin
            @(posedge core_clk_w);
            awaddr_r <= word_addr;
            awid_r <= id;
            awlen_r <= beats - 1;
            awvalid_r <= 1'b1;
            do @(posedge core_clk_w); while (!awready_w);
            awvalid_r <= 1'b0;

            index = 0;
            wdata_r <= pattern(tag, 0);
            wstrb_r <= 32'hffff_ffff;
            while (index < beats) begin
                @(posedge core_clk_w);
                if (wready_w) begin
                    expected_r[index] = wdata_r;
                    index = index + 1;
                    if (index < beats)
                        wdata_r <= pattern(tag, index);
                end
            end

            while (!wlast_w)
                @(posedge core_clk_w);
            check_true(wid_w == id, "write completion ID");
        end
    endtask

    task ui_read_check;
        input [27:0] word_addr;
        input [3:0] id;
        input integer beats;
        integer index;
        begin
            @(posedge core_clk_w);
            araddr_r <= word_addr;
            arid_r <= id;
            arlen_r <= beats - 1;
            arvalid_r <= 1'b1;
            do @(posedge core_clk_w); while (!arready_w);
            arvalid_r <= 1'b0;

            index = 0;
            start_cycle_r = cycle_r;
            while (index < beats) begin
                @(posedge core_clk_w);
                if (rvalid_w) begin
                    check_true(rid_w == id, "read response ID");
                    check_true(rdata_w === expected_r[index], "read data");
                    check_true(rlast_w == (index == beats - 1), "read last");
                    index = index + 1;
                end
            end
            end_cycle_r = cycle_r;
            $display("PANGO_DDR_IP_READ beats=%0d elapsed_core_cycles=%0d",
                     beats, end_cycle_r - start_cycle_r);
        end
    endtask

    pango_ddr200h_model u_model (
        .ref_clk_i(ref_clk_r), .resetn_i(resetn_r),
        .core_clk_o(core_clk_w), .init_done_o(init_done_w),
        .init_error_o(init_error_w),
        .ui_awaddr_i(awaddr_r), .ui_awid_i(awid_r), .ui_awlen_i(awlen_r),
        .ui_awvalid_i(awvalid_r), .ui_awready_o(awready_w),
        .ui_wdata_i(wdata_r), .ui_wstrb_i(wstrb_r),
        .ui_wready_o(wready_w), .ui_wid_o(wid_w), .ui_wlast_o(wlast_w),
        .ui_araddr_i(araddr_r), .ui_arid_i(arid_r), .ui_arlen_i(arlen_r),
        .ui_arvalid_i(arvalid_r), .ui_arready_o(arready_w),
        .ui_rdata_o(rdata_w), .ui_rid_o(rid_w), .ui_rlast_o(rlast_w),
        .ui_rvalid_o(rvalid_w)
    );

    initial begin
        ref_clk_r = 1'b0;
        resetn_r = 1'b0;
        awaddr_r = 0;
        awid_r = 0;
        awlen_r = 0;
        awvalid_r = 0;
        wdata_r = 0;
        wstrb_r = 0;
        araddr_r = 0;
        arid_r = 0;
        arlen_r = 0;
        arvalid_r = 0;
        checks_r = 0;
        failures_r = 0;
        cycle_r = 0;

        #100 resetn_r = 1'b1;
        wait (init_done_w || init_error_w);
        check_true(init_done_w && !init_error_w, "DDR training");
        $display("PANGO_DDR_IP_TRAINED time_ns=%0t", $time);

        ui_write(28'h000_0100, 4'h3, 1, 32'h1234_0000);
        ui_read_check(28'h000_0100, 4'h3, 1);
        ui_write(28'h000_0200, 4'h5, 8, 32'h5678_0000);
        ui_read_check(28'h000_0200, 4'h5, 8);
        ui_write(28'h000_0400, 4'h9, 16, 32'h9abc_0000);
        ui_read_check(28'h000_0400, 4'h9, 16);

        if (failures_r == 0)
            $display("PANGO_DDR_IP_PASS checks=%0d", checks_r);
        else
            $fatal(1, "PANGO_DDR_IP_FAIL checks=%0d failures=%0d",
                   checks_r, failures_r);
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "Pango DDR IP timeout init_done=%0d init_error=%0d",
               init_done_w, init_error_w);
    end

endmodule
