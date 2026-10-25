// File: edrv32_bus_sys_xbar.v
// Spec: sys-subsys-spec 2.1, 3.1, 5, 6, 7.
// Description: Independent per-target read ownership and M1 write routing with local DECERR.
//              Hold each target channel through the final response handshake.
// Clock domain: clk_sys.
module edrv32_bus_sys_xbar (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // m0 AR channel.
    input wire [3:0] m0_arid_i,
    input wire [31:0] m0_araddr_i,
    input wire [7:0] m0_arlen_i,
    input wire [2:0] m0_arsize_i,
    input wire [1:0] m0_arburst_i,
    input wire m0_arvalid_i,
    output wire m0_arready_o,

    // m0 R channel.
    output wire [3:0] m0_rid_o,
    output wire [63:0] m0_rdata_o,
    output wire [1:0] m0_rresp_o,
    output wire m0_rlast_o,
    output wire m0_rvalid_o,
    input wire m0_rready_i,

    // m1 AW channel.
    input wire [3:0] m1_awid_i,
    input wire [31:0] m1_awaddr_i,
    input wire [7:0] m1_awlen_i,
    input wire [2:0] m1_awsize_i,
    input wire [1:0] m1_awburst_i,
    input wire m1_awvalid_i,
    output wire m1_awready_o,

    // m1 W channel.
    input wire [63:0] m1_wdata_i,
    input wire [7:0] m1_wstrb_i,
    input wire m1_wlast_i,
    input wire m1_wvalid_i,
    output wire m1_wready_o,

    // m1 B channel.
    output wire [3:0] m1_bid_o,
    output wire [1:0] m1_bresp_o,
    output wire m1_bvalid_o,
    input wire m1_bready_i,

    // m1 AR channel.
    input wire [3:0] m1_arid_i,
    input wire [31:0] m1_araddr_i,
    input wire [7:0] m1_arlen_i,
    input wire [2:0] m1_arsize_i,
    input wire [1:0] m1_arburst_i,
    input wire m1_arvalid_i,
    output wire m1_arready_o,

    // m1 R channel.
    output wire [3:0] m1_rid_o,
    output wire [63:0] m1_rdata_o,
    output wire [1:0] m1_rresp_o,
    output wire m1_rlast_o,
    output wire m1_rvalid_o,
    input wire m1_rready_i,

    // s0 AW channel.
    output wire [3:0] s0_awid_o,
    output wire [31:0] s0_awaddr_o,
    output wire [7:0] s0_awlen_o,
    output wire [2:0] s0_awsize_o,
    output wire [1:0] s0_awburst_o,
    output wire s0_awvalid_o,
    input wire s0_awready_i,

    // s0 W channel.
    output wire [63:0] s0_wdata_o,
    output wire [7:0] s0_wstrb_o,
    output wire s0_wlast_o,
    output wire s0_wvalid_o,
    input wire s0_wready_i,

    // s0 B channel.
    input wire [3:0] s0_bid_i,
    input wire [1:0] s0_bresp_i,
    input wire s0_bvalid_i,
    output wire s0_bready_o,

    // s0 AR channel.
    output wire [3:0] s0_arid_o,
    output wire [31:0] s0_araddr_o,
    output wire [7:0] s0_arlen_o,
    output wire [2:0] s0_arsize_o,
    output wire [1:0] s0_arburst_o,
    output wire s0_arvalid_o,
    input wire s0_arready_i,

    // s0 R channel.
    input wire [3:0] s0_rid_i,
    input wire [63:0] s0_rdata_i,
    input wire [1:0] s0_rresp_i,
    input wire s0_rlast_i,
    input wire s0_rvalid_i,
    output wire s0_rready_o,

    // s1 AW channel.
    output wire [3:0] s1_awid_o,
    output wire [31:0] s1_awaddr_o,
    output wire [7:0] s1_awlen_o,
    output wire [2:0] s1_awsize_o,
    output wire [1:0] s1_awburst_o,
    output wire s1_awvalid_o,
    input wire s1_awready_i,

    // s1 W channel.
    output wire [63:0] s1_wdata_o,
    output wire [7:0] s1_wstrb_o,
    output wire s1_wlast_o,
    output wire s1_wvalid_o,
    input wire s1_wready_i,

    // s1 B channel.
    input wire [3:0] s1_bid_i,
    input wire [1:0] s1_bresp_i,
    input wire s1_bvalid_i,
    output wire s1_bready_o,

    // s1 AR channel.
    output wire [3:0] s1_arid_o,
    output wire [31:0] s1_araddr_o,
    output wire [7:0] s1_arlen_o,
    output wire [2:0] s1_arsize_o,
    output wire [1:0] s1_arburst_o,
    output wire s1_arvalid_o,
    input wire s1_arready_i,

    // s1 R channel.
    input wire [3:0] s1_rid_i,
    input wire [63:0] s1_rdata_i,
    input wire [1:0] s1_rresp_i,
    input wire s1_rlast_i,
    input wire s1_rvalid_i,
    output wire s1_rready_o,

    // s2 AW channel.
    output wire [3:0] s2_awid_o,
    output wire [31:0] s2_awaddr_o,
    output wire [7:0] s2_awlen_o,
    output wire [2:0] s2_awsize_o,
    output wire [1:0] s2_awburst_o,
    output wire s2_awvalid_o,
    input wire s2_awready_i,

    // s2 W channel.
    output wire [63:0] s2_wdata_o,
    output wire [7:0] s2_wstrb_o,
    output wire s2_wlast_o,
    output wire s2_wvalid_o,
    input wire s2_wready_i,

    // s2 B channel.
    input wire [3:0] s2_bid_i,
    input wire [1:0] s2_bresp_i,
    input wire s2_bvalid_i,
    output wire s2_bready_o,

    // s2 AR channel.
    output wire [3:0] s2_arid_o,
    output wire [31:0] s2_araddr_o,
    output wire [7:0] s2_arlen_o,
    output wire [2:0] s2_arsize_o,
    output wire [1:0] s2_arburst_o,
    output wire s2_arvalid_o,
    input wire s2_arready_i,

    // s2 R channel.
    input wire [3:0] s2_rid_i,
    input wire [63:0] s2_rdata_i,
    input wire [1:0] s2_rresp_i,
    input wire s2_rlast_i,
    input wire s2_rvalid_i,
    output wire s2_rready_o,

    // s3 AW channel.
    output wire [3:0] s3_awid_o,
    output wire [31:0] s3_awaddr_o,
    output wire [7:0] s3_awlen_o,
    output wire [2:0] s3_awsize_o,
    output wire [1:0] s3_awburst_o,
    output wire s3_awvalid_o,
    input wire s3_awready_i,

    // s3 W channel.
    output wire [63:0] s3_wdata_o,
    output wire [7:0] s3_wstrb_o,
    output wire s3_wlast_o,
    output wire s3_wvalid_o,
    input wire s3_wready_i,

    // s3 B channel.
    input wire [3:0] s3_bid_i,
    input wire [1:0] s3_bresp_i,
    input wire s3_bvalid_i,
    output wire s3_bready_o,

    // s3 AR channel.
    output wire [3:0] s3_arid_o,
    output wire [31:0] s3_araddr_o,
    output wire [7:0] s3_arlen_o,
    output wire [2:0] s3_arsize_o,
    output wire [1:0] s3_arburst_o,
    output wire s3_arvalid_o,
    input wire s3_arready_i,

    // s3 R channel.
    input wire [3:0] s3_rid_i,
    input wire [63:0] s3_rdata_i,
    input wire [1:0] s3_rresp_i,
    input wire s3_rlast_i,
    input wire s3_rvalid_i,
    output wire s3_rready_o,

    // s4 AW channel.
    output wire [3:0] s4_awid_o,
    output wire [31:0] s4_awaddr_o,
    output wire [7:0] s4_awlen_o,
    output wire [2:0] s4_awsize_o,
    output wire [1:0] s4_awburst_o,
    output wire s4_awvalid_o,
    input wire s4_awready_i,

    // s4 W channel.
    output wire [63:0] s4_wdata_o,
    output wire [7:0] s4_wstrb_o,
    output wire s4_wlast_o,
    output wire s4_wvalid_o,
    input wire s4_wready_i,

    // s4 B channel.
    input wire [3:0] s4_bid_i,
    input wire [1:0] s4_bresp_i,
    input wire s4_bvalid_i,
    output wire s4_bready_o,

    // s4 AR channel.
    output wire [3:0] s4_arid_o,
    output wire [31:0] s4_araddr_o,
    output wire [7:0] s4_arlen_o,
    output wire [2:0] s4_arsize_o,
    output wire [1:0] s4_arburst_o,
    output wire s4_arvalid_o,
    input wire s4_arready_i,

    // s4 R channel.
    input wire [3:0] s4_rid_i,
    input wire [63:0] s4_rdata_i,
    input wire [1:0] s4_rresp_i,
    input wire s4_rlast_i,
    input wire s4_rvalid_i,
    output wire s4_rready_o,

    // s5 AW channel.
    output wire [3:0] s5_awid_o,
    output wire [31:0] s5_awaddr_o,
    output wire [7:0] s5_awlen_o,
    output wire [2:0] s5_awsize_o,
    output wire [1:0] s5_awburst_o,
    output wire s5_awvalid_o,
    input wire s5_awready_i,

    // s5 W channel.
    output wire [63:0] s5_wdata_o,
    output wire [7:0] s5_wstrb_o,
    output wire s5_wlast_o,
    output wire s5_wvalid_o,
    input wire s5_wready_i,

    // s5 B channel.
    input wire [3:0] s5_bid_i,
    input wire [1:0] s5_bresp_i,
    input wire s5_bvalid_i,
    output wire s5_bready_o,

    // s5 AR channel.
    output wire [3:0] s5_arid_o,
    output wire [31:0] s5_araddr_o,
    output wire [7:0] s5_arlen_o,
    output wire [2:0] s5_arsize_o,
    output wire [1:0] s5_arburst_o,
    output wire s5_arvalid_o,
    input wire s5_arready_i,

    // s5 R channel.
    input wire [3:0] s5_rid_i,
    input wire [63:0] s5_rdata_i,
    input wire [1:0] s5_rresp_i,
    input wire s5_rlast_i,
    input wire s5_rvalid_i,
    output wire s5_rready_o,

    // s6 AW channel.
    output wire [3:0] s6_awid_o,
    output wire [31:0] s6_awaddr_o,
    output wire [7:0] s6_awlen_o,
    output wire [2:0] s6_awsize_o,
    output wire [1:0] s6_awburst_o,
    output wire s6_awvalid_o,
    input wire s6_awready_i,

    // s6 W channel.
    output wire [63:0] s6_wdata_o,
    output wire [7:0] s6_wstrb_o,
    output wire s6_wlast_o,
    output wire s6_wvalid_o,
    input wire s6_wready_i,

    // s6 B channel.
    input wire [3:0] s6_bid_i,
    input wire [1:0] s6_bresp_i,
    input wire s6_bvalid_i,
    output wire s6_bready_o,

    // s6 AR channel.
    output wire [3:0] s6_arid_o,
    output wire [31:0] s6_araddr_o,
    output wire [7:0] s6_arlen_o,
    output wire [2:0] s6_arsize_o,
    output wire [1:0] s6_arburst_o,
    output wire s6_arvalid_o,
    input wire s6_arready_i,

    // s6 R channel.
    input wire [3:0] s6_rid_i,
    input wire [63:0] s6_rdata_i,
    input wire [1:0] s6_rresp_i,
    input wire s6_rlast_i,
    input wire s6_rvalid_i,
    output wire s6_rready_o
);
    // The generated map also contains peripheral attributes and interrupt numbers.
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    /* verilator lint_on UNUSEDPARAM */
    localparam [2:0] TARGET_ERROR = 3'd7;
    reg [1:0] read_active_r;
    reg [1:0] read_issued_r;
    reg [2:0] read_target_r [0:1];
    reg [3:0] read_id_r [0:1];
    reg [31:0] read_addr_r [0:1];
    reg [7:0] read_len_r [0:1];
    reg [2:0] read_size_r [0:1];
    reg [1:0] read_burst_r [0:1];
    reg [7:0] error_remain_r [0:1];
    reg [6:0] slave_busy_r;
    reg [6:0] slave_owner_r;
    reg [6:0] round_robin_r;
    wire [1:0] ar_fire_w;
    wire [1:0] read_done_w;
    wire [6:0] slave_arready_w;
    wire [6:0] slave_arvalid_w;
    wire [6:0] slave_rvalid_w;
    wire [6:0] slave_rready_w;
    wire [6:0] slave_rlast_w;
    wire [3:0] slave_rid_w [0:6];
    wire [63:0] slave_rdata_w [0:6];
    wire [1:0] slave_rresp_w [0:6];
    wire [1:0] master_rready_w;
    wire [31:0] master_araddr_w [0:1];
    wire [3:0] master_arid_w [0:1];
    wire [7:0] master_arlen_w [0:1];
    wire [2:0] master_arsize_w [0:1];
    wire [1:0] master_arburst_w [0:1];
    reg write_active_r;
    reg write_issued_r;
    reg [2:0] write_target_r;
    reg [3:0] write_id_r;
    reg [31:0] write_addr_r;
    reg [7:0] write_len_r;
    reg [2:0] write_size_r;
    reg [1:0] write_burst_r;
    reg [7:0] write_remain_r;
    reg write_error_resp_r;
    wire aw_fire_w;
    wire write_done_w;
    wire [6:0] slave_awready_w;
    wire [6:0] slave_wready_w;
    wire [6:0] slave_bvalid_w;
    wire [3:0] slave_bid_w [0:6];
    wire [1:0] slave_bresp_w [0:6];
    genvar slave_idx;
    genvar master_idx;

    function [2:0] decode_target;
        input [31:0] addr_i;
        begin
            decode_target = TARGET_ERROR;
            if ((addr_i & ~(EDRV32_ROM_SIZE - 1)) == EDRV32_ROM_BASE) begin
                decode_target = 3'd0;
            end else if ((addr_i & ~(EDRV32_SRAM_SIZE - 1)) == EDRV32_SRAM_BASE) begin
                decode_target = 3'd1;
            end else if ((addr_i & ~(EDRV32_CLINT_SIZE - 1)) == EDRV32_CLINT_BASE) begin
                decode_target = 3'd2;
            end else if ((addr_i & ~(EDRV32_PLIC_SIZE - 1)) == EDRV32_PLIC_BASE) begin
                decode_target = 3'd3;
            end else if ((addr_i & ~(EDRV32_SYS_APB_SIZE - 1)) == EDRV32_SYS_APB_BASE) begin
                decode_target = 3'd4;
            end else if ((addr_i & ~(EDRV32_MEDIA_APB_SIZE - 1)) == EDRV32_MEDIA_APB_BASE) begin
                decode_target = 3'd5;
            end else if (((addr_i & ~(EDRV32_DDR_SIZE - 1)) == EDRV32_DDR_BASE) ||
                ((addr_i & ~(EDRV32_DDR_UNCACHED_SIZE - 1)) == EDRV32_DDR_UNCACHED_BASE)) begin
                decode_target = 3'd6;
            end
        end
    endfunction

    assign master_araddr_w[0] = m0_araddr_i;
    assign master_arid_w[0] = m0_arid_i;
    assign master_arlen_w[0] = m0_arlen_i;
    assign master_arsize_w[0] = m0_arsize_i;
    assign master_arburst_w[0] = m0_arburst_i;
    assign master_rready_w[0] = m0_rready_i;
    assign m0_arready_o = !read_active_r[0];
    assign ar_fire_w[0] = m0_arvalid_i && m0_arready_o;
    assign m0_rid_o = ((read_target_r[0] == TARGET_ERROR) ?
        read_id_r[0] : slave_rid_w[read_target_r[0]]);
    assign m0_rdata_o = ((read_target_r[0] == TARGET_ERROR) ?
        64'b0 : slave_rdata_w[read_target_r[0]]);
    assign m0_rresp_o = ((read_target_r[0] == TARGET_ERROR) ?
        2'b11 : slave_rresp_w[read_target_r[0]]);
    assign m0_rlast_o = ((read_target_r[0] == TARGET_ERROR) ?
        (error_remain_r[0] == 0) : slave_rlast_w[read_target_r[0]]);
    assign m0_rvalid_o = read_active_r[0] && ((read_target_r[0] == TARGET_ERROR) ?
        1'b1 : (read_issued_r[0] && slave_rvalid_w[read_target_r[0]]));
    assign read_done_w[0] = m0_rvalid_o && m0_rready_i && m0_rlast_o;
    assign master_araddr_w[1] = m1_araddr_i;
    assign master_arid_w[1] = m1_arid_i;
    assign master_arlen_w[1] = m1_arlen_i;
    assign master_arsize_w[1] = m1_arsize_i;
    assign master_arburst_w[1] = m1_arburst_i;
    assign master_rready_w[1] = m1_rready_i;
    assign m1_arready_o = !read_active_r[1];
    assign ar_fire_w[1] = m1_arvalid_i && m1_arready_o;
    assign m1_rid_o = ((read_target_r[1] == TARGET_ERROR) ?
        read_id_r[1] : slave_rid_w[read_target_r[1]]);
    assign m1_rdata_o = ((read_target_r[1] == TARGET_ERROR) ?
        64'b0 : slave_rdata_w[read_target_r[1]]);
    assign m1_rresp_o = ((read_target_r[1] == TARGET_ERROR) ?
        2'b11 : slave_rresp_w[read_target_r[1]]);
    assign m1_rlast_o = ((read_target_r[1] == TARGET_ERROR) ?
        (error_remain_r[1] == 0) : slave_rlast_w[read_target_r[1]]);
    assign m1_rvalid_o = read_active_r[1] && ((read_target_r[1] == TARGET_ERROR) ?
        1'b1 : (read_issued_r[1] && slave_rvalid_w[read_target_r[1]]));
    assign read_done_w[1] = m1_rvalid_o && m1_rready_i && m1_rlast_o;

    generate
        for (master_idx = 0; master_idx < 2; master_idx = master_idx + 1) begin : g_master
            wire [2:0] target_w;
            assign target_w = decode_target(master_araddr_w[master_idx]);
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    read_active_r[master_idx] <= 1'b0;
                    read_issued_r[master_idx] <= 1'b0;
                    error_remain_r[master_idx] <= 0;
                end else begin
                    if (ar_fire_w[master_idx]) begin
                        read_active_r[master_idx] <= 1'b1;
                        error_remain_r[master_idx] <= master_arlen_w[master_idx];
                    end
                    if (read_done_w[master_idx]) begin
                        read_active_r[master_idx] <= 1'b0;
                        read_issued_r[master_idx] <= 1'b0;
                    end else if (read_active_r[master_idx]) begin
                        if (read_target_r[master_idx] == TARGET_ERROR) begin
                            if (master_rready_w[master_idx]) begin
                                error_remain_r[master_idx] <= error_remain_r[master_idx] - 1'b1;
                            end
                        end else if (slave_arvalid_w[read_target_r[master_idx]] &&
                            slave_arready_w[read_target_r[master_idx]] &&
                            (slave_owner_r[read_target_r[master_idx]] == (master_idx == 1))) begin
                            read_issued_r[master_idx] <= 1'b1;
                        end
                    end
                end
            end
            always @(posedge clk_i) begin
                if (ar_fire_w[master_idx]) begin
                    // spec 2.1: the M0 connection matrix permits only S0, S1 and S6.
                    read_target_r[master_idx] <= ((master_idx == 0) &&
                        (target_w >= 2) && (target_w <= 5)) ? TARGET_ERROR : target_w;
                    read_id_r[master_idx] <= master_arid_w[master_idx];
                    read_addr_r[master_idx] <= master_araddr_w[master_idx];
                    read_len_r[master_idx] <= master_arlen_w[master_idx];
                    read_size_r[master_idx] <= master_arsize_w[master_idx];
                    read_burst_r[master_idx] <= master_arburst_w[master_idx];
                end
            end
        end

        for (slave_idx = 0; slave_idx < 7; slave_idx = slave_idx + 1) begin : g_slave
            wire request0_w;
            wire request1_w;
            assign request0_w = read_active_r[0] && !read_issued_r[0] &&
                (read_target_r[0] == slave_idx);
            assign request1_w = read_active_r[1] && !read_issued_r[1] &&
                (read_target_r[1] == slave_idx);
            assign slave_arvalid_w[slave_idx] = slave_busy_r[slave_idx] &&
                !read_issued_r[slave_owner_r[slave_idx]];
            assign slave_rready_w[slave_idx] = slave_busy_r[slave_idx] &&
                read_issued_r[slave_owner_r[slave_idx]] &&
                master_rready_w[slave_owner_r[slave_idx]];
            // Ownership is reserved before asserting ARVALID, so a stalled address never changes.
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    slave_busy_r[slave_idx] <= 1'b0;
                    slave_owner_r[slave_idx] <= 1'b0;
                    round_robin_r[slave_idx] <= 1'b0;
                end else begin
                    if (!slave_busy_r[slave_idx] && (request0_w || request1_w)) begin
                        slave_busy_r[slave_idx] <= 1'b1;
                        slave_owner_r[slave_idx] <= request1_w &&
                            (!request0_w || round_robin_r[slave_idx]);
                    end else if (slave_rvalid_w[slave_idx] && slave_rready_w[slave_idx] &&
                        slave_rlast_w[slave_idx]) begin
                        slave_busy_r[slave_idx] <= 1'b0;
                        round_robin_r[slave_idx] <= !slave_owner_r[slave_idx];
                    end
                end
            end
        end
    endgenerate

    assign m1_awready_o = !write_active_r;
    assign aw_fire_w = m1_awvalid_i && m1_awready_o;
    assign m1_wready_o = write_active_r && !write_error_resp_r &&
        ((write_target_r == TARGET_ERROR) ? 1'b1 :
        (write_issued_r && slave_wready_w[write_target_r]));
    assign m1_bid_o = (write_target_r == TARGET_ERROR) ?
        write_id_r : slave_bid_w[write_target_r];
    assign m1_bresp_o = (write_target_r == TARGET_ERROR) ?
        2'b11 : slave_bresp_w[write_target_r];
    assign m1_bvalid_o = write_active_r && ((write_target_r == TARGET_ERROR) ?
        write_error_resp_r : (write_issued_r && slave_bvalid_w[write_target_r]));
    assign write_done_w = m1_bvalid_o && m1_bready_i;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            write_active_r <= 1'b0;
            write_issued_r <= 1'b0;
            write_error_resp_r <= 1'b0;
            write_remain_r <= 0;
        end else begin
            if (aw_fire_w) begin
                write_active_r <= 1'b1;
                write_remain_r <= m1_awlen_i;
            end
            if (write_done_w) begin
                write_active_r <= 1'b0;
                write_issued_r <= 1'b0;
                write_error_resp_r <= 1'b0;
            end else if (write_active_r) begin
                if (write_target_r == TARGET_ERROR) begin
                    if (m1_wvalid_i && m1_wready_o) begin
                        if (write_remain_r == 0) begin
                            write_error_resp_r <= 1'b1;
                        end else begin
                            write_remain_r <= write_remain_r - 1'b1;
                        end
                    end
                end else if (slave_awready_w[write_target_r]) begin
                    write_issued_r <= 1'b1;
                end
            end
        end
    end

    always @(posedge clk_i) begin
        if (aw_fire_w) begin
            write_target_r <= decode_target(m1_awaddr_i);
            write_id_r <= m1_awid_i;
            write_addr_r <= m1_awaddr_i;
            write_len_r <= m1_awlen_i;
            write_size_r <= m1_awsize_i;
            write_burst_r <= m1_awburst_i;
        end
    end

    // Slave 0: independent read ownership; W follows the accepted M1 AW.
    assign s0_awid_o = write_id_r;
    assign s0_awaddr_o = write_addr_r;
    assign s0_awlen_o = write_len_r;
    assign s0_awsize_o = write_size_r;
    assign s0_awburst_o = write_burst_r;
    assign s0_awvalid_o = (write_active_r && !write_issued_r && (write_target_r == 3'd0));
    assign slave_awready_w[0] = s0_awready_i;
    assign s0_wdata_o = m1_wdata_i;
    assign s0_wstrb_o = m1_wstrb_i;
    assign s0_wlast_o = m1_wlast_i;
    assign s0_wvalid_o = write_active_r && write_issued_r && (write_target_r == 3'd0) &&
        m1_wvalid_i;
    assign slave_wready_w[0] = s0_wready_i;
    assign slave_bid_w[0] = s0_bid_i;
    assign slave_bresp_w[0] = s0_bresp_i;
    assign slave_bvalid_w[0] = s0_bvalid_i;
    assign s0_bready_o = write_active_r && write_issued_r && (write_target_r == 3'd0) &&
        m1_bready_i;
    assign s0_arid_o = read_id_r[slave_owner_r[0]];
    assign s0_araddr_o = read_addr_r[slave_owner_r[0]];
    assign s0_arlen_o = read_len_r[slave_owner_r[0]];
    assign s0_arsize_o = read_size_r[slave_owner_r[0]];
    assign s0_arburst_o = read_burst_r[slave_owner_r[0]];
    assign s0_arvalid_o = slave_arvalid_w[0];
    assign slave_arready_w[0] = s0_arready_i;
    assign slave_rid_w[0] = s0_rid_i;
    assign slave_rdata_w[0] = s0_rdata_i;
    assign slave_rresp_w[0] = s0_rresp_i;
    assign slave_rlast_w[0] = s0_rlast_i;
    assign slave_rvalid_w[0] = s0_rvalid_i;
    assign s0_rready_o = slave_rready_w[0];

    // Slave 1: independent read ownership; W follows the accepted M1 AW.
    assign s1_awid_o = write_id_r;
    assign s1_awaddr_o = write_addr_r;
    assign s1_awlen_o = write_len_r;
    assign s1_awsize_o = write_size_r;
    assign s1_awburst_o = write_burst_r;
    assign s1_awvalid_o = (write_active_r && !write_issued_r && (write_target_r == 3'd1));
    assign slave_awready_w[1] = s1_awready_i;
    assign s1_wdata_o = m1_wdata_i;
    assign s1_wstrb_o = m1_wstrb_i;
    assign s1_wlast_o = m1_wlast_i;
    assign s1_wvalid_o = write_active_r && write_issued_r && (write_target_r == 3'd1) &&
        m1_wvalid_i;
    assign slave_wready_w[1] = s1_wready_i;
    assign slave_bid_w[1] = s1_bid_i;
    assign slave_bresp_w[1] = s1_bresp_i;
    assign slave_bvalid_w[1] = s1_bvalid_i;
    assign s1_bready_o = write_active_r && write_issued_r && (write_target_r == 3'd1) &&
        m1_bready_i;
    assign s1_arid_o = read_id_r[slave_owner_r[1]];
    assign s1_araddr_o = read_addr_r[slave_owner_r[1]];
    assign s1_arlen_o = read_len_r[slave_owner_r[1]];
    assign s1_arsize_o = read_size_r[slave_owner_r[1]];
    assign s1_arburst_o = read_burst_r[slave_owner_r[1]];
    assign s1_arvalid_o = slave_arvalid_w[1];
    assign slave_arready_w[1] = s1_arready_i;
    assign slave_rid_w[1] = s1_rid_i;
    assign slave_rdata_w[1] = s1_rdata_i;
    assign slave_rresp_w[1] = s1_rresp_i;
    assign slave_rlast_w[1] = s1_rlast_i;
    assign slave_rvalid_w[1] = s1_rvalid_i;
    assign s1_rready_o = slave_rready_w[1];

    // Slave 2: independent read ownership; W follows the accepted M1 AW.
    assign s2_awid_o = write_id_r;
    assign s2_awaddr_o = write_addr_r;
    assign s2_awlen_o = write_len_r;
    assign s2_awsize_o = write_size_r;
    assign s2_awburst_o = write_burst_r;
    assign s2_awvalid_o = (write_active_r && !write_issued_r && (write_target_r == 3'd2));
    assign slave_awready_w[2] = s2_awready_i;
    assign s2_wdata_o = m1_wdata_i;
    assign s2_wstrb_o = m1_wstrb_i;
    assign s2_wlast_o = m1_wlast_i;
    assign s2_wvalid_o = write_active_r && write_issued_r && (write_target_r == 3'd2) &&
        m1_wvalid_i;
    assign slave_wready_w[2] = s2_wready_i;
    assign slave_bid_w[2] = s2_bid_i;
    assign slave_bresp_w[2] = s2_bresp_i;
    assign slave_bvalid_w[2] = s2_bvalid_i;
    assign s2_bready_o = write_active_r && write_issued_r && (write_target_r == 3'd2) &&
        m1_bready_i;
    assign s2_arid_o = read_id_r[slave_owner_r[2]];
    assign s2_araddr_o = read_addr_r[slave_owner_r[2]];
    assign s2_arlen_o = read_len_r[slave_owner_r[2]];
    assign s2_arsize_o = read_size_r[slave_owner_r[2]];
    assign s2_arburst_o = read_burst_r[slave_owner_r[2]];
    assign s2_arvalid_o = slave_arvalid_w[2];
    assign slave_arready_w[2] = s2_arready_i;
    assign slave_rid_w[2] = s2_rid_i;
    assign slave_rdata_w[2] = s2_rdata_i;
    assign slave_rresp_w[2] = s2_rresp_i;
    assign slave_rlast_w[2] = s2_rlast_i;
    assign slave_rvalid_w[2] = s2_rvalid_i;
    assign s2_rready_o = slave_rready_w[2];

    // Slave 3: independent read ownership; W follows the accepted M1 AW.
    assign s3_awid_o = write_id_r;
    assign s3_awaddr_o = write_addr_r;
    assign s3_awlen_o = write_len_r;
    assign s3_awsize_o = write_size_r;
    assign s3_awburst_o = write_burst_r;
    assign s3_awvalid_o = (write_active_r && !write_issued_r && (write_target_r == 3'd3));
    assign slave_awready_w[3] = s3_awready_i;
    assign s3_wdata_o = m1_wdata_i;
    assign s3_wstrb_o = m1_wstrb_i;
    assign s3_wlast_o = m1_wlast_i;
    assign s3_wvalid_o = write_active_r && write_issued_r && (write_target_r == 3'd3) &&
        m1_wvalid_i;
    assign slave_wready_w[3] = s3_wready_i;
    assign slave_bid_w[3] = s3_bid_i;
    assign slave_bresp_w[3] = s3_bresp_i;
    assign slave_bvalid_w[3] = s3_bvalid_i;
    assign s3_bready_o = write_active_r && write_issued_r && (write_target_r == 3'd3) &&
        m1_bready_i;
    assign s3_arid_o = read_id_r[slave_owner_r[3]];
    assign s3_araddr_o = read_addr_r[slave_owner_r[3]];
    assign s3_arlen_o = read_len_r[slave_owner_r[3]];
    assign s3_arsize_o = read_size_r[slave_owner_r[3]];
    assign s3_arburst_o = read_burst_r[slave_owner_r[3]];
    assign s3_arvalid_o = slave_arvalid_w[3];
    assign slave_arready_w[3] = s3_arready_i;
    assign slave_rid_w[3] = s3_rid_i;
    assign slave_rdata_w[3] = s3_rdata_i;
    assign slave_rresp_w[3] = s3_rresp_i;
    assign slave_rlast_w[3] = s3_rlast_i;
    assign slave_rvalid_w[3] = s3_rvalid_i;
    assign s3_rready_o = slave_rready_w[3];

    // Slave 4: independent read ownership; W follows the accepted M1 AW.
    assign s4_awid_o = write_id_r;
    assign s4_awaddr_o = write_addr_r;
    assign s4_awlen_o = write_len_r;
    assign s4_awsize_o = write_size_r;
    assign s4_awburst_o = write_burst_r;
    assign s4_awvalid_o = (write_active_r && !write_issued_r && (write_target_r == 3'd4));
    assign slave_awready_w[4] = s4_awready_i;
    assign s4_wdata_o = m1_wdata_i;
    assign s4_wstrb_o = m1_wstrb_i;
    assign s4_wlast_o = m1_wlast_i;
    assign s4_wvalid_o = write_active_r && write_issued_r && (write_target_r == 3'd4) &&
        m1_wvalid_i;
    assign slave_wready_w[4] = s4_wready_i;
    assign slave_bid_w[4] = s4_bid_i;
    assign slave_bresp_w[4] = s4_bresp_i;
    assign slave_bvalid_w[4] = s4_bvalid_i;
    assign s4_bready_o = write_active_r && write_issued_r && (write_target_r == 3'd4) &&
        m1_bready_i;
    assign s4_arid_o = read_id_r[slave_owner_r[4]];
    assign s4_araddr_o = read_addr_r[slave_owner_r[4]];
    assign s4_arlen_o = read_len_r[slave_owner_r[4]];
    assign s4_arsize_o = read_size_r[slave_owner_r[4]];
    assign s4_arburst_o = read_burst_r[slave_owner_r[4]];
    assign s4_arvalid_o = slave_arvalid_w[4];
    assign slave_arready_w[4] = s4_arready_i;
    assign slave_rid_w[4] = s4_rid_i;
    assign slave_rdata_w[4] = s4_rdata_i;
    assign slave_rresp_w[4] = s4_rresp_i;
    assign slave_rlast_w[4] = s4_rlast_i;
    assign slave_rvalid_w[4] = s4_rvalid_i;
    assign s4_rready_o = slave_rready_w[4];

    // Slave 5: independent read ownership; W follows the accepted M1 AW.
    assign s5_awid_o = write_id_r;
    assign s5_awaddr_o = write_addr_r;
    assign s5_awlen_o = write_len_r;
    assign s5_awsize_o = write_size_r;
    assign s5_awburst_o = write_burst_r;
    assign s5_awvalid_o = (write_active_r && !write_issued_r && (write_target_r == 3'd5));
    assign slave_awready_w[5] = s5_awready_i;
    assign s5_wdata_o = m1_wdata_i;
    assign s5_wstrb_o = m1_wstrb_i;
    assign s5_wlast_o = m1_wlast_i;
    assign s5_wvalid_o = write_active_r && write_issued_r && (write_target_r == 3'd5) &&
        m1_wvalid_i;
    assign slave_wready_w[5] = s5_wready_i;
    assign slave_bid_w[5] = s5_bid_i;
    assign slave_bresp_w[5] = s5_bresp_i;
    assign slave_bvalid_w[5] = s5_bvalid_i;
    assign s5_bready_o = write_active_r && write_issued_r && (write_target_r == 3'd5) &&
        m1_bready_i;
    assign s5_arid_o = read_id_r[slave_owner_r[5]];
    assign s5_araddr_o = read_addr_r[slave_owner_r[5]];
    assign s5_arlen_o = read_len_r[slave_owner_r[5]];
    assign s5_arsize_o = read_size_r[slave_owner_r[5]];
    assign s5_arburst_o = read_burst_r[slave_owner_r[5]];
    assign s5_arvalid_o = slave_arvalid_w[5];
    assign slave_arready_w[5] = s5_arready_i;
    assign slave_rid_w[5] = s5_rid_i;
    assign slave_rdata_w[5] = s5_rdata_i;
    assign slave_rresp_w[5] = s5_rresp_i;
    assign slave_rlast_w[5] = s5_rlast_i;
    assign slave_rvalid_w[5] = s5_rvalid_i;
    assign s5_rready_o = slave_rready_w[5];

    // Slave 6: independent read ownership; W follows the accepted M1 AW.
    assign s6_awid_o = write_id_r;
    assign s6_awaddr_o = write_addr_r;
    assign s6_awlen_o = write_len_r;
    assign s6_awsize_o = write_size_r;
    assign s6_awburst_o = write_burst_r;
    assign s6_awvalid_o = (write_active_r && !write_issued_r && (write_target_r == 3'd6));
    assign slave_awready_w[6] = s6_awready_i;
    assign s6_wdata_o = m1_wdata_i;
    assign s6_wstrb_o = m1_wstrb_i;
    assign s6_wlast_o = m1_wlast_i;
    assign s6_wvalid_o = write_active_r && write_issued_r && (write_target_r == 3'd6) &&
        m1_wvalid_i;
    assign slave_wready_w[6] = s6_wready_i;
    assign slave_bid_w[6] = s6_bid_i;
    assign slave_bresp_w[6] = s6_bresp_i;
    assign slave_bvalid_w[6] = s6_bvalid_i;
    assign s6_bready_o = write_active_r && write_issued_r && (write_target_r == 3'd6) &&
        m1_bready_i;
    assign s6_arid_o = read_id_r[slave_owner_r[6]];
    assign s6_araddr_o = read_addr_r[slave_owner_r[6]];
    assign s6_arlen_o = read_len_r[slave_owner_r[6]];
    assign s6_arsize_o = read_size_r[slave_owner_r[6]];
    assign s6_arburst_o = read_burst_r[slave_owner_r[6]];
    assign s6_arvalid_o = slave_arvalid_w[6];
    assign slave_arready_w[6] = s6_arready_i;
    assign slave_rid_w[6] = s6_rid_i;
    assign slave_rdata_w[6] = s6_rdata_i;
    assign slave_rresp_w[6] = s6_rresp_i;
    assign slave_rlast_w[6] = s6_rlast_i;
    assign slave_rvalid_w[6] = s6_rvalid_i;
    assign s6_rready_o = slave_rready_w[6];

endmodule
