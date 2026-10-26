// File: edrv32_mem_ddr_gw.v
// Spec: mem-subsys-spec 1, 2.1, 5.1, 6, 7; edrv32-soc-spec 6.3.
// Description: AXI64 CDC followed by independent read/write width converters.
//              System-side ownership lasts through the upstream response handshake.
//              A 256-bit payload register per direction holds one converted line.
// Clock domain: s_axi in clk_sys; converter and m_axi in clk_mem.
module edrv32_mem_ddr_gw (
    // Source and destination clocks; resets release synchronously in each domain.
    input wire clk_sys_i,
    input wire rst_sys_n_i,
    input wire clk_mem_i,
    input wire rst_mem_n_i,

    // s_axi interface (AXI64).
    input wire [3:0] s_axi_awid_i,
    input wire [31:0] s_axi_awaddr_i,
    input wire [7:0] s_axi_awlen_i,
    input wire [2:0] s_axi_awsize_i,
    input wire [1:0] s_axi_awburst_i,
    input wire s_axi_awvalid_i,
    output wire s_axi_awready_o,
    input wire [63:0] s_axi_wdata_i,
    input wire [7:0] s_axi_wstrb_i,
    input wire s_axi_wlast_i,
    input wire s_axi_wvalid_i,
    output wire s_axi_wready_o,
    output wire [3:0] s_axi_bid_o,
    output wire [1:0] s_axi_bresp_o,
    output wire s_axi_bvalid_o,
    input wire s_axi_bready_i,
    input wire [3:0] s_axi_arid_i,
    input wire [31:0] s_axi_araddr_i,
    input wire [7:0] s_axi_arlen_i,
    input wire [2:0] s_axi_arsize_i,
    input wire [1:0] s_axi_arburst_i,
    input wire s_axi_arvalid_i,
    output wire s_axi_arready_o,
    output wire [3:0] s_axi_rid_o,
    output wire [63:0] s_axi_rdata_o,
    output wire [1:0] s_axi_rresp_o,
    output wire s_axi_rlast_o,
    output wire s_axi_rvalid_o,
    input wire s_axi_rready_i,

    // m_axi interface (AXI256).
    output wire m_axi_awid_o,
    output wire [31:0] m_axi_awaddr_o,
    output wire [3:0] m_axi_awlen_o,
    output wire m_axi_awvalid_o,
    input wire m_axi_awready_i,
    output wire [255:0] m_axi_wdata_o,
    output wire [31:0] m_axi_wstrb_o,
    output wire m_axi_wlast_o,
    output wire m_axi_wvalid_o,
    input wire m_axi_wready_i,
    input wire m_axi_bid_i,
    input wire [1:0] m_axi_bresp_i,
    input wire m_axi_bvalid_i,
    output wire m_axi_bready_o,
    output wire m_axi_arid_o,
    output wire [31:0] m_axi_araddr_o,
    output wire [3:0] m_axi_arlen_o,
    output wire m_axi_arvalid_o,
    input wire m_axi_arready_i,
    input wire m_axi_rid_i,
    input wire [255:0] m_axi_rdata_i,
    input wire [1:0] m_axi_rresp_i,
    input wire m_axi_rlast_i,
    input wire m_axi_rvalid_i,
    output wire m_axi_rready_o
);
    wire [3:0] bridge_awid_w;
    wire [31:0] bridge_awaddr_w;
    wire [7:0] bridge_awlen_w;
    wire [2:0] bridge_awsize_w;
    wire [1:0] bridge_awburst_w;
    wire bridge_awvalid_w;
    wire bridge_awready_w;
    wire [63:0] bridge_wdata_w;
    wire [7:0] bridge_wstrb_w;
    wire bridge_wlast_w;
    wire bridge_wvalid_w;
    wire bridge_wready_w;
    wire [3:0] bridge_bid_w;
    wire [1:0] bridge_bresp_w;
    wire bridge_bvalid_w;
    wire bridge_bready_w;
    wire [3:0] bridge_arid_w;
    wire [31:0] bridge_araddr_w;
    wire [7:0] bridge_arlen_w;
    wire [2:0] bridge_arsize_w;
    wire [1:0] bridge_arburst_w;
    wire bridge_arvalid_w;
    wire bridge_arready_w;
    wire [3:0] bridge_rid_w;
    wire [63:0] bridge_rdata_w;
    wire [1:0] bridge_rresp_w;
    wire bridge_rlast_w;
    wire bridge_rvalid_w;
    wire bridge_rready_w;
    reg read_busy_r;
    reg write_busy_r;
    wire source_arready_w;
    wire source_awready_w;
    wire source_arvalid_w;
    wire source_awvalid_w;

    // mem-subsys 2.1: do not accept the next parent before its response returns.
    assign source_arvalid_w = s_axi_arvalid_i && !read_busy_r;
    assign source_awvalid_w = s_axi_awvalid_i && !write_busy_r;
    assign s_axi_arready_o = source_arready_w && !read_busy_r;
    assign s_axi_awready_o = source_awready_w && !write_busy_r;
    always @(posedge clk_sys_i or negedge rst_sys_n_i) begin
        if (!rst_sys_n_i) begin
            read_busy_r <= 1'b0;
            write_busy_r <= 1'b0;
        end else begin
            if (s_axi_arvalid_i && s_axi_arready_o) begin
                read_busy_r <= 1'b1;
            end else if (s_axi_rvalid_o && s_axi_rready_i && s_axi_rlast_o) begin
                read_busy_r <= 1'b0;
            end
            if (s_axi_awvalid_i && s_axi_awready_o) begin
                write_busy_r <= 1'b1;
            end else if (s_axi_bvalid_o && s_axi_bready_i) begin
                write_busy_r <= 1'b0;
            end
        end
    end

    edrv32_axi_async_bridge u_bridge (
        // CDC is exclusively on the 64-bit side (X2).
        .clk_sys_i(clk_sys_i),
        .rst_sys_n_i(rst_sys_n_i),
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_i),
        .s_axi_awid_i(s_axi_awid_i),
        .s_axi_awaddr_i(s_axi_awaddr_i),
        .s_axi_awlen_i(s_axi_awlen_i),
        .s_axi_awsize_i(s_axi_awsize_i),
        .s_axi_awburst_i(s_axi_awburst_i),
        .s_axi_awvalid_i(source_awvalid_w),
        .s_axi_awready_o(source_awready_w),
        .s_axi_wdata_i(s_axi_wdata_i),
        .s_axi_wstrb_i(s_axi_wstrb_i),
        .s_axi_wlast_i(s_axi_wlast_i),
        .s_axi_wvalid_i(s_axi_wvalid_i),
        .s_axi_wready_o(s_axi_wready_o),
        .s_axi_bid_o(s_axi_bid_o),
        .s_axi_bresp_o(s_axi_bresp_o),
        .s_axi_bvalid_o(s_axi_bvalid_o),
        .s_axi_bready_i(s_axi_bready_i),
        .s_axi_arid_i(s_axi_arid_i),
        .s_axi_araddr_i(s_axi_araddr_i),
        .s_axi_arlen_i(s_axi_arlen_i),
        .s_axi_arsize_i(s_axi_arsize_i),
        .s_axi_arburst_i(s_axi_arburst_i),
        .s_axi_arvalid_i(source_arvalid_w),
        .s_axi_arready_o(source_arready_w),
        .s_axi_rid_o(s_axi_rid_o),
        .s_axi_rdata_o(s_axi_rdata_o),
        .s_axi_rresp_o(s_axi_rresp_o),
        .s_axi_rlast_o(s_axi_rlast_o),
        .s_axi_rvalid_o(s_axi_rvalid_o),
        .s_axi_rready_i(s_axi_rready_i),
        .m_axi_awid_o(bridge_awid_w),
        .m_axi_awaddr_o(bridge_awaddr_w),
        .m_axi_awlen_o(bridge_awlen_w),
        .m_axi_awsize_o(bridge_awsize_w),
        .m_axi_awburst_o(bridge_awburst_w),
        .m_axi_awvalid_o(bridge_awvalid_w),
        .m_axi_awready_i(bridge_awready_w),
        .m_axi_wdata_o(bridge_wdata_w),
        .m_axi_wstrb_o(bridge_wstrb_w),
        .m_axi_wlast_o(bridge_wlast_w),
        .m_axi_wvalid_o(bridge_wvalid_w),
        .m_axi_wready_i(bridge_wready_w),
        .m_axi_bid_i(bridge_bid_w),
        .m_axi_bresp_i(bridge_bresp_w),
        .m_axi_bvalid_i(bridge_bvalid_w),
        .m_axi_bready_o(bridge_bready_w),
        .m_axi_arid_o(bridge_arid_w),
        .m_axi_araddr_o(bridge_araddr_w),
        .m_axi_arlen_o(bridge_arlen_w),
        .m_axi_arsize_o(bridge_arsize_w),
        .m_axi_arburst_o(bridge_arburst_w),
        .m_axi_arvalid_o(bridge_arvalid_w),
        .m_axi_arready_i(bridge_arready_w),
        .m_axi_rid_i(bridge_rid_w),
        .m_axi_rdata_i(bridge_rdata_w),
        .m_axi_rresp_i(bridge_rresp_w),
        .m_axi_rlast_i(bridge_rlast_w),
        .m_axi_rvalid_i(bridge_rvalid_w),
        .m_axi_rready_o(bridge_rready_w)
    );

    localparam [1:0] S_READ_IDLE = 2'd0;
    localparam [1:0] S_READ_ADDR = 2'd1;
    localparam [1:0] S_READ_DATA = 2'd2;
    localparam [1:0] S_READ_RESP = 2'd3;
    localparam [2:0] S_WRITE_IDLE = 3'd0;
    localparam [2:0] S_WRITE_COLLECT = 3'd1;
    localparam [2:0] S_WRITE_SEND = 3'd2;
    localparam [2:0] S_WRITE_WAIT = 3'd3;
    localparam [2:0] S_WRITE_RESP = 3'd4;
    reg [1:0] read_state_r;
    reg [2:0] write_state_r;
    reg [3:0] read_id_r;
    reg [3:0] write_id_r;
    reg [31:0] read_addr_r;
    reg [31:0] write_addr_r;
    reg [7:0] read_left_r;
    reg [7:0] write_left_r;
    reg [1:0] read_lane_r;
    reg [1:0] write_lane_r;
    reg read_legal_r;
    reg write_legal_r;
    reg [255:0] read_data_r;
    reg [255:0] write_data_r;
    reg [31:0] write_strb_r;
    reg [1:0] read_resp_r;
    reg [1:0] write_resp_r;
    reg aw_pending_r;
    reg w_pending_r;
    wire read_legal_w;
    wire write_legal_w;
    wire read_line_w;
    wire write_line_w;
    wire [31:0] read_align_mask_w;
    wire [31:0] write_align_mask_w;
    wire read_addr_take_w;
    wire write_addr_take_w;
    wire write_take_w;
    // The local ID is fixed and a legal downstream transaction is always one beat.
    wire [11:0] unused_payload_w;

    assign unused_payload_w = {bridge_wstrb_w, bridge_wlast_w,
                                m_axi_bid_i, m_axi_rid_i, m_axi_rlast_i};
    assign read_align_mask_w = (32'd1 << bridge_arsize_w) - 32'd1;
    assign write_align_mask_w = (32'd1 << bridge_awsize_w) - 32'd1;
    assign read_line_w = (bridge_arlen_w == 8'd3) && (bridge_arsize_w == 3'd3)
                        && (bridge_araddr_w[4:0] == 5'd0);
    assign write_line_w = (bridge_awlen_w == 8'd3) && (bridge_awsize_w == 3'd3)
                            && (bridge_awaddr_w[4:0] == 5'd0);
    // mem-subsys 2.1: only naturally aligned singles and aligned cache lines, INCR only.
    assign read_legal_w = (bridge_arburst_w == 2'b01) && (read_line_w ||
                            ((bridge_arlen_w == 8'd0) && (bridge_arsize_w <= 3'd3) &&
                            ((bridge_araddr_w & read_align_mask_w) == 32'd0)));
    assign write_legal_w = (bridge_awburst_w == 2'b01) && (write_line_w ||
                            ((bridge_awlen_w == 8'd0) && (bridge_awsize_w <= 3'd3) &&
                            ((bridge_awaddr_w & write_align_mask_w) == 32'd0)));
    assign bridge_arready_w = (read_state_r == S_READ_IDLE);
    assign bridge_awready_w = (write_state_r == S_WRITE_IDLE);
    assign read_addr_take_w = bridge_arvalid_w && bridge_arready_w;
    assign write_addr_take_w = bridge_awvalid_w && bridge_awready_w;
    assign bridge_wready_w = (write_state_r == S_WRITE_COLLECT);
    assign write_take_w = bridge_wvalid_w && bridge_wready_w;

    // All DDR requests have aligned physical addresses and one fixed-size beat.
    assign m_axi_arid_o = 1'b0;
    assign m_axi_araddr_o = read_addr_r;
    assign m_axi_arlen_o = 4'd0;
    assign m_axi_arvalid_o = (read_state_r == S_READ_ADDR);
    assign m_axi_rready_o = (read_state_r == S_READ_DATA);
    assign bridge_rvalid_w = (read_state_r == S_READ_RESP);
    assign bridge_rid_w = read_id_r;
    assign bridge_rdata_w = read_legal_r ? read_data_r[read_lane_r * 64 +: 64] : 64'd0;
    assign bridge_rresp_w = read_resp_r;
    assign bridge_rlast_w = (read_left_r == 8'd0);
    assign m_axi_awid_o = 1'b0;
    assign m_axi_awaddr_o = write_addr_r;
    assign m_axi_awlen_o = 4'd0;
    assign m_axi_awvalid_o = aw_pending_r;
    assign m_axi_wdata_o = write_data_r;
    assign m_axi_wstrb_o = write_strb_r;
    assign m_axi_wlast_o = 1'b1;
    assign m_axi_wvalid_o = w_pending_r;
    assign m_axi_bready_o = (write_state_r == S_WRITE_WAIT);
    assign bridge_bvalid_w = (write_state_r == S_WRITE_RESP);
    assign bridge_bid_w = write_id_r;
    assign bridge_bresp_w = write_resp_r;

    always @(posedge clk_mem_i or negedge rst_mem_n_i) begin
        if (!rst_mem_n_i) begin
            read_state_r <= S_READ_IDLE;
            read_left_r <= 8'd0;
            read_lane_r <= 2'd0;
        end else begin
            case (read_state_r)
                S_READ_IDLE: begin
                    if (read_addr_take_w) begin
                        read_left_r <= bridge_arlen_w;
                        read_lane_r <= bridge_araddr_w[4:3];
                        read_state_r <= read_legal_w ? S_READ_ADDR : S_READ_RESP;
                    end
                end
                S_READ_ADDR: begin
                    if (m_axi_arready_i) begin
                        read_state_r <= S_READ_DATA;
                    end
                end
                S_READ_DATA: begin
                    if (m_axi_rvalid_i) begin
                        read_state_r <= S_READ_RESP;
                    end
                end
                S_READ_RESP: begin
                    if (bridge_rready_w) begin
                        read_left_r <= read_left_r - 8'd1;
                        read_lane_r <= read_lane_r + 2'd1;
                        if (read_left_r == 8'd0) begin
                            read_state_r <= S_READ_IDLE;
                        end
                    end
                end
                default: begin
                    read_state_r <= S_READ_IDLE;
                end
            endcase
        end
    end
    always @(posedge clk_mem_i) begin
        if (read_addr_take_w) begin
            read_id_r <= bridge_arid_w;
            read_addr_r <= {2'b00, bridge_araddr_w[29:5], 5'd0};
            read_legal_r <= read_legal_w;
            read_resp_r <= 2'b10;
        end
        if (m_axi_rvalid_i && m_axi_rready_o) begin
            read_data_r <= m_axi_rdata_i;
            read_resp_r <= m_axi_rresp_i;
        end
    end

    always @(posedge clk_mem_i or negedge rst_mem_n_i) begin
        if (!rst_mem_n_i) begin
            write_state_r <= S_WRITE_IDLE;
            write_left_r <= 8'd0;
            write_lane_r <= 2'd0;
            aw_pending_r <= 1'b0;
            w_pending_r <= 1'b0;
        end else begin
            case (write_state_r)
                S_WRITE_IDLE: begin
                    if (write_addr_take_w) begin
                        write_left_r <= bridge_awlen_w;
                        write_lane_r <= bridge_awaddr_w[4:3];
                        write_state_r <= S_WRITE_COLLECT;
                    end
                end
                S_WRITE_COLLECT: begin
                    if (write_take_w) begin
                        write_left_r <= write_left_r - 8'd1;
                        write_lane_r <= write_lane_r + 2'd1;
                        if (write_left_r == 8'd0) begin
                            write_state_r <= write_legal_r ? S_WRITE_SEND : S_WRITE_RESP;
                            aw_pending_r <= write_legal_r;
                            w_pending_r <= write_legal_r;
                        end
                    end
                end
                S_WRITE_SEND: begin
                    if (m_axi_awready_i) begin
                        aw_pending_r <= 1'b0;
                    end
                    if (m_axi_wready_i) begin
                        w_pending_r <= 1'b0;
                    end
                    if ((!aw_pending_r || m_axi_awready_i) &&
                        (!w_pending_r || m_axi_wready_i)) begin
                        write_state_r <= S_WRITE_WAIT;
                    end
                end
                S_WRITE_WAIT: begin
                    if (m_axi_bvalid_i) begin
                        write_state_r <= S_WRITE_RESP;
                    end
                end
                S_WRITE_RESP: begin
                    if (bridge_bready_w) begin
                        write_state_r <= S_WRITE_IDLE;
                    end
                end
                default: begin
                    write_state_r <= S_WRITE_IDLE;
                end
            endcase
        end
    end
    always @(posedge clk_mem_i) begin
        if (write_addr_take_w) begin
            write_id_r <= bridge_awid_w;
            write_addr_r <= {2'b00, bridge_awaddr_w[29:5], 5'd0};
            write_legal_r <= write_legal_w;
            write_strb_r <= write_line_w ? 32'hffff_ffff :
                            ((32'hffff_ffff >> (32 - (32'd1 << bridge_awsize_w)))
                            << bridge_awaddr_w[4:0]);
            write_resp_r <= 2'b10;
        end
        if (write_take_w) begin
            write_data_r[write_lane_r * 64 +: 64] <= bridge_wdata_w;
        end
        if (m_axi_bvalid_i && m_axi_bready_o) begin
            write_resp_r <= m_axi_bresp_i;
        end
    end
endmodule
