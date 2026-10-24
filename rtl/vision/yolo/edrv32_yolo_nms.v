// ============================================================================
// File        : edrv32_yolo_nms.v
// Description : Class-aware greedy NMS with one synchronous candidate reader.
// Notes       : The selected winner is held in registers during suppression.
// ============================================================================
`include "edrv32_build_mode.vh"

module edrv32_yolo_nms (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         start_i,
    output wire         start_ready_o,
    input  wire         in_valid_i,
    output wire         in_ready_o,
    input  wire [6:0]   in_class_i,
    input  wire [15:0]  in_score_i,
    input  wire [31:0]  in_x1_i,
    input  wire [31:0]  in_y1_i,
    input  wire [31:0]  in_x2_i,
    input  wire [31:0]  in_y2_i,
    input  wire [1:0]   in_scale_i,
    input  wire [12:0]  in_anchor_i,
    input  wire         finish_i,
    output wire         out_valid_o,
    input  wire         out_ready_i,
    output wire [6:0]   out_class_o,
    output wire [15:0]  out_score_o,
    output wire [31:0]  out_x1_o,
    output wire [31:0]  out_y1_o,
    output wire [31:0]  out_x2_o,
    output wire [31:0]  out_y2_o,
    output wire [1:0]   out_scale_o,
    output wire [12:0]  out_anchor_o,
    output wire [6:0]   out_index_o,
    output wire [9:0]   candidate_count_o,
    output wire [6:0]   output_count_o,
    output wire         busy_o,
    output wire         done_o,
    output wire         error_o
);
    localparam [3:0] S_IDLE      = 4'd0;
    localparam [3:0] S_FILL      = 4'd1;
    localparam [3:0] S_SEARCH_RD = 4'd2;
    localparam [3:0] S_SEARCH    = 4'd3;
    localparam [3:0] S_OUTPUT    = 4'd4;
    localparam [3:0] S_SUPP_RD   = 4'd5;
    localparam [3:0] S_SUPP_XY   = 4'd6;
    localparam [3:0] S_SUPP_AREA = 4'd7;
    localparam [3:0] S_SUPP_DEC  = 4'd8;
    localparam [3:0] S_DONE      = 4'd9;
    localparam [3:0] S_SUPP_RATIO = 4'd10;
    localparam [3:0] S_SUPP_LIMIT = 4'd11;
    reg [3:0] state_r;
    reg [9:0] candidate_count_r, scan_index_r, winner_index_r;
    reg [6:0] output_count_r;
    reg [15:0] best_score_r;
    reg best_found_r, error_r, done_r;
    reg valid_r [0:511];
    reg [109:0] winner_r;
    reg compare_valid_r;
    reg [17:0] inter_width_r, inter_height_r;
    reg [17:0] winner_width_r, winner_height_r;
    reg [17:0] other_width_r, other_height_r;
    reg [35:0] inter_area_r, winner_area_r, other_area_r;
    reg [36:0] sum_area_r;
    reg [40:0] inter17_r, sum7_r;

    wire [109:0] input_record_w = {
        in_anchor_i, in_scale_i, in_y2_i[17:0], in_x2_i[17:0],
        in_y1_i[17:0], in_x1_i[17:0], in_score_i, in_class_i
    };
    wire record_wr_w = state_r == S_FILL && in_valid_i &&
                       candidate_count_r < 10'd512;
    wire record_rd_w = state_r == S_SEARCH_RD || state_r == S_SUPP_RD;
    wire [109:0] scan_record_w;
    wire [6:0] scan_class_w = scan_record_w[6:0];
    wire [15:0] scan_score_w = scan_record_w[22:7];
    wire [17:0] scan_x1_w = scan_record_w[40:23];
    wire [17:0] scan_y1_w = scan_record_w[58:41];
    wire [17:0] scan_x2_w = scan_record_w[76:59];
    wire [17:0] scan_y2_w = scan_record_w[94:77];
    wire [17:0] winner_x1_w = winner_r[40:23];
    wire [17:0] winner_y1_w = winner_r[58:41];
    wire [17:0] winner_x2_w = winner_r[76:59];
    wire [17:0] winner_y2_w = winner_r[94:77];
    wire [17:0] inter_left_w = winner_x1_w > scan_x1_w ?
                               winner_x1_w : scan_x1_w;
    wire [17:0] inter_top_w = winner_y1_w > scan_y1_w ?
                              winner_y1_w : scan_y1_w;
    wire [17:0] inter_right_w = winner_x2_w < scan_x2_w ?
                                winner_x2_w : scan_x2_w;
    wire [17:0] inter_bottom_w = winner_y2_w < scan_y2_w ?
                                 winner_y2_w : scan_y2_w;
    // 10*intersection >= 7*union is equivalent to
    // 17*intersection >= 7*(winner_area + other_area).
    wire [36:0] sum_area_w =
        {1'b0, winner_area_r} + {1'b0, other_area_r};
    wire [40:0] inter17_w =
        ({5'd0, inter_area_r} << 4) + {5'd0, inter_area_r};
    wire [40:0] sum7_w =
        ({4'd0, sum_area_r} << 2) +
        ({4'd0, sum_area_r} << 1) + {4'd0, sum_area_r};
    wire better_w = valid_r[scan_index_r[8:0]] &&
        (!best_found_r || scan_score_w > best_score_r);

`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`elsif EDRV32_FPGA_MEMORY_MODE
    wire [255:0] record_read_w;
    yolo_weight_ram u_candidate_ram (
        .wr_data({146'd0, input_record_w}),
        .wr_addr(candidate_count_r[8:0]), .wr_en(record_wr_w),
        .wr_clk(clk_i), .wr_rst(~rst_n_i),
        .wr_byte_en(32'hffff_ffff),
        .rd_data(record_read_w), .rd_addr(scan_index_r[8:0]),
        .rd_clk(clk_i), .rd_rst(~rst_n_i), .rd_clk_en(record_rd_w)
    );
    assign scan_record_w = record_read_w[109:0];
`else
    reg [109:0] candidate_mem_r [0:511];
    reg [109:0] candidate_read_r;
    always @(posedge clk_i) begin
        if (record_wr_w)
            candidate_mem_r[candidate_count_r[8:0]] <= input_record_w;
        if (record_rd_w)
            candidate_read_r <= candidate_mem_r[scan_index_r[8:0]];
    end
    assign scan_record_w = candidate_read_r;
`endif

    assign start_ready_o = state_r == S_IDLE;
    assign in_ready_o = state_r == S_FILL;
    assign out_valid_o = state_r == S_OUTPUT;
    assign out_class_o = winner_r[6:0];
    assign out_score_o = winner_r[22:7];
    assign out_x1_o = {14'd0, winner_x1_w};
    assign out_y1_o = {14'd0, winner_y1_w};
    assign out_x2_o = {14'd0, winner_x2_w};
    assign out_y2_o = {14'd0, winner_y2_w};
    assign out_scale_o = winner_r[96:95];
    assign out_anchor_o = winner_r[109:97];
    assign out_index_o = output_count_r;
    assign candidate_count_o = candidate_count_r;
    assign output_count_o = output_count_r;
    assign busy_o = state_r != S_IDLE;
    assign done_o = done_r;
    assign error_o = error_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            candidate_count_r <= 10'd0;
            output_count_r <= 7'd0;
            scan_index_r <= 10'd0;
            winner_index_r <= 10'd0;
            best_score_r <= 16'd0;
            best_found_r <= 1'b0;
            compare_valid_r <= 1'b0;
            inter_width_r <= 18'd0;
            inter_height_r <= 18'd0;
            winner_width_r <= 18'd0;
            winner_height_r <= 18'd0;
            other_width_r <= 18'd0;
            other_height_r <= 18'd0;
            inter_area_r <= 36'd0;
            winner_area_r <= 36'd0;
            other_area_r <= 36'd0;
            sum_area_r <= 37'd0;
            inter17_r <= 41'd0;
            sum7_r <= 41'd0;
            error_r <= 1'b0;
            done_r <= 1'b0;
        end else begin
            done_r <= 1'b0;
            case (state_r)
                S_IDLE: if (start_i) begin
                    candidate_count_r <= 10'd0;
                    output_count_r <= 7'd0;
                    scan_index_r <= 10'd0;
                    best_score_r <= 16'd0;
                    best_found_r <= 1'b0;
                    error_r <= 1'b0;
                    state_r <= S_FILL;
                end
                S_FILL: begin
                    if (record_wr_w) begin
                        valid_r[candidate_count_r[8:0]] <= 1'b1;
                        candidate_count_r <= candidate_count_r + 10'd1;
                    end else if (in_valid_i)
                        error_r <= 1'b1;
                    if (finish_i) begin
                        scan_index_r <= 10'd0;
                        best_found_r <= 1'b0;
                        state_r <= S_SEARCH_RD;
                    end
                end
                S_SEARCH_RD: begin
                    if (candidate_count_r == 10'd0)
                        state_r <= S_DONE;
                    else
                        state_r <= S_SEARCH;
                end
                S_SEARCH: begin
                    if (better_w) begin
                        winner_r <= scan_record_w;
                        winner_index_r <= scan_index_r;
                        best_score_r <= scan_score_w;
                        best_found_r <= 1'b1;
                    end
                    if (scan_index_r == candidate_count_r - 10'd1) begin
                        if (better_w || best_found_r) begin
                            if (output_count_r == 7'd100) begin
                                error_r <= 1'b1;
                                state_r <= S_DONE;
                            end else
                                state_r <= S_OUTPUT;
                        end else
                            state_r <= S_DONE;
                    end else begin
                        scan_index_r <= scan_index_r + 10'd1;
                        state_r <= S_SEARCH_RD;
                    end
                end
                S_OUTPUT: if (out_ready_i) begin
                    valid_r[winner_index_r[8:0]] <= 1'b0;
                    output_count_r <= output_count_r + 7'd1;
                    scan_index_r <= 10'd0;
                    state_r <= S_SUPP_RD;
                end
                S_SUPP_RD: state_r <= S_SUPP_XY;
                S_SUPP_XY: begin
                    compare_valid_r <= valid_r[scan_index_r[8:0]] &&
                        scan_class_w == winner_r[6:0];
                    inter_width_r <= inter_right_w > inter_left_w ?
                        inter_right_w - inter_left_w : 18'd0;
                    inter_height_r <= inter_bottom_w > inter_top_w ?
                        inter_bottom_w - inter_top_w : 18'd0;
                    winner_width_r <= winner_x2_w - winner_x1_w;
                    winner_height_r <= winner_y2_w - winner_y1_w;
                    other_width_r <= scan_x2_w - scan_x1_w;
                    other_height_r <= scan_y2_w - scan_y1_w;
                    state_r <= S_SUPP_AREA;
                end
                S_SUPP_AREA: begin
                    inter_area_r <= inter_width_r * inter_height_r;
                    winner_area_r <= winner_width_r * winner_height_r;
                    other_area_r <= other_width_r * other_height_r;
                    state_r <= S_SUPP_RATIO;
                end
                S_SUPP_RATIO: begin
                    sum_area_r <= sum_area_w;
                    inter17_r <= inter17_w;
                    state_r <= S_SUPP_LIMIT;
                end
                S_SUPP_LIMIT: begin
                    sum7_r <= sum7_w;
                    state_r <= S_SUPP_DEC;
                end
                S_SUPP_DEC: begin
                    if (compare_valid_r && inter_area_r != 36'd0 &&
                        inter17_r >= sum7_r)
                        valid_r[scan_index_r[8:0]] <= 1'b0;
                    if (scan_index_r == candidate_count_r - 10'd1) begin
                        scan_index_r <= 10'd0;
                        best_score_r <= 16'd0;
                        best_found_r <= 1'b0;
                        state_r <= S_SEARCH_RD;
                    end else begin
                        scan_index_r <= scan_index_r + 10'd1;
                        state_r <= S_SUPP_RD;
                    end
                end
                S_DONE: begin
                    done_r <= 1'b1;
                    state_r <= S_IDLE;
                end
                default: state_r <= S_IDLE;
            endcase
        end
    end
endmodule
