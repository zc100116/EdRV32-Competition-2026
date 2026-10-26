// File: edrv32_mem_xbar.v
// Spec: mem-subsys-spec 2.2, 4.1, 5-7; edrv32-soc-spec 4.2, 6.4, 7.1.
// Description: Seven-port AXI256 crossbar with registered grant decisions.
// Global outstanding releases on DDR B/RLAST; port outstanding on upstream B/RLAST.
// Port limits are 0-8. B FIFOs have eight entries; R credit reserves exact LEN+1 beats.
// Statistics count DDR handshakes; WAIT includes capacity stalls and the grant pipeline.
// APB writes ignore PSTRB. CTRL is unused; ERR_CODE aliases ERR_TYPE.
// LEN is four bits: LEN>15 cannot be represented and has no detector.
// Clock: clk_mem; reset is externally synchronized rst_mem_core_n.
module edrv32_mem_xbar (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,
    // p0 upstream.
    input wire p0_arid_i,
    input wire [31:0] p0_araddr_i,
    input wire [3:0] p0_arlen_i,
    input wire p0_arvalid_i,
    output wire p0_arready_o,
    output wire p0_rid_o,
    output wire [255:0] p0_rdata_o,
    output wire [1:0] p0_rresp_o,
    output wire p0_rlast_o,
    output wire p0_rvalid_o,
    input wire p0_rready_i,
    input wire p0_urgent_i,
    // p1 upstream.
    input wire p1_awid_i,
    input wire [31:0] p1_awaddr_i,
    input wire [3:0] p1_awlen_i,
    input wire p1_awvalid_i,
    output wire p1_awready_o,
    input wire [255:0] p1_wdata_i,
    input wire [31:0] p1_wstrb_i,
    input wire p1_wlast_i,
    input wire p1_wvalid_i,
    output wire p1_wready_o,
    output wire p1_bid_o,
    output wire [1:0] p1_bresp_o,
    output wire p1_bvalid_o,
    input wire p1_bready_i,
    input wire p1_urgent_i,
    // p2 upstream.
    input wire p2_awid_i,
    input wire [31:0] p2_awaddr_i,
    input wire [3:0] p2_awlen_i,
    input wire p2_awvalid_i,
    output wire p2_awready_o,
    input wire [255:0] p2_wdata_i,
    input wire [31:0] p2_wstrb_i,
    input wire p2_wlast_i,
    input wire p2_wvalid_i,
    output wire p2_wready_o,
    output wire p2_bid_o,
    output wire [1:0] p2_bresp_o,
    output wire p2_bvalid_o,
    input wire p2_bready_i,
    input wire p2_arid_i,
    input wire [31:0] p2_araddr_i,
    input wire [3:0] p2_arlen_i,
    input wire p2_arvalid_i,
    output wire p2_arready_o,
    output wire p2_rid_o,
    output wire [255:0] p2_rdata_o,
    output wire [1:0] p2_rresp_o,
    output wire p2_rlast_o,
    output wire p2_rvalid_o,
    input wire p2_rready_i,
    // p3 upstream.
    input wire p3_awid_i,
    input wire [31:0] p3_awaddr_i,
    input wire [3:0] p3_awlen_i,
    input wire p3_awvalid_i,
    output wire p3_awready_o,
    input wire [255:0] p3_wdata_i,
    input wire [31:0] p3_wstrb_i,
    input wire p3_wlast_i,
    input wire p3_wvalid_i,
    output wire p3_wready_o,
    output wire p3_bid_o,
    output wire [1:0] p3_bresp_o,
    output wire p3_bvalid_o,
    input wire p3_bready_i,
    input wire p3_arid_i,
    input wire [31:0] p3_araddr_i,
    input wire [3:0] p3_arlen_i,
    input wire p3_arvalid_i,
    output wire p3_arready_o,
    output wire p3_rid_o,
    output wire [255:0] p3_rdata_o,
    output wire [1:0] p3_rresp_o,
    output wire p3_rlast_o,
    output wire p3_rvalid_o,
    input wire p3_rready_i,
    // p4 upstream.
    input wire p4_awid_i,
    input wire [31:0] p4_awaddr_i,
    input wire [3:0] p4_awlen_i,
    input wire p4_awvalid_i,
    output wire p4_awready_o,
    input wire [255:0] p4_wdata_i,
    input wire [31:0] p4_wstrb_i,
    input wire p4_wlast_i,
    input wire p4_wvalid_i,
    output wire p4_wready_o,
    output wire p4_bid_o,
    output wire [1:0] p4_bresp_o,
    output wire p4_bvalid_o,
    input wire p4_bready_i,
    input wire p4_arid_i,
    input wire [31:0] p4_araddr_i,
    input wire [3:0] p4_arlen_i,
    input wire p4_arvalid_i,
    output wire p4_arready_o,
    output wire p4_rid_o,
    output wire [255:0] p4_rdata_o,
    output wire [1:0] p4_rresp_o,
    output wire p4_rlast_o,
    output wire p4_rvalid_o,
    input wire p4_rready_i,
    // p5 upstream.
    input wire p5_awid_i,
    input wire [31:0] p5_awaddr_i,
    input wire [3:0] p5_awlen_i,
    input wire p5_awvalid_i,
    output wire p5_awready_o,
    input wire [255:0] p5_wdata_i,
    input wire [31:0] p5_wstrb_i,
    input wire p5_wlast_i,
    input wire p5_wvalid_i,
    output wire p5_wready_o,
    output wire p5_bid_o,
    output wire [1:0] p5_bresp_o,
    output wire p5_bvalid_o,
    input wire p5_bready_i,
    input wire p5_arid_i,
    input wire [31:0] p5_araddr_i,
    input wire [3:0] p5_arlen_i,
    input wire p5_arvalid_i,
    output wire p5_arready_o,
    output wire p5_rid_o,
    output wire [255:0] p5_rdata_o,
    output wire [1:0] p5_rresp_o,
    output wire p5_rlast_o,
    output wire p5_rvalid_o,
    input wire p5_rready_i,
    // p6 upstream.
    input wire p6_awid_i,
    input wire [31:0] p6_awaddr_i,
    input wire [3:0] p6_awlen_i,
    input wire p6_awvalid_i,
    output wire p6_awready_o,
    input wire [255:0] p6_wdata_i,
    input wire [31:0] p6_wstrb_i,
    input wire p6_wlast_i,
    input wire p6_wvalid_i,
    output wire p6_wready_o,
    output wire p6_bid_o,
    output wire [1:0] p6_bresp_o,
    output wire p6_bvalid_o,
    input wire p6_bready_i,
    input wire p6_arid_i,
    input wire [31:0] p6_araddr_i,
    input wire [3:0] p6_arlen_i,
    input wire p6_arvalid_i,
    output wire p6_arready_o,
    output wire p6_rid_o,
    output wire [255:0] p6_rdata_o,
    output wire [1:0] p6_rresp_o,
    output wire p6_rlast_o,
    output wire p6_rvalid_o,
    input wire p6_rready_i,
    // DDR downstream.
    output wire [3:0] ddr_awid_o,
    output wire [31:0] ddr_awaddr_o,
    output wire [3:0] ddr_awlen_o,
    output wire ddr_awvalid_o,
    input wire ddr_awready_i,
    output wire [255:0] ddr_wdata_o,
    output wire [31:0] ddr_wstrb_o,
    output wire ddr_wlast_o,
    output wire ddr_wvalid_o,
    input wire ddr_wready_i,
    input wire [3:0] ddr_bid_i,
    input wire [1:0] ddr_bresp_i,
    input wire ddr_bvalid_i,
    output wire [3:0] ddr_arid_o,
    output wire [31:0] ddr_araddr_o,
    output wire [3:0] ddr_arlen_o,
    output wire ddr_arvalid_o,
    input wire ddr_arready_i,
    input wire [3:0] ddr_rid_i,
    input wire [255:0] ddr_rdata_i,
    input wire [1:0] ddr_rresp_i,
    input wire ddr_rlast_i,
    input wire ddr_rvalid_i,
    // APB control.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output wire [31:0] apb_prdata_o,
    output wire apb_pslverr_o,
    // Interrupt.
    output wire irq_o
);
    wire [6:0] awid_w;
    assign awid_w = {p6_awid_i, p5_awid_i, p4_awid_i, p3_awid_i, p2_awid_i, p1_awid_i, 1'b0};
    wire [223:0] awaddr_w;
    assign awaddr_w = {p6_awaddr_i,
        p5_awaddr_i,
        p4_awaddr_i,
        p3_awaddr_i,
        p2_awaddr_i,
        p1_awaddr_i,
        32'b0};
    wire [27:0] awlen_w;
    assign awlen_w = {p6_awlen_i, p5_awlen_i, p4_awlen_i, p3_awlen_i, p2_awlen_i, p1_awlen_i, 4'b0};
    wire [6:0] awvalid_w;
    assign awvalid_w = {p6_awvalid_i,
        p5_awvalid_i,
        p4_awvalid_i,
        p3_awvalid_i,
        p2_awvalid_i,
        p1_awvalid_i,
        1'b0};
    wire [6:0] awready_w;
    wire unused_p0_awready_w;
    assign {p6_awready_o,
        p5_awready_o,
        p4_awready_o,
        p3_awready_o,
        p2_awready_o,
        p1_awready_o,
        unused_p0_awready_w} = awready_w;
    wire [1791:0] wdata_w;
    assign wdata_w = {p6_wdata_i,
        p5_wdata_i,
        p4_wdata_i,
        p3_wdata_i,
        p2_wdata_i,
        p1_wdata_i,
        256'b0};
    wire [223:0] wstrb_w;
    assign wstrb_w = {p6_wstrb_i,
        p5_wstrb_i,
        p4_wstrb_i,
        p3_wstrb_i,
        p2_wstrb_i,
        p1_wstrb_i,
        32'b0};
    wire [6:0] wlast_w;
    assign wlast_w = {p6_wlast_i, p5_wlast_i, p4_wlast_i, p3_wlast_i, p2_wlast_i, p1_wlast_i, 1'b0};
    wire [6:0] wvalid_w;
    assign wvalid_w = {p6_wvalid_i,
        p5_wvalid_i,
        p4_wvalid_i,
        p3_wvalid_i,
        p2_wvalid_i,
        p1_wvalid_i,
        1'b0};
    wire [6:0] wready_w;
    wire unused_p0_wready_w;
    assign {p6_wready_o,
        p5_wready_o,
        p4_wready_o,
        p3_wready_o,
        p2_wready_o,
        p1_wready_o,
        unused_p0_wready_w} = wready_w;
    wire [6:0] bid_w;
    wire unused_p0_bid_w;
    assign {p6_bid_o, p5_bid_o, p4_bid_o, p3_bid_o, p2_bid_o, p1_bid_o, unused_p0_bid_w} = bid_w;
    wire [13:0] bresp_w;
    wire [1:0] unused_p0_bresp_w;
    assign {p6_bresp_o,
        p5_bresp_o,
        p4_bresp_o,
        p3_bresp_o,
        p2_bresp_o,
        p1_bresp_o,
        unused_p0_bresp_w} = bresp_w;
    wire [6:0] bvalid_w;
    wire unused_p0_bvalid_w;
    assign {p6_bvalid_o,
        p5_bvalid_o,
        p4_bvalid_o,
        p3_bvalid_o,
        p2_bvalid_o,
        p1_bvalid_o,
        unused_p0_bvalid_w} = bvalid_w;
    wire [6:0] bready_w;
    assign bready_w = {p6_bready_i,
        p5_bready_i,
        p4_bready_i,
        p3_bready_i,
        p2_bready_i,
        p1_bready_i,
        1'b0};
    wire [6:0] arid_w;
    assign arid_w = {p6_arid_i, p5_arid_i, p4_arid_i, p3_arid_i, p2_arid_i, 1'b0, p0_arid_i};
    wire [223:0] araddr_w;
    assign araddr_w = {p6_araddr_i,
        p5_araddr_i,
        p4_araddr_i,
        p3_araddr_i,
        p2_araddr_i,
        32'b0,
        p0_araddr_i};
    wire [27:0] arlen_w;
    assign arlen_w = {p6_arlen_i, p5_arlen_i, p4_arlen_i, p3_arlen_i, p2_arlen_i, 4'b0, p0_arlen_i};
    wire [6:0] arvalid_w;
    assign arvalid_w = {p6_arvalid_i,
        p5_arvalid_i,
        p4_arvalid_i,
        p3_arvalid_i,
        p2_arvalid_i,
        1'b0,
        p0_arvalid_i};
    wire [6:0] arready_w;
    wire unused_p1_arready_w;
    assign {p6_arready_o,
        p5_arready_o,
        p4_arready_o,
        p3_arready_o,
        p2_arready_o,
        unused_p1_arready_w,
        p0_arready_o} = arready_w;
    wire [6:0] rid_w;
    wire unused_p1_rid_w;
    assign {p6_rid_o, p5_rid_o, p4_rid_o, p3_rid_o, p2_rid_o, unused_p1_rid_w, p0_rid_o} = rid_w;
    wire [1791:0] rdata_w;
    wire [255:0] unused_p1_rdata_w;
    assign {p6_rdata_o,
        p5_rdata_o,
        p4_rdata_o,
        p3_rdata_o,
        p2_rdata_o,
        unused_p1_rdata_w,
        p0_rdata_o} = rdata_w;
    wire [13:0] rresp_w;
    wire [1:0] unused_p1_rresp_w;
    assign {p6_rresp_o,
        p5_rresp_o,
        p4_rresp_o,
        p3_rresp_o,
        p2_rresp_o,
        unused_p1_rresp_w,
        p0_rresp_o} = rresp_w;
    wire [6:0] rlast_w;
    wire unused_p1_rlast_w;
    assign {p6_rlast_o,
        p5_rlast_o,
        p4_rlast_o,
        p3_rlast_o,
        p2_rlast_o,
        unused_p1_rlast_w,
        p0_rlast_o} = rlast_w;
    wire [6:0] rvalid_w;
    wire unused_p1_rvalid_w;
    assign {p6_rvalid_o,
        p5_rvalid_o,
        p4_rvalid_o,
        p3_rvalid_o,
        p2_rvalid_o,
        unused_p1_rvalid_w,
        p0_rvalid_o} = rvalid_w;
    wire [6:0] rready_w;
    assign rready_w = {p6_rready_i,
        p5_rready_i,
        p4_rready_i,
        p3_rready_i,
        p2_rready_i,
        1'b0,
        p0_rready_i};
    wire unused_no_w_port_w;
    assign unused_no_w_port_w = &{wdata_w[255:0], wstrb_w[31:0]};
    wire unused_pstrb_w;
    assign unused_pstrb_w = &apb_pstrb_i;
    reg [6:0] aw_pending_r;
    reg [6:0] ar_pending_r;
    reg [6:0] awid_r;
    reg [6:0] arid_r;
    reg [31:0] awaddr_r [0:6];
    reg [31:0] araddr_r [0:6];
    reg [3:0] awlen_r [0:6];
    reg [3:0] arlen_r [0:6];
    reg [2:0] aw_error_r [0:6];
    reg [2:0] ar_error_r [0:6];
    reg [31:0] aw_wait_r [0:6];
    reg [31:0] ar_wait_r [0:6];
    reg [6:0] w_complete_r;
    reg [4:0] w_count_r [0:6];
    wire [2015:0] w_ram_data_w;
    reg w_active_r;
    reg [2:0] w_port_r;
    reg [3:0] w_index_r;
    reg [3:0] w_length_r;
    reg cmd_valid_r;
    reg cmd_write_r;
    reg [31:0] cmd_wait_r;
    reg cmd_urgent_r;
    reg cmd_switch_r;
    wire [31:0] stat_wait_w;
    reg [3:0] cmd_id_r;
    reg [31:0] cmd_addr_r;
    reg [3:0] cmd_len_r;
    wire cmd_take_w;
    wire w_take_w;
    reg [3:0] ds_count_r;
    reg [3:0] rd_count_r [0:6];
    reg [3:0] wr_count_r [0:6];
    reg [2:0] b_head_r [0:6];
    reg [2:0] b_tail_r [0:6];
    reg [3:0] b_count_r [0:6];
    reg [2:0] b_fifo_r [0:55];
    wire [31:0] outst_total_w;
    wire [31:0] urg_max_w;
    wire [31:0] starve_cyc_w;
    wire [31:0] dir_batch_w;
    wire [223:0] outst_rd_w;
    wire [223:0] outst_wr_w;
    wire [223:0] weight_w;
    wire [223:0] rate_w;
    reg [13:0] eligible_w;
    reg [69:0] beats_w;
    reg [447:0] wait_w;
    wire grant_w;
    wire [2:0] grant_port_w;
    wire grant_write_w;
    wire grant_urgent_w;
    wire dir_switch_w;
    reg bad_read_w;
    reg [2:0] bad_read_port_w;
    reg bad_write_w;
    reg [2:0] bad_write_port_w;
    wire reserve_w;
    wire [2:0] reserve_port_w;
    wire reserve_id_w;
    wire [4:0] reserve_beats_w;
    wire [7:0] free_cnt_w;
    reg err_valid_w;
    reg [2:0] err_port_w;
    reg [31:0] err_addr_w;
    reg [2:0] err_type_w;
    reg busy_w;
    integer eligible_idx;
    integer error_idx;
    integer update_idx;
    integer payload_idx;
    genvar p;
    function [2:0] violation;
        input [11:0] addr_i;
        input [3:0] len_i;
        begin
            violation = {addr_i[4:0] != 0, 1'b0,
                ({1'b0, addr_i} + ({9'b0, len_i} + 13'd1)*13'd32) > 13'd4096};
        end
    endfunction
    assign stat_wait_w = cmd_wait_r == 32'hffff_ffff ? cmd_wait_r : cmd_wait_r + 32'd1;
    assign cmd_take_w = cmd_valid_r &&
                        (cmd_write_r ? ddr_awready_i : ddr_arready_i);
    assign ddr_awvalid_o = rst_n_i && cmd_valid_r && cmd_write_r;
    assign ddr_arvalid_o = rst_n_i && cmd_valid_r && !cmd_write_r;
    assign ddr_awid_o = cmd_id_r;
    assign ddr_awaddr_o = cmd_addr_r;
    assign ddr_awlen_o = cmd_len_r;
    assign ddr_arid_o = cmd_id_r;
    assign ddr_araddr_o = cmd_addr_r;
    assign ddr_arlen_o = cmd_len_r;
    assign ddr_wvalid_o = rst_n_i && w_active_r;
    assign ddr_wdata_o = w_ram_data_w[w_port_r*288 +: 256];
    assign ddr_wstrb_o = w_ram_data_w[w_port_r*288+256 +: 32];
    assign ddr_wlast_o = w_index_r == w_length_r;
    assign w_take_w = ddr_wvalid_o && ddr_wready_i;
    assign reserve_w = bad_read_w || (grant_w && !grant_write_w);
    assign reserve_port_w = bad_read_w ? bad_read_port_w : grant_port_w;
    assign reserve_id_w = arid_r[reserve_port_w];
    assign reserve_beats_w = {1'b0, arlen_r[reserve_port_w]} + 5'd1;
    generate
        for (p = 0; p < 7; p = p + 1) begin : g_port
            wire w_read_w;
            wire [3:0] w_addr_w;
            assign awready_w[p] = rst_n_i && !aw_pending_r[p] &&
                !(cmd_valid_r && cmd_write_r && cmd_id_r[3:1] == p) &&
                                    !(w_active_r && w_port_r == p) && p != 0;
            assign arready_w[p] = rst_n_i && !ar_pending_r[p] && p != 1;
            assign wready_w[p] = rst_n_i && !w_complete_r[p] &&
                                    !(w_active_r && w_port_r == p) && p != 0;
            assign bvalid_w[p] = rst_n_i && b_count_r[p] != 0;
            assign bid_w[p] = b_fifo_r[p*8+{29'b0, b_head_r[p]}][2];
            assign bresp_w[p*2 +: 2] = b_fifo_r[p*8+{29'b0, b_head_r[p]}][1:0];
            assign w_read_w = (cmd_take_w && cmd_write_r && cmd_id_r[3:1] == p) ||
                                (w_take_w && !ddr_wlast_o && w_port_r == p);
            assign w_addr_w = w_active_r ? w_index_r + 4'd1 : 4'b0;
            if (p != 0) begin : g_w_ram
                edrv32_ram_mem_xbar_w u_ram (
                    .clk_i(clk_i),
                    .wr_en_i(wvalid_w[p] && wready_w[p]),
                    .wr_addr_i(w_count_r[p][3:0]),
                    .wr_data_i({wstrb_w[p*32 +: 32], wdata_w[p*256 +: 256]}),
                    .rd_en_i(w_read_w),
                    .rd_addr_i(w_addr_w),
                    .rd_data_o(w_ram_data_w[p*288 +: 288])
                );
            end else begin : g_no_w_ram
                wire unused_read_w;
                assign unused_read_w = w_read_w ^ &w_addr_w;
                assign w_ram_data_w[p*288 +: 288] = 288'b0;
            end
        end
    endgenerate
    edrv32_mem_xbar_rbuf u_rbuf (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .reserve_i(reserve_w),
        .reserve_port_i(reserve_port_w),
        .reserve_id_i(reserve_id_w),
        .reserve_beats_i(reserve_beats_w),
        .reserve_error_i(bad_read_w),
        .free_cnt_o(free_cnt_w),
        .ddr_rid_i(ddr_rid_i),
        .ddr_rdata_i(ddr_rdata_i),
        .ddr_rresp_i(ddr_rresp_i),
        .ddr_rlast_i(ddr_rlast_i),
        .ddr_rvalid_i(ddr_rvalid_i),
        .rid_o(rid_w),
        .rdata_o(rdata_w),
        .rresp_o(rresp_w),
        .rlast_o(rlast_w),
        .rvalid_o(rvalid_w),
        .rready_i(rready_w)
    );
    edrv32_mem_xbar_sched u_sched (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .enable_i(rst_n_i && !cmd_valid_r && !bad_read_w),
        .eligible_i(eligible_w),
        .beats_i(beats_w),
        .wait_i(wait_w),
        .urgent_i({p1_urgent_i, p0_urgent_i}),
        .grant_o(grant_w),
        .port_o(grant_port_w),
        .write_o(grant_write_w),
        .urgent_o(grant_urgent_w),
        .dir_switch_o(dir_switch_w),
        .urg_max_i(urg_max_w),
        .starve_cyc_i(starve_cyc_w),
        .dir_batch_i(dir_batch_w),
        .weight_i(weight_w),
        .rate_i(rate_w)
    );
    edrv32_mem_xbar_regs u_regs (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .apb_paddr_i(apb_paddr_i),
        .apb_psel_i(apb_psel_i),
        .apb_penable_i(apb_penable_i),
        .apb_pwrite_i(apb_pwrite_i),
        .apb_pwdata_i(apb_pwdata_i),
        .apb_pready_o(apb_pready_o),
        .apb_prdata_o(apb_prdata_o),
        .apb_pslverr_o(apb_pslverr_o),
        .outst_total_o(outst_total_w),
        .urg_max_o(urg_max_w),
        .starve_cyc_o(starve_cyc_w),
        .dir_batch_o(dir_batch_w),
        .outst_rd_o(outst_rd_w),
        .outst_wr_o(outst_wr_w),
        .weight_o(weight_w),
        .rate_o(rate_w),
        .grant_i(cmd_take_w),
        .grant_port_i(cmd_id_r[3:1]),
        .grant_beats_i({1'b0, cmd_len_r} + 5'd1),
        .grant_wait_i(stat_wait_w),
        .grant_urgent_i(cmd_urgent_r),
        .dir_switch_i(cmd_take_w && cmd_switch_r),
        .ds_busy_i(ds_count_r != 0),
        .busy_i(busy_w),
        .err_valid_i(err_valid_w),
        .err_port_i(err_port_w),
        .err_addr_i(err_addr_w),
        .err_type_i(err_type_w),
        .irq_o(irq_o)
    );
    always @(*) begin
        eligible_w = 14'b0;
        beats_w = 70'b0;
        wait_w = 448'b0;
        bad_read_w = 1'b0;
        bad_read_port_w = 3'b0;
        bad_write_w = 1'b0;
        bad_write_port_w = 3'b0;
        busy_w = cmd_valid_r || w_active_r || ds_count_r != 0 || free_cnt_w != 8'd128;
        for (eligible_idx = 0; eligible_idx < 7; eligible_idx = eligible_idx + 1) begin
            beats_w[(eligible_idx*2)*5 +: 5] = {1'b0, arlen_r[eligible_idx]} + 5'd1;
            beats_w[(eligible_idx*2+1)*5 +: 5] = {1'b0, awlen_r[eligible_idx]} + 5'd1;
            wait_w[(eligible_idx*2)*32 +: 32] = ar_wait_r[eligible_idx];
            wait_w[(eligible_idx*2+1)*32 +: 32] = aw_wait_r[eligible_idx];
            if ({28'b0, ds_count_r} < outst_total_w) begin
                eligible_w[eligible_idx*2] = ar_pending_r[eligible_idx] &&
                    ar_error_r[eligible_idx] == 0 &&
                    {28'b0, rd_count_r[eligible_idx]} < outst_rd_w[eligible_idx*32 +: 32] &&
                    free_cnt_w >= {4'b0, arlen_r[eligible_idx]} + 8'd1;
                eligible_w[eligible_idx*2+1] = aw_pending_r[eligible_idx] &&
                    aw_error_r[eligible_idx] == 0 && w_complete_r[eligible_idx] &&
                    !w_active_r &&
                    {28'b0, wr_count_r[eligible_idx]} < outst_wr_w[eligible_idx*32 +: 32];
            end
            if (!bad_read_w && ar_pending_r[eligible_idx] &&
                ar_error_r[eligible_idx] != 0 && rd_count_r[eligible_idx] < 8 &&
                free_cnt_w >= {4'b0, arlen_r[eligible_idx]} + 8'd1) begin
                bad_read_w = 1'b1;
                bad_read_port_w = eligible_idx[2:0];
            end
            // A local B error waits behind previously accepted writes, preserving ID order.
            if (!bad_write_w && aw_pending_r[eligible_idx] &&
                aw_error_r[eligible_idx] != 0 && w_complete_r[eligible_idx] &&
                wr_count_r[eligible_idx] == 0 &&
                !(ddr_bvalid_i && {29'b0, ddr_bid_i[3:1]} == eligible_idx)) begin
                bad_write_w = 1'b1;
                bad_write_port_w = eligible_idx[2:0];
            end
            busy_w = busy_w || ar_pending_r[eligible_idx] || aw_pending_r[eligible_idx] ||
                        w_count_r[eligible_idx] != 0 || b_count_r[eligible_idx] != 0;
        end
    end
    // Report violations at ingress; no additional protocol checks are implemented.
    always @(*) begin
        err_valid_w = 1'b0;
        err_port_w = 3'b0;
        err_addr_w = 32'b0;
        err_type_w = 3'b0;
        for (error_idx = 0; error_idx < 7; error_idx = error_idx + 1) begin
            if (arvalid_w[error_idx] && arready_w[error_idx] &&
                violation(araddr_w[error_idx*32 +: 12], arlen_w[error_idx*4 +: 4]) != 0)
            begin
                err_valid_w = 1'b1;
                err_port_w = error_idx[2:0];
                err_addr_w = araddr_w[error_idx*32 +: 32];
                err_type_w = violation(araddr_w[error_idx*32 +: 12], arlen_w[error_idx*4 +: 4]);
            end
            if (awvalid_w[error_idx] && awready_w[error_idx] &&
                violation(awaddr_w[error_idx*32 +: 12], awlen_w[error_idx*4 +: 4]) != 0)
            begin
                err_valid_w = 1'b1;
                err_port_w = error_idx[2:0];
                err_addr_w = awaddr_w[error_idx*32 +: 32];
                err_type_w = violation(awaddr_w[error_idx*32 +: 12], awlen_w[error_idx*4 +: 4]);
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            aw_pending_r <= 7'b0;
            ar_pending_r <= 7'b0;
            w_complete_r <= 7'b0;
            w_active_r <= 1'b0;
            w_port_r <= 3'b0;
            w_index_r <= 4'b0;
            w_length_r <= 4'b0;
            cmd_valid_r <= 1'b0;
            cmd_write_r <= 1'b0;
            cmd_wait_r <= 32'b0;
            ds_count_r <= 4'b0;
            for (update_idx = 0; update_idx < 7; update_idx = update_idx + 1) begin
                w_count_r[update_idx] <= 5'b0;
                rd_count_r[update_idx] <= 4'b0;
                wr_count_r[update_idx] <= 4'b0;
                b_count_r[update_idx] <= 4'b0;
                b_head_r[update_idx] <= 3'b0;
                b_tail_r[update_idx] <= 3'b0;
                aw_wait_r[update_idx] <= 32'b0;
                ar_wait_r[update_idx] <= 32'b0;
            end
        end else begin
            ds_count_r <= ds_count_r + (cmd_take_w ? 4'd1 : 4'd0) -
                            (ddr_bvalid_i ? 4'd1 : 4'd0) -
                            (ddr_rvalid_i && ddr_rlast_i ? 4'd1 : 4'd0);
            if (cmd_valid_r && cmd_wait_r != 32'hffff_ffff) begin
                cmd_wait_r <= cmd_wait_r + 32'd1;
            end
            if (cmd_take_w) begin
                cmd_valid_r <= 1'b0;
                if (cmd_write_r) begin
                    w_active_r <= 1'b1;
                    w_port_r <= cmd_id_r[3:1];
                    w_index_r <= 4'b0;
                    w_length_r <= cmd_len_r;
                end
            end
            if (w_take_w) begin
                w_index_r <= w_index_r + 4'd1;
                if (ddr_wlast_o) begin
                    w_active_r <= 1'b0;
                    w_complete_r[w_port_r] <= 1'b0;
                    w_count_r[w_port_r] <= 5'b0;
                end
            end
            if (grant_w) begin
                cmd_valid_r <= 1'b1;
                cmd_write_r <= grant_write_w;
                cmd_wait_r <= grant_write_w ?
                    (aw_wait_r[grant_port_w] == 32'hffff_ffff ? 32'hffff_ffff :
                        aw_wait_r[grant_port_w] + 32'd1) :
                    (ar_wait_r[grant_port_w] == 32'hffff_ffff ? 32'hffff_ffff :
                        ar_wait_r[grant_port_w] + 32'd1);
            end
            for (update_idx = 0; update_idx < 7; update_idx = update_idx + 1) begin
                rd_count_r[update_idx] <= rd_count_r[update_idx] +
                    ((reserve_w && {29'b0, reserve_port_w} == update_idx) ? 4'd1 : 4'd0) -
                    ((rvalid_w[update_idx] && rready_w[update_idx] && rlast_w[update_idx]) ?
                        4'd1 : 4'd0);
                wr_count_r[update_idx] <= wr_count_r[update_idx] +
                    ((grant_w && grant_write_w && {29'b0, grant_port_w} == update_idx) ||
                        (bad_write_w && {29'b0, bad_write_port_w} == update_idx) ? 4'd1 : 4'd0) -
                    ((bvalid_w[update_idx] && bready_w[update_idx]) ? 4'd1 : 4'd0);
                b_count_r[update_idx] <= b_count_r[update_idx] +
                    ((ddr_bvalid_i && {29'b0, ddr_bid_i[3:1]} == update_idx) ||
                        (bad_write_w && {29'b0, bad_write_port_w} == update_idx) ? 4'd1 : 4'd0) -
                    ((bvalid_w[update_idx] && bready_w[update_idx]) ? 4'd1 : 4'd0);
                if (bvalid_w[update_idx] && bready_w[update_idx]) begin
                    b_head_r[update_idx] <= b_head_r[update_idx] + 3'd1;
                end
                if ((ddr_bvalid_i && {29'b0, ddr_bid_i[3:1]} == update_idx) ||
                    (bad_write_w && {29'b0, bad_write_port_w} == update_idx)) begin
                    b_tail_r[update_idx] <= b_tail_r[update_idx] + 3'd1;
                end
                if (wvalid_w[update_idx] && wready_w[update_idx]) begin
                    w_count_r[update_idx] <= w_count_r[update_idx] + 5'd1;
                    if (wlast_w[update_idx]) begin
                        w_complete_r[update_idx] <= 1'b1;
                    end
                end
                if (awvalid_w[update_idx] && awready_w[update_idx]) begin
                    aw_pending_r[update_idx] <= 1'b1;
                    aw_wait_r[update_idx] <= 32'b0;
                end else if (aw_pending_r[update_idx] && w_complete_r[update_idx] &&
                    aw_wait_r[update_idx] != 32'hffff_ffff)
                begin
                    aw_wait_r[update_idx] <= aw_wait_r[update_idx] + 32'd1;
                end
                if (arvalid_w[update_idx] && arready_w[update_idx]) begin
                    ar_pending_r[update_idx] <= 1'b1;
                    ar_wait_r[update_idx] <= 32'b0;
                end else if (ar_pending_r[update_idx] && ar_wait_r[update_idx] != 32'hffff_ffff)
                begin
                    ar_wait_r[update_idx] <= ar_wait_r[update_idx] + 32'd1;
                end
                if ((grant_w && grant_write_w && {29'b0, grant_port_w} == update_idx) ||
                    (bad_write_w && {29'b0, bad_write_port_w} == update_idx)) begin
                    aw_pending_r[update_idx] <= 1'b0;
                    aw_wait_r[update_idx] <= 32'b0;
                end
                if (reserve_w && {29'b0, reserve_port_w} == update_idx) begin
                    ar_pending_r[update_idx] <= 1'b0;
                    ar_wait_r[update_idx] <= 32'b0;
                end
                if (bad_write_w && {29'b0, bad_write_port_w} == update_idx) begin
                    w_complete_r[update_idx] <= 1'b0;
                    w_count_r[update_idx] <= 5'b0;
                end
            end
        end
    end
    // Transaction and response payloads are not reset.
    always @(posedge clk_i) begin
        for (payload_idx = 0; payload_idx < 7; payload_idx = payload_idx + 1) begin
            if (awvalid_w[payload_idx] && awready_w[payload_idx]) begin
                awid_r[payload_idx] <= awid_w[payload_idx];
                awaddr_r[payload_idx] <= awaddr_w[payload_idx*32 +: 32];
                awlen_r[payload_idx] <= awlen_w[payload_idx*4 +: 4];
                aw_error_r[payload_idx] <=
                    violation(awaddr_w[payload_idx*32 +: 12], awlen_w[payload_idx*4 +: 4]);
            end
            if (arvalid_w[payload_idx] && arready_w[payload_idx]) begin
                arid_r[payload_idx] <= arid_w[payload_idx];
                araddr_r[payload_idx] <= araddr_w[payload_idx*32 +: 32];
                arlen_r[payload_idx] <= arlen_w[payload_idx*4 +: 4];
                ar_error_r[payload_idx] <=
                    violation(araddr_w[payload_idx*32 +: 12], arlen_w[payload_idx*4 +: 4]);
            end
            if (ddr_bvalid_i && {29'b0, ddr_bid_i[3:1]} == payload_idx) begin
                b_fifo_r[payload_idx*8+{29'b0, b_tail_r[payload_idx]}] <=
                    {ddr_bid_i[0], ddr_bresp_i};
            end
            if (bad_write_w && {29'b0, bad_write_port_w} == payload_idx) begin
                b_fifo_r[payload_idx*8+{29'b0, b_tail_r[payload_idx]}] <=
                    {awid_r[payload_idx], 2'b10};
            end
        end
        if (grant_w) begin
            cmd_urgent_r <= grant_urgent_w;
            cmd_switch_r <= dir_switch_w;
            cmd_id_r <= {grant_port_w, grant_write_w ?
                            awid_r[grant_port_w] : arid_r[grant_port_w]};
            cmd_addr_r <= grant_write_w ? awaddr_r[grant_port_w] : araddr_r[grant_port_w];
            cmd_len_r <= grant_write_w ? awlen_r[grant_port_w] : arlen_r[grant_port_w];
        end
    end
endmodule
