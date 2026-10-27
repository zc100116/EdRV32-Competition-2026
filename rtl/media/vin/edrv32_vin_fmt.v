// File: edrv32_vin_fmt.v
// Spec: vin 2.2, 5.2, 6.
// Description: Normalize DVP lines and frames, retaining the final word until EOF.
//              The final word carries the completed frame's incomplete status.
// Clock domain: clk_mem.
module edrv32_vin_fmt (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Frontend item stream.
    input wire item_valid_i,
    output wire item_ready_o,
    input wire [35:0] item_data_i,

    // Normalized pixel stream.
    output wire valid_o,
    input wire ready_i,
    output wire [31:0] data_o,
    output wire sof_o,
    output wire eol_o,
    output wire eof_o,
    output wire [31:0] frame_id_o,
    output wire [10:0] width_o,
    output wire [11:0] height_o,
    output wire incomplete_o,

    // Frame configuration and event pulses.
    input wire enable_i,
    input wire [10:0] width_i,
    input wire [11:0] height_i,
    output reg frame_o,
    output reg incomplete_frame_o,
    output reg cfg_error_o
);
    localparam S_WAIT = 3'd0;
    localparam S_DATA = 3'd1;
    localparam S_LINE = 3'd2;
    localparam S_PAD = 3'd3;
    localparam S_TAIL = 3'd4;
    localparam S_FINAL = 3'd5;
    localparam S_FRAME = 3'd6;
    reg [2:0] state_r;
    reg [1:0] discard_r;
    reg enable_r;
    reg discard_active_r;
    reg [10:0] width_r;
    reg [11:0] height_r;
    reg [9:0] x_r;
    reg [11:0] y_r;
    reg [31:0] frame_count_r;
    reg [31:0] frame_id_r;
    reg incomplete_r;
    reg end_seen_r;
    reg [31:0] last_word_r;
    reg first_r;
    wire [1:0] type_w;
    wire data_item_w;
    wire end_line_w;
    wire last_x_w;
    wire last_y_w;
    wire transfer_w;
    wire item_fire_w;
    wire output_data_w;
    wire output_pad_w;
    wire frame_start_w;
    wire cfg_valid_w;

    assign cfg_valid_w = width_i != 0 && width_i <= 11'd1280 && height_i != 0;
    assign frame_start_w = state_r == S_WAIT && item_fire_w && type_w == 2'd2 &&
        enable_i && discard_r == 2'd2 && cfg_valid_w;
    assign type_w = item_data_i[35:34];
    assign data_item_w = type_w == 2'd0;
    assign end_line_w = type_w == 2'd1 || (data_item_w && item_data_i[33]);
    assign last_x_w = x_r == width_r[10:1] - 10'd1;
    assign last_y_w = y_r == height_r - 12'd1;
    assign output_data_w = state_r == S_DATA && item_valid_i && data_item_w && !last_x_w;
    assign output_pad_w = state_r == S_PAD || state_r == S_LINE;
    assign valid_o = output_data_w || (output_pad_w && !(last_x_w && last_y_w)) ||
        state_r == S_FINAL;
    assign data_o = output_data_w ? item_data_i[31:0] :
        ((state_r == S_LINE || state_r == S_FINAL) ? last_word_r : 32'd0);
    assign sof_o = first_r;
    assign eol_o = last_x_w;
    assign eof_o = state_r == S_FINAL;
    assign incomplete_o = incomplete_r;
    assign frame_id_o = frame_id_r;
    assign width_o = width_r;
    assign height_o = height_r;
    assign transfer_w = valid_o && ready_i;
    assign item_ready_o = state_r == S_WAIT || state_r == S_TAIL || state_r == S_FRAME ||
        (state_r == S_DATA && (!data_item_w || last_x_w || ready_i));
    assign item_fire_w = item_valid_i && item_ready_o;

    always @(posedge clk_i) begin
        if (frame_start_w)
            frame_id_r <= frame_count_r;
        if (item_fire_w && type_w == 2'd2) begin
            width_r <= width_i;
            height_r <= height_i;
        end
        if (item_fire_w && state_r == S_DATA && data_item_w && last_x_w)
            last_word_r <= item_data_i[31:0];
        else if (state_r == S_PAD && last_x_w && last_y_w)
            last_word_r <= 32'd0;
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_WAIT;
            discard_r <= 2'd0;
            enable_r <= 1'b0;
            discard_active_r <= 1'b0;
            x_r <= 10'd0;
            y_r <= 12'd0;
            frame_count_r <= 32'd0;
            incomplete_r <= 1'b0;
            end_seen_r <= 1'b0;
            first_r <= 1'b1;
            frame_o <= 1'b0;
            incomplete_frame_o <= 1'b0;
            cfg_error_o <= 1'b0;
        end else begin
            enable_r <= enable_i;
            frame_o <= 1'b0;
            incomplete_frame_o <= 1'b0;
            cfg_error_o <= 1'b0;
            if (!enable_i || !enable_r) begin
                discard_r <= 2'd0;
                discard_active_r <= 1'b0;
            end
            if (transfer_w)
                first_r <= 1'b0;
            case (state_r)
                S_WAIT: begin
                    if (item_fire_w && type_w == 2'd2 && enable_i)
                        discard_active_r <= 1'b1;
                    if (item_fire_w && type_w == 2'd3 && enable_i &&
                        discard_active_r && discard_r < 2'd2) begin
                        discard_r <= discard_r + 2'd1;
                        discard_active_r <= 1'b0;
                    end
                    if (item_fire_w && type_w == 2'd2 && enable_i && !cfg_valid_w)
                        cfg_error_o <= 1'b1;
                    if (frame_start_w) begin
                        state_r <= S_DATA;
                        x_r <= 10'd0;
                        y_r <= 12'd0;
                        first_r <= 1'b1;
                        incomplete_r <= 1'b0;
                        end_seen_r <= 1'b0;
                        frame_count_r <= frame_count_r + 32'd1;
                        frame_o <= 1'b1;
                    end
                end
                S_DATA: begin
                    if (item_fire_w) begin
                        if (type_w == 2'd3) begin
                            end_seen_r <= 1'b1;
                            incomplete_r <= 1'b1;
                            state_r <= S_PAD;
                        end else if (data_item_w) begin
                            if (last_x_w) begin
                                state_r <= item_data_i[33] ? S_LINE : S_TAIL;
                            end else begin
                                x_r <= x_r + 10'd1;
                                if (end_line_w) begin
                                    incomplete_r <= 1'b1;
                                    state_r <= S_PAD;
                                end
                            end
                        end else if (end_line_w) begin
                            incomplete_r <= 1'b1;
                            state_r <= S_PAD;
                        end
                    end
                end
                S_TAIL: begin
                    if (item_fire_w) begin
                        if (type_w == 2'd3) begin
                            end_seen_r <= 1'b1;
                            if (item_data_i[32])
                                incomplete_r <= 1'b1;
                            state_r <= last_y_w ? S_FINAL : S_LINE;
                            if (!last_y_w)
                                incomplete_r <= 1'b1;
                        end else begin
                            if (data_item_w)
                                incomplete_r <= 1'b1;
                            if (end_line_w)
                                state_r <= S_LINE;
                        end
                    end
                end
                S_LINE, S_PAD: begin
                    if (last_x_w && last_y_w) begin
                        if (end_seen_r)
                            state_r <= S_FINAL;
                        else begin
                            state_r <= S_FRAME;
                        end
                    end else if (transfer_w) begin
                        if (last_x_w) begin
                            x_r <= 10'd0;
                            y_r <= y_r + 12'd1;
                            state_r <= end_seen_r ? S_PAD : S_DATA;
                        end else begin
                            x_r <= x_r + 10'd1;
                        end
                    end
                end
                S_FRAME: begin
                    if (item_fire_w) begin
                        if (type_w == 2'd3) begin
                            state_r <= S_FINAL;
                            if (item_data_i[32])
                                incomplete_r <= 1'b1;
                        end else begin
                            incomplete_r <= 1'b1;
                        end
                    end
                end
                S_FINAL: begin
                    if (transfer_w) begin
                        state_r <= S_WAIT;
                        incomplete_frame_o <= incomplete_r;
                    end
                end
                default: state_r <= S_WAIT;
            endcase
        end
    end
endmodule
