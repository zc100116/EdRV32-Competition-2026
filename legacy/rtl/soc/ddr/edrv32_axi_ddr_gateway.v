// ============================================================================
// File        : edrv32_axi_ddr_gateway.v
// Description : 64-bit System AXI slave to 256-bit DDR AXI master gateway.
// Notes       : The two 1-GiB CPU views at 0x8000_0000 and 0xc000_0000 map to
//               the same zero-based DDR physical address.  One read and one
//               write parent may be active independently.  The DDR-facing
//               profile is limited to at most 16 256-bit beats.  Writes are
//               packed before issue so the wide W channel has no bubbles.
// ============================================================================

module edrv32_axi_ddr_gateway #(
    parameter integer S_ID_W = 5,
    parameter integer M_ID_W = 4,
    parameter integer LEN_W = 8,
    parameter integer MAX_WIDE_BEATS = 16,
    parameter integer WIDE_INDEX_W = 4
) (
    input  wire                     clk_i,
    input  wire                     rst_n_i,

    input  wire [S_ID_W-1:0]        s_awid_i,
    input  wire [31:0]              s_awaddr_i,
    input  wire [LEN_W-1:0]         s_awlen_i,
    input  wire [2:0]               s_awsize_i,
    input  wire [1:0]               s_awburst_i,
    input  wire                     s_awvalid_i,
    output wire                     s_awready_o,
    input  wire [63:0]              s_wdata_i,
    input  wire [7:0]               s_wstrb_i,
    input  wire                     s_wlast_i,
    input  wire                     s_wvalid_i,
    output wire                     s_wready_o,
    output wire [S_ID_W-1:0]        s_bid_o,
    output wire [1:0]               s_bresp_o,
    output wire                     s_bvalid_o,
    input  wire                     s_bready_i,

    input  wire [S_ID_W-1:0]        s_arid_i,
    input  wire [31:0]              s_araddr_i,
    input  wire [LEN_W-1:0]         s_arlen_i,
    input  wire [2:0]               s_arsize_i,
    input  wire [1:0]               s_arburst_i,
    input  wire                     s_arvalid_i,
    output wire                     s_arready_o,
    output wire [S_ID_W-1:0]        s_rid_o,
    output wire [63:0]              s_rdata_o,
    output wire [1:0]               s_rresp_o,
    output wire                     s_rlast_o,
    output wire                     s_rvalid_o,
    input  wire                     s_rready_i,

    output wire [M_ID_W-1:0]        m_awid_o,
    output wire [31:0]              m_awaddr_o,
    output wire [LEN_W-1:0]         m_awlen_o,
    output wire [2:0]               m_awsize_o,
    output wire [1:0]               m_awburst_o,
    output wire [3:0]               m_awqos_o,
    output wire                     m_awvalid_o,
    input  wire                     m_awready_i,
    output wire [255:0]             m_wdata_o,
    output wire [31:0]              m_wstrb_o,
    output wire                     m_wlast_o,
    output wire                     m_wvalid_o,
    input  wire                     m_wready_i,
    input  wire [M_ID_W-1:0]        m_bid_i,
    input  wire [1:0]               m_bresp_i,
    input  wire                     m_bvalid_i,
    output wire                     m_bready_o,

    output wire [M_ID_W-1:0]        m_arid_o,
    output wire [31:0]              m_araddr_o,
    output wire [LEN_W-1:0]         m_arlen_o,
    output wire [2:0]               m_arsize_o,
    output wire [1:0]               m_arburst_o,
    output wire [3:0]               m_arqos_o,
    output wire                     m_arvalid_o,
    input  wire                     m_arready_i,
    input  wire [M_ID_W-1:0]        m_rid_i,
    input  wire [255:0]             m_rdata_i,
    input  wire [1:0]               m_rresp_i,
    input  wire                     m_rlast_i,
    input  wire                     m_rvalid_i,
    output wire                     m_rready_o,

    output wire                     protocol_error_o
);

    localparam [1:0] RESP_OKAY = 2'b00;
    localparam [1:0] RESP_DECERR = 2'b11;

    localparam [2:0] WR_IDLE = 3'd0;
    localparam [2:0] WR_COLLECT = 3'd1;
    localparam [2:0] WR_ISSUE = 3'd2;
    localparam [2:0] WR_SEND = 3'd3;
    localparam [2:0] WR_WAIT = 3'd4;
    localparam [2:0] WR_RESP = 3'd5;

    localparam [1:0] RD_IDLE = 2'd0;
    localparam [1:0] RD_ISSUE = 2'd1;
    localparam [1:0] RD_DATA = 2'd2;
    localparam [1:0] RD_ERROR = 2'd3;

    function [31:0] physical_addr;
        input [31:0] cpu_addr_i;
        begin
            physical_addr = {2'b00, cpu_addr_i[29:0]};
        end
    endfunction

    function [63:0] narrow_read_data;
        input [255:0] wide_data_i;
        input [4:0] byte_offset_i;
        input [2:0] bus_lane_i;
        input [2:0] size_i;
        integer byte_i;
        integer transfer_bytes;
        integer wide_byte;
        integer lane_base;
        integer offset_base;
        begin
            narrow_read_data = 64'b0;
            transfer_bytes = 1 << size_i;
            lane_base = {29'b0, bus_lane_i};
            offset_base = {27'b0, byte_offset_i};
            for (byte_i = 0; byte_i < 8; byte_i = byte_i + 1) begin
                if ((byte_i >= lane_base) &&
                    (byte_i < lane_base + transfer_bytes)) begin
                    wide_byte = offset_base + byte_i - lane_base;
                    narrow_read_data[byte_i*8 +: 8] =
                        wide_data_i[wide_byte*8 +: 8];
                end
            end
        end
    endfunction

    wire [32:0] s_aw_beats_w = {25'b0, s_awlen_i} + 33'd1;
    wire [32:0] s_aw_span_w = s_aw_beats_w << s_awsize_i;
    wire [32:0] s_aw_last_w = {1'b0, s_awaddr_i} + s_aw_span_w - 33'd1;
    wire s_aw_legal_w = (s_awaddr_i[31] == 1'b1) &&
        (s_awburst_i == 2'b01) && (s_awsize_i <= 3'd3) &&
        (s_aw_last_w[32] == 1'b0) &&
        (s_awaddr_i[11:0] + s_aw_span_w[12:0] <= 13'd4096);
    wire [31:0] s_aw_phys_w = physical_addr(s_awaddr_i);
    wire [31:0] s_aw_first_wide_w = {s_aw_phys_w[31:5], 5'b0};
    wire [31:0] s_aw_last_phys_w = physical_addr(s_aw_last_w[31:0]);
    wire [31:0] s_aw_wide_count_full_w =
        ({5'b0, s_aw_last_phys_w[31:5]} -
         {5'b0, s_aw_first_wide_w[31:5]}) + 32'd1;
    wire [WIDE_INDEX_W:0] s_aw_wide_count_w =
        s_aw_wide_count_full_w[WIDE_INDEX_W:0];

    wire [32:0] s_ar_beats_w = {25'b0, s_arlen_i} + 33'd1;
    wire [32:0] s_ar_span_w = s_ar_beats_w << s_arsize_i;
    wire [32:0] s_ar_last_w = {1'b0, s_araddr_i} + s_ar_span_w - 33'd1;
    wire s_ar_legal_w = (s_araddr_i[31] == 1'b1) &&
        (s_arburst_i == 2'b01) && (s_arsize_i <= 3'd3) &&
        (s_ar_last_w[32] == 1'b0) &&
        (s_araddr_i[11:0] + s_ar_span_w[12:0] <= 13'd4096);
    wire [31:0] s_ar_phys_w = physical_addr(s_araddr_i);
    wire [31:0] s_ar_first_wide_w = {s_ar_phys_w[31:5], 5'b0};
    wire [31:0] s_ar_last_phys_w = physical_addr(s_ar_last_w[31:0]);
    wire [31:0] s_ar_wide_count_full_w =
        ({5'b0, s_ar_last_phys_w[31:5]} -
         {5'b0, s_ar_first_wide_w[31:5]}) + 32'd1;
    wire [WIDE_INDEX_W:0] s_ar_wide_count_w =
        s_ar_wide_count_full_w[WIDE_INDEX_W:0];

    // ---------------------------------------------------------------------
    // Write packing and response aggregation.
    // ---------------------------------------------------------------------
    reg [2:0] wr_state_r;
    reg [S_ID_W-1:0] wr_id_r;
    reg [2:0] wr_size_r;
    reg [31:0] wr_src_addr_r;
    reg [LEN_W:0] wr_src_left_r;
    reg [31:0] wr_wide_addr_r;
    reg [WIDE_INDEX_W:0] wr_wide_count_r;
    reg [WIDE_INDEX_W-1:0] wr_send_index_r;
    reg wr_legal_r;
    reg [1:0] wr_resp_r;
    reg [255:0] wr_data_r [0:MAX_WIDE_BEATS-1];
    reg [31:0] wr_strb_r [0:MAX_WIDE_BEATS-1];
    reg [MAX_WIDE_BEATS-1:0] wr_line_seen_r;
    reg wr_protocol_error_r;

    wire s_aw_fire_w = s_awvalid_i && s_awready_o;
    wire s_w_fire_w = s_wvalid_i && s_wready_o;
    wire m_aw_fire_w = m_awvalid_o && m_awready_i;
    wire m_w_fire_w = m_wvalid_o && m_wready_i;
    wire m_b_fire_w = m_bvalid_i && m_bready_o;
    wire s_b_fire_w = s_bvalid_o && s_bready_i;

    assign s_awready_o = (wr_state_r == WR_IDLE);
    assign s_wready_o = (wr_state_r == WR_COLLECT);
    assign s_bid_o = wr_id_r;
    assign s_bresp_o = wr_resp_r;
    assign s_bvalid_o = (wr_state_r == WR_RESP);

    assign m_awid_o = {M_ID_W{1'b0}};
    assign m_awaddr_o = wr_wide_addr_r;
    assign m_awlen_o =
        {{(LEN_W-WIDE_INDEX_W-1){1'b0}}, wr_wide_count_r} - 1'b1;
    assign m_awsize_o = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awqos_o = 4'b0;
    assign m_awvalid_o = (wr_state_r == WR_ISSUE);
    assign m_wdata_o = wr_data_r[wr_send_index_r];
    assign m_wstrb_o = wr_strb_r[wr_send_index_r];
    assign m_wlast_o = ({1'b0, wr_send_index_r} +
                        {{WIDE_INDEX_W{1'b0}}, 1'b1}) == wr_wide_count_r;
    assign m_wvalid_o = (wr_state_r == WR_SEND);
    assign m_bready_o = (wr_state_r == WR_WAIT);

    integer wr_byte_i;
    integer wr_wide_byte_w;
    wire [31:0] wr_bus_base_w = {wr_src_addr_r[31:3], 3'b000};
    wire [31:0] wr_line_index_full_w =
        (wr_bus_base_w - wr_wide_addr_r) >> 5;
    wire [WIDE_INDEX_W-1:0] wr_line_index_w =
        wr_line_index_full_w[WIDE_INDEX_W-1:0];
    reg [255:0] wr_merge_data_w;
    reg [31:0] wr_merge_strb_w;
    always @(*) begin
        if (wr_line_seen_r[wr_line_index_w]) begin
            wr_merge_data_w = wr_data_r[wr_line_index_w];
            wr_merge_strb_w = wr_strb_r[wr_line_index_w];
        end else begin
            wr_merge_data_w = 256'b0;
            wr_merge_strb_w = 32'b0;
        end
        for (wr_byte_i = 0; wr_byte_i < 8; wr_byte_i = wr_byte_i + 1) begin
            wr_wide_byte_w = {27'b0, wr_bus_base_w[4:0]};
            wr_wide_byte_w = wr_wide_byte_w + wr_byte_i;
            if (s_wstrb_i[wr_byte_i]) begin
                wr_merge_data_w[wr_wide_byte_w*8 +: 8] =
                    s_wdata_i[wr_byte_i*8 +: 8];
                wr_merge_strb_w[wr_wide_byte_w] = 1'b1;
            end
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            wr_state_r <= WR_IDLE;
            wr_id_r <= {S_ID_W{1'b0}};
            wr_size_r <= 3'b0;
            wr_src_addr_r <= 32'b0;
            wr_src_left_r <= {(LEN_W+1){1'b0}};
            wr_wide_addr_r <= 32'b0;
            wr_wide_count_r <= {(WIDE_INDEX_W+1){1'b0}};
            wr_send_index_r <= {WIDE_INDEX_W{1'b0}};
            wr_legal_r <= 1'b0;
            wr_resp_r <= RESP_OKAY;
            wr_protocol_error_r <= 1'b0;
            wr_line_seen_r <= {MAX_WIDE_BEATS{1'b0}};
        end else begin
            if (s_aw_fire_w) begin
                wr_state_r <= WR_COLLECT;
                wr_id_r <= s_awid_i;
                wr_size_r <= s_awsize_i;
                wr_src_addr_r <= s_aw_phys_w;
                wr_src_left_r <= {1'b0, s_awlen_i} + 1'b1;
                wr_wide_addr_r <= s_aw_first_wide_w;
                wr_wide_count_r <= s_aw_wide_count_w;
                wr_send_index_r <= {WIDE_INDEX_W{1'b0}};
                wr_legal_r <= s_aw_legal_w &&
                    (s_aw_wide_count_full_w <= MAX_WIDE_BEATS);
                wr_resp_r <= RESP_OKAY;
                wr_line_seen_r <= {MAX_WIDE_BEATS{1'b0}};
            end

            if (s_w_fire_w) begin
                if (s_wlast_i != (wr_src_left_r == 1))
                    wr_protocol_error_r <= 1'b1;

                if (wr_legal_r) begin
                    wr_data_r[wr_line_index_w] <= wr_merge_data_w;
                    wr_strb_r[wr_line_index_w] <= wr_merge_strb_w;
                    wr_line_seen_r[wr_line_index_w] <= 1'b1;
                end

                wr_src_addr_r <= wr_src_addr_r + (32'd1 << wr_size_r);
                wr_src_left_r <= wr_src_left_r - 1'b1;
                if (wr_src_left_r == 1) begin
                    if (wr_legal_r)
                        wr_state_r <= WR_ISSUE;
                    else begin
                        wr_resp_r <= RESP_DECERR;
                        wr_state_r <= WR_RESP;
                    end
                end
            end

            if (m_aw_fire_w)
                wr_state_r <= WR_SEND;

            if (m_w_fire_w) begin
                if (m_wlast_o) begin
                    wr_send_index_r <= {WIDE_INDEX_W{1'b0}};
                    wr_state_r <= WR_WAIT;
                end else begin
                    wr_send_index_r <= wr_send_index_r + 1'b1;
                end
            end

            if (m_b_fire_w) begin
                if (m_bid_i != {M_ID_W{1'b0}})
                    wr_protocol_error_r <= 1'b1;
                wr_resp_r <= m_bresp_i;
                wr_state_r <= WR_RESP;
            end

            if (s_b_fire_w)
                wr_state_r <= WR_IDLE;
        end
    end

    // ---------------------------------------------------------------------
    // Read widening, response buffering and 256-to-64 beat extraction.
    // ---------------------------------------------------------------------
    reg [1:0] rd_state_r;
    reg [S_ID_W-1:0] rd_id_r;
    reg [2:0] rd_size_r;
    reg [31:0] rd_src_addr_r;
    reg [LEN_W:0] rd_src_left_r;
    reg [31:0] rd_wide_addr_r;
    reg [WIDE_INDEX_W:0] rd_wide_left_r;
    reg rd_line_valid_r;
    reg [255:0] rd_line_data_r;
    reg [1:0] rd_line_resp_r;
    reg rd_protocol_error_r;

    wire s_ar_fire_w = s_arvalid_i && s_arready_o;
    wire s_r_fire_w = s_rvalid_o && s_rready_i;
    wire m_ar_fire_w = m_arvalid_o && m_arready_i;
    wire rd_source_last_w = (rd_src_left_r == 1);
    wire [31:0] rd_next_src_addr_w =
        rd_src_addr_r + (32'd1 << rd_size_r);
    wire rd_source_leaves_line_w =
        rd_next_src_addr_w[31:5] != rd_src_addr_r[31:5];
    wire rd_release_line_w = (rd_state_r == RD_DATA) && s_r_fire_w &&
        (rd_source_last_w || rd_source_leaves_line_w);
    wire m_r_fire_w = m_rvalid_i && m_rready_o;

    assign s_arready_o = (rd_state_r == RD_IDLE);
    assign s_rid_o = rd_id_r;
    assign s_rdata_o = (rd_state_r == RD_ERROR) ? 64'b0 :
        narrow_read_data(rd_line_data_r, rd_src_addr_r[4:0],
                         rd_src_addr_r[2:0], rd_size_r);
    assign s_rresp_o = (rd_state_r == RD_ERROR) ? RESP_DECERR :
        rd_line_resp_r;
    assign s_rlast_o = rd_source_last_w;
    assign s_rvalid_o = (rd_state_r == RD_ERROR) ||
        ((rd_state_r == RD_DATA) && rd_line_valid_r);

    assign m_arid_o = {M_ID_W{1'b0}};
    assign m_araddr_o = rd_wide_addr_r;
    assign m_arlen_o =
        {{(LEN_W-WIDE_INDEX_W-1){1'b0}}, rd_wide_left_r} - 1'b1;
    assign m_arsize_o = 3'd5;
    assign m_arburst_o = 2'b01;
    assign m_arqos_o = 4'b0;
    assign m_arvalid_o = (rd_state_r == RD_ISSUE);
    assign m_rready_o = (rd_state_r == RD_DATA) &&
        (!rd_line_valid_r || rd_release_line_w);

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rd_state_r <= RD_IDLE;
            rd_id_r <= {S_ID_W{1'b0}};
            rd_size_r <= 3'b0;
            rd_src_addr_r <= 32'b0;
            rd_src_left_r <= {(LEN_W+1){1'b0}};
            rd_wide_addr_r <= 32'b0;
            rd_wide_left_r <= {(WIDE_INDEX_W+1){1'b0}};
            rd_line_valid_r <= 1'b0;
            rd_line_data_r <= 256'b0;
            rd_line_resp_r <= RESP_OKAY;
            rd_protocol_error_r <= 1'b0;
        end else begin
            if (s_ar_fire_w) begin
                rd_id_r <= s_arid_i;
                rd_size_r <= s_arsize_i;
                rd_src_addr_r <= s_ar_phys_w;
                rd_src_left_r <= {1'b0, s_arlen_i} + 1'b1;
                rd_wide_addr_r <= s_ar_first_wide_w;
                rd_wide_left_r <= s_ar_wide_count_w;
                rd_line_valid_r <= 1'b0;
                if (s_ar_legal_w &&
                    (s_ar_wide_count_full_w <= MAX_WIDE_BEATS))
                    rd_state_r <= RD_ISSUE;
                else
                    rd_state_r <= RD_ERROR;
            end

            if (m_ar_fire_w)
                rd_state_r <= RD_DATA;

            if (rd_release_line_w)
                rd_line_valid_r <= 1'b0;

            if (m_r_fire_w) begin
                rd_line_valid_r <= 1'b1;
                rd_line_data_r <= m_rdata_i;
                rd_line_resp_r <= m_rresp_i;
                rd_wide_addr_r <= rd_wide_addr_r + 32;
                if ((m_rid_i != {M_ID_W{1'b0}}) ||
                    (m_rlast_i != (rd_wide_left_r == 1)))
                    rd_protocol_error_r <= 1'b1;
                rd_wide_left_r <= rd_wide_left_r - 1'b1;
            end

            if (s_r_fire_w) begin
                rd_src_addr_r <= rd_next_src_addr_w;
                rd_src_left_r <= rd_src_left_r - 1'b1;
                if (rd_source_last_w) begin
                    rd_line_valid_r <= 1'b0;
                    rd_state_r <= RD_IDLE;
                end
            end
        end
    end

    assign protocol_error_o = wr_protocol_error_r | rd_protocol_error_r;

endmodule
