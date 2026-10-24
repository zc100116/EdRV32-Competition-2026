// ============================================================================
// File        : edrv32_render_a8_blur_dma.v
// Description : Separable zero-padded A8 box blur through a DDR scratch mask.
// Notes       : Radius is 0..15. Source, scratch and output rows are aligned
//               to 32 bytes; the scratch region must not overlap the source.
//               Horizontal pixels use a sliding sum. Vertical row beats are
//               accumulated as they arrive instead of retaining 31 beats.
// ============================================================================

module edrv32_render_a8_blur_dma #(
    parameter [3:0] AXI_ID = 4'h7
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [31:0]  source_base_i,
    input  wire [31:0]  source_stride_i,
    input  wire [31:0]  scratch_base_i,
    input  wire [31:0]  scratch_stride_i,
    input  wire [31:0]  output_base_i,
    input  wire [31:0]  output_stride_i,
    input  wire [15:0]  width_i,
    input  wire [15:0]  height_i,
    input  wire [4:0]   radius_i,
    output wire         busy_o,
    output wire         done_o,
    output wire         error_o,
    output wire [31:0]  write_beat_count_o,

    output wire [3:0]   m_arid_o,
    output wire [31:0]  m_araddr_o,
    output wire [7:0]   m_arlen_o,
    output wire [2:0]   m_arsize_o,
    output wire [1:0]   m_arburst_o,
    output wire [3:0]   m_arqos_o,
    output wire         m_arvalid_o,
    input  wire         m_arready_i,
    input  wire [3:0]   m_rid_i,
    input  wire [255:0] m_rdata_i,
    input  wire [1:0]   m_rresp_i,
    input  wire         m_rlast_i,
    input  wire         m_rvalid_i,
    output wire         m_rready_o,

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

    localparam [3:0] ST_IDLE    = 4'd0;
    localparam [3:0] ST_H_PREP  = 4'd1;
    localparam [3:0] ST_H_AR    = 4'd2;
    localparam [3:0] ST_H_R     = 4'd3;
    localparam [3:0] ST_H_PIXEL = 4'd4;
    localparam [3:0] ST_V_PREP  = 4'd5;
    localparam [3:0] ST_V_AR    = 4'd6;
    localparam [3:0] ST_V_R     = 4'd7;
    localparam [3:0] ST_V_PIXEL = 4'd8;
    localparam [3:0] ST_AW      = 4'd9;
    localparam [3:0] ST_W       = 4'd10;
    localparam [3:0] ST_B       = 4'd11;
    localparam [3:0] ST_NEXT    = 4'd12;

    // ceil(2^16 / (2*radius+1)); one correction gives exact division for
    // every possible rounded A8 window sum (0..255*window_size+radius).
    function [15:0] reciprocal;
        input [4:0] radius;
        begin
            case (radius)
                5'd1: reciprocal = 16'd21846;
                5'd2: reciprocal = 16'd13108;
                5'd3: reciprocal = 16'd9363;
                5'd4: reciprocal = 16'd7282;
                5'd5: reciprocal = 16'd5958;
                5'd6: reciprocal = 16'd5042;
                5'd7: reciprocal = 16'd4370;
                5'd8: reciprocal = 16'd3856;
                5'd9: reciprocal = 16'd3450;
                5'd10: reciprocal = 16'd3121;
                5'd11: reciprocal = 16'd2850;
                5'd12: reciprocal = 16'd2622;
                5'd13: reciprocal = 16'd2428;
                5'd14: reciprocal = 16'd2260;
                5'd15: reciprocal = 16'd2115;
                default: reciprocal = 16'd0;
            endcase
        end
    endfunction

    reg [3:0]   state_r;
    reg         done_r;
    reg         error_r;
    reg         vertical_r;
    reg [31:0]  source_row_addr_r;
    reg [31:0]  scratch_row_addr_r;
    reg [31:0]  output_row_addr_r;
    reg [31:0]  source_stride_r;
    reg [31:0]  scratch_stride_r;
    reg [31:0]  output_stride_r;
    reg [31:0]  scratch_base_r;
    reg [31:0]  output_base_r;
    reg [15:0]  width_r;
    reg [15:0]  height_r;
    reg [4:0]   radius_r;
    reg [5:0]   window_size_r;
    reg [11:0]  beats_per_row_r;
    reg [15:0]  row_r;
    reg [11:0]  beat_r;
    reg [4:0]   lane_r;
    reg [1:0]   h_load_index_r;
    reg [4:0]   v_init_count_r;
    reg [15:0]  v_next_row_r;
    reg         v_init_r;
    reg         v_sub_r;
    reg [31:0]  v_old_addr_r;
    reg [31:0]  v_next_addr_r;
    reg [255:0] h_prev_r;
    reg [255:0] h_current_r;
    reg [255:0] h_next_r;
    reg [13:0]  horizontal_sum_r;
    reg [13:0]  vertical_sum_r [0:31];
    reg [255:0] write_word_r;
    reg [31:0]  write_beat_count_r;

    wire [16:0] width_rounded_w = {1'b0,width_i} + 17'd31;
    wire [11:0] beats_per_row_w = width_rounded_w[16:5];
    wire [31:0] row_bytes_w = {15'd0,beats_per_row_w,5'd0};
    wire [31:0] beat_offset_w = {15'd0,beat_r,5'd0};
    wire [16:0] pixel_x_w = {beat_r,lane_r};
    wire pixel_valid_w = pixel_x_w < {1'b0,width_r};
    wire [31:0] h_read_addr_w = source_row_addr_r + beat_offset_w +
        (h_load_index_r == 2'd0 ? 32'hffff_ffe0 :
         h_load_index_r == 2'd2 ? 32'd32 : 32'd0);
    wire h_neighbor_valid_w = h_load_index_r == 2'd1 ||
        (h_load_index_r == 2'd0 && beat_r != 12'd0) ||
        (h_load_index_r == 2'd2 &&
         ({1'b0,beat_r} + 13'd1) <
         {1'b0,beats_per_row_r});
    wire [767:0] horizontal_words_w =
        {h_next_r,h_current_r,h_prev_r};
    wire read_fault_w = (m_rid_i != AXI_ID) ||
                        (m_rresp_i != 2'b00) || !m_rlast_i;
    wire write_fault_w = (m_bid_i != AXI_ID) ||
                         (m_bresp_i != 2'b00);

    wire [6:0] h_remove_index_w =
        7'd32 + {2'd0,lane_r} - {2'd0,radius_r};
    wire [6:0] h_add_index_w =
        7'd33 + {2'd0,lane_r} + {2'd0,radius_r};
    wire [17:0] h_add_x_w =
        {1'b0,pixel_x_w} + {13'd0,radius_r} + 18'd1;
    wire [7:0] h_remove_byte_w =
        (pixel_x_w >= {12'd0,radius_r}) ?
        horizontal_words_w[h_remove_index_w*8 +: 8] : 8'd0;
    wire [7:0] h_add_byte_w =
        (h_add_x_w < {2'd0,width_r}) ?
        horizontal_words_w[h_add_index_w*8 +: 8] : 8'd0;

    // Only the first pixel of a row needs a new window sum. All following
    // pixels, including those in later beats, advance the same running sum.
    wire [13:0] h_seed_0 [0:15];
    wire [13:0] h_seed_1 [0:7];
    wire [13:0] h_seed_2 [0:3];
    wire [13:0] h_seed_3 [0:1];
    wire [13:0] h_seed_w;
    genvar seed_index;
    generate
        for (seed_index=0; seed_index<16; seed_index=seed_index+1) begin: g_h_seed
            assign h_seed_0[seed_index] =
                (seed_index <= radius_r && seed_index < width_r) ?
                {6'd0,m_rdata_i[seed_index*8 +: 8]} : 14'd0;
        end
        for (seed_index=0; seed_index<8; seed_index=seed_index+1) begin: g_h_sum_1
            assign h_seed_1[seed_index] = h_seed_0[seed_index*2] +
                                            h_seed_0[seed_index*2+1];
        end
        for (seed_index=0; seed_index<4; seed_index=seed_index+1) begin: g_h_sum_2
            assign h_seed_2[seed_index] = h_seed_1[seed_index*2] +
                                            h_seed_1[seed_index*2+1];
        end
        for (seed_index=0; seed_index<2; seed_index=seed_index+1) begin: g_h_sum_3
            assign h_seed_3[seed_index] = h_seed_2[seed_index*2] +
                                            h_seed_2[seed_index*2+1];
        end
    endgenerate
    assign h_seed_w = h_seed_3[0] + h_seed_3[1];

    wire [13:0] selected_sum_w = vertical_r ?
        vertical_sum_r[lane_r] : horizontal_sum_r;
    wire [13:0] rounded_sum_w =
        selected_sum_w + {8'd0,window_size_r[5:1]};
    wire [15:0] reciprocal_w = reciprocal(radius_r);
    wire [29:0] reciprocal_product_w = rounded_sum_w * reciprocal_w;
    wire [7:0] quotient_approx_w = reciprocal_product_w[23:16];
    wire [13:0] quotient_test_w =
        quotient_approx_w * window_size_r;
    wire [7:0] pixel_result_w = radius_r == 5'd0 ?
        rounded_sum_w[7:0] :
        (quotient_test_w > rounded_sum_w ?
         quotient_approx_w - 8'd1 : quotient_approx_w);
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
    assign write_beat_count_o = write_beat_count_r;

    assign m_arid_o = AXI_ID;
    assign m_araddr_o = vertical_r ?
        (v_sub_r ? v_old_addr_r : v_next_addr_r) + beat_offset_w :
        h_read_addr_w;
    assign m_arlen_o = 8'd0;
    assign m_arsize_o = 3'd5;
    assign m_arburst_o = 2'b01;
    assign m_arqos_o = 4'd2;
    assign m_arvalid_o = (state_r == ST_H_AR &&
                          h_neighbor_valid_w) ||
                         (state_r == ST_V_AR);
    assign m_rready_o = (state_r == ST_H_R) ||
                        (state_r == ST_V_R);

    assign m_awid_o = AXI_ID;
    assign m_awaddr_o = vertical_r ?
        output_row_addr_r + beat_offset_w :
        scratch_row_addr_r + beat_offset_w;
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

    integer lane_index;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= ST_IDLE;
            done_r <= 1'b0;
            error_r <= 1'b0;
            vertical_r <= 1'b0;
            source_row_addr_r <= 32'd0;
            scratch_row_addr_r <= 32'd0;
            output_row_addr_r <= 32'd0;
            source_stride_r <= 32'd0;
            scratch_stride_r <= 32'd0;
            output_stride_r <= 32'd0;
            scratch_base_r <= 32'd0;
            output_base_r <= 32'd0;
            width_r <= 16'd0;
            height_r <= 16'd0;
            radius_r <= 5'd0;
            window_size_r <= 6'd1;
            beats_per_row_r <= 12'd0;
            row_r <= 16'd0;
            beat_r <= 12'd0;
            lane_r <= 5'd0;
            h_load_index_r <= 2'd0;
            v_init_count_r <= 5'd0;
            v_next_row_r <= 16'd0;
            v_init_r <= 1'b0;
            v_sub_r <= 1'b0;
            v_old_addr_r <= 32'd0;
            v_next_addr_r <= 32'd0;
            horizontal_sum_r <= 14'd0;
            write_word_r <= 256'd0;
            write_beat_count_r <= 32'd0;
        end else begin
            done_r <= 1'b0;
            if (start_i && start_ready_o) begin
                error_r <= (source_base_i[4:0] != 5'd0) ||
                           (scratch_base_i[4:0] != 5'd0) ||
                           (output_base_i[4:0] != 5'd0) ||
                           (source_stride_i[4:0] != 5'd0) ||
                           (scratch_stride_i[4:0] != 5'd0) ||
                           (output_stride_i[4:0] != 5'd0) ||
                           (row_bytes_w > source_stride_i) ||
                           (row_bytes_w > scratch_stride_i) ||
                           (row_bytes_w > output_stride_i) ||
                           (radius_i > 5'd15) ||
                           (scratch_base_i == source_base_i) ||
                           (scratch_base_i == output_base_i);
                write_beat_count_r <= 32'd0;
                if (width_i == 16'd0 || height_i == 16'd0) begin
                    done_r <= 1'b1;
                end else if ((source_base_i[4:0] != 5'd0) ||
                             (scratch_base_i[4:0] != 5'd0) ||
                             (output_base_i[4:0] != 5'd0) ||
                             (source_stride_i[4:0] != 5'd0) ||
                             (scratch_stride_i[4:0] != 5'd0) ||
                             (output_stride_i[4:0] != 5'd0) ||
                             (row_bytes_w > source_stride_i) ||
                             (row_bytes_w > scratch_stride_i) ||
                             (row_bytes_w > output_stride_i) ||
                             (radius_i > 5'd15) ||
                             (scratch_base_i == source_base_i) ||
                             (scratch_base_i == output_base_i)) begin
                    done_r <= 1'b1;
                end else begin
                    source_row_addr_r <= source_base_i;
                    scratch_row_addr_r <= scratch_base_i;
                    output_row_addr_r <= output_base_i;
                    source_stride_r <= source_stride_i;
                    scratch_stride_r <= scratch_stride_i;
                    output_stride_r <= output_stride_i;
                    scratch_base_r <= scratch_base_i;
                    output_base_r <= output_base_i;
                    width_r <= width_i;
                    height_r <= height_i;
                    radius_r <= radius_i;
                    window_size_r <= {radius_i,1'b0} + 6'd1;
                    beats_per_row_r <= beats_per_row_w;
                    vertical_r <= 1'b0;
                    row_r <= 16'd0;
                    beat_r <= 12'd0;
                    state_r <= ST_H_PREP;
                end
            end else begin
                case (state_r)
                    ST_H_PREP: begin
                        if (beat_r == 12'd0) begin
                            h_load_index_r <= 2'd0;
                        end else begin
                            // The previous beat's current/next words become
                            // this beat's previous/current words.
                            h_prev_r <= h_current_r;
                            h_current_r <= h_next_r;
                            h_load_index_r <= 2'd2;
                        end
                        lane_r <= 5'd0;
                        write_word_r <= 256'd0;
                        state_r <= ST_H_AR;
                    end
                    ST_H_AR: begin
                        if (!h_neighbor_valid_w) begin
                            case (h_load_index_r)
                                2'd0: h_prev_r <= 256'd0;
                                2'd1: h_current_r <= 256'd0;
                                default: h_next_r <= 256'd0;
                            endcase
                            if (h_load_index_r == 2'd2)
                                state_r <= ST_H_PIXEL;
                            else
                                h_load_index_r <= h_load_index_r + 2'd1;
                        end else if (m_arready_i) begin
                            state_r <= ST_H_R;
                        end
                    end
                    ST_H_R: begin
                        if (m_rvalid_i) begin
                            if (read_fault_w) begin
                                error_r <= 1'b1;
                                done_r <= 1'b1;
                                state_r <= ST_IDLE;
                            end else begin
                                case (h_load_index_r)
                                    2'd0: h_prev_r <= m_rdata_i;
                                    2'd1: begin
                                        h_current_r <= m_rdata_i;
                                        if (beat_r == 12'd0)
                                            horizontal_sum_r <= h_seed_w;
                                    end
                                    default: h_next_r <= m_rdata_i;
                                endcase
                                if (h_load_index_r == 2'd2)
                                    state_r <= ST_H_PIXEL;
                                else begin
                                    h_load_index_r <= h_load_index_r +
                                                      2'd1;
                                    state_r <= ST_H_AR;
                                end
                            end
                        end
                    end
                    ST_H_PIXEL: begin
                        if (pixel_valid_w)
                            write_word_r[lane_r*8 +: 8] <=
                                pixel_result_w;
                        horizontal_sum_r <= horizontal_sum_r +
                                            {6'd0,h_add_byte_w} -
                                            {6'd0,h_remove_byte_w};
                        if (lane_r == 5'd31)
                            state_r <= ST_AW;
                        else
                            lane_r <= lane_r + 5'd1;
                    end
                    ST_V_PREP: begin
                        lane_r <= 5'd0;
                        write_word_r <= 256'd0;
                        if (row_r == 16'd0) begin
                            for (lane_index=0; lane_index<32;
                                 lane_index=lane_index+1)
                                vertical_sum_r[lane_index] <= 14'd0;
                            v_init_count_r <= 5'd0;
                            v_next_row_r <= 16'd0;
                            v_init_r <= 1'b1;
                            v_sub_r <= 1'b0;
                            v_old_addr_r <= scratch_base_r;
                            v_next_addr_r <= scratch_base_r;
                            state_r <= ST_V_AR;
                        end else if (row_r > {11'd0,radius_r}) begin
                            v_sub_r <= 1'b1;
                            state_r <= ST_V_AR;
                        end else if (v_next_row_r < height_r) begin
                            v_sub_r <= 1'b0;
                            state_r <= ST_V_AR;
                        end else begin
                            state_r <= ST_V_PIXEL;
                        end
                    end
                    ST_V_AR: begin
                        if (m_arready_i)
                            state_r <= ST_V_R;
                    end
                    ST_V_R: begin
                        if (m_rvalid_i) begin
                            if (read_fault_w) begin
                                error_r <= 1'b1;
                                done_r <= 1'b1;
                                state_r <= ST_IDLE;
                            end else begin
                                for (lane_index=0; lane_index<32;
                                     lane_index=lane_index+1)
                                    vertical_sum_r[lane_index] <= v_sub_r ?
                                        vertical_sum_r[lane_index] -
                                        {6'd0,m_rdata_i[lane_index*8 +: 8]} :
                                        vertical_sum_r[lane_index] +
                                        {6'd0,m_rdata_i[lane_index*8 +: 8]};
                                if (v_sub_r) begin
                                    v_old_addr_r <= v_old_addr_r +
                                                    scratch_stride_r;
                                    v_sub_r <= 1'b0;
                                    state_r <= v_next_row_r < height_r ?
                                               ST_V_AR : ST_V_PIXEL;
                                end else begin
                                    v_next_addr_r <= v_next_addr_r +
                                                     scratch_stride_r;
                                    v_next_row_r <= v_next_row_r + 16'd1;
                                    if (v_init_r &&
                                        v_init_count_r < radius_r &&
                                        v_next_row_r + 16'd1 < height_r) begin
                                        v_init_count_r <= v_init_count_r +
                                                          5'd1;
                                        state_r <= ST_V_AR;
                                    end else begin
                                        v_init_r <= 1'b0;
                                        state_r <= ST_V_PIXEL;
                                    end
                                end
                            end
                        end
                    end
                    ST_V_PIXEL: begin
                        if (pixel_valid_w)
                            write_word_r[lane_r*8 +: 8] <=
                                pixel_result_w;
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
                                write_beat_count_r <=
                                    write_beat_count_r + 32'd1;
                                state_r <= ST_NEXT;
                            end
                        end
                    end
                    ST_NEXT: begin
                        if (vertical_r) begin
                            if (row_r + 16'd1 < height_r) begin
                                row_r <= row_r + 16'd1;
                                output_row_addr_r <=
                                    output_row_addr_r + output_stride_r;
                                state_r <= ST_V_PREP;
                            end else if (({1'b0,beat_r} + 13'd1) <
                                         {1'b0,beats_per_row_r}) begin
                                beat_r <= beat_r + 12'd1;
                                row_r <= 16'd0;
                                output_row_addr_r <= output_base_r;
                                state_r <= ST_V_PREP;
                            end else begin
                                done_r <= 1'b1;
                                state_r <= ST_IDLE;
                            end
                        end else if (({1'b0,beat_r} + 13'd1) <
                                     {1'b0,beats_per_row_r}) begin
                            beat_r <= beat_r + 12'd1;
                            state_r <= ST_H_PREP;
                        end else if (row_r + 16'd1 < height_r) begin
                            row_r <= row_r + 16'd1;
                            beat_r <= 12'd0;
                                source_row_addr_r <=
                                    source_row_addr_r + source_stride_r;
                                scratch_row_addr_r <=
                                    scratch_row_addr_r + scratch_stride_r;
                                state_r <= ST_H_PREP;
                        end else begin
                            vertical_r <= 1'b1;
                            row_r <= 16'd0;
                            beat_r <= 12'd0;
                            output_row_addr_r <= output_base_r;
                            state_r <= ST_V_PREP;
                        end
                    end
                    default: state_r <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
