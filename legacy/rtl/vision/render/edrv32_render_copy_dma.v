// ============================================================================
// File        : edrv32_render_copy_dma.v
// Description : Same-format rectangle copy with same-Surface overlap handling.
// Notes       : Source beats for a tile are captured before any tile write.
//               WSTRB preserves pixels outside the destination rectangle.
//               Different strides require explicitly disjoint Surfaces.
// ============================================================================

module edrv32_render_copy_dma #(
    parameter [3:0] AXI_ID = 4'h7
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [31:0]  source_row0_addr_i,
    input  wire [31:0]  source_stride_i,
    input  wire [15:0]  source_x_i,
    input  wire [31:0]  target_row0_addr_i,
    input  wire [31:0]  target_stride_i,
    input  wire [15:0]  target_x_i,
    input  wire [15:0]  width_i,
    input  wire [15:0]  height_i,
    input  wire         argb_i,
    input  wire         separate_surfaces_i,
    output wire         busy_o,
    output wire         done_o,
    output wire         error_o,
    output wire [31:0]  beat_count_o,

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
    localparam [3:0] ST_SEEK    = 4'd1;
    localparam [3:0] ST_SRC_AR0 = 4'd2;
    localparam [3:0] ST_SRC_R0  = 4'd3;
    localparam [3:0] ST_SRC_AR1 = 4'd4;
    localparam [3:0] ST_SRC_R1  = 4'd5;
    localparam [3:0] ST_PREP    = 4'd6;
    localparam [3:0] ST_AW      = 4'd7;
    localparam [3:0] ST_W       = 4'd8;
    localparam [3:0] ST_B       = 4'd9;
    localparam [3:0] ST_TILE    = 4'd10;

    reg [3:0]   state_r;
    reg         done_r;
    reg         error_r;
    reg         reverse_r;
    reg [31:0]  source_row_addr_r;
    reg [31:0]  target_row_addr_r;
    reg [31:0]  source_stride_r;
    reg [31:0]  target_stride_r;
    reg [31:0]  source_x_bytes_r;
    reg [31:0]  target_x_bytes_r;
    reg [31:0]  width_bytes_r;
    reg [15:0]  height_r;
    reg [15:0]  row_r;
    reg [15:0]  beat_r;
    reg [15:0]  first_beat_r;
    reg [15:0]  last_beat_r;
    reg [255:0] source_word0_r;
    reg [255:0] source_word1_r;
    reg [255:0] write_cache_r [0:7];
    reg [31:0]  strobe_cache_r [0:7];
    reg [15:0]  tile_first_beat_r;
    reg [3:0]   tile_len_r;
    reg [3:0]   tile_processed_r;
    reg [3:0]   write_index_r;
    reg [31:0]  beat_count_r;

    wire [16:0] source_end_pixel_w =
        {1'b0,source_x_i} + {1'b0,width_i};
    wire [16:0] target_end_pixel_w =
        {1'b0,target_x_i} + {1'b0,width_i};
    wire [31:0] source_x_bytes_w = argb_i ?
        {14'd0,source_x_i,2'b00} : {15'd0,source_x_i,1'b0};
    wire [31:0] target_x_bytes_w = argb_i ?
        {14'd0,target_x_i,2'b00} : {15'd0,target_x_i,1'b0};
    wire [31:0] width_bytes_w = argb_i ?
        {14'd0,width_i,2'b00} : {15'd0,width_i,1'b0};
    wire [31:0] source_end_bytes_w = source_x_bytes_w + width_bytes_w;
    wire [31:0] target_end_bytes_w = target_x_bytes_w + width_bytes_w;
    wire [31:0] target_last_byte_w = target_end_bytes_w - 32'd1;
    wire reverse_w = !separate_surfaces_i &&
                     (({1'b0,target_row0_addr_i} +
                      {1'b0,target_x_bytes_w}) >
                     ({1'b0,source_row0_addr_i} +
                      {1'b0,source_x_bytes_w}));

    wire [31:0] beat_addr_w = target_row_addr_r +
                              {11'd0,beat_r,5'd0};
    wire [31:0] tile_addr_w = target_row_addr_r +
                              {11'd0,tile_first_beat_r,5'd0};
    wire [15:0] remaining_beats_w = reverse_r ?
        (beat_r - first_beat_r + 16'd1) :
        (last_beat_r - beat_r + 16'd1);
    wire [7:0] boundary_beats_w = reverse_r ?
        {1'b0,beat_addr_w[11:5]} + 8'd1 :
        8'd128 - {1'b0,beat_addr_w[11:5]};
    wire [3:0] next_tile_len_w = remaining_beats_w < 16'd8 ?
        (remaining_beats_w < {8'd0,boundary_beats_w} ?
         remaining_beats_w[3:0] : boundary_beats_w[3:0]) :
        (boundary_beats_w < 8'd8 ? boundary_beats_w[3:0] : 4'd8);
    wire [15:0] tile_start_beat_w = reverse_r ?
        beat_r - {12'd0,next_tile_len_w} + 16'd1 : beat_r;
    wire [15:0] cache_index_w = beat_r - tile_first_beat_r;
    wire [31:0] rect_first_addr_w = target_row_addr_r +
                                    target_x_bytes_r;
    wire [31:0] rect_end_addr_w = rect_first_addr_w + width_bytes_r;
    wire [31:0] beat_end_addr_w = beat_addr_w + 32'd32;
    wire [31:0] first_offset_w = rect_first_addr_w - beat_addr_w;
    wire [31:0] end_offset_w = rect_end_addr_w - beat_addr_w;
    wire [5:0] first_active_w = rect_first_addr_w > beat_addr_w ?
        first_offset_w[5:0] : 6'd0;
    wire [5:0] end_active_w = rect_end_addr_w < beat_end_addr_w ?
        end_offset_w[5:0] : 6'd32;
    wire [5:0] active_length_w = end_active_w - first_active_w;
    wire [31:0] first_source_addr_w = source_row_addr_r +
        source_x_bytes_r + beat_addr_w +
        {26'd0,first_active_w} - rect_first_addr_w;
    wire [31:0] last_source_addr_w = first_source_addr_w +
        {26'd0,active_length_w} - 32'd1;
    wire [31:0] source_addr0_w = {first_source_addr_w[31:5],5'b0};
    wire [31:0] source_addr1_w = {last_source_addr_w[31:5],5'b0};
    wire need_source1_w = source_addr0_w != source_addr1_w;
    wire read_fault_w = (m_rid_i != AXI_ID) ||
                        (m_rresp_i != 2'b00) || !m_rlast_i;
    wire write_fault_w = (m_bid_i != AXI_ID) ||
                         (m_bresp_i != 2'b00);
    wire start_fire_w = start_i && start_ready_o;
    wire row_last_w = reverse_r ? (row_r == 16'd0) :
                                  (row_r == height_r - 16'd1);
    wire beat_last_w = reverse_r ? (beat_r == first_beat_r) :
                                   (beat_r == last_beat_r);

    reg [255:0] prepared_word_w;
    reg [31:0]  prepared_strobe_w;
    integer byte_index;
    integer source_byte_index;
    always @(*) begin
        prepared_word_w = 256'd0;
        prepared_strobe_w = 32'd0;
        source_byte_index = 0;
        for (byte_index = 0; byte_index < 32;
             byte_index = byte_index + 1) begin
            if ((byte_index >= first_active_w) &&
                (byte_index < end_active_w)) begin
                source_byte_index = {27'd0,first_source_addr_w[4:0]} +
                                    byte_index - {26'd0,first_active_w};
                prepared_strobe_w[byte_index] = 1'b1;
                if (source_byte_index < 32)
                    prepared_word_w[byte_index*8 +: 8] =
                        source_word0_r[source_byte_index*8 +: 8];
                else
                    prepared_word_w[byte_index*8 +: 8] =
                        source_word1_r[(source_byte_index-32)*8 +: 8];
            end
        end
    end

    assign start_ready_o = state_r == ST_IDLE;
    assign busy_o = state_r != ST_IDLE;
    assign done_o = done_r;
    assign error_o = error_r;
    assign beat_count_o = beat_count_r;

    assign m_arid_o = AXI_ID;
    assign m_araddr_o = state_r == ST_SRC_AR1 ? source_addr1_w :
                        source_addr0_w;
    assign m_arlen_o = 8'd0;
    assign m_arsize_o = 3'd5;
    assign m_arburst_o = 2'b01;
    assign m_arqos_o = 4'd3;
    assign m_arvalid_o = (state_r == ST_SRC_AR0) ||
                         (state_r == ST_SRC_AR1);
    assign m_rready_o = (state_r == ST_SRC_R0) ||
                        (state_r == ST_SRC_R1);

    assign m_awid_o = AXI_ID;
    assign m_awaddr_o = tile_addr_w;
    assign m_awlen_o = {4'd0,tile_len_r} - 8'd1;
    assign m_awsize_o = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awqos_o = 4'd3;
    assign m_awvalid_o = state_r == ST_AW;
    assign m_wdata_o = write_cache_r[write_index_r[2:0]];
    assign m_wstrb_o = strobe_cache_r[write_index_r[2:0]];
    assign m_wlast_o = write_index_r == tile_len_r - 4'd1;
    assign m_wvalid_o = state_r == ST_W;
    assign m_bready_o = state_r == ST_B;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= ST_IDLE;
            done_r <= 1'b0;
            error_r <= 1'b0;
            reverse_r <= 1'b0;
            source_row_addr_r <= 32'd0;
            target_row_addr_r <= 32'd0;
            source_stride_r <= 32'd0;
            target_stride_r <= 32'd0;
            source_x_bytes_r <= 32'd0;
            target_x_bytes_r <= 32'd0;
            width_bytes_r <= 32'd0;
            height_r <= 16'd0;
            row_r <= 16'd0;
            beat_r <= 16'd0;
            first_beat_r <= 16'd0;
            last_beat_r <= 16'd0;
            tile_first_beat_r <= 16'd0;
            tile_len_r <= 4'd0;
            tile_processed_r <= 4'd0;
            write_index_r <= 4'd0;
            beat_count_r <= 32'd0;
        end else begin
            done_r <= 1'b0;
            if (start_fire_w) begin
                error_r <= (source_row0_addr_i[4:0] != 5'd0) ||
                           (target_row0_addr_i[4:0] != 5'd0) ||
                           (source_stride_i[4:0] != 5'd0) ||
                           (target_stride_i[4:0] != 5'd0) ||
                           (!separate_surfaces_i &&
                            source_stride_i != target_stride_i) ||
                           (source_end_pixel_w > 17'd65536) ||
                           (target_end_pixel_w > 17'd65536) ||
                           (source_end_bytes_w > source_stride_i) ||
                           (target_end_bytes_w > target_stride_i);
                beat_count_r <= 32'd0;
                if ((width_i == 16'd0) || (height_i == 16'd0)) begin
                    done_r <= 1'b1;
                end else if ((source_row0_addr_i[4:0] != 5'd0) ||
                             (target_row0_addr_i[4:0] != 5'd0) ||
                             (source_stride_i[4:0] != 5'd0) ||
                             (target_stride_i[4:0] != 5'd0) ||
                             (!separate_surfaces_i &&
                              source_stride_i != target_stride_i) ||
                             (source_end_pixel_w > 17'd65536) ||
                             (target_end_pixel_w > 17'd65536) ||
                             (source_end_bytes_w > source_stride_i) ||
                             (target_end_bytes_w > target_stride_i)) begin
                    done_r <= 1'b1;
                end else begin
                    reverse_r <= reverse_w;
                    source_row_addr_r <= source_row0_addr_i;
                    target_row_addr_r <= target_row0_addr_i;
                    source_stride_r <= source_stride_i;
                    target_stride_r <= target_stride_i;
                    source_x_bytes_r <= source_x_bytes_w;
                    target_x_bytes_r <= target_x_bytes_w;
                    width_bytes_r <= width_bytes_w;
                    height_r <= height_i;
                    row_r <= 16'd0;
                    first_beat_r <= target_x_bytes_w[20:5];
                    last_beat_r <= target_last_byte_w[20:5];
                    beat_r <= reverse_w ? target_last_byte_w[20:5] :
                                          target_x_bytes_w[20:5];
                    state_r <= reverse_w && (height_i > 16'd1) ?
                               ST_SEEK : ST_TILE;
                end
            end else begin
                case (state_r)
                    ST_SEEK: begin
                        if (row_r == height_r - 16'd1)
                            state_r <= ST_TILE;
                        else begin
                            row_r <= row_r + 16'd1;
                            source_row_addr_r <= source_row_addr_r +
                                                 source_stride_r;
                            target_row_addr_r <= target_row_addr_r +
                                                 target_stride_r;
                        end
                    end
                    ST_TILE: begin
                        tile_first_beat_r <= tile_start_beat_w;
                        tile_len_r <= next_tile_len_w;
                        tile_processed_r <= 4'd0;
                        state_r <= ST_SRC_AR0;
                    end
                    ST_SRC_AR0: begin
                        if (m_arready_i)
                            state_r <= ST_SRC_R0;
                    end
                    ST_SRC_R0: begin
                        if (m_rvalid_i) begin
                            if (read_fault_w) begin
                                error_r <= 1'b1;
                                done_r <= 1'b1;
                                state_r <= ST_IDLE;
                            end else begin
                                source_word0_r <= m_rdata_i;
                                state_r <= need_source1_w ?
                                           ST_SRC_AR1 : ST_PREP;
                            end
                        end
                    end
                    ST_SRC_AR1: begin
                        if (m_arready_i)
                            state_r <= ST_SRC_R1;
                    end
                    ST_SRC_R1: begin
                        if (m_rvalid_i) begin
                            if (read_fault_w) begin
                                error_r <= 1'b1;
                                done_r <= 1'b1;
                                state_r <= ST_IDLE;
                            end else begin
                                source_word1_r <= m_rdata_i;
                                state_r <= ST_PREP;
                            end
                        end
                    end
                    ST_PREP: begin
                        write_cache_r[cache_index_w[2:0]] <=
                            prepared_word_w;
                        strobe_cache_r[cache_index_w[2:0]] <=
                            prepared_strobe_w;
                        if (tile_processed_r == tile_len_r - 4'd1) begin
                            state_r <= ST_AW;
                        end else begin
                            tile_processed_r <= tile_processed_r + 4'd1;
                            beat_r <= reverse_r ? beat_r - 16'd1 :
                                                  beat_r + 16'd1;
                            state_r <= ST_SRC_AR0;
                        end
                    end
                    ST_AW: begin
                        if (m_awready_i) begin
                            write_index_r <= 4'd0;
                            state_r <= ST_W;
                        end
                    end
                    ST_W: begin
                        if (m_wready_i) begin
                            if (m_wlast_o)
                                state_r <= ST_B;
                            else
                                write_index_r <= write_index_r + 4'd1;
                        end
                    end
                    ST_B: begin
                        if (m_bvalid_i) begin
                            if (write_fault_w) begin
                                error_r <= 1'b1;
                                done_r <= 1'b1;
                                state_r <= ST_IDLE;
                            end else begin
                                beat_count_r <= beat_count_r +
                                                {28'd0,tile_len_r};
                                if (beat_last_w) begin
                                    if (row_last_w) begin
                                        done_r <= 1'b1;
                                        state_r <= ST_IDLE;
                                    end else if (reverse_r) begin
                                        row_r <= row_r - 16'd1;
                                        source_row_addr_r <=
                                            source_row_addr_r -
                                            source_stride_r;
                                        target_row_addr_r <=
                                            target_row_addr_r -
                                            target_stride_r;
                                        beat_r <= last_beat_r;
                                        state_r <= ST_TILE;
                                    end else begin
                                        row_r <= row_r + 16'd1;
                                        source_row_addr_r <=
                                            source_row_addr_r +
                                            source_stride_r;
                                        target_row_addr_r <=
                                            target_row_addr_r +
                                            target_stride_r;
                                        beat_r <= first_beat_r;
                                        state_r <= ST_TILE;
                                    end
                                end else begin
                                    beat_r <= reverse_r ? beat_r - 16'd1 :
                                                          beat_r + 16'd1;
                                    state_r <= ST_TILE;
                                end
                            end
                        end
                    end
                    default: state_r <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
