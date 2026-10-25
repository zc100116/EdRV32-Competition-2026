// ============================================================================
// File        : edrv32_vision_telemetry.v
// Description : One-second video frame counts and last-frame phase timing.
// Notes       : All inputs are synchronous to clk_i. The output is a compact
//               ASCII hexadecimal CSV record at 115200 8-N-1 by default.
//               No video payload is stored or routed through this module.
// ============================================================================

module edrv32_vision_telemetry #(
    parameter integer CLK_HZ = 125000000,
    parameter integer BAUD = 115200,
    parameter integer REPORT_CYCLES = CLK_HZ
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire [4:0]   mode_i,
    input  wire         source_frame_i,
    input  wire [31:0]  source_drop_count_i,
    input  wire         geometry_start_i,
    input  wire         geometry_done_i,
    input  wire         geometry_error_i,
    input  wire [2:0]   geometry_phase_i,
    input  wire         display_flip_i,
    input  wire [31:0]  reader_frame_count_i,
    input  wire [31:0]  underflow_count_i,
    input  wire [31:0]  cam0_frame_count_i,
    input  wire [31:0]  cam1_frame_count_i,
    input  wire [31:0]  pixel_frame_count_i,
    input  wire [31:0]  replaced_frame_count_i,
    input  wire         input_stream_stall_i,
    input  wire         output_stream_stall_i,
    input  wire         camera_w_stall_i,
    input  wire         write_owner_valid_i,
    input  wire         write_owner_geometry_i,
    input  wire         mux_eof_i,
    input  wire [31:0]  unpack_frame_count_i,
    input  wire [31:0]  point_frame_count_i,
    input  wire [31:0]  spatial_frame_count_i,
    input  wire         mux_error_i,
    input  wire         pixel_cfg_pending_i,
    input  wire         writer_active_i,
    input  wire         mux_valid_i,
    input  wire         pixel_valid_i,
    input  wire         cam0_overflow_i,
    input  wire         cam1_overflow_i,
    input  wire         writer_error_i,
    input  wire         active_camera_i,

    input  wire         rd_arvalid_i,
    input  wire         rd_arready_i,
    input  wire [7:0]   rd_arlen_i,
    input  wire         rd_rvalid_i,
    input  wire         rd_rready_i,
    input  wire         wr_awvalid_i,
    input  wire         wr_awready_i,
    input  wire         wr_wvalid_i,
    input  wire         wr_wready_i,
    input  wire         wr_bvalid_i,
    input  wire         wr_bready_i,

    output wire         uart_tx_o
);

    localparam [2:0] PHASE_PREP   = 3'd1;
    localparam [2:0] PHASE_FETCH  = 3'd2;
    localparam [2:0] PHASE_SAMPLE = 3'd3;
    localparam [2:0] PHASE_DRAIN  = 3'd4;
    localparam [2:0] PHASE_CONFIG = 3'd5;
    localparam [2:0] PHASE_WRITER = 3'd6;

    localparam [2:0] STATE_WAIT   = 3'd0;
    localparam [2:0] STATE_PREFIX = 3'd1;
    localparam [2:0] STATE_SEP    = 3'd2;
    localparam [2:0] STATE_HEX    = 3'd3;
    localparam [2:0] STATE_LF     = 3'd4;
    localparam [5:0] FIELD_COUNT  = 6'd47;

    function [7:0] hex_char;
        input [3:0] value_i;
        begin
            hex_char = value_i < 4'd10 ?
                (8'h30 + {4'b0, value_i}) :
                (8'h41 + {4'b0, value_i} - 8'd10);
        end
    endfunction

    reg [31:0] window_cycle_r;
    reg [31:0] window_source_r;
    reg [31:0] window_start_r;
    reg [31:0] window_success_r;
    reg [31:0] window_error_r;
    reg [31:0] window_flip_r;
    reg [31:0] drop_previous_r;
    reg [31:0] reader_previous_r;
    reg [31:0] underflow_previous_r;
    reg [31:0] cam0_previous_r;
    reg [31:0] cam1_previous_r;
    reg [31:0] pixel_previous_r;
    reg [31:0] replaced_previous_r;
    reg [31:0] window_input_stall_r;
    reg [31:0] window_output_stall_r;
    reg [31:0] window_mux_eof_r;
    reg [31:0] window_mux_valid_r;
    reg [31:0] window_pixel_valid_r;
    reg [31:0] unpack_previous_r;
    reg [31:0] point_previous_r;
    reg [31:0] spatial_previous_r;

    reg frame_active_r;
    reg [31:0] frame_cycles_r;
    reg [31:0] frame_prep_r;
    reg [31:0] frame_fetch_r;
    reg [31:0] frame_sample_r;
    reg [31:0] frame_drain_r;
    reg [31:0] frame_config_r;
    reg [31:0] frame_writer_r;
    reg [31:0] frame_ar_r;
    reg [31:0] frame_beats_r;
    reg [31:0] frame_ar_stall_r;
    reg [31:0] frame_r_wait_r;
    reg [31:0] frame_aw_stall_r;
    reg [31:0] frame_w_stall_r;
    reg [31:0] frame_b_wait_r;
    reg [31:0] frame_camera_w_stall_r;
    reg [31:0] frame_owner_wait_r;
    reg [31:0] frame_downstream_wait_r;

    reg [31:0] last_cycles_r;
    reg [31:0] last_prep_r;
    reg [31:0] last_fetch_r;
    reg [31:0] last_sample_r;
    reg [31:0] last_drain_r;
    reg [31:0] last_config_r;
    reg [31:0] last_writer_r;
    reg [31:0] last_ar_r;
    reg [31:0] last_beats_r;
    reg [31:0] last_ar_stall_r;
    reg [31:0] last_r_wait_r;
    reg [31:0] last_aw_stall_r;
    reg [31:0] last_w_stall_r;
    reg [31:0] last_b_wait_r;
    reg [31:0] last_camera_w_stall_r;
    reg [31:0] last_owner_wait_r;
    reg [31:0] last_downstream_wait_r;

    reg [31:0] snapshot_r [0:46];
    reg [2:0] send_state_r;
    reg [5:0] field_index_r;
    reg [2:0] nibble_index_r;

    wire report_tick_w = window_cycle_r == REPORT_CYCLES - 1;
    wire ar_fire_w = rd_arvalid_i && rd_arready_i;
    wire uart_ready_w;
    wire uart_fire_w = uart_ready_w &&
        (send_state_r != STATE_WAIT);

    reg [31:0] field_value_w;
    reg [3:0] nibble_w;
    reg [7:0] uart_data_w;

    always @(*) begin
        field_value_w = 32'b0;
        case (field_index_r)
            5'd0: field_value_w = snapshot_r[0];
            5'd1: field_value_w = snapshot_r[1];
            5'd2: field_value_w = snapshot_r[2];
            5'd3: field_value_w = snapshot_r[3];
            5'd4: field_value_w = snapshot_r[4];
            5'd5: field_value_w = snapshot_r[5];
            5'd6: field_value_w = snapshot_r[6];
            5'd7: field_value_w = snapshot_r[7];
            5'd8: field_value_w = snapshot_r[8];
            5'd9: field_value_w = snapshot_r[9];
            5'd10: field_value_w = snapshot_r[10];
            5'd11: field_value_w = snapshot_r[11];
            5'd12: field_value_w = snapshot_r[12];
            5'd13: field_value_w = snapshot_r[13];
            5'd14: field_value_w = snapshot_r[14];
            5'd15: field_value_w = snapshot_r[15];
            5'd16: field_value_w = snapshot_r[16];
            5'd17: field_value_w = snapshot_r[17];
            5'd18: field_value_w = snapshot_r[18];
            5'd19: field_value_w = snapshot_r[19];
            5'd20: field_value_w = snapshot_r[20];
            5'd21: field_value_w = snapshot_r[21];
            5'd22: field_value_w = snapshot_r[22];
            5'd23: field_value_w = snapshot_r[23];
            5'd24: field_value_w = snapshot_r[24];
            6'd25: field_value_w = snapshot_r[25];
            6'd26: field_value_w = snapshot_r[26];
            6'd27: field_value_w = snapshot_r[27];
            6'd28: field_value_w = snapshot_r[28];
            6'd29: field_value_w = snapshot_r[29];
            6'd30: field_value_w = snapshot_r[30];
            6'd31: field_value_w = snapshot_r[31];
            6'd32: field_value_w = snapshot_r[32];
            6'd33: field_value_w = snapshot_r[33];
            6'd34: field_value_w = snapshot_r[34];
            6'd35: field_value_w = snapshot_r[35];
            6'd36: field_value_w = snapshot_r[36];
            6'd37: field_value_w = snapshot_r[37];
            6'd38: field_value_w = snapshot_r[38];
            6'd39: field_value_w = snapshot_r[39];
            6'd40: field_value_w = snapshot_r[40];
            6'd41: field_value_w = snapshot_r[41];
            6'd42: field_value_w = snapshot_r[42];
            6'd43: field_value_w = snapshot_r[43];
            6'd44: field_value_w = snapshot_r[44];
            6'd45: field_value_w = snapshot_r[45];
            6'd46: field_value_w = snapshot_r[46];
            default: field_value_w = 32'b0;
        endcase
    end

    always @(*) begin
        nibble_w = 4'b0;
        case (nibble_index_r)
            3'd0: nibble_w = field_value_w[31:28];
            3'd1: nibble_w = field_value_w[27:24];
            3'd2: nibble_w = field_value_w[23:20];
            3'd3: nibble_w = field_value_w[19:16];
            3'd4: nibble_w = field_value_w[15:12];
            3'd5: nibble_w = field_value_w[11:8];
            3'd6: nibble_w = field_value_w[7:4];
            3'd7: nibble_w = field_value_w[3:0];
        endcase
    end

    always @(*) begin
        uart_data_w = 8'h47;
        case (send_state_r)
            STATE_PREFIX: uart_data_w = 8'h47; // 'G'
            STATE_SEP: uart_data_w = field_index_r == FIELD_COUNT ?
                8'h0d : 8'h2c; // CR or comma
            STATE_HEX: uart_data_w = hex_char(nibble_w);
            STATE_LF: uart_data_w = 8'h0a;
            default: uart_data_w = 8'h47;
        endcase
    end

    edrv32_uart_tx #(
        .CLK_HZ(CLK_HZ), .BAUD(BAUD)
    ) u_uart_tx (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .data_valid_i(send_state_r != STATE_WAIT),
        .data_ready_o(uart_ready_w), .data_i(uart_data_w),
        .tx_o(uart_tx_o)
    );

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            window_cycle_r <= 32'b0;
            window_source_r <= 32'b0;
            window_start_r <= 32'b0;
            window_success_r <= 32'b0;
            window_error_r <= 32'b0;
            window_flip_r <= 32'b0;
            drop_previous_r <= 32'b0;
            reader_previous_r <= 32'b0;
            underflow_previous_r <= 32'b0;
            cam0_previous_r <= 32'b0;
            cam1_previous_r <= 32'b0;
            pixel_previous_r <= 32'b0;
            replaced_previous_r <= 32'b0;
            window_input_stall_r <= 32'b0;
            window_output_stall_r <= 32'b0;
            window_mux_eof_r <= 32'b0;
            window_mux_valid_r <= 32'b0;
            window_pixel_valid_r <= 32'b0;
            unpack_previous_r <= 32'b0;
            point_previous_r <= 32'b0;
            spatial_previous_r <= 32'b0;
            frame_active_r <= 1'b0;
            frame_cycles_r <= 32'b0;
            frame_prep_r <= 32'b0;
            frame_fetch_r <= 32'b0;
            frame_sample_r <= 32'b0;
            frame_drain_r <= 32'b0;
            frame_config_r <= 32'b0;
            frame_writer_r <= 32'b0;
            frame_ar_r <= 32'b0;
            frame_beats_r <= 32'b0;
            frame_ar_stall_r <= 32'b0;
            frame_r_wait_r <= 32'b0;
            frame_aw_stall_r <= 32'b0;
            frame_w_stall_r <= 32'b0;
            frame_b_wait_r <= 32'b0;
            frame_camera_w_stall_r <= 32'b0;
            frame_owner_wait_r <= 32'b0;
            frame_downstream_wait_r <= 32'b0;
            last_cycles_r <= 32'b0;
            last_prep_r <= 32'b0;
            last_fetch_r <= 32'b0;
            last_sample_r <= 32'b0;
            last_drain_r <= 32'b0;
            last_config_r <= 32'b0;
            last_writer_r <= 32'b0;
            last_ar_r <= 32'b0;
            last_beats_r <= 32'b0;
            last_ar_stall_r <= 32'b0;
            last_r_wait_r <= 32'b0;
            last_aw_stall_r <= 32'b0;
            last_w_stall_r <= 32'b0;
            last_b_wait_r <= 32'b0;
            last_camera_w_stall_r <= 32'b0;
            last_owner_wait_r <= 32'b0;
            last_downstream_wait_r <= 32'b0;
            send_state_r <= STATE_WAIT;
            field_index_r <= 6'b0;
            nibble_index_r <= 3'b0;
        end else begin
            window_cycle_r <= report_tick_w ?
                32'b0 : window_cycle_r + 1'b1;
            if (source_frame_i)
                window_source_r <= window_source_r + 1'b1;
            if (geometry_start_i)
                window_start_r <= window_start_r + 1'b1;
            if (geometry_done_i) begin
                if (geometry_error_i)
                    window_error_r <= window_error_r + 1'b1;
                else
                    window_success_r <= window_success_r + 1'b1;
            end
            if (display_flip_i)
                window_flip_r <= window_flip_r + 1'b1;
            if (input_stream_stall_i)
                window_input_stall_r <= window_input_stall_r + 1'b1;
            if (output_stream_stall_i)
                window_output_stall_r <= window_output_stall_r + 1'b1;
            if (mux_eof_i)
                window_mux_eof_r <= window_mux_eof_r + 1'b1;
            if (mux_valid_i)
                window_mux_valid_r <= window_mux_valid_r + 1'b1;
            if (pixel_valid_i)
                window_pixel_valid_r <= window_pixel_valid_r + 1'b1;

            if (geometry_start_i) begin
                frame_active_r <= 1'b1;
                frame_cycles_r <= 32'b0;
                frame_prep_r <= 32'b0;
                frame_fetch_r <= 32'b0;
                frame_sample_r <= 32'b0;
                frame_drain_r <= 32'b0;
                frame_config_r <= 32'b0;
                frame_writer_r <= 32'b0;
                frame_ar_r <= 32'b0;
                frame_beats_r <= 32'b0;
                frame_ar_stall_r <= 32'b0;
                frame_r_wait_r <= 32'b0;
                frame_aw_stall_r <= 32'b0;
                frame_w_stall_r <= 32'b0;
                frame_b_wait_r <= 32'b0;
                frame_camera_w_stall_r <= 32'b0;
                frame_owner_wait_r <= 32'b0;
                frame_downstream_wait_r <= 32'b0;
            end else if (frame_active_r) begin
                frame_cycles_r <= frame_cycles_r + 1'b1;
                case (geometry_phase_i)
                    PHASE_PREP: frame_prep_r <= frame_prep_r + 1'b1;
                    PHASE_FETCH: frame_fetch_r <= frame_fetch_r + 1'b1;
                    PHASE_SAMPLE: frame_sample_r <= frame_sample_r + 1'b1;
                    PHASE_DRAIN: frame_drain_r <= frame_drain_r + 1'b1;
                    PHASE_CONFIG: frame_config_r <= frame_config_r + 1'b1;
                    PHASE_WRITER: frame_writer_r <= frame_writer_r + 1'b1;
                    default: begin end
                endcase
                if (ar_fire_w) begin
                    frame_ar_r <= frame_ar_r + 1'b1;
                    frame_beats_r <= frame_beats_r +
                        {24'b0, rd_arlen_i} + 1'b1;
                end
                if (rd_arvalid_i && !rd_arready_i)
                    frame_ar_stall_r <= frame_ar_stall_r + 1'b1;
                if (rd_rready_i && !rd_rvalid_i)
                    frame_r_wait_r <= frame_r_wait_r + 1'b1;
                if (wr_awvalid_i && !wr_awready_i)
                    frame_aw_stall_r <= frame_aw_stall_r + 1'b1;
                if (wr_wvalid_i && !wr_wready_i) begin
                    frame_w_stall_r <= frame_w_stall_r + 1'b1;
                    if (write_owner_valid_i) begin
                        if (write_owner_geometry_i)
                            frame_downstream_wait_r <=
                                frame_downstream_wait_r + 1'b1;
                        else
                            frame_owner_wait_r <=
                                frame_owner_wait_r + 1'b1;
                    end
                end
                if (wr_bready_i && !wr_bvalid_i)
                    frame_b_wait_r <= frame_b_wait_r + 1'b1;
                if (camera_w_stall_i)
                    frame_camera_w_stall_r <=
                        frame_camera_w_stall_r + 1'b1;
            end

            if (geometry_done_i) begin
                frame_active_r <= 1'b0;
                if (!geometry_error_i) begin
                    last_cycles_r <= frame_cycles_r;
                    last_prep_r <= frame_prep_r;
                    last_fetch_r <= frame_fetch_r;
                    last_sample_r <= frame_sample_r;
                    last_drain_r <= frame_drain_r;
                    last_config_r <= frame_config_r;
                    last_writer_r <= frame_writer_r;
                    last_ar_r <= frame_ar_r;
                    last_beats_r <= frame_beats_r;
                    last_ar_stall_r <= frame_ar_stall_r;
                    last_r_wait_r <= frame_r_wait_r;
                    last_aw_stall_r <= frame_aw_stall_r;
                    last_w_stall_r <= frame_w_stall_r;
                    last_b_wait_r <= frame_b_wait_r;
                    last_camera_w_stall_r <= frame_camera_w_stall_r;
                    last_owner_wait_r <= frame_owner_wait_r;
                    last_downstream_wait_r <= frame_downstream_wait_r;
                end
            end

            if (report_tick_w) begin
                window_source_r <= 32'b0;
                window_start_r <= 32'b0;
                window_success_r <= 32'b0;
                window_error_r <= 32'b0;
                window_flip_r <= 32'b0;
                drop_previous_r <= source_drop_count_i;
                reader_previous_r <= reader_frame_count_i;
                underflow_previous_r <= underflow_count_i;
                cam0_previous_r <= cam0_frame_count_i;
                cam1_previous_r <= cam1_frame_count_i;
                pixel_previous_r <= pixel_frame_count_i;
                replaced_previous_r <= replaced_frame_count_i;
                unpack_previous_r <= unpack_frame_count_i;
                point_previous_r <= point_frame_count_i;
                spatial_previous_r <= spatial_frame_count_i;
                window_input_stall_r <= 32'b0;
                window_output_stall_r <= 32'b0;
                window_mux_eof_r <= 32'b0;
                window_mux_valid_r <= 32'b0;
                window_pixel_valid_r <= 32'b0;
                if (send_state_r == STATE_WAIT) begin
                    snapshot_r[0] <= {27'b0, mode_i};
                    snapshot_r[1] <= window_source_r + source_frame_i;
                    snapshot_r[2] <= source_drop_count_i -
                        drop_previous_r;
                    snapshot_r[3] <= window_start_r + geometry_start_i;
                    snapshot_r[4] <= window_success_r +
                        (geometry_done_i && !geometry_error_i);
                    snapshot_r[5] <= window_error_r +
                        (geometry_done_i && geometry_error_i);
                    snapshot_r[6] <= window_flip_r + display_flip_i;
                    snapshot_r[7] <= reader_frame_count_i -
                        reader_previous_r;
                    snapshot_r[8] <= underflow_count_i -
                        underflow_previous_r;
                    snapshot_r[9] <= last_cycles_r;
                    snapshot_r[10] <= last_prep_r;
                    snapshot_r[11] <= last_fetch_r;
                    snapshot_r[12] <= last_sample_r;
                    snapshot_r[13] <= last_drain_r;
                    snapshot_r[14] <= last_ar_r;
                    snapshot_r[15] <= last_beats_r;
                    snapshot_r[16] <= last_ar_stall_r;
                    snapshot_r[17] <= last_r_wait_r;
                    snapshot_r[18] <= last_aw_stall_r;
                    snapshot_r[19] <= last_w_stall_r;
                    snapshot_r[20] <= last_b_wait_r;
                    snapshot_r[21] <= last_config_r;
                    snapshot_r[22] <= last_writer_r;
                    snapshot_r[23] <= frame_active_r ?
                        {29'b0, geometry_phase_i} : 32'b0;
                    snapshot_r[24] <= frame_active_r ?
                        frame_cycles_r : 32'b0;
                    snapshot_r[25] <= cam0_frame_count_i -
                        cam0_previous_r;
                    snapshot_r[26] <= cam1_frame_count_i -
                        cam1_previous_r;
                    snapshot_r[27] <= pixel_frame_count_i -
                        pixel_previous_r;
                    snapshot_r[28] <= replaced_frame_count_i -
                        replaced_previous_r;
                    snapshot_r[29] <= window_input_stall_r +
                        input_stream_stall_i;
                    snapshot_r[30] <= window_output_stall_r +
                        output_stream_stall_i;
                    snapshot_r[31] <= last_camera_w_stall_r;
                    snapshot_r[32] <= last_owner_wait_r;
                    snapshot_r[33] <= last_downstream_wait_r;
                    snapshot_r[34] <= window_mux_eof_r + mux_eof_i;
                    snapshot_r[35] <= unpack_frame_count_i -
                        unpack_previous_r;
                    snapshot_r[36] <= point_frame_count_i -
                        point_previous_r;
                    snapshot_r[37] <= spatial_frame_count_i -
                        spatial_previous_r;
                    snapshot_r[38] <= {31'b0, mux_error_i};
                    snapshot_r[39] <= {31'b0, pixel_cfg_pending_i};
                    snapshot_r[40] <= {31'b0, writer_active_i};
                    snapshot_r[41] <= window_mux_valid_r + mux_valid_i;
                    snapshot_r[42] <= window_pixel_valid_r + pixel_valid_i;
                    snapshot_r[43] <= {31'b0, cam0_overflow_i};
                    snapshot_r[44] <= {31'b0, cam1_overflow_i};
                    snapshot_r[45] <= {31'b0, writer_error_i};
                    snapshot_r[46] <= {31'b0, active_camera_i};
                    send_state_r <= STATE_PREFIX;
                    field_index_r <= 6'b0;
                    nibble_index_r <= 3'b0;
                end
            end

            if (uart_fire_w) begin
                case (send_state_r)
                    STATE_PREFIX: send_state_r <= STATE_SEP;
                    STATE_SEP: begin
                        if (field_index_r == FIELD_COUNT)
                            send_state_r <= STATE_LF;
                        else
                            send_state_r <= STATE_HEX;
                    end
                    STATE_HEX: begin
                        if (nibble_index_r == 3'd7) begin
                            nibble_index_r <= 3'b0;
                            field_index_r <= field_index_r + 1'b1;
                            send_state_r <= STATE_SEP;
                        end else begin
                            nibble_index_r <= nibble_index_r + 1'b1;
                        end
                    end
                    STATE_LF: send_state_r <= STATE_WAIT;
                    default: send_state_r <= STATE_WAIT;
                endcase
            end
        end
    end

endmodule
