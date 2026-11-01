// File: edrv32_vin_p1_arb.v
// Spec: vin 2.9; SoC 4.2.
// Description: Three-channel round robin with whole-burst admission and ordered B routing.
//              Register whole-burst admission before exposing AW; retain ownership through W.
// Clock domain: clk_mem.
module edrv32_vin_p1_arb (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Three DMA write clients, channel zero in the low slice.
    input wire [95:0] ch_awaddr_i,
    input wire [11:0] ch_awlen_i,
    input wire [2:0] ch_awvalid_i,
    output wire [2:0] ch_awready_o,
    input wire [767:0] ch_wdata_i,
    input wire [95:0] ch_wstrb_i,
    input wire [2:0] ch_wlast_i,
    input wire [2:0] ch_wvalid_i,
    output wire [2:0] ch_wready_o,
    output wire [5:0] ch_bresp_o,
    output wire [2:0] ch_bvalid_o,
    input wire [2:0] ch_bready_i,
    input wire [29:0] ch_count_i,
    input wire [2:0] ch_abort_i,

    // P1 write master.
    output wire p1_awid_o,
    output wire [31:0] p1_awaddr_o,
    output wire [3:0] p1_awlen_o,
    output wire p1_awvalid_o,
    input wire p1_awready_i,
    output wire [255:0] p1_wdata_o,
    output wire [31:0] p1_wstrb_o,
    output wire p1_wlast_o,
    output wire p1_wvalid_o,
    input wire p1_wready_i,
    input wire p1_bid_i,
    input wire [1:0] p1_bresp_i,
    input wire p1_bvalid_i,
    output wire p1_bready_o
);
    reg [1:0] turn_r;
    reg [1:0] grant_r;
    reg [1:0] grant_data_r [0:3] /* synthesis syn_preserve=1 */;
    integer grant_slice;
    reg hold_r;
    reg writing_r;
    wire [2:0] eligible_w;
    wire [1:0] selected_w;
    wire [1:0] candidate_w;
    wire acquire_w;
    wire address_w;
    wire finish_w;
    wire owners_ready_w;
    wire owners_valid_w;
    wire [1:0] owner_w;
    wire unused_id_w;
    wire [1:0] next_w;
    wire [1:0] last_w;

    assign unused_id_w = p1_bid_i;
    assign eligible_w[0] = ch_awvalid_i[0] &&
        (ch_abort_i[0] || ch_count_i[9:0] >= {6'd0, ch_awlen_i[3:0]} + 10'd1);
    assign eligible_w[1] = ch_awvalid_i[1] &&
        (ch_abort_i[1] || ch_count_i[19:10] >= {6'd0, ch_awlen_i[7:4]} + 10'd1);
    assign next_w = turn_r == 2'd2 ? 2'd0 : turn_r + 2'd1;
    assign last_w = next_w == 2'd2 ? 2'd0 : next_w + 2'd1;
    assign eligible_w[2] = ch_awvalid_i[2] &&
        (ch_abort_i[2] || ch_count_i[29:20] >= {6'd0, ch_awlen_i[11:8]} + 10'd1);
    assign candidate_w = eligible_w[turn_r] ? turn_r :
        (eligible_w[next_w] ? next_w : last_w);
    assign acquire_w = !hold_r && !writing_r && owners_ready_w && |eligible_w;
    assign selected_w = grant_r;
    assign p1_awid_o = 1'b0;
    assign p1_awaddr_o = ch_awaddr_i[selected_w * 32 +: 32];
    assign p1_awlen_o = ch_awlen_i[selected_w * 4 +: 4];
    assign p1_awvalid_o = hold_r;
    assign ch_awready_o = {3{p1_awvalid_o && p1_awready_i}} &
        (3'b001 << selected_w);
    assign address_w = p1_awvalid_o && p1_awready_i;
    genvar data_slice;
    generate
        for (data_slice = 0; data_slice < 4; data_slice = data_slice + 1) begin : g_data_slice
            assign p1_wdata_o[data_slice*64 +: 64] =
                ch_wdata_i[grant_data_r[data_slice]*256 + data_slice*64 +: 64];
        end
    endgenerate
    assign p1_wstrb_o = ch_wstrb_i[selected_w * 32 +: 32];
    assign p1_wlast_o = ch_wlast_i[selected_w];
    assign p1_wvalid_o = (writing_r || address_w) && ch_wvalid_i[selected_w];
    assign ch_wready_o = {3{(writing_r || address_w) && p1_wready_i}} &
        (3'b001 << selected_w);
    assign finish_w = p1_wvalid_o && p1_wready_i && p1_wlast_o;
    assign ch_bresp_o = {3{p1_bresp_i}};
    assign ch_bvalid_o = {3{p1_bvalid_i && owners_valid_w}} &
        (3'b001 << owner_w);
    assign p1_bready_o = owners_valid_w && ch_bready_i[owner_w];

    edrv32_sync_fifo #(
        .WIDTH(2),
        .DEPTH(16)
    ) u_owners (
        // At most four outstanding per DMA, twelve in total.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .valid_i(address_w),
        .ready_o(owners_ready_w),
        .data_i(selected_w),
        .valid_o(owners_valid_w),
        .ready_i(p1_bvalid_i && p1_bready_o),
        .data_o(owner_w)
    );

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            turn_r <= 2'd0;
            grant_r <= 2'd0;
            for (grant_slice = 0; grant_slice < 4; grant_slice = grant_slice + 1)
                grant_data_r[grant_slice] <= 2'd0;
            hold_r <= 1'b0;
            writing_r <= 1'b0;
        end else begin
            // No client can consume FIFO beats before its registered grant is exposed.
            if (acquire_w) begin
                grant_r <= candidate_w;
                for (grant_slice = 0; grant_slice < 4; grant_slice = grant_slice + 1)
                    grant_data_r[grant_slice] <= candidate_w;
                hold_r <= 1'b1;
            end else if (address_w) begin
                hold_r <= 1'b0;
            end
            if (address_w)
                writing_r <= !finish_w;
            else if (finish_w)
                writing_r <= 1'b0;
            if (finish_w)
                turn_r <= selected_w == 2'd2 ? 2'd0 : selected_w + 2'd1;
        end
    end
endmodule
