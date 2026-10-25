`timescale 1ns/1ps

module tb_geometry_patch_reader;

    reg clk_i = 1'b0;
    always #5 clk_i = !clk_i;
    reg rst_n_i = 1'b0;
    reg req_valid_i = 1'b0;
    reg [15:0] req_x_base_i = 16'd0;
    reg [2:0] req_width_beats_i = 3'd2;
    reg [6:0] req_height_i = 7'd4;
    wire req_ready_o;
    wire patch_wr_en_o;
    wire [1:0] patch_wr_column_o;
    wire [5:0] patch_wr_row_o;
    wire [255:0] patch_wr_data_o;
    wire done_o;
    wire error_o;
    wire [3:0] m_arid_o;
    wire [31:0] m_araddr_o;
    wire [7:0] m_arlen_o;
    wire [2:0] m_arsize_o;
    wire [1:0] m_arburst_o;
    wire [3:0] m_arqos_o;
    wire m_arvalid_o;
    reg m_arready_i = 1'b1;
    reg [3:0] m_rid_i = 4'b0;
    reg [255:0] m_rdata_i = 256'b0;
    reg [1:0] m_rresp_i = 2'b0;
    reg m_rlast_i = 1'b0;
    reg m_rvalid_i = 1'b0;
    wire m_rready_o;
    integer ar_count_r = 0;
    integer wr_count_r = 0;
    integer checks_r = 0;
    integer scenario_r = 0;

    edrv32_geometry_axi_patch_reader dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .req_valid_i(req_valid_i), .req_ready_o(req_ready_o),
        .req_surface_base_i(32'h00001000),
        .req_stride_i(32'd64),
        .req_x_base_i(req_x_base_i), .req_y_base_i(16'd0),
        .req_width_beats_i(req_width_beats_i),
        .req_height_i(req_height_i),
        .patch_wr_en_o(patch_wr_en_o),
        .patch_wr_column_o(patch_wr_column_o),
        .patch_wr_row_o(patch_wr_row_o),
        .patch_wr_data_o(patch_wr_data_o),
        .done_o(done_o), .error_o(error_o),
        .m_arid_o(m_arid_o), .m_araddr_o(m_araddr_o),
        .m_arlen_o(m_arlen_o), .m_arsize_o(m_arsize_o),
        .m_arburst_o(m_arburst_o), .m_arqos_o(m_arqos_o),
        .m_arvalid_o(m_arvalid_o), .m_arready_i(m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(m_rvalid_i), .m_rready_o(m_rready_o)
    );

    always @(posedge clk_i) begin
        if (rst_n_i && m_arvalid_o && m_arready_i) begin
            checks_r = checks_r + 1;
            if (scenario_r == 0) begin
                if (m_arid_o !== ar_count_r[3:0] ||
                    m_araddr_o !== (32'h00001000 + ar_count_r * 64) ||
                    m_arlen_o !== 8'd1)
                    $fatal(1, "row AR %0d id=%0d addr=%h len=%0d",
                        ar_count_r, m_arid_o, m_araddr_o, m_arlen_o);
            end else begin
                if (m_arid_o !== (ar_count_r - 4) ||
                    m_araddr_o !== (ar_count_r == 4 ?
                        32'h00001fe0 : 32'h00002000) ||
                    m_arlen_o !== (ar_count_r == 4 ? 8'd0 : 8'd2))
                    $fatal(1, "split AR %0d id=%0d addr=%h len=%0d",
                        ar_count_r, m_arid_o, m_araddr_o, m_arlen_o);
            end
            ar_count_r = ar_count_r + 1;
        end
        if (rst_n_i && patch_wr_en_o) begin
            checks_r = checks_r + 1;
            if (((scenario_r == 0) &&
                 (patch_wr_row_o !== patch_wr_data_o[7:4])) ||
                ((scenario_r == 1) && (patch_wr_row_o !== 6'd0)) ||
                patch_wr_column_o !== patch_wr_data_o[3:0])
                $fatal(1, "response mapped incorrectly row=%0d col=%0d data=%h",
                    patch_wr_row_o, patch_wr_column_o,
                    patch_wr_data_o[7:0]);
            wr_count_r = wr_count_r + 1;
        end
    end

    task send_beat;
        input [3:0] row_i;
        input [3:0] beat_i;
        input last_i;
        begin
            @(negedge clk_i);
            m_rid_i = row_i;
            m_rdata_i = {248'b0, row_i, beat_i};
            m_rlast_i = last_i;
            m_rvalid_i = 1'b1;
            @(negedge clk_i);
            m_rvalid_i = 1'b0;
        end
    endtask

    initial begin
        repeat (4) @(negedge clk_i);
        rst_n_i = 1'b1;
        @(negedge clk_i);
        req_valid_i = 1'b1;
        @(negedge clk_i);
        req_valid_i = 1'b0;
        wait (ar_count_r == 4);
        if (done_o || error_o)
            $fatal(1, "reader did not retain four outstanding rows");
        checks_r = checks_r + 1;
        send_beat(4'd3, 4'd0, 1'b0);
        send_beat(4'd3, 4'd1, 1'b1);
        send_beat(4'd2, 4'd0, 1'b0);
        send_beat(4'd2, 4'd1, 1'b1);
        send_beat(4'd1, 4'd0, 1'b0);
        send_beat(4'd1, 4'd1, 1'b1);
        send_beat(4'd0, 4'd0, 1'b0);
        send_beat(4'd0, 4'd1, 1'b1);
        wait (done_o);
        if (error_o || ar_count_r != 4 || wr_count_r != 8)
            $fatal(1, "reader failed completion count/error");
        checks_r = checks_r + 1;

        @(negedge clk_i);
        scenario_r = 1;
        req_x_base_i = 16'd2032;
        req_width_beats_i = 3'd4;
        req_height_i = 7'd1;
        req_valid_i = 1'b1;
        @(negedge clk_i);
        req_valid_i = 1'b0;
        wait (ar_count_r == 6);
        send_beat(4'd1, 4'd1, 1'b0);
        send_beat(4'd1, 4'd2, 1'b0);
        send_beat(4'd1, 4'd3, 1'b1);
        send_beat(4'd0, 4'd0, 1'b1);
        wait (done_o);
        if (error_o || ar_count_r != 6 || wr_count_r != 12)
            $fatal(1, "reader failed 4-KiB split/reordered response");
        checks_r = checks_r + 1;
        $display("GEOMETRY_PATCH_READER_PASS checks=%0d", checks_r);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "patch reader timeout");
    end

endmodule
