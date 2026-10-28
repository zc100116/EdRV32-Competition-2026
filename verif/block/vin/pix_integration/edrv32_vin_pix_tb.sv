// File: edrv32_vin_pix_tb.sv
// Spec: vin-testplan v0.2 VI-18; vin 2.5, 5.3; pix 2.6-2.8.
// Description: Camera and memory frames through real VIN and PIX into AXI RAM.
//              Abort an unfinished PIX frame and verify slot reuse and clean recovery.
// Clock domain: clk_mem=125MHz, independent camera pclk.
`timescale 1ns/1ps
module edrv32_vin_pix_tb;
    logic clk_mem = 0;
    logic rst_mem_n = 0;
    logic rst_cam0_n = 0;
    logic rst_cam1_n = 0;
    wire cam0_pclk;
    wire cam0_vsync;
    wire cam0_href;
    wire [7:0] cam0_data;
    wire cam1_pclk;
    wire cam1_vsync;
    wire cam1_href;
    wire [7:0] cam1_data;
    wire p1_urgent;
    wire irq;
    wire pix_irq;
    wire pix_in_valid;
    wire pix_in_ready;
    wire [31:0] pix_in_data;
    wire pix_in_sof;
    wire pix_in_eol;
    wire pix_in_eof;
    wire pix_out_valid;
    wire pix_out_ready;
    wire [31:0] pix_out_data;
    wire pix_out_sof;
    wire pix_out_eol;
    wire pix_out_eof;
    int checker_errors;
    int input_words = 0;
    int output_words = 0;
    bit aborted_frame = 0;
    string directory;
    logic [15:0] image[4][1024];
    logic [15:0] expected[4][1024];
    edrv32_axi256_if axi();
    edrv32_apb_if apb();
    assign apb.pready[15:3] = 0;
    assign apb.pready[0] = 0;
    assign apb.pslverr[15:3] = 0;
    assign apb.pslverr[0] = 0;
    assign apb.prdata[511:96] = 0;
    assign apb.prdata[31:0] = 0;
    always #4 clk_mem = ~clk_mem;

    dvp_camera_model u_cam0 (
        .pclk_o(cam0_pclk),
        .vsync_o(cam0_vsync),
        .href_o(cam0_href),
        .data_o(cam0_data)
    );
    dvp_camera_model u_cam1 (
        .pclk_o(cam1_pclk),
        .vsync_o(cam1_vsync),
        .href_o(cam1_href),
        .data_o(cam1_data)
    );
    edrv32_vin_memory u_memory (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(axi)
    );
    edrv32_axi256_checker u_checker (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(axi),
        .errors_o(checker_errors)
    );
    `include "dut_connections.svh"
    edrv32_pix u_pix (
        .clk_mem_i(clk_mem),
        .rst_mem_n_i(rst_mem_n),

        .pix_in_valid_i(pix_in_valid),
        .pix_in_ready_o(pix_in_ready),
        .pix_in_data_i(pix_in_data),
        .pix_in_sof_i(pix_in_sof),
        .pix_in_eol_i(pix_in_eol),
        .pix_in_eof_i(pix_in_eof),

        .pix_out_valid_o(pix_out_valid),
        .pix_out_ready_i(pix_out_ready),
        .pix_out_data_o(pix_out_data),
        .pix_out_sof_o(pix_out_sof),
        .pix_out_eol_o(pix_out_eol),
        .pix_out_eof_o(pix_out_eof),

        .apb_paddr_i(apb.paddr),
        .apb_psel_i(apb.psel[2]),
        .apb_penable_i(apb.penable),
        .apb_pwrite_i(apb.pwrite),
        .apb_pwdata_i(apb.pwdata),
        .apb_pstrb_i(apb.pstrb),
        .apb_prdata_o(apb.prdata[95:64]),
        .apb_pready_o(apb.pready[2]),
        .apb_pslverr_o(apb.pslverr[2]),

        .irq_o(pix_irq)
    );

    always @(posedge clk_mem) begin
        if (rst_mem_n) begin
            if (pix_in_valid && pix_in_ready) input_words++;
            if (pix_out_valid && pix_out_ready) begin
                output_words++;
                if (aborted_frame && pix_out_eof)
                    $fatal(1, "FAIL VI-18 aborted PIX frame produced EOF t=%0t", $time);
            end
        end
    end

    task automatic equal(input string label_i, input logic [31:0] expected_i,
        input logic [31:0] actual_i);
        if (actual_i !== expected_i)
            $fatal(1, "FAIL VI-18 %s expected=%h actual=%h t=%0t",
                label_i, expected_i, actual_i, $time);
    endtask

    task automatic access(input bit write_i, input int slot_i,
        input logic [11:0] address_i, input logic [31:0] value_i,
        output logic [31:0] read_o);
        @(negedge clk_mem);
        apb.psel = 16'(1 << slot_i);
        apb.paddr = address_i;
        apb.penable = 0;
        apb.pwrite = write_i;
        apb.pwdata = value_i;
        apb.pstrb = 4'hf;
        @(negedge clk_mem);
        apb.penable = 1;
        @(posedge clk_mem);
        equal("APB PREADY", 1, 32'(apb.pready[slot_i]));
        equal("APB PSLVERR", 0, 32'(apb.pslverr[slot_i]));
        read_o = apb.prdata[slot_i*32+:32];
        @(negedge clk_mem);
        apb.psel = 0;
        apb.penable = 0;
    endtask

    task automatic write_reg(input int slot_i, input logic [11:0] address_i,
        input logic [31:0] value_i);
        logic [31:0] unused_value;
        access(1, slot_i, address_i, value_i, unused_value);
    endtask

    task automatic check_reg(input int slot_i, input logic [11:0] address_i,
        input logic [31:0] expected_i);
        logic [31:0] actual;
        access(0, slot_i, address_i, 0, actual);
        equal($sformatf("APB slot%0d addr%03h", slot_i, address_i), expected_i, actual);
    endtask

    task automatic camera(input int frame_i);
        logic [15:0] pixels[];
        pixels = new[1024];
        foreach (pixels[p]) pixels[p] = image[frame_i][p];
        u_cam0.send_frame(64, 16, pixels);
        equal("camera returned idle", 0, 32'(u_cam0.transmitting));
    endtask

    task automatic idle;
        logic [31:0] status;
        do access(0, 1, 12'h008, 0, status); while (!status[1]);
        equal("AXI checker", 0, 32'(checker_errors));
        equal("AW/B drained", 32'(u_memory.aw_count), 32'(u_memory.b_count));
        equal("write queue drained", 0, 32'(u_memory.writes.size()));
        equal("response queue drained", 0, 32'(u_memory.responses.size()));
        equal("read queue drained", 0, 32'(u_memory.reads.size()));
        equal("read beats drained", 0, 32'(u_memory.read_beat));
    endtask

    task automatic completed(input int frame_i, input int slot_i,
        input int source_i, input int frame_id_i, input int count_i);
        logic [31:0] status;
        logic [31:0] address;
        logic [15:0] actual;
        do access(0, 1, 12'h010, 0, status); while (!status[2]);
        idle();
        check_reg(1, 12'h220, 32'(slot_i | (source_i << 2)));
        check_reg(1, 12'h224, 32'(frame_id_i));
        check_reg(1, 12'h02c, 32'(count_i));
        check_reg(1, 12'h014, 0);
        for (int y = 0; y < 16; y++) begin
            for (int x = 0; x < 64; x++) begin
                address = 32'h01000000 + 32'(slot_i*4096+y*128+x*2);
                actual = {u_memory.peek(address+1), u_memory.peek(address)};
                equal($sformatf("DDR frame%0d x%0d y%0d", frame_i, x, y),
                    32'(expected[frame_i][y*64+x]), 32'(actual));
            end
        end
        write_reg(1, 12'h010, 5);
        $display("VI-18 frame%0d src%0d slot%0d PASS t=%0t", frame_i, source_i, slot_i, $time);
    endtask

    initial begin
        logic [15:0] loaded[1024];
        apb.psel = 0;
        apb.penable = 0;
        apb.paddr = 0;
        apb.pwrite = 0;
        apb.pwdata = 0;
        apb.pstrb = 0;
        if (!$value$plusargs("DIR=%s", directory)) $fatal(1, "FAIL VI-18 missing DIR");
        for (int f = 0; f < 4; f++) begin
            $readmemh($sformatf("%s/in%0d.hex", directory, f), loaded);
            foreach (loaded[p]) image[f][p] = loaded[p];
            $readmemh($sformatf("%s/out%0d.hex", directory, f), loaded);
            foreach (loaded[p]) expected[f][p] = loaded[p];
        end
        repeat (20) @(negedge clk_mem);
        rst_mem_n = 1;
        @(negedge cam0_pclk);
        rst_cam0_n = 1;
        @(negedge cam1_pclk);
        rst_cam1_n = 1;
        write_reg(2, 12'h100, 32'h00060420); // Gaussian, Sobel, BIN then INV.
        write_reg(2, 12'h004, 1);
        write_reg(1, 12'h100, 32'h00100040);
        write_reg(1, 12'h200, 32'h31);
        write_reg(1, 12'h204, 128);
        for (int s = 0; s < 3; s++)
            write_reg(1, 12'('h208+s*4), 32'h01000000+32'(s*4096));
        write_reg(1, 12'h00c, 7);
        write_reg(1, 12'h004, 1);
        camera(0);
        camera(0); // VIN discards the first two complete camera frames.
        camera(0);
        completed(0, 0, 0, 0, 1);
        check_reg(2, 12'h02c, 1);

        write_reg(1, 12'h200, 32'h35);
        for (int y = 0; y < 16; y++) begin
            for (int x = 0; x < 64; x++)
                u_memory.poke16(32'h03000000+32'(y*160+x*2), image[1][y*64+x]);
        end
        write_reg(1, 12'h110, 32'h03000000);
        write_reg(1, 12'h114, 160);
        write_reg(1, 12'h118, 32'h00100040);
        write_reg(1, 12'h11c, 1);
        completed(1, 1, 2, 0, 2);
        check_reg(2, 12'h02c, 2);
        check_reg(2, 12'h04c, 0);

        write_reg(1, 12'h200, 32'h31);
        input_words = 0;
        output_words = 0;
        fork
            camera(2);
            begin
                wait (input_words >= 96);
                check_reg(2, 12'h008, 1); // PIX holds an unfinished input frame.
                equal("PIX partial output", 1, 32'(output_words < 512));
                aborted_frame = 1;
                write_reg(1, 12'h004, 5);
            end
        join
        idle();
        check_reg(1, 12'h02c, 2);
        check_reg(1, 12'h010, 0);
        check_reg(1, 12'h220, 9); // Last completed frame remains the memory frame, slot 1.
        check_reg(2, 12'h04c, 0); // Discard happens when the next SOF appears.
        aborted_frame = 0;
        camera(3);
        completed(3, 2, 0, 2, 3); // Aborted slot 2 is reused.
        check_reg(2, 12'h04c, 1);
        check_reg(2, 12'h02c, 3);
        $display("PASS VI-18 camera, memory, ABORT and recovery with real PIX");
        $finish;
    end

    initial begin
        #10000000;
        $fatal(1, "FAIL VI-18 timeout t=%0t", $time);
    end
endmodule
