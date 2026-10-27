// File: edrv32_disp_scan.v
// Spec: disp-spec 2.3, 2.4, 2.7, 4.3, 6.
// Description: Expand packed RGB565 and repay missed-beat debt in stream order.
//              A missing group remains black for all sixteen pixel positions.
// Clock domain: clk_pix (clk_i).
module edrv32_disp_scan (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Raster and synchronized scan enable.
    input wire enable_i,
    input wire de_i,
    input wire [10:0] x_i,
    input wire [9:0] y_i,
    input wire vblank_i,

    // Scan FIFO consumer.
    input wire fifo_valid_i,
    output wire fifo_ready_o,
    input wire [255:0] fifo_data_i,
    output wire [23:0] rgb_o,

    // Events and unit-step counters for X6 CDC.
    output wire frame_req_o,
    output wire underflow_o,
    output wire [9:0] read_cnt_o,
    output wire [31:0] perf0_o,
    output wire [31:0] perf1_o,
    output wire [31:0] perf2_o
);
    reg scan_frame_r;
    reg group_good_r;
    reg underflow_seen_r;
    reg [239:0] pixels_r;
    reg [31:0] debt_r;
    reg [9:0] read_cnt_r;
    reg [31:0] perf0_r;
    reg [31:0] perf1_r;
    reg [31:0] perf2_r;
    wire group_start_w;
    wire group_good_w;
    wire missing_w;
    wire discard_w;
    wire [15:0] pixel_w;

    assign frame_req_o = vblank_i && enable_i;
    assign group_start_w = scan_frame_r && de_i && x_i[3:0] == 4'd0;
    assign group_good_w = debt_r == 32'd0 && fifo_valid_i;
    assign missing_w = group_start_w && !group_good_w;
    // spec 2.7 clarification: repay debt even in blanking or disabled frames.
    assign discard_w = debt_r != 32'd0 && fifo_valid_i;
    assign fifo_ready_o = debt_r != 32'd0 || group_start_w;
    assign underflow_o = missing_w && !underflow_seen_r;
    assign pixel_w = !scan_frame_r || !de_i ? 16'd0 :
        (group_start_w ? (group_good_w ? fifo_data_i[15:0] : 16'd0) :
            (group_good_r ? pixels_r[15:0] : 16'd0));
    assign rgb_o = {pixel_w[15:11], pixel_w[15:13],
                    pixel_w[10:5], pixel_w[10:9], pixel_w[4:0], pixel_w[4:2]};
    assign read_cnt_o = read_cnt_r;
    assign perf0_o = perf0_r;
    assign perf1_o = perf1_r;
    assign perf2_o = perf2_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            scan_frame_r <= 1'b0;
            group_good_r <= 1'b0;
            underflow_seen_r <= 1'b0;
            debt_r <= 32'd0;
            read_cnt_r <= 10'd0;
            perf0_r <= 32'd0;
            perf1_r <= 32'd0;
            perf2_r <= 32'd0;
        end else begin
            if (vblank_i) begin
                scan_frame_r <= enable_i;
                underflow_seen_r <= 1'b0;
            end else if (underflow_o) begin
                underflow_seen_r <= 1'b1;
            end
            if (group_start_w) begin
                group_good_r <= group_good_w;
            end
            if (fifo_valid_i && fifo_ready_o) begin
                read_cnt_r <= read_cnt_r + 10'd1;
            end
            // Completion count also lets clk_mem derive scan BUSY from request count.
            if (scan_frame_r && de_i && x_i == 11'd1279 && y_i == 10'd719) begin
                perf0_r <= perf0_r + 32'd1;
            end
            if (underflow_o) begin
                perf1_r <= perf1_r + 32'd1;
            end
            if (missing_w) begin
                perf2_r <= perf2_r + 32'd1;
            end
            case ({missing_w, discard_w})
                2'b10: debt_r <= debt_r + 32'd1;
                2'b01: debt_r <= debt_r - 32'd1;
                default: begin end
            endcase
        end
    end

    always @(posedge clk_i) begin
        if (group_start_w && group_good_w) begin
            pixels_r <= fifo_data_i[255:16];
        end else if (scan_frame_r && de_i) begin
            pixels_r <= {16'd0, pixels_r[239:16]};
        end
    end
endmodule
