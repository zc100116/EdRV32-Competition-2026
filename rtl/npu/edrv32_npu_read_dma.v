// File: edrv32_npu_read_dma.v
// Spec: npu-spec 3, 5.5, 6; edrv32-soc-spec 4.2.
// Description: Four ordered burst contexts and a registered return holding stage.
// Cancellation drains presented addresses and their complete responses.
// Clock: clk_npu.
module edrv32_npu_read_dma (
    // Clock and transaction cancellation.
    input wire clk_i,
    input wire rst_n_i,
    input wire stop_i,

    // Burst requests, already split at 512-byte and 4-KiB boundaries.
    input wire req_valid_i,
    output wire req_ready_o,
    input wire [31:0] req_addr_i,
    input wire [4:0] req_beats_i,
    input wire [31:0] req_tag_i,
    output wire data_valid_o,
    input wire data_ready_i,
    output wire [255:0] data_o,
    output wire [31:0] data_tag_o,
    output wire [3:0] data_index_o,
    output wire data_last_o,

    // AXI read channels, local side of X9.
    output wire axi_arid_o,
    output wire [31:0] axi_araddr_o,
    output wire [3:0] axi_arlen_o,
    output wire axi_arvalid_o,
    input wire axi_arready_i,
    input wire axi_rid_i,
    input wire [255:0] axi_rdata_i,
    input wire [1:0] axi_rresp_i,
    input wire axi_rlast_i,
    input wire axi_rvalid_i,
    output wire axi_rready_o,

    // Activity and specified response errors.
    output wire idle_o,
    output wire error_o
);
    reg arvalid_r;
    reg [31:0] araddr_r;
    reg [3:0] arlen_r;
    reg [31:0] tag_r [0:3];
    reg [1:0] write_ptr_r;
    reg [1:0] read_ptr_r;
    reg [2:0] count_r;
    reg [3:0] index_r;
    reg data_valid_r;
    reg [255:0] data_r;
    reg [31:0] data_tag_r;
    reg [3:0] data_index_r;
    reg data_last_r;
    wire accept_w;
    wire response_w;
    wire finish_w;
    wire unused_rid_w;
    wire unused_beats_w;
    assign unused_beats_w = req_beats_i[4];
    assign unused_rid_w = axi_rid_i;
    assign req_ready_o = !stop_i && !arvalid_r && (count_r < 3'd4);
    assign accept_w = req_valid_i && req_ready_o;
    assign axi_arid_o = 1'b0;
    assign axi_araddr_o = araddr_r;
    assign axi_arlen_o = arlen_r;
    assign axi_arvalid_o = arvalid_r;
    assign axi_rready_o = stop_i || !data_valid_r || data_ready_i;
    assign response_w = axi_rvalid_i && axi_rready_o;
    assign finish_w = response_w && axi_rlast_i;
    assign data_valid_o = data_valid_r && !stop_i;
    assign data_o = data_r;
    assign data_tag_o = data_tag_r;
    assign data_index_o = data_index_r;
    assign data_last_o = data_last_r;
    assign idle_o = (count_r == 3'd0) && !arvalid_r && !data_valid_r;
    assign error_o = response_w && ((axi_rresp_i == 2'd2) || (axi_rresp_i == 2'd3));

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            arvalid_r <= 1'b0;
            write_ptr_r <= 2'd0;
            read_ptr_r <= 2'd0;
            count_r <= 3'd0;
            index_r <= 4'd0;
            data_valid_r <= 1'b0;
        end else begin
            if (accept_w) begin
                arvalid_r <= 1'b1;
                write_ptr_r <= write_ptr_r + 2'd1;
            end else if (axi_arready_i) begin
                arvalid_r <= 1'b0;
            end
            if (accept_w && !finish_w) begin
                count_r <= count_r + 3'd1;
            end else if (!accept_w && finish_w) begin
                count_r <= count_r - 3'd1;
            end
            if (response_w) begin
                if (axi_rlast_i) begin
                    read_ptr_r <= read_ptr_r + 2'd1;
                    index_r <= 4'd0;
                end else begin
                    index_r <= index_r + 4'd1;
                end
            end
            if (stop_i) begin
                data_valid_r <= 1'b0;
            end else if (axi_rready_o) begin
                data_valid_r <= axi_rvalid_i;
            end
        end
    end
    always @(posedge clk_i) begin
        if (accept_w) begin
            araddr_r <= req_addr_i;
            arlen_r <= req_beats_i[3:0] - 4'd1;
            tag_r[write_ptr_r] <= req_tag_i;
        end
        if (response_w) begin
            data_r <= axi_rdata_i;
            data_tag_r <= tag_r[read_ptr_r];
            data_index_r <= index_r;
            data_last_r <= axi_rlast_i;
        end
    end
endmodule
