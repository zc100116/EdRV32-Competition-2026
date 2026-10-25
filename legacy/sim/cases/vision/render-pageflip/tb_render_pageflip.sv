`timescale 1ns/1ps

module tb_render_pageflip;
    localparam [31:0] BASE0 = 32'h0000_1000;
    localparam [31:0] BASE1 = 32'h0000_2000;
    localparam [31:0] BASE2 = 32'h0000_3000;
    localparam [31:0] BASE3 = 32'h0000_4000;
    localparam integer FRAME_BEATS = 16;

    reg clk, rst_n;
    reg display_valid;
    wire display_ready;
    reg [2:0] display_token;
    reg [31:0] display_base;
    wire release_valid;
    wire [2:0] release_token;
    wire active;
    wire [2:0] active_token;
    wire prefill_done;
    wire [31:0] frame_count;
    wire error;
    wire [3:0] arid, rid;
    wire [31:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire [3:0] arqos;
    wire arvalid, arready, rvalid, rready, rlast;
    wire [255:0] rdata, fifo_data;
    wire [1:0] rresp;
    wire fifo_valid;
    reg fifo_ready;
    integer cycle_count, beat_count, frame_index, release_count;
    integer stalled_cycles;
    integer i, j;
    reg [2:0] expected_token [0:3];
    reg [255:0] expected_data [0:3];

    always #5 clk = ~clk;

    edrv32_hdmi_axi_reader_pageflip #(
        .H_ACTIVE(32), .V_ACTIVE(8),
        .BURST_BEATS(4), .PREFILL_BEATS(4),
        .TOKEN_WIDTH(3), .DISPLAY_HANDSHAKE(1)
    ) u_reader (
        .clk_i(clk), .rst_n_i(rst_n),
        .display_valid_i(display_valid),
        .display_ready_o(display_ready),
        .display_buffer_i(display_token),
        .display_base_i(display_base),
        .release_valid_o(release_valid),
        .release_buffer_o(release_token),
        .active_o(active), .active_buffer_o(active_token),
        .prefill_done_o(prefill_done),
        .frame_count_o(frame_count), .error_o(error),
        .m_arid_o(arid), .m_araddr_o(araddr),
        .m_arlen_o(arlen), .m_arsize_o(arsize),
        .m_arburst_o(arburst), .m_arqos_o(arqos),
        .m_arvalid_o(arvalid), .m_arready_i(arready),
        .m_rid_i(rid), .m_rdata_i(rdata),
        .m_rresp_i(rresp), .m_rlast_i(rlast),
        .m_rvalid_i(rvalid), .m_rready_o(rready),
        .fifo_data_o(fifo_data), .fifo_valid_o(fifo_valid),
        .fifo_ready_i(fifo_ready)
    );

    axi256_mem_model #(.WORDS(1024)) u_mem (
        .clk_i(clk), .rst_n_i(rst_n),
        .awid_i(4'd0), .awaddr_i(32'd0),
        .awlen_i(8'd0), .awsize_i(3'd5),
        .awburst_i(2'b01), .awvalid_i(1'b0), .awready_o(),
        .wdata_i(256'd0), .wstrb_i(32'd0),
        .wlast_i(1'b0), .wvalid_i(1'b0), .wready_o(),
        .bid_o(), .bresp_o(), .bvalid_o(), .bready_i(1'b0),
        .arid_i(arid), .araddr_i(araddr),
        .arlen_i(arlen), .arsize_i(arsize),
        .arburst_i(arburst), .arvalid_i(arvalid),
        .arready_o(arready), .rid_o(rid),
        .rdata_o(rdata), .rresp_o(rresp),
        .rlast_o(rlast), .rvalid_o(rvalid),
        .rready_i(rready)
    );

    task automatic send_token;
        input [2:0] token;
        input [31:0] base;
        begin
            @(negedge clk);
            display_token = token;
            display_base = base;
            display_valid = 1'b1;
            do @(posedge clk); while (!display_ready);
            @(negedge clk);
            display_valid = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        display_valid = 1'b0;
        display_token = 3'd0;
        display_base = 32'd0;
        fifo_ready = 1'b1;
        cycle_count = 0;
        beat_count = 0;
        frame_index = 0;
        release_count = 0;
        stalled_cycles = 0;
        expected_token[0] = 3'd0;
        expected_token[1] = 3'd4;
        expected_token[2] = 3'd5;
        expected_token[3] = 3'd6;
        expected_data[0] = {16{16'h001f}};
        expected_data[1] = {16{16'hf800}};
        expected_data[2] = {16{16'h07e0}};
        expected_data[3] = {16{16'hffff}};
        for (i=0; i<1024; i=i+1)
            u_mem.store[i] = 256'd0;
        for (j=0; j<FRAME_BEATS; j=j+1) begin
            u_mem.store[(BASE0 >> 5)+j] = expected_data[0];
            u_mem.store[(BASE1 >> 5)+j] = expected_data[1];
            u_mem.store[(BASE2 >> 5)+j] = expected_data[2];
            u_mem.store[(BASE3 >> 5)+j] = expected_data[3];
        end
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        send_token(3'd0,BASE0);
        send_token(3'd4,BASE1);
        send_token(3'd5,BASE2);
        @(negedge clk);
        if (display_ready)
            $fatal(1,"pageflip queue should be full");
        display_token = 3'd6;
        display_base = BASE3;
        display_valid = 1'b1;
        do begin
            @(posedge clk);
            if (!display_ready)
                stalled_cycles = stalled_cycles + 1;
        end while (!display_ready);
        @(negedge clk);
        display_valid = 1'b0;
        wait(frame_index == 4);
        if (release_count != 3 || stalled_cycles < 1 ||
            !prefill_done || error)
            $fatal(1,"pageflip status releases=%0d stalled=%0d prefill=%b error=%b",
                   release_count,stalled_cycles,prefill_done,error);
        $display("RENDER_PAGEFLIP_PASS frames=%0d releases=%0d stalled=%0d cycles=%0d",
                 frame_index,release_count,stalled_cycles,cycle_count);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;
            if (fifo_valid && fifo_ready) begin
                if (frame_index > 3 || active_token !==
                    expected_token[frame_index] || fifo_data !==
                    expected_data[frame_index])
                    $fatal(1,"frame read mismatch frame=%0d beat=%0d token=%h",
                           frame_index,beat_count,active_token);
                beat_count = beat_count + 1;
                if (beat_count == FRAME_BEATS) begin
                    beat_count = 0;
                    frame_index = frame_index + 1;
                end
            end
            if (release_valid) begin
                if (release_count > 2 || release_token !==
                    expected_token[release_count])
                    $fatal(1,"retired wrong token index=%0d token=%h",
                           release_count,release_token);
                release_count = release_count + 1;
            end
            if (cycle_count > 5000)
                $fatal(1,"pageflip timeout frame=%0d beat=%0d",
                       frame_index,beat_count);
        end
    end
endmodule
