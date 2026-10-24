// ============================================================================
// File        : edrv32_render_shadow_mask_dma.v
// Description : A8 rounded-box shadow seed mask written to DDR.
// Notes       : The opaque rounded box is inset by blur_radius pixels, so
//               the following separable blur has zero-padded fade margins.
// ============================================================================

module edrv32_render_shadow_mask_dma #(
    parameter [3:0] AXI_ID = 4'h7
) (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [31:0]  mask_base_i,
    input  wire [31:0]  mask_stride_i,
    input  wire [15:0]  width_i,
    input  wire [15:0]  height_i,
    input  wire [7:0]   corner_radius_i,
    input  wire [4:0]   blur_radius_i,
    output wire         busy_o,
    output wire         done_o,
    output wire         error_o,
    output wire [31:0]  beat_count_o,

    output wire [3:0]   m_awid_o,
    output wire [31:0]  m_awaddr_o,
    output wire [7:0]   m_awlen_o,
    output wire [2:0]   m_awsize_o,
    output wire [1:0]   m_awburst_o,
    output wire [3:0]   m_awqos_o,
    output wire         m_awvalid_o,
    input  wire         m_awready_i,
    output wire [255:0] m_wdata_o,
    output wire [31:0]  m_wstrb_o,
    output wire         m_wlast_o,
    output wire         m_wvalid_o,
    input  wire         m_wready_i,
    input  wire [3:0]   m_bid_i,
    input  wire [1:0]   m_bresp_i,
    input  wire         m_bvalid_i,
    output wire         m_bready_o
);

    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_PREP = 3'd1;
    localparam [2:0] ST_AW   = 3'd2;
    localparam [2:0] ST_W    = 3'd3;
    localparam [2:0] ST_B    = 3'd4;
    localparam [2:0] ST_NEXT = 3'd5;

    reg [2:0]   state_r;
    reg         done_r;
    reg         error_r;
    reg [31:0]  row_addr_r;
    reg [31:0]  stride_r;
    reg [15:0]  width_r;
    reg [15:0]  height_r;
    reg [15:0]  inner_width_r;
    reg [15:0]  inner_height_r;
    reg [7:0]   corner_radius_r;
    reg [4:0]   blur_radius_r;
    reg [11:0]  beats_per_row_r;
    reg [15:0]  row_r;
    reg [11:0]  beat_r;
    reg [4:0]   lane_r;
    reg [255:0] write_word_r;
    reg [31:0]  beat_count_r;

    wire [16:0] width_rounded_w = {1'b0,width_i} + 17'd31;
    wire [11:0] beats_per_row_w = width_rounded_w[16:5];
    wire [31:0] row_bytes_w = {15'd0,beats_per_row_w,5'd0};
    wire [15:0] inset_twice_w = {10'd0,blur_radius_i,1'b0};
    wire [15:0] inner_width_w = width_i - inset_twice_w;
    wire [15:0] inner_height_w = height_i - inset_twice_w;
    wire [16:0] pixel_x_w = {beat_r,lane_r};
    wire x_in_content_w =
        (pixel_x_w >= {12'd0,blur_radius_r}) &&
        (pixel_x_w < {1'b0,width_r} -
         {12'd0,blur_radius_r});
    wire y_in_content_w =
        (row_r >= {11'd0,blur_radius_r}) &&
        (row_r < height_r - {11'd0,blur_radius_r});
    wire [15:0] local_x_w = pixel_x_w[15:0] -
                            {11'd0,blur_radius_r};
    wire [15:0] local_y_w = row_r -
                            {11'd0,blur_radius_r};
    wire [15:0] right_room_w = inner_width_r - 16'd1 - local_x_w;
    wire [15:0] bottom_room_w = inner_height_r - 16'd1 - local_y_w;
    wire [15:0] x_room_w = local_x_w < right_room_w ?
                           local_x_w : right_room_w;
    wire [15:0] y_room_w = local_y_w < bottom_room_w ?
                           local_y_w : bottom_room_w;
    wire [8:0] corner_dx_w = x_room_w < {8'd0,corner_radius_r} ?
        {1'b0,corner_radius_r} - 9'd1 - {1'b0,x_room_w[7:0]} : 9'd0;
    wire [8:0] corner_dy_w = y_room_w < {8'd0,corner_radius_r} ?
        {1'b0,corner_radius_r} - 9'd1 - {1'b0,y_room_w[7:0]} : 9'd0;
    wire [17:0] corner_distance_w =
        corner_dx_w*corner_dx_w + corner_dy_w*corner_dy_w;
    wire [15:0] corner_radius_square_w =
        corner_radius_r*corner_radius_r;
    wire inside_w = x_in_content_w && y_in_content_w &&
        ((corner_radius_r == 8'd0) ||
         (corner_distance_w <= {2'd0,corner_radius_square_w}));
    wire [31:0] beat_offset_w = {15'd0,beat_r,5'd0};
    wire write_fault_w = (m_bid_i != AXI_ID) ||
                         (m_bresp_i != 2'b00);

    reg [31:0] beat_strobe_w;
    integer byte_index;
    always @(*) begin
        beat_strobe_w = 32'd0;
        for (byte_index=0; byte_index<32;
             byte_index=byte_index+1)
            if (({15'd0,beat_r,5'd0} + byte_index) <
                {16'd0,width_r})
                beat_strobe_w[byte_index] = 1'b1;
    end

    assign start_ready_o = state_r == ST_IDLE;
    assign busy_o = state_r != ST_IDLE;
    assign done_o = done_r;
    assign error_o = error_r;
    assign beat_count_o = beat_count_r;
    assign m_awid_o = AXI_ID;
    assign m_awaddr_o = row_addr_r + beat_offset_w;
    assign m_awlen_o = 8'd0;
    assign m_awsize_o = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awqos_o = 4'd2;
    assign m_awvalid_o = state_r == ST_AW;
    assign m_wdata_o = write_word_r;
    assign m_wstrb_o = beat_strobe_w;
    assign m_wlast_o = 1'b1;
    assign m_wvalid_o = state_r == ST_W;
    assign m_bready_o = state_r == ST_B;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= ST_IDLE;
            done_r <= 1'b0;
            error_r <= 1'b0;
            row_addr_r <= 32'd0;
            stride_r <= 32'd0;
            width_r <= 16'd0;
            height_r <= 16'd0;
            inner_width_r <= 16'd0;
            inner_height_r <= 16'd0;
            corner_radius_r <= 8'd0;
            blur_radius_r <= 5'd0;
            beats_per_row_r <= 12'd0;
            row_r <= 16'd0;
            beat_r <= 12'd0;
            lane_r <= 5'd0;
            write_word_r <= 256'd0;
            beat_count_r <= 32'd0;
        end else begin
            done_r <= 1'b0;
            if (start_i && start_ready_o) begin
                error_r <= (mask_base_i[4:0] != 5'd0) ||
                           (mask_stride_i[4:0] != 5'd0) ||
                           (row_bytes_w > mask_stride_i) ||
                           (blur_radius_i > 5'd15) ||
                           (width_i <= inset_twice_w) ||
                           (height_i <= inset_twice_w) ||
                           ({8'd0,corner_radius_i} >
                            (inner_width_w >> 1)) ||
                           ({8'd0,corner_radius_i} >
                            (inner_height_w >> 1));
                beat_count_r <= 32'd0;
                if (width_i == 16'd0 || height_i == 16'd0) begin
                    done_r <= 1'b1;
                end else if ((mask_base_i[4:0] != 5'd0) ||
                             (mask_stride_i[4:0] != 5'd0) ||
                             (row_bytes_w > mask_stride_i) ||
                             (blur_radius_i > 5'd15) ||
                             (width_i <= inset_twice_w) ||
                             (height_i <= inset_twice_w) ||
                             ({8'd0,corner_radius_i} >
                              (inner_width_w >> 1)) ||
                             ({8'd0,corner_radius_i} >
                              (inner_height_w >> 1))) begin
                    done_r <= 1'b1;
                end else begin
                    row_addr_r <= mask_base_i;
                    stride_r <= mask_stride_i;
                    width_r <= width_i;
                    height_r <= height_i;
                    inner_width_r <= inner_width_w;
                    inner_height_r <= inner_height_w;
                    corner_radius_r <= corner_radius_i;
                    blur_radius_r <= blur_radius_i;
                    beats_per_row_r <= beats_per_row_w;
                    row_r <= 16'd0;
                    beat_r <= 12'd0;
                    lane_r <= 5'd0;
                    write_word_r <= 256'd0;
                    state_r <= ST_PREP;
                end
            end else begin
                case (state_r)
                    ST_PREP: begin
                        if (pixel_x_w < {1'b0,width_r})
                            write_word_r[lane_r*8 +: 8] <=
                                inside_w ? 8'hff : 8'd0;
                        if (lane_r == 5'd31)
                            state_r <= ST_AW;
                        else
                            lane_r <= lane_r + 5'd1;
                    end
                    ST_AW: begin
                        if (m_awready_i)
                            state_r <= ST_W;
                    end
                    ST_W: begin
                        if (m_wready_i)
                            state_r <= ST_B;
                    end
                    ST_B: begin
                        if (m_bvalid_i) begin
                            if (write_fault_w) begin
                                error_r <= 1'b1;
                                done_r <= 1'b1;
                                state_r <= ST_IDLE;
                            end else begin
                                beat_count_r <= beat_count_r + 32'd1;
                                state_r <= ST_NEXT;
                            end
                        end
                    end
                    ST_NEXT: begin
                        lane_r <= 5'd0;
                        write_word_r <= 256'd0;
                        if (({1'b0,beat_r} + 13'd1) <
                            {1'b0,beats_per_row_r}) begin
                            beat_r <= beat_r + 12'd1;
                            state_r <= ST_PREP;
                        end else if (row_r + 16'd1 < height_r) begin
                            row_r <= row_r + 16'd1;
                            beat_r <= 12'd0;
                            row_addr_r <= row_addr_r + stride_r;
                            state_r <= ST_PREP;
                        end else begin
                            done_r <= 1'b1;
                            state_r <= ST_IDLE;
                        end
                    end
                    default: state_r <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
