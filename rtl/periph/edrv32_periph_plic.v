// File: edrv32_periph_plic.v
// Spec: sys-subsys-spec 2.5, 4.2, 5, 6.
// Description: Fifteen level gateways, priority arbitration and claim/complete.
//              AXI64 accepts single-beat SIZE=2 register accesses.
// Clock domain: clk_sys.
module edrv32_periph_plic (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // AXI64 slave write address.
    input wire [3:0] axi_awid_i,
    input wire [31:0] axi_awaddr_i,
    input wire [7:0] axi_awlen_i,
    input wire [2:0] axi_awsize_i,
    input wire [1:0] axi_awburst_i,
    input wire axi_awvalid_i,
    output wire axi_awready_o,

    // AXI64 slave write data and response.
    input wire [63:0] axi_wdata_i,
    input wire [7:0] axi_wstrb_i,
    input wire axi_wlast_i,
    input wire axi_wvalid_i,
    output wire axi_wready_o,
    output reg [3:0] axi_bid_o,
    output reg [1:0] axi_bresp_o,
    output reg axi_bvalid_o,
    input wire axi_bready_i,

    // AXI64 slave read address and response.
    input wire [3:0] axi_arid_i,
    input wire [31:0] axi_araddr_i,
    input wire [7:0] axi_arlen_i,
    input wire [2:0] axi_arsize_i,
    input wire [1:0] axi_arburst_i,
    input wire axi_arvalid_i,
    output wire axi_arready_o,
    output reg [3:0] axi_rid_o,
    output reg [63:0] axi_rdata_o,
    output reg [1:0] axi_rresp_o,
    output wire axi_rlast_o,
    output reg axi_rvalid_o,
    input wire axi_rready_i,

    // Interrupt sources and machine external interrupt.
    input wire [15:1] irq_src_i,
    output reg irq_meip_o
);
    // Address-map constants unused by this device are shared with other users.
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    /* verilator lint_on UNUSEDPARAM */
    reg write_active_r;
    reg write_error_r;
    reg [31:0] write_offset_r;
    reg [3:0] write_id_r;
    reg [7:0] write_left_r;
    reg [7:0] read_left_r;
    reg [31:0] read_data_w;
    wire [21:0] read_offset_w;
    wire [31:0] write_data_w;
    wire read_error_w;
    wire read_accept_w;
    wire write_accept_w;
    wire register_write_w;
    wire unused_w;

    // SIZE=2 writes from D$ select the complete addressed 32-bit half.
    assign unused_w = &{1'b0, axi_awburst_i, axi_arburst_i, axi_wlast_i, axi_wstrb_i,
                        axi_araddr_i[31:22]};
    assign axi_awready_o = !write_active_r && !axi_bvalid_o;
    assign axi_wready_o = write_active_r;
    assign axi_arready_o = !axi_rvalid_o;
    assign axi_rlast_o = read_left_r == 8'd0;
    assign read_accept_w = axi_arvalid_i && axi_arready_o;
    assign write_accept_w = axi_wvalid_i && axi_wready_o;
    assign register_write_w = write_accept_w && !write_error_r;
    // sys_xbar routes only the aligned 4 MiB PLIC window (soc_map PLIC_SIZE).
    assign read_offset_w = axi_araddr_i[21:0];
    assign write_data_w = write_offset_r[2] ? axi_wdata_i[63:32] : axi_wdata_i[31:0];
    assign read_error_w = axi_arlen_i != 8'd0 || axi_arsize_i != 3'd2;

    // spec 6: reject the whole illegal transaction, draining every write beat.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            write_active_r <= 1'b0;
            axi_bvalid_o <= 1'b0;
            axi_rvalid_o <= 1'b0;
            write_left_r <= 8'd0;
            read_left_r <= 8'd0;
        end else begin
            if (axi_awvalid_i && axi_awready_o) begin
                write_active_r <= 1'b1;
                write_left_r <= axi_awlen_i;
            end
            if (write_accept_w) begin
                if (write_left_r == 8'd0) begin
                    write_active_r <= 1'b0;
                    axi_bvalid_o <= 1'b1;
                end else begin
                    write_left_r <= write_left_r - 1'b1;
                end
            end
            if (axi_bvalid_o && axi_bready_i) begin
                axi_bvalid_o <= 1'b0;
            end
            if (read_accept_w) begin
                axi_rvalid_o <= 1'b1;
                read_left_r <= axi_arlen_i;
            end else if (axi_rvalid_o && axi_rready_i) begin
                if (read_left_r == 8'd0) begin
                    axi_rvalid_o <= 1'b0;
                end else begin
                    read_left_r <= read_left_r - 1'b1;
                end
            end
        end
    end
    // Payload is written only when owned, and held throughout response stalls.
    always @(posedge clk_i) begin
        if (axi_awvalid_i && axi_awready_o) begin
            write_offset_r <= axi_awaddr_i - EDRV32_PLIC_BASE;
            write_id_r <= axi_awid_i;
            write_error_r <= axi_awlen_i != 8'd0 || axi_awsize_i != 3'd2;
        end
        if (write_accept_w && write_left_r == 8'd0) begin
            axi_bid_o <= write_id_r;
            axi_bresp_o <= write_error_r ? 2'b10 : 2'b00;
        end
        if (read_accept_w) begin
            axi_rid_o <= axi_arid_i;
            axi_rresp_o <= read_error_w ? 2'b10 : 2'b00;
            axi_rdata_o <= read_error_w ? 64'd0 :
                            (read_offset_w[2] ? {read_data_w, 32'd0} :
                                                {32'd0, read_data_w});
        end
    end
    reg [2:0] priority_r [1:15];
    reg [2:0] threshold_r;
    reg [15:1] enable_r;
    reg [15:1] pending_r;
    reg [15:1] claimed_r;
    wire [15:1] irq_sync_w;
    wire [3:0] winner_w;
    reg [3:0] winner_r;
    wire [6:0] candidate_w [0:15];
    wire [6:0] pair_w [0:7];
    wire [6:0] quad_w [0:3];
    wire [6:0] half_w [0:1];
    wire [6:0] best_w;
    wire claim_w;
    integer source_idx;
    genvar source;
    genvar node;

    generate
        for (source = 1; source <= 15; source = source + 1) begin : g_source
            edrv32_cdc_sync_bit u_irq (
                .clk_i(clk_i),
                .rst_n_i(rst_n_i),
                .bit_i(irq_src_i[source]),
                .bit_o(irq_sync_w[source])
            );
        end
    endgenerate
    // Each candidate carries {priority, source}; left owns lower IDs and wins ties.
    function [6:0] select_candidate;
        input [6:0] left_i;
        input [6:0] right_i;
        begin
            select_candidate = left_i[6:4] >= right_i[6:4] ? left_i : right_i;
        end
    endfunction
    assign candidate_w[0] = 7'd0;
    generate
        for (source = 1; source <= 15; source = source + 1) begin : g_candidate
            wire [2:0] priority_w;
            assign priority_w = pending_r[source] && enable_r[source] ? priority_r[source] :
                                                                        3'd0;
            assign candidate_w[source] = {priority_w, source[3:0]};
        end
        // Separate arrays make the four acyclic comparison levels explicit.
        for (node = 0; node < 8; node = node + 1) begin : g_pair
            assign pair_w[node] = select_candidate(candidate_w[2 * node],
                                                    candidate_w[2 * node + 1]);
        end
        for (node = 0; node < 4; node = node + 1) begin : g_quad
            assign quad_w[node] = select_candidate(pair_w[2 * node], pair_w[2 * node + 1]);
        end
        for (node = 0; node < 2; node = node + 1) begin : g_half
            assign half_w[node] = select_candidate(quad_w[2 * node], quad_w[2 * node + 1]);
        end
    endgenerate
    assign best_w = select_candidate(half_w[0], half_w[1]);
    assign winner_w = best_w[6:4] > threshold_r ? best_w[3:0] : 4'd0;
    // spec 5: both claim side effects and returned data use this same snapshot.
    // ARREADY stays low through RVALID, leaving a refresh edge between claims.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            winner_r <= 4'd0;
        end else begin
            winner_r <= winner_w;
        end
    end
    assign claim_w = read_accept_w && !read_error_w && read_offset_w == 22'h200004;
    always @(*) begin
        read_data_w = 32'd0;
        case (read_offset_w)
            22'h001000: read_data_w = {16'd0, pending_r, 1'b0};
            22'h002000: read_data_w = {16'd0, enable_r, 1'b0};
            22'h200000: read_data_w = {29'd0, threshold_r};
            22'h200004: read_data_w = {28'd0, winner_r};
            22'h000004: read_data_w = {29'd0, priority_r[1]};
            22'h000008: read_data_w = {29'd0, priority_r[2]};
            22'h00000c: read_data_w = {29'd0, priority_r[3]};
            22'h000010: read_data_w = {29'd0, priority_r[4]};
            22'h000014: read_data_w = {29'd0, priority_r[5]};
            22'h000018: read_data_w = {29'd0, priority_r[6]};
            22'h00001c: read_data_w = {29'd0, priority_r[7]};
            22'h000020: read_data_w = {29'd0, priority_r[8]};
            22'h000024: read_data_w = {29'd0, priority_r[9]};
            22'h000028: read_data_w = {29'd0, priority_r[10]};
            22'h00002c: read_data_w = {29'd0, priority_r[11]};
            22'h000030: read_data_w = {29'd0, priority_r[12]};
            22'h000034: read_data_w = {29'd0, priority_r[13]};
            22'h000038: read_data_w = {29'd0, priority_r[14]};
            22'h00003c: read_data_w = {29'd0, priority_r[15]};
            default: read_data_w = 32'd0;
        endcase
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            threshold_r <= 3'd0;
            enable_r <= 15'd0;
            pending_r <= 15'd0;
            claimed_r <= 15'd0;
            irq_meip_o <= 1'b0;
            for (source_idx = 1; source_idx <= 15; source_idx = source_idx + 1) begin
                priority_r[source_idx] <= 3'd0;
            end
        end else begin
            // spec 2.5: MEIP is the nonzero flag of the same registered result.
            irq_meip_o <= winner_w != 4'd0;
            for (source_idx = 1; source_idx <= 15; source_idx = source_idx + 1) begin
                if (irq_sync_w[source_idx] && !claimed_r[source_idx]) begin
                    pending_r[source_idx] <= 1'b1;
                end
                // spec 5: claim at AR acceptance, independently of RREADY.
                if (claim_w && winner_r == source_idx[3:0]) begin
                    pending_r[source_idx] <= 1'b0;
                    claimed_r[source_idx] <= 1'b1;
                end
                if (register_write_w) begin
                    if (write_offset_r == 32'd4 * source_idx) begin
                        priority_r[source_idx] <= write_data_w[2:0];
                    end
                    if (write_offset_r == 32'h00200004 &&
                        write_data_w == {28'd0, source_idx[3:0]}) begin
                        claimed_r[source_idx] <= 1'b0;
                    end
                end
            end
            if (register_write_w && write_offset_r == 32'h00002000) begin
                enable_r <= write_data_w[15:1];
            end
            if (register_write_w && write_offset_r == 32'h00200000) begin
                threshold_r <= write_data_w[2:0];
            end
        end
    end
endmodule
