// File: edrv32_dma2d_rd.v
// Spec: dma2d 2, 3, 5, 6; SoC 4.2, 7.1.
// Description: Greedy row/page burst splitting with bounded outstanding transactions.
//              ABORT drains committed AXI traffic before returning idle.
// Clock domain: clk_mem (clk_i).
module edrv32_dma2d_rd #(
    parameter OUTSTANDING = 4
) (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Descriptor and data stream.
    input wire desc_valid_i,
    output wire desc_ready_o,
    input wire [31:0] desc_base_i,
    input wire [31:0] desc_stride_i,
    input wire [15:0] desc_width_bytes_i,
    input wire [11:0] desc_height_i,
    output wire data_valid_o,
    input wire data_ready_i,
    output wire [255:0] data_o,
    output wire data_sol_o,
    output wire data_eol_o,
    output wire data_eof_o,

    // AXI256 read channels.
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

    // Control and status.
    input wire abort_i,
    output wire idle_o,
    output reg done_o,
    output wire err_o
);
    localparam COUNT_WIDTH = $clog2(OUTSTANDING + 1);
    localparam [COUNT_WIDTH-1:0] LIMIT = OUTSTANDING[COUNT_WIDTH-1:0];

    reg active_r;
    reg abort_r;
    reg error_r;
    reg issued_all_r;
    reg address_hold_r;
    reg [COUNT_WIDTH-1:0] outstanding_r;
    reg [31:0] addr_r;
    reg [31:0] line_addr_r;
    reg [31:0] stride_r;
    reg [11:0] width_beats_r;
    reg [11:0] address_left_r;
    reg [11:0] address_rows_r;
    wire desc_fire_w;
    wire address_fire_w;
    wire response_fire_w;
    wire stop_w;
    wire [11:0] desc_beats_w;
    wire [7:0] page_beats_w;
    reg [4:0] burst_beats_w;
    wire unused_id_w;

    assign desc_fire_w = desc_valid_i && desc_ready_o;
    assign desc_ready_o = !active_r;
    assign idle_o = !active_r;
    assign err_o = done_o && error_r;
    assign stop_w = abort_r || abort_i;
    assign desc_beats_w = {1'b0, desc_width_bytes_i[15:5]} +
        {11'b0, (|desc_width_bytes_i[4:0])};
    assign page_beats_w = 8'd128 - {1'b0, addr_r[11:5]};

    // spec 2.2: greedy minimum of line remainder, 16 beats, and page remainder.
    always @(*) begin
        burst_beats_w = 5'd16;
        if (address_left_r < 12'd16)
            burst_beats_w = address_left_r[4:0];
        if (page_beats_w < {3'b0, burst_beats_w})
            burst_beats_w = page_beats_w[4:0];
    end

    reg [11:0] data_left_r;
    reg [11:0] data_rows_r;
    wire data_fire_w;

    assign unused_id_w = axi_rid_i;
    assign axi_arid_o = 1'b0;
    assign axi_araddr_o = addr_r;
    assign axi_arlen_o = burst_beats_w[3:0] - 4'd1;
    // spec 5.4: recycle a retiring credit on the same edge to avoid burst gaps.
    assign axi_arvalid_o = address_hold_r ||
        (active_r && !stop_w && !issued_all_r &&
            (outstanding_r < LIMIT || response_fire_w));
    assign address_fire_w = axi_arvalid_o && axi_arready_i;
    assign response_fire_w = axi_rvalid_i && axi_rready_o && axi_rlast_i;
    assign axi_rready_o = stop_w ? 1'b1 : data_ready_i;
    assign data_valid_o = axi_rvalid_i && active_r && !stop_w;
    assign data_o = axi_rdata_i;
    assign data_sol_o = data_left_r == width_beats_r;
    assign data_eol_o = data_left_r == 12'd1;
    assign data_eof_o = data_eol_o && data_rows_r == 12'd1;
    assign data_fire_w = data_valid_o && data_ready_i;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            data_left_r <= 12'd0;
            data_rows_r <= 12'd0;
        end else if (desc_fire_w) begin
            data_left_r <= desc_beats_w;
            data_rows_r <= desc_height_i;
        end else if (data_fire_w) begin
            if (data_left_r == 12'd1) begin
                data_left_r <= width_beats_r;
                data_rows_r <= data_rows_r - 12'd1;
            end else begin
                data_left_r <= data_left_r - 12'd1;
            end
        end
    end

    // Descriptor/address payload is never reset; validity belongs to control below.
    always @(posedge clk_i) begin
        if (desc_fire_w) begin
            addr_r <= desc_base_i;
            line_addr_r <= desc_base_i;
            stride_r <= desc_stride_i;
            width_beats_r <= desc_beats_w;
        end else if (address_fire_w) begin
            if (address_left_r == {7'd0, burst_beats_w}) begin
                addr_r <= line_addr_r + stride_r;
                line_addr_r <= line_addr_r + stride_r;
            end else begin
                addr_r <= addr_r + {22'd0, burst_beats_w, 5'd0};
            end
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            active_r <= 1'b0;
            abort_r <= 1'b0;
            error_r <= 1'b0;
            issued_all_r <= 1'b0;
            address_hold_r <= 1'b0;
            outstanding_r <= {COUNT_WIDTH{1'b0}};
            address_left_r <= 12'd0;
            address_rows_r <= 12'd0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            address_hold_r <= axi_arvalid_o && !axi_arready_i;
            if (desc_fire_w) begin
                active_r <= 1'b1;
                abort_r <= 1'b0;
                error_r <= 1'b0;
                issued_all_r <= 1'b0;
                address_left_r <= desc_beats_w;
                address_rows_r <= desc_height_i;
            end
            if (active_r && abort_i)
                abort_r <= 1'b1;
            if (active_r && (axi_rvalid_i && axi_rready_o && axi_rresp_i != 2'b00))
                error_r <= 1'b1;
            if (address_fire_w) begin
                if (address_left_r == {7'd0, burst_beats_w}) begin
                    address_left_r <= width_beats_r;
                    address_rows_r <= address_rows_r - 12'd1;
                    if (address_rows_r == 12'd1)
                        issued_all_r <= 1'b1;
                end else begin
                    address_left_r <= address_left_r - {7'd0, burst_beats_w};
                end
            end
            if (active_r && !stop_w && (data_fire_w && data_eof_o)) begin
                active_r <= 1'b0;
                done_o <= 1'b1;
            end
            // spec 5.3: a stalled address remains committed until it handshakes.
            if (active_r && stop_w && outstanding_r == 0 && !axi_arvalid_o)
                active_r <= 1'b0;
            case ({address_fire_w, response_fire_w})
                2'b10: outstanding_r <= outstanding_r + 1'b1;
                2'b01: outstanding_r <= outstanding_r - 1'b1;
                default: outstanding_r <= outstanding_r;
            endcase
        end
    end
endmodule
