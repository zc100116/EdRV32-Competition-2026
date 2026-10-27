// File: edrv32_npu_write_dma.v
// Spec: npu-spec 3, 5.1 W2, 5.5, 6; edrv32-soc-spec 4.2.
// Description: A registered W holding stage with eight independent B credits.
// Presented AW and its complete W burst survive cancellation; B never fences a row.
// Clock: clk_npu.
module edrv32_npu_write_dma (
    // Clock and stop of new bursts.
    input wire clk_i,
    input wire rst_n_i,
    input wire stop_i,

    // One burst and its stream; source retains data until accepted.
    input wire req_valid_i,
    output wire req_ready_o,
    input wire [31:0] req_addr_i,
    input wire [4:0] req_beats_i,
    input wire data_valid_i,
    output wire data_ready_o,
    input wire [255:0] data_i,
    input wire [31:0] data_strb_i,
    output wire stream_idle_o,

    // AXI write channels, local side of X9.
    output wire axi_awid_o,
    output wire [31:0] axi_awaddr_o,
    output wire [3:0] axi_awlen_o,
    output wire axi_awvalid_o,
    input wire axi_awready_i,
    output wire [255:0] axi_wdata_o,
    output wire [31:0] axi_wstrb_o,
    output wire axi_wlast_o,
    output wire axi_wvalid_o,
    input wire axi_wready_i,
    input wire axi_bid_i,
    input wire [1:0] axi_bresp_i,
    input wire axi_bvalid_i,
    output wire axi_bready_o,

    // Fence and statistics.
    output wire idle_o,
    output wire error_o,
    output wire beat_o,
    output wire response_wait_o
);
    reg active_r;
    reg awvalid_r;
    reg [31:0] awaddr_r;
    reg [3:0] awlen_r;
    reg [4:0] remaining_r;
    reg [3:0] outstanding_r;
    reg wvalid_r;
    reg [255:0] wdata_r;
    reg [31:0] wstrb_r;
    reg wlast_r;
    wire accept_w;
    wire data_accept_w;
    wire last_w;
    wire unused_bid_w;
    assign unused_bid_w = axi_bid_i;
    assign req_ready_o = !stop_i && !active_r && !awvalid_r && !wvalid_r
        && (outstanding_r < 4'd8);
    assign accept_w = req_valid_i && req_ready_o;
    assign data_ready_o = active_r && (remaining_r != 5'd0)
        && (!wvalid_r || axi_wready_i);
    assign data_accept_w = data_valid_i && data_ready_o;
    assign last_w = wvalid_r && axi_wready_i && wlast_r;
    assign stream_idle_o = !active_r && !awvalid_r && !wvalid_r;
    assign idle_o = stream_idle_o && (outstanding_r == 4'd0);
    assign axi_awid_o = 1'b0;
    assign axi_awaddr_o = awaddr_r;
    assign axi_awlen_o = awlen_r;
    assign axi_awvalid_o = awvalid_r;
    assign axi_wdata_o = wdata_r;
    assign axi_wstrb_o = wstrb_r;
    assign axi_wlast_o = wlast_r;
    assign axi_wvalid_o = wvalid_r;
    assign axi_bready_o = 1'b1;
    assign error_o = axi_bvalid_i && ((axi_bresp_i == 2'd2) || (axi_bresp_i == 2'd3));
    assign beat_o = wvalid_r && axi_wready_i;
    assign response_wait_o = (outstanding_r != 4'd0);

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            active_r <= 1'b0;
            awvalid_r <= 1'b0;
            wvalid_r <= 1'b0;
            remaining_r <= 5'd0;
            outstanding_r <= 4'd0;
        end else begin
            if (accept_w) begin
                active_r <= 1'b1;
                awvalid_r <= 1'b1;
                remaining_r <= req_beats_i;
            end else if (axi_awready_i) begin
                awvalid_r <= 1'b0;
            end
            if (last_w) begin
                active_r <= 1'b0;
            end
            if (data_ready_o) begin
                wvalid_r <= data_valid_i;
            end else if (axi_wready_i) begin
                wvalid_r <= 1'b0;
            end
            if (data_accept_w) begin
                remaining_r <= remaining_r - 5'd1;
            end
            case ({accept_w, axi_bvalid_i})
                2'b10: outstanding_r <= outstanding_r + 4'd1;
                2'b01: outstanding_r <= outstanding_r - 4'd1;
                default: begin end
            endcase
        end
    end
    always @(posedge clk_i) begin
        if (accept_w) begin
            awaddr_r <= req_addr_i;
            awlen_r <= req_beats_i[3:0] - 4'd1;
        end
        if (data_accept_w) begin
            wdata_r <= data_i;
            wstrb_r <= data_strb_i;
            wlast_r <= (remaining_r == 5'd1);
        end
    end
endmodule
