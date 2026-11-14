// File: edrv32_dma2d_wr.v
// Spec: dma2d 2, 3, 5, 6; SoC 4.2, 7.1.
// Description: Greedy row/page burst splitting with bounded outstanding transactions.
//              ABORT drains committed AXI traffic before returning idle.
// Clock domain: clk_mem (clk_i).
module edrv32_dma2d_wr #(
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
    input wire data_valid_i,
    output wire data_ready_o,
    input wire [255:0] data_i,
    input wire [31:0] data_strb_i,

    // AXI256 write channels.
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
    (* keep = "true", syn_keep = 1 *) wire [7:0] stop_w;
    (* keep = "true", syn_keep = 1 *) wire abort_latch_w;
    wire [11:0] desc_beats_w;
    wire [7:0] page_beats_w;
    reg [4:0] burst_beats_w;
    wire unused_id_w;

    assign desc_fire_w = desc_valid_i && desc_ready_o;
    assign desc_ready_o = !active_r;
    assign idle_o = !active_r;
    assign err_o = done_o && error_r;
    genvar stop_group;
    generate for (stop_group = 0; stop_group < 8;
        stop_group = stop_group + 1) begin : g_stop
        assign stop_w[stop_group] = abort_r || abort_i;
    end endgenerate
    assign abort_latch_w = active_r && abort_i;
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

    reg write_active_r;
    reg [4:0] write_left_r;
    reg write_hold_r;
    reg [255:0] write_data_r;
    reg [31:0] write_strb_r;
    wire write_fire_w;
    wire write_available_w;

    assign unused_id_w = axi_bid_i;
    assign axi_awid_o = 1'b0;
    assign axi_awaddr_o = addr_r;
    assign axi_awlen_o = burst_beats_w[3:0] - 4'd1;
    // spec 5.4: recycle a retiring credit on the same edge to avoid burst gaps.
    assign axi_awvalid_o = address_hold_r ||
        (active_r && !stop_w[0] && !issued_all_r && !write_active_r &&
            data_valid_i && (outstanding_r < LIMIT || response_fire_w));
    assign address_fire_w = axi_awvalid_o && axi_awready_i;
    assign response_fire_w = axi_bvalid_i && axi_bready_o;
    assign axi_bready_o = 1'b1;
    assign write_available_w = write_active_r || address_fire_w;
    assign axi_wvalid_o = write_hold_r ||
        (write_available_w && (stop_w[1] || data_valid_i));
    assign axi_wdata_o = write_hold_r ? write_data_r : data_i;
    genvar strb_slice;
    generate for (strb_slice = 0; strb_slice < 4;
        strb_slice = strb_slice + 1) begin : g_strb
        assign axi_wstrb_o[strb_slice*8 +: 8] = write_hold_r ?
            write_strb_r[strb_slice*8 +: 8] :
            (stop_w[3+strb_slice] ? 8'd0 : data_strb_i[strb_slice*8 +: 8]);
    end endgenerate
    assign axi_wlast_o = write_active_r ? write_left_r == 5'd1 : burst_beats_w == 5'd1;
    assign data_ready_o = write_available_w && !stop_w[2] && axi_wready_i;
    assign write_fire_w = axi_wvalid_o && axi_wready_i;

    // Once WVALID is exposed, retain its payload through ABORT and backpressure.
    always @(posedge clk_i) begin
        if (axi_wvalid_o && !axi_wready_i && !write_hold_r) begin
            write_data_r <= axi_wdata_o;
            write_strb_r <= axi_wstrb_o;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            write_active_r <= 1'b0;
            write_left_r <= 5'd0;
            write_hold_r <= 1'b0;
        end else begin
            write_hold_r <= axi_wvalid_o && !axi_wready_i;
            if (address_fire_w) begin
                write_active_r <= !(write_fire_w && burst_beats_w == 5'd1);
                write_left_r <= burst_beats_w - {4'd0, write_fire_w};
            end else if (write_fire_w) begin
                write_active_r <= write_left_r != 5'd1;
                write_left_r <= write_left_r - 5'd1;
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
            address_hold_r <= axi_awvalid_o && !axi_awready_i;
            if (desc_fire_w) begin
                active_r <= 1'b1;
                abort_r <= 1'b0;
                error_r <= 1'b0;
                issued_all_r <= 1'b0;
                address_left_r <= desc_beats_w;
                address_rows_r <= desc_height_i;
            end
            if (abort_latch_w)
                abort_r <= 1'b1;
            if (active_r && (response_fire_w && axi_bresp_i != 2'b00))
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
            if (active_r && !stop_w[7] && issued_all_r && response_fire_w &&
                outstanding_r == {{(COUNT_WIDTH-1){1'b0}}, 1'b1}) begin
                active_r <= 1'b0;
                done_o <= 1'b1;
            end
            // spec 5.3: a stalled address remains committed until it handshakes.
            if (active_r && stop_w[7] && outstanding_r == 0 && !axi_awvalid_o)
                active_r <= 1'b0;
            case ({address_fire_w, response_fire_w})
                2'b10: outstanding_r <= outstanding_r + 1'b1;
                2'b01: outstanding_r <= outstanding_r - 1'b1;
                default: outstanding_r <= outstanding_r;
            endcase
        end
    end
endmodule
