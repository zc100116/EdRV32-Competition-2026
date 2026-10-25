// ============================================================================
// File        : tb_soc_ddr.sv
// Description : CPU software regression through System AXI, DDR Gateway,
//               256-bit DDR interconnect, Pango adapter and fast UI model.
// ============================================================================

`timescale 1ns/1ps
`include "edrv32_axi4.vh"

module tb_soc_ddr (
    input wire clk,
    input wire rst_n
);

    reg init_done_r;
    reg [5:0] init_count_r;

    wire [3:0] cpu_awid_w;
    wire [31:0] cpu_awaddr_w;
    wire [7:0] cpu_awlen_w;
    wire [2:0] cpu_awsize_w;
    wire [1:0] cpu_awburst_w;
    wire [3:0] cpu_awqos_w;
    wire cpu_awvalid_w;
    wire cpu_awready_w;
    wire [255:0] cpu_wdata_w;
    wire [31:0] cpu_wstrb_w;
    wire cpu_wlast_w;
    wire cpu_wvalid_w;
    wire cpu_wready_w;
    wire [3:0] cpu_bid_w;
    wire [1:0] cpu_bresp_w;
    wire cpu_bvalid_w;
    wire cpu_bready_w;
    wire [3:0] cpu_arid_w;
    wire [31:0] cpu_araddr_w;
    wire [7:0] cpu_arlen_w;
    wire [2:0] cpu_arsize_w;
    wire [1:0] cpu_arburst_w;
    wire [3:0] cpu_arqos_w;
    wire cpu_arvalid_w;
    wire cpu_arready_w;
    wire [3:0] cpu_rid_w;
    wire [255:0] cpu_rdata_w;
    wire [1:0] cpu_rresp_w;
    wire cpu_rlast_w;
    wire cpu_rvalid_w;
    wire cpu_rready_w;

    wire [3:0] fabric_awid_w;
    wire [31:0] fabric_awaddr_w;
    wire [7:0] fabric_awlen_w;
    wire [2:0] fabric_awsize_w;
    wire [1:0] fabric_awburst_w;
    wire [3:0] fabric_awqos_w;
    wire fabric_awvalid_w;
    wire fabric_awready_w;
    wire [255:0] fabric_wdata_w;
    wire [31:0] fabric_wstrb_w;
    wire fabric_wlast_w;
    wire fabric_wvalid_w;
    wire fabric_wready_w;
    wire [3:0] fabric_bid_w;
    wire [1:0] fabric_bresp_w;
    wire fabric_bvalid_w;
    wire fabric_bready_w;
    wire [3:0] fabric_arid_w;
    wire [31:0] fabric_araddr_w;
    wire [7:0] fabric_arlen_w;
    wire [2:0] fabric_arsize_w;
    wire [1:0] fabric_arburst_w;
    wire [3:0] fabric_arqos_w;
    wire fabric_arvalid_w;
    wire fabric_arready_w;
    wire [3:0] fabric_rid_w;
    wire [255:0] fabric_rdata_w;
    wire [1:0] fabric_rresp_w;
    wire fabric_rlast_w;
    wire fabric_rvalid_w;
    wire fabric_rready_w;

    wire [27:0] ui_awaddr_w;
    wire [3:0] ui_awid_w;
    wire [3:0] ui_awlen_w;
    wire ui_awvalid_w;
    wire ui_awready_w;
    wire [255:0] ui_wdata_w;
    wire [31:0] ui_wstrb_w;
    wire ui_wready_w;
    wire [3:0] ui_wid_w;
    wire ui_wlast_w;
    wire [27:0] ui_araddr_w;
    wire [3:0] ui_arid_w;
    wire [3:0] ui_arlen_w;
    wire ui_arvalid_w;
    wire ui_arready_w;
    wire [255:0] ui_rdata_w;
    wire [3:0] ui_rid_w;
    wire ui_rlast_w;
    wire ui_rvalid_w;
    wire ui_rerror_w;

    wire interconnect_read_error_w;
    wire interconnect_write_error_w;
    wire adapter_error_w;
    wire [255:0] unused_debug_w;
    wire unused_uart_tx_w;
    wire [15:0] unused_gpio_out_w;
    wire [15:0] unused_gpio_oe_w;
    wire [3:0] unused_spi_io_w;
    wire [3:0] unused_spi_oe_w;
    wire unused_spi_clk_w;
    wire [3:0] unused_spi_cs_w;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_count_r <= 0;
            init_done_r <= 0;
        end else if (!init_done_r) begin
            init_count_r <= init_count_r + 1'b1;
            if (init_count_r == 6'd31)
                init_done_r <= 1'b1;
        end
    end

    edrv32_soc_top #(
        .RESET_PC(32'h1000_0000),
        .SRAM_WORDS(65536),
        .DDR_ENABLE(1),
        .CPU_HPM_ENABLE(0),
        .AXI_MON_ENABLE(1)
    ) u_soc (
        .clk(clk), .rst_n(rst_n),
        .uart0_tx_o(unused_uart_tx_w), .uart0_rx_i(1'b1),
        .gpio_in_i(16'b0), .gpio_out_o(unused_gpio_out_w),
        .gpio_oe_o(unused_gpio_oe_w), .spi_io_i(4'hf),
        .spi_io_o(unused_spi_io_w), .spi_io_oe_o(unused_spi_oe_w),
        .spi_sclk_o(unused_spi_clk_w), .spi_cs_n_o(unused_spi_cs_w),
        .platform_irq_i(28'b0),
        .vision_cam0_init_done_i(1'b0),
        .vision_cam1_init_done_i(1'b0),
        .vision_cam_error_i(1'b0),
        .vision_cam0_frame_count_i(32'b0),
        .vision_cam1_frame_count_i(32'b0),
        .vision_cam_cfg_ack_toggle_i(1'b0),
        .vision_cam_cfg_response_error_i(1'b0),
        .vision_cam_cfg_response_data_i(8'b0),
        .vision_disp_active_buffer_i(2'b0),
        .vision_disp_error_i(1'b0),
        .vision_disp_frame_count_i(32'b0),
        .vision_disp_underflow_count_i(32'b0),
        .vision_cam0_enable_o(), .vision_cam1_enable_o(),
        .vision_cam_cfg_req_toggle_o(), .vision_cam_cfg_camera_o(),
        .vision_cam_cfg_read_o(),
        .vision_cam_cfg_reg_addr_o(), .vision_cam_cfg_write_data_o(),
        .vision_disp_enable_o(),
        .ddr_awid_o(cpu_awid_w), .ddr_awaddr_o(cpu_awaddr_w),
        .ddr_awlen_o(cpu_awlen_w), .ddr_awsize_o(cpu_awsize_w),
        .ddr_awburst_o(cpu_awburst_w), .ddr_awqos_o(cpu_awqos_w),
        .ddr_awvalid_o(cpu_awvalid_w), .ddr_awready_i(cpu_awready_w),
        .ddr_wdata_o(cpu_wdata_w), .ddr_wstrb_o(cpu_wstrb_w),
        .ddr_wlast_o(cpu_wlast_w), .ddr_wvalid_o(cpu_wvalid_w),
        .ddr_wready_i(cpu_wready_w), .ddr_bid_i(cpu_bid_w),
        .ddr_bresp_i(cpu_bresp_w), .ddr_bvalid_i(cpu_bvalid_w),
        .ddr_bready_o(cpu_bready_w), .ddr_arid_o(cpu_arid_w),
        .ddr_araddr_o(cpu_araddr_w), .ddr_arlen_o(cpu_arlen_w),
        .ddr_arsize_o(cpu_arsize_w), .ddr_arburst_o(cpu_arburst_w),
        .ddr_arqos_o(cpu_arqos_w), .ddr_arvalid_o(cpu_arvalid_w),
        .ddr_arready_i(cpu_arready_w), .ddr_rid_i(cpu_rid_w),
        .ddr_rdata_i(cpu_rdata_w), .ddr_rresp_i(cpu_rresp_w),
        .ddr_rlast_i(cpu_rlast_w), .ddr_rvalid_i(cpu_rvalid_w),
        .ddr_rready_o(cpu_rready_w), .debug_o(unused_debug_w)
    );

    edrv32_axi_m2s_interconnect #(
        .NUM_M(1), .ADDR_W(32), .DATA_W(256), .ID_W(4),
        .S_ID_W(4), .LEN_W(8), .WR_ORDER_DEPTH(4),
        .STARVE_CYCLES(64), .COUNT_W(5)
    ) u_ddr_interconnect (
        .clk_i(clk), .rst_n_i(rst_n), .accept_i(init_done_r),
        .m_awid_i(cpu_awid_w), .m_awaddr_i(cpu_awaddr_w),
        .m_awlen_i(cpu_awlen_w), .m_awsize_i(cpu_awsize_w),
        .m_awburst_i(cpu_awburst_w), .m_awqos_i(cpu_awqos_w),
        .m_awvalid_i(cpu_awvalid_w), .m_awready_o(cpu_awready_w),
        .m_wdata_i(cpu_wdata_w), .m_wstrb_i(cpu_wstrb_w),
        .m_wlast_i(cpu_wlast_w), .m_wvalid_i(cpu_wvalid_w),
        .m_wready_o(cpu_wready_w), .m_bid_o(cpu_bid_w),
        .m_bresp_o(cpu_bresp_w), .m_bvalid_o(cpu_bvalid_w),
        .m_bready_i(cpu_bready_w), .m_arid_i(cpu_arid_w),
        .m_araddr_i(cpu_araddr_w), .m_arlen_i(cpu_arlen_w),
        .m_arsize_i(cpu_arsize_w), .m_arburst_i(cpu_arburst_w),
        .m_arqos_i(cpu_arqos_w), .m_arvalid_i(cpu_arvalid_w),
        .m_arready_o(cpu_arready_w), .m_rid_o(cpu_rid_w),
        .m_rdata_o(cpu_rdata_w), .m_rresp_o(cpu_rresp_w),
        .m_rlast_o(cpu_rlast_w), .m_rvalid_o(cpu_rvalid_w),
        .m_rready_i(cpu_rready_w), .m_read_urgent_i(1'b0),
        .m_write_urgent_i(1'b0), .m_read_weight_i(4'd1),
        .m_write_weight_i(4'd1), .m_read_credit_i(5'd4),
        .m_write_credit_i(5'd4),
        .s_awid_o(fabric_awid_w), .s_awaddr_o(fabric_awaddr_w),
        .s_awlen_o(fabric_awlen_w), .s_awsize_o(fabric_awsize_w),
        .s_awburst_o(fabric_awburst_w), .s_awqos_o(fabric_awqos_w),
        .s_awvalid_o(fabric_awvalid_w), .s_awready_i(fabric_awready_w),
        .s_wdata_o(fabric_wdata_w), .s_wstrb_o(fabric_wstrb_w),
        .s_wlast_o(fabric_wlast_w), .s_wvalid_o(fabric_wvalid_w),
        .s_wready_i(fabric_wready_w), .s_bid_i(fabric_bid_w),
        .s_bresp_i(fabric_bresp_w), .s_bvalid_i(fabric_bvalid_w),
        .s_bready_o(fabric_bready_w), .s_arid_o(fabric_arid_w),
        .s_araddr_o(fabric_araddr_w), .s_arlen_o(fabric_arlen_w),
        .s_arsize_o(fabric_arsize_w), .s_arburst_o(fabric_arburst_w),
        .s_arqos_o(fabric_arqos_w), .s_arvalid_o(fabric_arvalid_w),
        .s_arready_i(fabric_arready_w), .s_rid_i(fabric_rid_w),
        .s_rdata_i(fabric_rdata_w), .s_rresp_i(fabric_rresp_w),
        .s_rlast_i(fabric_rlast_w), .s_rvalid_i(fabric_rvalid_w),
        .s_rready_o(fabric_rready_w), .read_outstanding_o(),
        .write_outstanding_o(),
        .read_protocol_error_o(interconnect_read_error_w),
        .write_protocol_error_o(interconnect_write_error_w)
    );

    edrv32_pango_ddr_axi_adapter #(.ID_W(4)) u_adapter (
        .clk_i(clk), .rst_n_i(rst_n), .init_done_i(init_done_r),
        .s_awid_i(fabric_awid_w), .s_awaddr_i(fabric_awaddr_w),
        .s_awlen_i(fabric_awlen_w), .s_awsize_i(fabric_awsize_w),
        .s_awburst_i(fabric_awburst_w), .s_awvalid_i(fabric_awvalid_w),
        .s_awready_o(fabric_awready_w), .s_wdata_i(fabric_wdata_w),
        .s_wstrb_i(fabric_wstrb_w), .s_wlast_i(fabric_wlast_w),
        .s_wvalid_i(fabric_wvalid_w), .s_wready_o(fabric_wready_w),
        .s_bid_o(fabric_bid_w), .s_bresp_o(fabric_bresp_w),
        .s_bvalid_o(fabric_bvalid_w), .s_bready_i(fabric_bready_w),
        .s_arid_i(fabric_arid_w), .s_araddr_i(fabric_araddr_w),
        .s_arlen_i(fabric_arlen_w), .s_arsize_i(fabric_arsize_w),
        .s_arburst_i(fabric_arburst_w), .s_arvalid_i(fabric_arvalid_w),
        .s_arready_o(fabric_arready_w), .s_rid_o(fabric_rid_w),
        .s_rdata_o(fabric_rdata_w), .s_rresp_o(fabric_rresp_w),
        .s_rlast_o(fabric_rlast_w), .s_rvalid_o(fabric_rvalid_w),
        .s_rready_i(fabric_rready_w), .ui_awaddr_o(ui_awaddr_w),
        .ui_awid_o(ui_awid_w), .ui_awlen_o(ui_awlen_w),
        .ui_awvalid_o(ui_awvalid_w), .ui_awready_i(ui_awready_w),
        .ui_wdata_o(ui_wdata_w), .ui_wstrb_o(ui_wstrb_w),
        .ui_wready_i(ui_wready_w), .ui_wusero_id_i(ui_wid_w),
        .ui_wusero_last_i(ui_wlast_w), .ui_araddr_o(ui_araddr_w),
        .ui_arid_o(ui_arid_w), .ui_arlen_o(ui_arlen_w),
        .ui_arvalid_o(ui_arvalid_w), .ui_arready_i(ui_arready_w),
        .ui_rdata_i(ui_rdata_w), .ui_rid_i(ui_rid_w),
        .ui_rlast_i(ui_rlast_w), .ui_rvalid_i(ui_rvalid_w),
        .protocol_error_o(adapter_error_w)
    );

    pango_ddr_ui_model #(
        .MEMORY_LINES(8192), .RANDOM_STALL(1),
        .INJECT_RERROR(0), .ALLOW_AW_DURING_W(1)
    ) u_ddr_model (
        .clk_i(clk), .rst_n_i(rst_n), .init_done_i(init_done_r),
        .awvalid_i(ui_awvalid_w), .awready_o(ui_awready_w),
        .awaddr_i(ui_awaddr_w), .awlen_i(ui_awlen_w), .awid_i(ui_awid_w),
        .wdata_i(ui_wdata_w), .wstrb_i(ui_wstrb_w), .wready_o(ui_wready_w),
        .wusero_id_o(ui_wid_w), .wusero_last_o(ui_wlast_w),
        .arvalid_i(ui_arvalid_w), .arready_o(ui_arready_w),
        .araddr_i(ui_araddr_w), .arlen_i(ui_arlen_w), .arid_i(ui_arid_w),
        .rvalid_o(ui_rvalid_w), .rdata_o(ui_rdata_w), .rid_o(ui_rid_w),
        .rlast_o(ui_rlast_w), .rerror_o(ui_rerror_w),
        .write_count_o(), .read_count_o()
    );

    wire console_write_w = u_soc.apb_psel_w && u_soc.apb_penable_w &&
        u_soc.apb_pwrite_w && u_soc.apb_pready_w &&
        (u_soc.apb_paddr_w == 32'h4000_0000);
    reg [3:0] pass_index_r;
    reg pass_seen_r;
    reg [7:0] console_byte_r;
    reg [31:0] commit_count_r;
    reg [31:0] last_commit_pc_r;

    function [7:0] pass_char;
        input [3:0] index;
        begin
            case (index)
                4'd0: pass_char = "D";
                4'd1: pass_char = "D";
                4'd2: pass_char = "R";
                4'd3: pass_char = "_";
                4'd4: pass_char = "S";
                4'd5: pass_char = "M";
                4'd6: pass_char = "O";
                4'd7: pass_char = "K";
                4'd8: pass_char = "E";
                4'd9: pass_char = "_";
                4'd10: pass_char = "P";
                4'd11: pass_char = "A";
                4'd12: pass_char = "S";
                default: pass_char = "S";
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pass_index_r <= 0;
            pass_seen_r <= 0;
            console_byte_r <= 0;
            commit_count_r <= 0;
            last_commit_pc_r <= 0;
        end else begin
            if (u_soc.debug_commit_valid_w) begin
                commit_count_r <= commit_count_r + 1'b1;
                last_commit_pc_r <= u_soc.debug_commit_pc_w;
            end
            if (console_write_w) begin
                console_byte_r <= u_soc.apb_pwdata_w[7:0];
                $write("%c", u_soc.apb_pwdata_w[7:0]);
                if (u_soc.apb_pwdata_w[7:0] == pass_char(pass_index_r)) begin
                    if (pass_index_r == 4'd13)
                        pass_seen_r <= 1'b1;
                    else
                        pass_index_r <= pass_index_r + 1'b1;
                end else begin
                    pass_index_r <=
                        (u_soc.apb_pwdata_w[7:0] == "D") ? 4'd1 : 4'd0;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n && $test$plusargs("TRACE") &&
            u_soc.debug_commit_valid_w)
            $display("SOC_DDR_COMMIT pc=%08x instr=%08x",
                     u_soc.debug_commit_pc_w, u_soc.debug_commit_instr_w);
        if (rst_n && $test$plusargs("TRACE") &&
            u_soc.m1_rvalid_w && u_soc.m1_rready_w)
            $display("SOC_DDR_M1_R id=%x resp=%x last=%x data=%016x",
                     u_soc.m1_rid_w, u_soc.m1_rresp_w,
                     u_soc.m1_rlast_w, u_soc.m1_rdata_w);
        if (rst_n && $test$plusargs("TRACE") &&
            u_soc.m1_arvalid_w && u_soc.m1_arready_w)
            $display("SOC_DDR_M1_AR addr=%08x len=%0d hit=%b connect=%b",
                     u_soc.m1_araddr_w, u_soc.m1_arlen_w,
                     u_soc.u_axi_interconnect.u_axi_rd_fabric.hit_oh_r[1],
                     u_soc.axi_read_connect_w);
        if (rst_n &&
            u_soc.u_cached_core.u_core.commit_redirect_exception_valid_w)
            $display("SOC_DDR_EXCEPTION pc=%08x cause=%08x",
                     u_soc.u_cached_core.u_core.mem2_packet_pc_w,
                     u_soc.u_cached_core.u_core.u_commit_stage.synchronous_cause_w);

        if (pass_seen_r) begin
            if (adapter_error_w || interconnect_read_error_w ||
                interconnect_write_error_w || ui_rerror_w)
                $fatal(1, "DDR chain protocol error");
            $display("\nSOC_DDR_SMOKE_PASS");
            $finish;
        end
    end

    initial begin
        #2000000;
        $fatal(1, "SoC DDR software timeout commits=%0d pc=%08x pass_index=%0d last=%h",
               commit_count_r, last_commit_pc_r, pass_index_r, console_byte_r);
    end

endmodule
