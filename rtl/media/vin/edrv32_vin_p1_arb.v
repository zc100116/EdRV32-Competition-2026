// File: edrv32_vin_p1_arb.v
// Spec: vin 2.9; SoC 4.2.
// Description: Two-channel round robin with whole-burst admission and ordered B routing.
//              Hold a grant from exposed AW through the final W handshake.
// Clock domain: clk_mem.
module edrv32_vin_p1_arb (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Two DMA write clients, channel zero in the low slice.
    input wire [63:0] ch_awaddr_i,
    input wire [7:0] ch_awlen_i,
    input wire [1:0] ch_awvalid_i,
    output wire [1:0] ch_awready_o,
    input wire [511:0] ch_wdata_i,
    input wire [63:0] ch_wstrb_i,
    input wire [1:0] ch_wlast_i,
    input wire [1:0] ch_wvalid_i,
    output wire [1:0] ch_wready_o,
    output wire [3:0] ch_bresp_o,
    output wire [1:0] ch_bvalid_o,
    input wire [1:0] ch_bready_i,
    input wire [19:0] ch_count_i,
    input wire [1:0] ch_abort_i,

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
    reg turn_r;
    reg grant_r;
    reg hold_r;
    reg writing_r;
    wire [1:0] eligible_w;
    wire selected_w;
    wire address_w;
    wire finish_w;
    wire owners_ready_w;
    wire owners_valid_w;
    wire owner_w;
    wire unused_id_w;

    assign unused_id_w = p1_bid_i;
    assign eligible_w[0] = ch_awvalid_i[0] &&
        (ch_abort_i[0] || ch_count_i[9:0] >= {6'd0, ch_awlen_i[3:0]} + 10'd1);
    assign eligible_w[1] = ch_awvalid_i[1] &&
        (ch_abort_i[1] || ch_count_i[19:10] >= {6'd0, ch_awlen_i[7:4]} + 10'd1);
    assign selected_w = hold_r || writing_r ? grant_r :
        (eligible_w[turn_r] ? turn_r : !turn_r);
    assign p1_awid_o = 1'b0;
    assign p1_awaddr_o = selected_w ? ch_awaddr_i[63:32] : ch_awaddr_i[31:0];
    assign p1_awlen_o = selected_w ? ch_awlen_i[7:4] : ch_awlen_i[3:0];
    assign p1_awvalid_o = !writing_r && owners_ready_w &&
        (hold_r || eligible_w[selected_w]);
    assign ch_awready_o = {2{p1_awvalid_o && p1_awready_i}} &
        (selected_w ? 2'b10 : 2'b01);
    assign address_w = p1_awvalid_o && p1_awready_i;
    assign p1_wdata_o = selected_w ? ch_wdata_i[511:256] : ch_wdata_i[255:0];
    assign p1_wstrb_o = selected_w ? ch_wstrb_i[63:32] : ch_wstrb_i[31:0];
    assign p1_wlast_o = ch_wlast_i[selected_w];
    assign p1_wvalid_o = (writing_r || address_w) && ch_wvalid_i[selected_w];
    assign ch_wready_o = {2{(writing_r || address_w) && p1_wready_i}} &
        (selected_w ? 2'b10 : 2'b01);
    assign finish_w = p1_wvalid_o && p1_wready_i && p1_wlast_o;
    assign ch_bresp_o = {2{p1_bresp_i}};
    assign ch_bvalid_o = {2{p1_bvalid_i && owners_valid_w}} &
        (owner_w ? 2'b10 : 2'b01);
    assign p1_bready_o = owners_valid_w && ch_bready_i[owner_w];

    edrv32_sync_fifo #(
        .WIDTH(1),
        .DEPTH(8)
    ) u_owners (
        // At most four outstanding per DMA, eight in total.
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
            turn_r <= 1'b0;
            grant_r <= 1'b0;
            hold_r <= 1'b0;
            writing_r <= 1'b0;
        end else begin
            if (p1_awvalid_o) begin
                grant_r <= selected_w;
                hold_r <= !p1_awready_i;
            end
            if (address_w)
                writing_r <= !finish_w;
            else if (finish_w)
                writing_r <= 1'b0;
            if (finish_w)
                turn_r <= !selected_w;
        end
    end
endmodule
