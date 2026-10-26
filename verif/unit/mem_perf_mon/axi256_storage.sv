// File: axi256_storage.sv
// Spec: mem-subsys-testplan PM-01--PM-07 unit storage stub.
// Description: Ordered storage with configurable first-read and write-response latency.
// Clock: clk_i.
module axi256_storage (
    input wire clk_i,
    input wire rst_n_i,
    input wire [31:0] read_delay_i,
    input wire [31:0] b_delay_i,
    input wire allow_ar_i,
    input wire allow_aw_i,
    input wire allow_w_i,
    input wire  axi_awid_i,
    input wire  [31:0] axi_awaddr_i,
    input wire  [3:0] axi_awlen_i,
    input wire  axi_awvalid_i,
    output wire axi_awready_o,
    input wire  [255:0] axi_wdata_i,
    input wire  [31:0] axi_wstrb_i,
    input wire  axi_wlast_i,
    input wire  axi_wvalid_i,
    output wire axi_wready_o,
    output wire axi_bid_o,
    output wire [1:0] axi_bresp_o,
    output wire axi_bvalid_o,
    input wire  axi_bready_i,
    input wire  axi_arid_i,
    input wire  [31:0] axi_araddr_i,
    input wire  [3:0] axi_arlen_i,
    input wire  axi_arvalid_i,
    output wire axi_arready_o,
    output wire axi_rid_o,
    output wire [255:0] axi_rdata_o,
    output wire [1:0] axi_rresp_o,
    output wire axi_rlast_o,
    output wire axi_rvalid_o,
    input wire  axi_rready_i
);
    reg [31:0] memory [0:4095];
    integer tick_r = 0;
    integer rd_head_r = 0;
    integer rd_tail_r = 0;
    integer wr_head_r = 0;
    integer wr_tail_r = 0;
    integer b_head_r = 0;
    integer b_tail_r = 0;
    integer rd_beat_r = 0;
    integer wr_beat_r = 0;
    integer rd_addr_r [0:1023];
    integer rd_due_r [0:1023];
    integer rd_len_r [0:1023];
    reg rd_id_r [0:1023];
    integer wr_addr_r [0:1023];
    integer wr_len_r [0:1023];
    reg wr_id_r [0:1023];
    integer b_due_r [0:1023];
    reg b_id_r [0:1023];
    integer lane;
    integer octet;
    wire [31:0] wr_address_w = 32'(wr_addr_r[wr_head_r] + wr_beat_r*32);
    wire [31:0] rd_address_w = 32'(rd_addr_r[rd_head_r] + rd_beat_r*32);
    assign axi_arready_o = rst_n_i && allow_ar_i && rd_tail_r-rd_head_r < 16;
    assign axi_awready_o = rst_n_i && allow_aw_i && wr_tail_r-wr_head_r < 16;
    assign axi_wready_o = rst_n_i && allow_w_i && wr_tail_r > wr_head_r;
    assign axi_bvalid_o = rst_n_i && b_tail_r > b_head_r && tick_r >= b_due_r[b_head_r];
    assign axi_bid_o = b_id_r[b_head_r];
    assign axi_bresp_o = 0;
    assign axi_rvalid_o = rst_n_i && rd_tail_r > rd_head_r && tick_r >= rd_due_r[rd_head_r];
    assign axi_rid_o = rd_id_r[rd_head_r];
    assign axi_rresp_o = 0;
    assign axi_rlast_o = rd_beat_r == rd_len_r[rd_head_r];
    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : g_read
            assign axi_rdata_o[g*32 +: 32] = memory[(rd_address_w/4)+g];
        end
    endgenerate
    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            tick_r <= 0;
            rd_head_r <= 0; rd_tail_r <= 0; wr_head_r <= 0; wr_tail_r <= 0;
            b_head_r <= 0; b_tail_r <= 0; rd_beat_r <= 0; wr_beat_r <= 0;
        end else begin
            tick_r <= tick_r + 1;
            if (axi_arvalid_i && axi_arready_o) begin
                rd_addr_r[rd_tail_r] <= int'(axi_araddr_i);
                rd_len_r[rd_tail_r] <= int'(axi_arlen_i);
                rd_id_r[rd_tail_r] <= axi_arid_i;
                rd_due_r[rd_tail_r] <= tick_r + int'(read_delay_i);
                rd_tail_r <= rd_tail_r + 1;
            end
            if (axi_awvalid_i && axi_awready_o) begin
                wr_addr_r[wr_tail_r] <= int'(axi_awaddr_i);
                wr_len_r[wr_tail_r] <= int'(axi_awlen_i);
                wr_id_r[wr_tail_r] <= axi_awid_i;
                wr_tail_r <= wr_tail_r + 1;
            end
            if (axi_rvalid_o && axi_rready_i) begin
                rd_beat_r <= rd_beat_r + 1;
                if (axi_rlast_o) begin rd_beat_r <= 0; rd_head_r <= rd_head_r + 1; end
            end
            if (axi_wvalid_i && axi_wready_o) begin
                for (lane = 0; lane < 8; lane = lane + 1)
                    for (octet = 0; octet < 4; octet = octet + 1)
                        if (axi_wstrb_i[lane*4+octet])
                            memory[(wr_address_w/4)+lane][octet*8 +: 8] <=
                                axi_wdata_i[(lane*4+octet)*8 +: 8];
                if (axi_wlast_i != (wr_beat_r == wr_len_r[wr_head_r]))
                    $fatal(1, "FAIL WLAST");
                wr_beat_r <= wr_beat_r + 1;
                if (axi_wlast_i) begin
                    b_due_r[b_tail_r] <= tick_r + int'(b_delay_i);
                    b_id_r[b_tail_r] <= wr_id_r[wr_head_r];
                    b_tail_r <= b_tail_r + 1;
                    wr_beat_r <= 0; wr_head_r <= wr_head_r + 1;
                end
            end
            if (axi_bvalid_o && axi_bready_i) b_head_r <= b_head_r + 1;
        end
    end
endmodule
