// File: edrv32_disp_reader.v
// Spec: disp-spec 2.4-2.6, 4.3, 5.2.
// Description: Queue frame requests and reserve a full scan line before each DMA.
//              Frame descriptors retire only after all returned data is accepted.
// Clock domain: clk_mem (clk_i).
module edrv32_disp_reader (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Frame configuration and request events.
    input wire frame_req_i,
    input wire soft_clear_i,
    input wire [31:0] next_base_i,
    input wire [31:0] stride_i,
    input wire [9:0] read_cnt_i,
    input wire write_i,

    // DMA descriptor interface; one descriptor is exactly one display line.
    output wire desc_valid_o,
    input wire desc_ready_i,
    output wire [31:0] desc_base_o,
    output wire [31:0] desc_stride_o,
    output wire [15:0] desc_width_bytes_o,
    output wire [11:0] desc_height_o,
    input wire done_i,

    // Frame status and performance events.
    output wire frame_start_o,
    output wire busy_o,
    output wire urgent_o,
    output wire delayed_req_o,
    output wire [31:0] req_cnt_o,
    output wire fifo_pending_o
);
    reg active_r;
    reg line_pending_r;
    reg [9:0] line_r;
    reg [31:0] pending_cnt_r;
    reg [31:0] req_cnt_r;
    reg [9:0] write_cnt_r;
    reg [31:0] line_base_r;
    reg [31:0] stride_r;
    wire [9:0] used_w;
    wire desc_fire_w;

    assign used_w = write_cnt_r - read_cnt_i;
    assign frame_start_o = !active_r && (pending_cnt_r != 32'd0 || frame_req_i);
    assign busy_o = active_r || pending_cnt_r != 32'd0 || frame_req_i;
    assign urgent_o = active_r && used_w < 10'd80;
    assign delayed_req_o = frame_req_i && active_r;
    assign req_cnt_o = req_cnt_r;
    assign fifo_pending_o = used_w != 10'd0;
    assign desc_valid_o = active_r && !line_pending_r && used_w <= 10'd432;
    assign desc_fire_w = desc_valid_o && desc_ready_i;
    assign desc_base_o = line_base_r;
    assign desc_stride_o = stride_r;
    assign desc_width_bytes_o = 16'd2560;
    assign desc_height_o = 12'd1;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            active_r <= 1'b0;
            line_pending_r <= 1'b0;
            line_r <= 10'd0;
            pending_cnt_r <= 32'd0;
            req_cnt_r <= 32'd0;
            write_cnt_r <= 10'd0;
        end else begin
            if (soft_clear_i) begin
                req_cnt_r <= 32'd0;
            end else if (frame_req_i) begin
                req_cnt_r <= req_cnt_r + 32'd1;
            end
            if (write_i) begin
                write_cnt_r <= write_cnt_r + 10'd1;
            end
            if (frame_start_o) begin
                active_r <= 1'b1;
                line_pending_r <= 1'b0;
                line_r <= 10'd0;
            end else if (done_i) begin
                line_pending_r <= 1'b0;
                if (line_r == 10'd719) begin
                    active_r <= 1'b0;
                end else begin
                    line_r <= line_r + 10'd1;
                end
            end else if (desc_fire_w) begin
                line_pending_r <= 1'b1;
            end
            case ({frame_req_i, frame_start_o})
                2'b10: pending_cnt_r <= pending_cnt_r + 32'd1;
                2'b01: pending_cnt_r <= pending_cnt_r - 32'd1;
                default: begin end
            endcase
        end
    end

    // spec 2.4: a delayed request samples the latest software configuration on start.
    always @(posedge clk_i) begin
        if (frame_start_o) begin
            line_base_r <= next_base_i;
            stride_r <= stride_i;
        end else if (done_i) begin
            line_base_r <= line_base_r + stride_r;
        end
    end
endmodule
