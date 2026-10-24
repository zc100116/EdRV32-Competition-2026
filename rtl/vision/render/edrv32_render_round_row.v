// ============================================================================
// File        : edrv32_render_round_row.v
// Description : Per-row rounded-rectangle edge generator with integer sqrt.
// Notes       : Q4 edge positions feed a two-pixel antialias coverage stage.
// ============================================================================

module edrv32_render_round_row (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         row_valid_i,
    output wire         row_ready_o,
    input  wire [15:0]  width_i,
    input  wire [15:0]  height_i,
    input  wire [15:0]  row_y_i,
    input  wire [9:0]   radius_i,
    input  wire [9:0]   border_i,

    output wire         edge_valid_o,
    input  wire         edge_ready_i,
    output wire [15:0]  outer_edge_q4_o,
    output wire [15:0]  inner_edge_q4_o,
    output wire         inner_active_o
);

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_PREP  = 2'd1;
    localparam [1:0] ST_OUTER = 2'd2;
    localparam [1:0] ST_INNER = 2'd3;

    reg [1:0]  state_r;
    reg        edge_valid_r;
    reg [15:0] outer_edge_r;
    reg [15:0] inner_edge_r;
    reg        inner_active_r;
    reg        border_zero_r;
    reg        outer_needs_root_r;
    reg        inner_needs_root_r;
    reg [15:0] outer_radius_q4_r;
    reg [15:0] outer_dy_q4_r;
    reg [15:0] inner_radius_q4_r;
    reg [15:0] inner_dy_q4_r;
    reg [15:0] border_q4_r;
    reg [15:0] root_radius_q4_r;
    reg [31:0] radicand_r;
    reg [31:0] remainder_r;
    reg [15:0] root_r;
    reg [4:0]  step_r;

    wire [15:0] half_min_w =
        (width_i < height_i ? width_i : height_i) >> 1;
    wire [15:0] radius_w = {6'd0, radius_i} < half_min_w ?
                           {6'd0, radius_i} : half_min_w;
    wire [15:0] outer_ydist_w = row_y_i < (height_i - 16'd1 - row_y_i) ?
                                row_y_i : (height_i - 16'd1 - row_y_i);
    wire outer_needs_root_w = (radius_w != 16'd0) &&
                              (outer_ydist_w < radius_w);
    wire [15:0] outer_radius_q4_w = {radius_w[11:0], 4'b0};
    wire [11:0] outer_delta_w = radius_w[11:0] -
                                outer_ydist_w[11:0] - 12'd1;
    wire [15:0] outer_dy_q4_w =
        {outer_delta_w, 4'b0} + 16'd8;
    wire inner_active_w =
        (width_i > {5'd0, border_i, 1'b0}) &&
        (height_i > {5'd0, border_i, 1'b0}) &&
        (row_y_i >= {6'd0, border_i}) &&
        (row_y_i < height_i - {6'd0, border_i});
    wire [15:0] inner_height_w = height_i - {5'd0, border_i, 1'b0};
    wire [15:0] inner_y_w = row_y_i - {6'd0, border_i};
    wire [15:0] inner_ydist_w = inner_y_w <
        (inner_height_w - 16'd1 - inner_y_w) ?
        inner_y_w : (inner_height_w - 16'd1 - inner_y_w);
    wire [15:0] inner_radius_w = radius_w > {6'd0, border_i} ?
        radius_w - {6'd0, border_i} : 16'd0;
    wire inner_needs_root_w = inner_active_w &&
                              (inner_radius_w != 16'd0) &&
                              (inner_ydist_w < inner_radius_w);
    wire [15:0] inner_radius_q4_w = {inner_radius_w[11:0], 4'b0};
    wire [11:0] inner_delta_w = inner_radius_w[11:0] -
                                inner_ydist_w[11:0] - 12'd1;
    wire [15:0] inner_dy_q4_w =
        {inner_delta_w, 4'b0} + 16'd8;
    wire [31:0] outer_rad_w =
        outer_radius_q4_r * outer_radius_q4_r -
        outer_dy_q4_r * outer_dy_q4_r;
    wire [31:0] inner_rad_w =
        inner_radius_q4_r * inner_radius_q4_r -
        inner_dy_q4_r * inner_dy_q4_r;
    wire [4:0] radicand_bit_w = (step_r - 5'd1) << 1;
    wire [31:0] remainder_shift_w =
        {remainder_r[29:0], radicand_r[radicand_bit_w +: 2]};
    wire [31:0] trial_w = {14'b0, root_r, 2'b01};
    wire root_bit_w = remainder_shift_w >= trial_w;
    wire [31:0] remainder_next_w = root_bit_w ?
        remainder_shift_w - trial_w : remainder_shift_w;
    wire [15:0] root_next_w = {root_r[14:0], root_bit_w};

    assign row_ready_o      = (state_r == ST_IDLE) && !edge_valid_r;
    assign edge_valid_o     = edge_valid_r;
    assign outer_edge_q4_o  = outer_edge_r;
    assign inner_edge_q4_o  = inner_edge_r;
    assign inner_active_o   = inner_active_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= ST_IDLE;
            edge_valid_r <= 1'b0;
            outer_edge_r <= 16'b0;
            inner_edge_r <= 16'b0;
            inner_active_r <= 1'b0;
            border_zero_r <= 1'b0;
            outer_needs_root_r <= 1'b0;
            inner_needs_root_r <= 1'b0;
            outer_radius_q4_r <= 16'b0;
            outer_dy_q4_r <= 16'b0;
            inner_radius_q4_r <= 16'b0;
            inner_dy_q4_r <= 16'b0;
            border_q4_r <= 16'b0;
            root_radius_q4_r <= 16'b0;
            radicand_r <= 32'b0;
            remainder_r <= 32'b0;
            root_r <= 16'b0;
            step_r <= 5'b0;
        end else begin
            if (edge_valid_r && edge_ready_i)
                edge_valid_r <= 1'b0;
            if (row_valid_i && row_ready_o) begin
                outer_edge_r <= 16'd0;
                inner_edge_r <= {2'b0, border_i, 4'b0};
                inner_active_r <= inner_active_w;
                border_zero_r <= border_i == 10'd0;
                outer_needs_root_r <= outer_needs_root_w;
                inner_needs_root_r <= inner_needs_root_w;
                outer_radius_q4_r <= outer_radius_q4_w;
                outer_dy_q4_r <= outer_dy_q4_w;
                inner_radius_q4_r <= inner_radius_q4_w;
                inner_dy_q4_r <= inner_dy_q4_w;
                border_q4_r <= {2'b0, border_i, 4'b0};
                state_r <= ST_PREP;
            end else if (state_r == ST_PREP) begin
                if (outer_needs_root_r) begin
                    root_radius_q4_r <= outer_radius_q4_r;
                    radicand_r <= outer_rad_w;
                    remainder_r <= 32'd0;
                    root_r <= 16'd0;
                    step_r <= 5'd16;
                    state_r <= ST_OUTER;
                end else if (inner_needs_root_r && !border_zero_r) begin
                    root_radius_q4_r <= inner_radius_q4_r;
                    radicand_r <= inner_rad_w;
                    remainder_r <= 32'd0;
                    root_r <= 16'd0;
                    step_r <= 5'd16;
                    state_r <= ST_INNER;
                end else begin
                    edge_valid_r <= 1'b1;
                    state_r <= ST_IDLE;
                end
            end else if ((state_r == ST_OUTER) ||
                         (state_r == ST_INNER)) begin
                remainder_r <= remainder_next_w;
                root_r <= root_next_w;
                step_r <= step_r - 5'd1;
                if (step_r == 5'd1) begin
                    if (state_r == ST_OUTER) begin
                        outer_edge_r <= root_radius_q4_r - root_next_w;
                        if (border_zero_r) begin
                            inner_edge_r <= root_radius_q4_r - root_next_w;
                            edge_valid_r <= 1'b1;
                            state_r <= ST_IDLE;
                        end else if (inner_needs_root_r) begin
                            root_radius_q4_r <= inner_radius_q4_r;
                            radicand_r <= inner_rad_w;
                            remainder_r <= 32'd0;
                            root_r <= 16'd0;
                            step_r <= 5'd16;
                            state_r <= ST_INNER;
                        end else begin
                            edge_valid_r <= 1'b1;
                            state_r <= ST_IDLE;
                        end
                    end else begin
                        inner_edge_r <= border_q4_r +
                                        root_radius_q4_r - root_next_w;
                        edge_valid_r <= 1'b1;
                        state_r <= ST_IDLE;
                    end
                end
            end
        end
    end

endmodule
