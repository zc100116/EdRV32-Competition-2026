`timescale 1ns/1ps

module tb_display_axi_writer;

    reg clk_i = 1'b0;
    always #5 clk_i = !clk_i;
    reg rst_n_i = 1'b0;
    reg [257:0] stream_data_i = 258'b0;
    reg stream_valid_i = 1'b0;
    wire stream_ready_o;
    wire completed_valid_o;
    wire [1:0] completed_buffer_o;
    wire [31:0] completed_base_o;
    wire [31:0] frame_count_o;
    wire [31:0] dropped_frame_count_o;
    wire active_o;
    wire error_o;
    wire [3:0] m_awid_o;
    wire [31:0] m_awaddr_o;
    wire [7:0] m_awlen_o;
    wire [2:0] m_awsize_o;
    wire [1:0] m_awburst_o;
    wire [3:0] m_awqos_o;
    wire m_awvalid_o;
    wire [255:0] m_wdata_o;
    wire [31:0] m_wstrb_o;
    wire m_wlast_o;
    wire m_wvalid_o;
    reg m_wready_i = 1'b1;
    wire m_bready_o;
    reg m_bvalid_i = 1'b0;
    integer aw_count_r = 0;
    integer w_count_r = 0;
    integer completed_count_r = 0;
    integer checks_r = 0;

    edrv32_display_axi_writer #(
        .H_ACTIVE(32), .V_ACTIVE(2), .BURST_BEATS(2),
        .FRAME_BASE0(32'h00001000),
        .FRAME_BASE1(32'h00002000),
        .FRAME_BASE2(32'h00003000)
    ) dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .stream_data_i(stream_data_i),
        .stream_valid_i(stream_valid_i),
        .stream_ready_o(stream_ready_o),
        .release_valid_i(1'b0), .release_buffer_i(2'b0),
        .completed_valid_o(completed_valid_o),
        .completed_buffer_o(completed_buffer_o),
        .completed_base_o(completed_base_o),
        .frame_count_o(frame_count_o),
        .dropped_frame_count_o(dropped_frame_count_o),
        .active_o(active_o), .error_o(error_o),
        .m_awid_o(m_awid_o), .m_awaddr_o(m_awaddr_o),
        .m_awlen_o(m_awlen_o), .m_awsize_o(m_awsize_o),
        .m_awburst_o(m_awburst_o), .m_awqos_o(m_awqos_o),
        .m_awvalid_o(m_awvalid_o), .m_awready_i(1'b1),
        .m_wdata_o(m_wdata_o), .m_wstrb_o(m_wstrb_o),
        .m_wlast_o(m_wlast_o), .m_wvalid_o(m_wvalid_o),
        .m_wready_i(m_wready_i), .m_bid_i(4'b0),
        .m_bresp_i(2'b0), .m_bvalid_i(m_bvalid_i),
        .m_bready_o(m_bready_o)
    );

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            m_bvalid_i <= 1'b0;
        end else begin
            if (m_wvalid_o && m_wready_i && m_wlast_o)
                m_bvalid_i <= 1'b1;
            else if (m_bvalid_i && m_bready_o)
                m_bvalid_i <= 1'b0;
        end
    end

    always @(posedge clk_i) begin
        if (rst_n_i) begin
            if (m_awvalid_o) begin
                checks_r = checks_r + 1;
                if (m_awlen_o !== 8'd1 ||
                    m_awaddr_o !== (32'h00001000 + aw_count_r * 64))
                    $fatal(1, "AW not a staged two-beat burst");
                aw_count_r = aw_count_r + 1;
            end
            if (m_wvalid_o && m_wready_i) begin
                checks_r = checks_r + 1;
                if (m_wdata_o[31:0] !== (32'h12340000 + w_count_r) ||
                    m_wlast_o !== w_count_r[0] || stream_valid_i)
                    $fatal(1, "W beat not replayed contiguously from buffer");
                w_count_r = w_count_r + 1;
            end
            if (completed_valid_o)
                completed_count_r = completed_count_r + 1;
        end
    end

    task send_word;
        input integer index_i;
        begin
            @(negedge clk_i);
            stream_data_i = {index_i == 0, index_i == 3,
                224'b0, (32'h12340000 + index_i)};
            stream_valid_i = 1'b1;
            do @(posedge clk_i);
            while (!stream_ready_o);
            @(negedge clk_i);
            stream_valid_i = 1'b0;
        end
    endtask

    initial begin
        repeat (4) @(negedge clk_i);
        rst_n_i = 1'b1;
        send_word(0);
        repeat (10) @(negedge clk_i);
        if (aw_count_r != 0)
            $fatal(1, "AW issued before complete burst was staged");
        checks_r = checks_r + 1;
        send_word(1);
        wait (w_count_r == 2);
        send_word(2);
        send_word(3);
        wait (completed_count_r == 1);
        if (error_o || frame_count_o != 1 ||
            dropped_frame_count_o != 0 || aw_count_r != 2 ||
            w_count_r != 4)
            $fatal(1, "frame completion mismatch");
        checks_r = checks_r + 1;
        $display("DISPLAY_AXI_WRITER_PASS checks=%0d", checks_r);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "display writer timeout state=%0d burst=%0d frame=%0d aw=%0d w=%0d complete=%0d valid=%b ready=%b",
            dut.state_r, dut.burst_beat_r, dut.frame_beat_r,
            aw_count_r, w_count_r, completed_count_r,
            stream_valid_i, stream_ready_o);
    end

endmodule
