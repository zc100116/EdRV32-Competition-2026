// File: edrv32_npu_conv.v
// Spec: npu-spec 5.1, 5.2, 5.4; datapath design 4.2.2, 4.4, 4.8.
// Description: Row-first CONV scheduler, resident model loading and five/two row slots.
// Independent input/model/residual producers share ordered DMA burst requests.
// Clock: clk_npu.
module edrv32_npu_conv (
    // Clock and equal-edge reset/start/cancel copies for execution units.
    input wire clk_i,
    input wire [3:0] rst_n_i,
    input wire [3:0] start_i,
    input wire stop_i,
    input wire [3:0] cancel_i,
    input wire [511:0] desc_i,
    input wire [31:0] in_addr_i,
    input wire [31:0] out_addr_i,
    input wire [31:0] residual_addr_i,
    input wire [31:0] weight_addr_i,
    input wire [31:0] quant_addr_i,

    // Read DMA burst producer and tagged registered responses.
    output wire read_req_valid_o,
    input wire read_req_ready_i,
    output wire [31:0] read_req_addr_o,
    output wire [4:0] read_req_beats_o,
    output wire [31:0] read_req_tag_o,
    input wire read_data_valid_i,
    output wire read_data_ready_o,
    input wire [255:0] read_data_i,
    input wire [31:0] read_data_tag_i,
    input wire [3:0] read_data_index_i,
    input wire read_data_last_i,

    // Write DMA stream, sharing the datapath result RAM.
    output wire write_req_valid_o,
    input wire write_req_ready_i,
    output wire [31:0] write_req_addr_o,
    output wire [4:0] write_req_beats_o,
    output wire write_data_valid_o,
    input wire write_data_ready_i,
    output wire [255:0] write_data_o,
    input wire write_stream_idle_i,

    // Local completion and PERF events.
    output wire done_o,
    output wire writer_idle_o,
    output wire mac_beat_o,
    output wire input_wait_o,
    output wire model_wait_o
);
    wire dp_cfg_k3_w;
    wire dp_cfg_s2_w;
    wire dp_cfg_in_c4_w;
    wire dp_cfg_half_tail_w;
    wire dp_cfg_lut_en_w;
    wire dp_cfg_res_en_w;
    wire [7:0] dp_cfg_out_zp_w;
    wire [11:0] dp_cfg_in_w_w;
    wire [11:0] dp_cfg_out_w_w;
    wire [5:0] dp_cfg_cin_blocks_w;
    wire [3:0] dp_cfg_cout_blocks_w;
    wire [10:0] dp_cfg_k_count_w;
    wire dp_cfg_valid_w;
    wire dp_cfg_ready_w;
    wire dp_line_wr_valid_w;
    wire dp_line_wr_ready_w;
    wire dp_line_wr_bank_w;
    wire [9:0] dp_line_wr_addr_w;
    wire [255:0] dp_line_wr_data_w;
    wire dp_line_wr_row_last_w;
    wire dp_line_wr_row_done_w;
    wire unused_dp_line_wr_idle_w;
    wire dp_weight_wr_valid_w;
    wire [13:0] dp_weight_wr_addr_w;
    wire [255:0] dp_weight_wr_data_w;
    wire dp_quant_wr_valid_w;
    wire [2:0] dp_quant_wr_block_w;
    wire [4:0] dp_quant_wr_channel_w;
    wire [31:0] dp_quant_wr_bias_w;
    wire [15:0] dp_quant_wr_mult_w;
    wire [5:0] dp_quant_wr_shift_w;
    wire dp_lut_wr_valid_w;
    wire [2:0] dp_lut_wr_block_w;
    wire [7:0] dp_lut_wr_addr_w;
    wire [7:0] dp_lut_wr_data_w;
    wire dp_cmd_valid_w;
    wire [11:0] dp_cmd_row_w;
    wire [2:0] dp_cmd_block_w;
    wire [10:0] dp_cmd_weight_base_w;
    wire [9:0] dp_cmd_row_base0_w;
    wire [9:0] dp_cmd_row_base1_w;
    wire [9:0] dp_cmd_row_base2_w;
    wire [2:0] dp_cmd_row_valid_w;
    wire dp_cmd_ready_w;
    wire dp_issue_enable_w;
    wire dp_residual_begin_valid_w;
    wire dp_residual_begin_ready_w;
    wire dp_residual_begin_bank_w;
    wire [4:0] dp_residual_begin_pairs_w;
    wire dp_residual_begin_half_w;
    wire dp_residual_wr_valid_w;
    wire dp_residual_wr_bank_w;
    wire [3:0] dp_residual_wr_index_w;
    wire [255:0] dp_residual_wr_data_w;
    wire dp_residual_commit_w;
    wire [5:0] unused_dp_result_credit_w;
    wire dp_result_chunk_valid_w;
    wire dp_result_chunk_ready_w;
    wire [4:0] dp_result_chunk_base_w;
    wire [4:0] dp_result_chunk_pairs_w;
    wire [11:0] unused_dp_result_chunk_row_w;
    wire [2:0] dp_result_chunk_block_w;
    wire [10:0] dp_result_chunk_pair_w;
    wire dp_result_chunk_half_w;
    wire dp_result_chunk_last_w;
    wire dp_result_release_w;
    wire dp_result_rd_en_w;
    wire [4:0] dp_result_rd_index_w;
    wire dp_result_rd_plane_w;
    wire dp_result_rd_valid_w;
    wire [255:0] dp_result_rd_data_w;
    wire unused_dp_cmd_issued_w;
    wire [11:0] unused_dp_cmd_issued_row_w;
    wire [2:0] unused_dp_cmd_issued_block_w;
    wire dp_cmd_read_done_w;
    wire [11:0] dp_cmd_read_done_row_w;
    wire [2:0] dp_cmd_read_done_block_w;
    wire unused_dp_cmd_done_w;
    wire [11:0] unused_dp_cmd_done_row_w;
    wire [2:0] unused_dp_cmd_done_block_w;
    wire dp_idle_w;
    wire dp_mac_beat_w;

    localparam [2:0] ROLE_WEIGHT = 3'd0;
    localparam [2:0] ROLE_QUANT = 3'd1;
    localparam [2:0] ROLE_LUT = 3'd2;
    localparam [2:0] ROLE_LINE = 3'd3;
    localparam [2:0] ROLE_RESIDUAL = 3'd4;
    localparam [1:0] S_MODEL_WEIGHT = 2'd0;
    localparam [1:0] S_MODEL_QUANT = 2'd1;
    localparam [1:0] S_MODEL_LUT = 2'd2;
    localparam [1:0] S_MODEL_DONE = 2'd3;
    localparam [1:0] S_RES_BEGIN = 2'd0;
    localparam [1:0] S_RES_READ = 2'd1;
    localparam [1:0] S_RES_WAIT = 2'd2;
    localparam [1:0] S_RES_DONE = 2'd3;
    reg [511:0] desc_r;
    wire [511:0] unused_desc_w;
    wire [31:0] unused_read_tag_w;
    assign unused_desc_w = desc_r;
    assign unused_read_tag_w = read_data_tag_i;
    reg cfg_valid_r;
    reg active_r;
    reg [1:0] model_state_r;
    reg [2:0] model_block_r;
    reg [31:0] model_addr_r;
    reg [14:0] model_remaining_r;
    reg [13:0] weight_index_r;
    reg [3:0] record_index_r;
    reg [7:0] block_ready_r;
    reg [1:0] block_finish_r;
    reg [2:0] block_finish_idx_r;
    reg serial_valid_r;
    reg serial_lut_r;
    reg [255:0] serial_data_r;
    reg [4:0] serial_phase_r;
    reg [7:0] serial_base_r;
    reg [2:0] serial_block_r;
    reg serial_last_r;
    reg quant_valid_r;
    reg [2:0] quant_block_r;
    reg [4:0] quant_channel_r;
    reg [31:0] quant_bias_r;
    reg [15:0] quant_mult_r;
    reg [5:0] quant_shift_r;
    reg lut_valid_r;
    reg [2:0] lut_block_r;
    reg [7:0] lut_addr_r;
    reg [7:0] lut_data_r;
    reg line_valid_r;
    reg line_bank_r;
    reg [9:0] line_addr_r;
    reg [255:0] line_data_r;
    reg line_last_r;
    reg [2:0] line_slot_r;
    reg [2:0] completed_slot_r [0:7];
    reg [2:0] completed_write_ptr_r;
    reg [2:0] completed_read_ptr_r;
    reg [4:0] slot_used_r;
    reg [4:0] slot_ready_r;
    reg [11:0] slot_row_r [0:4];
    reg [9:0] slot_base_r [0:4];
    reg [12:0] load_row_r;
    reg [2:0] load_slot_r;
    reg [5:0] load_plane_r;
    reg [10:0] load_pair_r;
    reg [9:0] load_plane_base_r;
    reg [31:0] load_row_addr_r;
    reg [31:0] load_addr_r;
    reg [31:0] load_plane_addr_r;
    wire [31:0] load_next_plane_addr_w;
    wire [31:0] load_next_row_addr_w;
    reg [12:0] retire_min_r;
    reg cmd_valid_r;
    reg [11:0] cmd_row_r;
    reg [2:0] cmd_block_r;
    reg [10:0] cmd_weight_base_r;
    reg [9:0] cmd_base0_r;
    reg [9:0] cmd_base1_r;
    reg [9:0] cmd_base2_r;
    reg [2:0] cmd_row_valid_r;
    reg [11:0] schedule_row_r;
    reg [2:0] schedule_block_r;
    reg [10:0] schedule_weight_base_r;
    reg all_submitted_r;
    reg rows_ready_w;
    reg [9:0] schedule_base_w [0:2];
    reg [2:0] schedule_row_valid_w;
    reg signed [13:0] required_row_w;
    reg row_found_w;
    reg [1:0] residual_state_r;
    reg residual_bank_r;
    reg [11:0] residual_row_r;
    reg [2:0] residual_block_r;
    reg [10:0] residual_pair_r;
    reg [4:0] residual_pairs_r;
    reg residual_half_r;
    reg residual_plane_r;
    reg [4:0] residual_sent_r;
    reg [31:0] residual_row_addr_r;
    reg [31:0] residual_block_addr_r;
    reg [31:0] residual_addr_r;
    reg residual_wr_valid_r;
    reg residual_wr_bank_r;
    reg [3:0] residual_wr_index_r;
    reg [255:0] residual_wr_data_r;
    reg residual_commit_r;
    wire [31:0] unused_flags_w;
    wire [11:0] in_w_w;
    wire [11:0] in_h_w;
    wire [11:0] out_w_w;
    wire [11:0] out_h_w;
    wire [5:0] cin_blocks_w;
    wire [3:0] cout_blocks_w;
    wire [10:0] unused_row_slot_beats_w;
    wire [19:0] weight_block_bytes_w;
    wire [10:0] input_row_beats_w;
    wire [10:0] output_row_pairs_w;
    wire [31:0] input_row_bytes_w;
    wire [31:0] output_row_bytes_w;
    wire [2:0] response_role_w;
    wire [4:0] response_record_w;
    wire [4:0] response_line_pair_w;
    wire [4:0] unused_response_residual_pair_w;
    reg [4:0] model_beats_r;
    reg model_burst_last_r;
    reg [31:0] model_boundary_addr_r;
    reg [31:0] model_next_weight_addr_r;
    reg [31:0] model_weight_base_r;
    reg [31:0] model_quant_addr_r;
    reg [31:0] model_quant_boundary_r;
    reg [4:0] model_quant_beats_r;
    reg [14:0] model_quant_remaining_r;
    reg model_quant_last_r;
    reg [31:0] model_lut_addr_r;
    reg [31:0] model_lut_boundary_r;
    reg [4:0] model_lut_beats_r;
    reg [14:0] model_lut_remaining_r;
    reg model_lut_last_r;
    reg [14:0] model_first_count_r;
    reg [4:0] model_first_boundary_beats_r;
    reg [4:0] model_next_weight_boundary_beats_r;
    wire [3:0] model_next_weight_offset_w;
    reg [14:0] model_next_weight_count_r;
    wire [14:0] model_future_weight_count_w;
    wire [4:0] line_beats_w;
    reg [4:0] residual_beats_r;
    reg [4:0] residual_remaining_r;
    reg residual_burst_last_r;
    reg [31:0] residual_boundary_addr_r;
    reg [31:0] residual_second_addr_r;
    reg [31:0] residual_next_row_addr_r;
    reg [31:0] residual_next_block_addr_r;
    reg [31:0] residual_next_chunk_addr_r;
    wire [31:0] residual_second_addr_w;
    wire residual_begin_w;
    wire line_candidate_w;
    wire model_candidate_w;
    wire residual_candidate_w;
    wire line_accept_w;
    wire model_accept_w;
    wire residual_accept_w;
    wire line_row_last_w;
    wire model_record_last_w;
    wire residual_read_last_w;
    wire response_accept_w;
    wire line_take_w;
    wire cmd_prepare_w;
    wire residual_finish_block_w;
    reg residual_finish_block_r;
    reg [10:0] residual_chunk_end_pair_r;
    wire residual_next_half_w;
    wire [10:0] residual_next_pairs_w;
    reg request_valid_r;
    reg [31:0] request_addr_r;
    reg [4:0] request_beats_r;
    reg [31:0] request_tag_r;
    wire request_prepare_w;
    reg [1:0] select_w;
    reg [31:0] read_tag_w;
    integer slot_base_idx;
    integer slot_idx;
    integer row_idx;
    integer scan_idx;

    // Capture only at layer entry; live scheduler and datapath fields stay local.
    always @(posedge clk_i) begin
        if (start_i[0]) desc_r[127:0] <= desc_i[127:0];
        if (start_i[1]) desc_r[255:128] <= desc_i[255:128];
        if (start_i[2]) desc_r[383:256] <= desc_i[383:256];
        if (start_i[3]) desc_r[511:384] <= desc_i[511:384];
    end

    // Burst boundaries are prepared outside the A1 address path.
    function [4:0] burst_beats;
        input [31:0] unused_addr_i;
        input [14:0] remaining_i;
        begin
            burst_beats = (remaining_i < {10'd0, 5'd16 - {1'b0, unused_addr_i[8:5]}})
                ? remaining_i[4:0] : 5'd16 - {1'b0, unused_addr_i[8:5]};
        end
    endfunction
    // Compare and subtract in parallel rather than subtracting the selected beat count.
    function [14:0] burst_remaining;
        input [31:0] unused_addr_i;
        input [14:0] remaining_i;
        begin
            burst_remaining = (remaining_i <= {10'd0, 5'd16 - {1'b0, unused_addr_i[8:5]}})
                ? 15'd0 : remaining_i - {10'd0, 5'd16 - {1'b0, unused_addr_i[8:5]}};
        end
    endfunction
    // Model boundary arithmetic is a preceding register stage, so the 15-bit
    // comparison/subtraction below cannot absorb the address-to-boundary carry.
    function [14:0] model_burst_remaining;
        input [4:0] boundary_beats_i;
        input [14:0] remaining_i;
        begin
            model_burst_remaining = (remaining_i <= {10'd0, boundary_beats_i})
                ? 15'd0 : remaining_i - {10'd0, boundary_beats_i};
        end
    endfunction
    function [4:0] residual_burst_remaining;
        input [31:0] unused_addr_i;
        input [4:0] remaining_i;
        begin
            residual_burst_remaining = (remaining_i <= 5'd16 - {1'b0, unused_addr_i[8:5]})
                ? 5'd0 : remaining_i - (5'd16 - {1'b0, unused_addr_i[8:5]});
        end
    endfunction
    function burst_last;
        input [31:0] unused_addr_i;
        input [14:0] remaining_i;
        begin
            burst_last = remaining_i <= {10'd0, 5'd16 - {1'b0, unused_addr_i[8:5]}};
        end
    endfunction
    // A nonfinal burst ends at a 512-byte boundary. The next burst can therefore
    // use at most 16 beats without another address-dependent burst calculation.
    function [31:0] burst_boundary;
        input [31:0] unused_addr_i;
        begin
            burst_boundary = {unused_addr_i[31:9] + 23'd1, 9'd0};
        end
    endfunction
    assign unused_flags_w = desc_r[31:0];
    assign in_w_w = desc_r[267:256];
    assign in_h_w = desc_r[283:272];
    assign out_w_w = desc_r[299:288];
    assign out_h_w = desc_r[315:304];
    assign cin_blocks_w = desc_r[325:320];
    assign cout_blocks_w = desc_r[331:328];
    assign unused_row_slot_beats_w = desc_r[362:352];
    assign weight_block_bytes_w = desc_r[403:384];
    assign input_row_beats_w = unused_flags_w[8] ? {2'd0, in_w_w[11:3]} : in_w_w[11:1];
    assign output_row_pairs_w = out_w_w[11:1];
    assign input_row_bytes_w = {16'd0, input_row_beats_w, 5'd0};
    assign output_row_bytes_w = {16'd0, output_row_pairs_w, 5'd0};
    assign model_future_weight_count_w = unused_flags_w[9] && !unused_flags_w[8]
        && ({1'b0, model_block_r} == cout_blocks_w - 4'd3)
        ? {1'b0, weight_block_bytes_w[19:6]} : weight_block_bytes_w[19:5];
    assign line_beats_w = burst_beats(load_addr_r,
        {4'd0, input_row_beats_w - load_pair_r});
    assign line_candidate_w = active_r && (load_row_r < {1'b0, in_h_w})
        && (!slot_used_r[load_slot_r] || (load_plane_r != 6'd0) || (load_pair_r != 11'd0));
    assign model_candidate_w = active_r && (model_state_r != S_MODEL_DONE);
    assign residual_candidate_w = active_r && (residual_state_r == S_RES_READ);
    assign request_prepare_w = !stop_i && (!request_valid_r || read_req_ready_i)
        && (line_candidate_w || model_candidate_w || residual_candidate_w);
    assign read_req_valid_o = request_valid_r && !stop_i;
    assign read_req_addr_o = request_addr_r;
    assign read_req_beats_o = request_beats_r;
    assign read_req_tag_o = request_tag_r;
    always @(posedge clk_i or negedge rst_n_i[0]) begin
        if (!rst_n_i[0]) begin
            request_valid_r <= 1'b0;
        end else if (cancel_i[0] || stop_i) begin
            request_valid_r <= 1'b0;
        end else if (!request_valid_r || read_req_ready_i) begin
            request_valid_r <= request_prepare_w;
        end
    end
    always @(posedge clk_i) begin
        if (request_prepare_w) begin
            request_addr_r <= (select_w == 2'd0) ? residual_addr_r
                : (select_w == 2'd1) ? load_addr_r : model_addr_r;
            request_beats_r <= (select_w == 2'd0) ? residual_beats_r
                : (select_w == 2'd1) ? line_beats_w : model_beats_r;
            request_tag_r <= read_tag_w;
        end
    end
    // Qualify each priority winner directly; do not decode the shared request mux
    // back into counter enables on the APB ABORT-to-request path.
    assign line_accept_w = !stop_i && (!request_valid_r || read_req_ready_i)
        && !residual_candidate_w && line_candidate_w;
    assign model_accept_w = !stop_i && (!request_valid_r || read_req_ready_i)
        && !residual_candidate_w && !line_candidate_w && model_candidate_w;
    assign residual_accept_w = !stop_i && (!request_valid_r || read_req_ready_i)
        && residual_candidate_w;
    assign line_row_last_w = (load_pair_r + {6'd0, line_beats_w} == input_row_beats_w)
        && (load_plane_r == cin_blocks_w - 6'd1);
    assign model_record_last_w = model_burst_last_r
        && ((model_state_r == S_MODEL_LUT) ||
        ((model_state_r == S_MODEL_QUANT) && !unused_flags_w[6]));
    assign residual_read_last_w = residual_burst_last_r
        && (residual_half_r || residual_plane_r);
    always @(*) begin
        select_w = 2'd2;
        read_tag_w = 32'd0;
        if (residual_candidate_w) begin
            select_w = 2'd0;
            read_tag_w[31:29] = ROLE_RESIDUAL;
            read_tag_w[28] = residual_read_last_w;
            read_tag_w[7:3] = residual_sent_r;
            read_tag_w[2] = residual_plane_r;
            read_tag_w[1] = residual_half_r;
            read_tag_w[0] = residual_bank_r;
        end else if (line_candidate_w) begin
            select_w = 2'd1;
            read_tag_w[31:29] = ROLE_LINE;
            read_tag_w[28] = line_row_last_w;
            read_tag_w[13:11] = load_slot_r;
            read_tag_w[10] = !unused_flags_w[8] && load_pair_r[0];
            read_tag_w[9:0] = slot_base_r[load_slot_r] + load_plane_base_r
                + (unused_flags_w[8] ? {load_pair_r[8:0], 1'b0} : load_pair_r[10:1]);
        end else begin
            read_tag_w[31:29] = (model_state_r == S_MODEL_WEIGHT) ? ROLE_WEIGHT
                : (model_state_r == S_MODEL_QUANT) ? ROLE_QUANT : ROLE_LUT;
            read_tag_w[28] = model_record_last_w;
            if (model_state_r == S_MODEL_WEIGHT) begin
                read_tag_w[13:0] = weight_index_r;
            end else begin
                read_tag_w[7:4] = record_index_r;
                read_tag_w[2:0] = model_block_r;
            end
        end
    end

    // All signals entering the datapath come from state or payload registers.
    assign dp_cfg_valid_w = cfg_valid_r;
    assign dp_cfg_k3_w = unused_flags_w[4];
    assign dp_cfg_s2_w = unused_flags_w[5];
    assign dp_cfg_in_c4_w = unused_flags_w[8];
    assign dp_cfg_half_tail_w = unused_flags_w[9];
    assign dp_cfg_lut_en_w = unused_flags_w[6];
    assign dp_cfg_res_en_w = unused_flags_w[7];
    assign dp_cfg_out_zp_w = desc_r[343:336];
    assign dp_cfg_in_w_w = in_w_w;
    assign dp_cfg_out_w_w = out_w_w;
    assign dp_cfg_cin_blocks_w = cin_blocks_w;
    assign dp_cfg_cout_blocks_w = cout_blocks_w;
    assign dp_cfg_k_count_w = desc_r[378:368];
    assign dp_issue_enable_w = active_r && !stop_i;
    assign dp_quant_wr_valid_w = quant_valid_r;
    assign dp_quant_wr_block_w = quant_block_r;
    assign dp_quant_wr_channel_w = quant_channel_r;
    assign dp_quant_wr_bias_w = quant_bias_r;
    assign dp_quant_wr_mult_w = quant_mult_r;
    assign dp_quant_wr_shift_w = quant_shift_r;
    assign dp_lut_wr_valid_w = lut_valid_r;
    assign dp_lut_wr_block_w = lut_block_r;
    assign dp_lut_wr_addr_w = lut_addr_r;
    assign dp_lut_wr_data_w = lut_data_r;
    assign dp_line_wr_valid_w = line_valid_r && !stop_i;
    assign dp_line_wr_bank_w = line_bank_r;
    assign dp_line_wr_addr_w = line_addr_r;
    assign dp_line_wr_data_w = line_data_r;
    assign dp_line_wr_row_last_w = line_last_r;
    assign dp_cmd_valid_w = cmd_valid_r && !stop_i;
    assign dp_cmd_row_w = cmd_row_r;
    assign dp_cmd_block_w = cmd_block_r;
    assign dp_cmd_weight_base_w = cmd_weight_base_r;
    assign dp_cmd_row_base0_w = cmd_base0_r;
    assign dp_cmd_row_base1_w = cmd_base1_r;
    assign dp_cmd_row_base2_w = cmd_base2_r;
    assign dp_cmd_row_valid_w = cmd_row_valid_r;
    assign mac_beat_o = dp_mac_beat_w;
    assign input_wait_o = active_r && !all_submitted_r && !rows_ready_w;
    assign model_wait_o = active_r && !all_submitted_r && !block_ready_r[schedule_block_r];
    assign done_o = active_r && all_submitted_r && !cmd_valid_r && dp_idle_w && writer_idle_o;
    assign response_role_w = read_data_tag_i[31:29];
    assign response_record_w = {1'b0, read_data_tag_i[7:4]} + {1'b0, read_data_index_i};
    assign response_line_pair_w = {4'd0, read_data_tag_i[10]}
        + {1'b0, read_data_index_i};
    assign unused_response_residual_pair_w = read_data_tag_i[7:3] + {1'b0, read_data_index_i};
    assign read_data_ready_o = (response_role_w == ROLE_LINE)
        ? (!line_valid_r || dp_line_wr_ready_w)
        : (((response_role_w == ROLE_QUANT) || (response_role_w == ROLE_LUT))
        ? !serial_valid_r : 1'b1);
    assign response_accept_w = read_data_valid_i && read_data_ready_o && !stop_i;
    assign line_take_w = dp_line_wr_valid_w && dp_line_wr_ready_w;

    // Model beats retain their global pool index; quant/LUT beats serialize locally.
    reg weight_valid_r;
    reg [13:0] weight_addr_r;
    reg [255:0] weight_data_r;
    assign dp_weight_wr_valid_w = weight_valid_r;
    assign dp_weight_wr_addr_w = weight_addr_r;
    assign dp_weight_wr_data_w = weight_data_r;
    always @(posedge clk_i or negedge rst_n_i[1]) begin
        if (!rst_n_i[1]) begin
            cfg_valid_r <= 1'b0;
            active_r <= 1'b0;
            model_state_r <= S_MODEL_DONE;
            model_block_r <= 3'd0;
            weight_index_r <= 14'd0;
            record_index_r <= 4'd0;
            block_ready_r <= 8'd0;
            block_finish_r <= 2'd0;
            serial_valid_r <= 1'b0;
            serial_phase_r <= 5'd0;
            quant_valid_r <= 1'b0;
            lut_valid_r <= 1'b0;
            weight_valid_r <= 1'b0;
        end else if (cancel_i[1]) begin
            cfg_valid_r <= 1'b0;
            active_r <= 1'b0;
            model_state_r <= S_MODEL_DONE;
            block_ready_r <= 8'd0;
            block_finish_r <= 2'd0;
            serial_valid_r <= 1'b0;
            quant_valid_r <= 1'b0;
            lut_valid_r <= 1'b0;
            weight_valid_r <= 1'b0;
        end else begin
            quant_valid_r <= 1'b0;
            lut_valid_r <= 1'b0;
            weight_valid_r <= response_accept_w && (response_role_w == ROLE_WEIGHT);
            if (start_i[0]) begin
                cfg_valid_r <= 1'b1;
                model_block_r <= 3'd0;
                weight_index_r <= 14'd0;
                record_index_r <= 4'd0;
                model_state_r <= S_MODEL_WEIGHT;
                block_ready_r <= 8'd0;
            end
            if (cfg_valid_r && dp_cfg_ready_w) begin
                cfg_valid_r <= 1'b0;
                active_r <= 1'b1;
            end
            if (done_o) begin
                active_r <= 1'b0;
            end
            if (model_accept_w) begin
                if (model_state_r == S_MODEL_WEIGHT) begin
                    weight_index_r <= weight_index_r + {9'd0, model_beats_r};
                    if (model_burst_last_r) begin
                        model_state_r <= S_MODEL_QUANT;
                        record_index_r <= 4'd0;
                    end
                end else begin
                    record_index_r <= record_index_r + model_beats_r[3:0];
                    if (model_burst_last_r) begin
                        if ((model_state_r == S_MODEL_QUANT) && unused_flags_w[6]) begin
                            model_state_r <= S_MODEL_LUT;
                            record_index_r <= 4'd8;
                        end else if ({1'b0, model_block_r} == cout_blocks_w - 4'd1) begin
                            model_state_r <= S_MODEL_DONE;
                        end else begin
                            model_block_r <= model_block_r + 3'd1;
                            model_state_r <= S_MODEL_WEIGHT;
                            weight_index_r <= weight_index_r;
                        end
                    end
                end
            end
            if (response_accept_w && ((response_role_w == ROLE_QUANT)
                || (response_role_w == ROLE_LUT))) begin
                serial_valid_r <= 1'b1;
                serial_phase_r <= 5'd0;
            end else if (serial_valid_r) begin
                quant_valid_r <= !serial_lut_r;
                lut_valid_r <= serial_lut_r;
                serial_phase_r <= serial_phase_r + 5'd1;
                if ((!serial_lut_r && (serial_phase_r == 5'd3))
                    || (serial_lut_r && (serial_phase_r == 5'd31))) begin
                    serial_valid_r <= 1'b0;
                    if (serial_last_r) begin
                        block_finish_r <= 2'd3;
                    end
                end
            end
            if (block_finish_r != 2'd0) begin
                block_finish_r <= block_finish_r - 2'd1;
                if (block_finish_r == 2'd1) begin
                    block_ready_r[block_finish_idx_r] <= 1'b1;
                end
            end
        end
    end
    always @(posedge clk_i) begin
        if (start_i[1]) begin
            model_addr_r <= weight_addr_i;
        end else if (model_accept_w) begin
            model_addr_r <= model_boundary_addr_r;
            if ((model_state_r == S_MODEL_WEIGHT)
                && model_burst_last_r) begin
                model_addr_r <= model_quant_addr_r;
            end else if ((model_state_r == S_MODEL_QUANT) && model_burst_last_r
                && unused_flags_w[6]) begin
                model_addr_r <= model_lut_addr_r;
            end else if (model_record_last_w) begin
                model_addr_r <= model_next_weight_addr_r;
            end
        end
        if (response_accept_w) begin
            if (response_role_w == ROLE_WEIGHT) begin
                weight_addr_r <= read_data_tag_i[13:0] + {10'd0, read_data_index_i};
                weight_data_r <= read_data_i;
            end
            if ((response_role_w == ROLE_QUANT) || (response_role_w == ROLE_LUT)) begin
                serial_data_r <= read_data_i;
                serial_lut_r <= (response_role_w == ROLE_LUT);
                serial_base_r <= (response_role_w == ROLE_LUT)
                    ? {response_record_w[2:0], 5'd0} : {response_record_w[4:0], 3'd0} >> 1;
                serial_block_r <= read_data_tag_i[2:0];
                serial_last_r <= read_data_tag_i[28] && read_data_last_i;
                if (read_data_tag_i[28] && read_data_last_i) begin
                    block_finish_idx_r <= read_data_tag_i[2:0];
                end
            end
        end
        if (serial_valid_r) begin
            serial_data_r <= serial_lut_r ? {8'd0, serial_data_r[255:8]}
                : {64'd0, serial_data_r[255:64]};
            quant_block_r <= serial_block_r;
            quant_channel_r <= serial_base_r[4:0] + serial_phase_r;
            quant_bias_r <= serial_data_r[31:0];
            quant_mult_r <= serial_data_r[47:32];
            quant_shift_r <= serial_data_r[53:48];
            lut_block_r <= serial_block_r;
            lut_addr_r <= serial_base_r + {3'd0, serial_phase_r};
            lut_data_r <= serial_data_r[7:0];
        end
    end

    // Remaining is request payload. START captures the initial count separately;
    // the registered configuration handshake initializes the live counter before
    // requests become valid. Cancellation only controls valid/state.
    always @(posedge clk_i) begin
        if (cfg_valid_r && dp_cfg_ready_w) begin
            model_remaining_r <= model_burst_remaining(model_first_boundary_beats_r,
                model_first_count_r);
        end else if (model_accept_w) begin
            model_remaining_r <= (model_remaining_r > 15'd16)
                ? model_remaining_r - 15'd16 : 15'd0;
            if (model_burst_last_r) begin
                if (model_state_r == S_MODEL_WEIGHT) begin
                    model_remaining_r <= model_quant_remaining_r;
                end else if ((model_state_r == S_MODEL_QUANT) && unused_flags_w[6]) begin
                    model_remaining_r <= model_lut_remaining_r;
                end else if ({1'b0, model_block_r} != cout_blocks_w - 4'd1) begin
                    model_remaining_r <= model_burst_remaining(model_next_weight_boundary_beats_r,
                        model_next_weight_count_r);
                end
            end
        end
    end

    // Only bits [8:5] affect the next burst boundary. Compute their modular
    // address sum alongside the full pointer, then register the boundary count.
    assign model_next_weight_offset_w = model_weight_base_r[8:5]
        + weight_block_bytes_w[8:5];
    // Spec 5.4: prepare model segment transitions independently of arbitration/ABORT.
    // These plans settle during the preceding weight/parameter segment.
    always @(posedge clk_i) begin
        // Keep the complete address addition independent of request/START selection.
        model_next_weight_addr_r <= model_weight_base_r + {12'd0, weight_block_bytes_w};
        model_next_weight_boundary_beats_r <= 5'd16 - {1'b0, model_next_weight_offset_w};
        model_quant_beats_r <= burst_beats(model_quant_addr_r, 15'd8);
        model_quant_remaining_r <= burst_remaining(model_quant_addr_r, 15'd8);
        model_quant_last_r <= burst_last(model_quant_addr_r, 15'd8);
        model_lut_beats_r <= burst_beats(model_lut_addr_r, 15'd8);
        model_lut_remaining_r <= burst_remaining(model_lut_addr_r, 15'd8);
        model_lut_last_r <= burst_last(model_lut_addr_r, 15'd8);
        if (start_i[2]) begin
            model_first_count_r <= (desc_i[9] && !desc_i[8]
                && (desc_i[331:328] == 4'd1))
                ? {1'b0, desc_i[403:390]} : desc_i[403:389];
            model_first_boundary_beats_r <= 5'd16 - {1'b0, weight_addr_i[8:5]};
            model_quant_addr_r <= quant_addr_i;
            model_quant_boundary_r <= burst_boundary(quant_addr_i);
            model_lut_addr_r <= quant_addr_i + 32'd256;
            model_weight_base_r <= weight_addr_i;
            model_next_weight_count_r <= (desc_i[9] && !desc_i[8]
                && (desc_i[331:328] == 4'd2))
                ? {1'b0, desc_i[403:390]} : desc_i[403:389];
        end
        if (cfg_valid_r && dp_cfg_ready_w) begin
            model_lut_boundary_r <= burst_boundary(model_lut_addr_r);
            model_beats_r <= (model_first_count_r < {10'd0, model_first_boundary_beats_r})
                ? model_first_count_r[4:0] : model_first_boundary_beats_r;
            model_burst_last_r <= model_first_count_r <= {10'd0, model_first_boundary_beats_r};
            model_boundary_addr_r <= burst_boundary(model_addr_r);
        end else if (model_accept_w) begin
            model_beats_r <= (model_remaining_r < 15'd16)
                ? model_remaining_r[4:0] : 5'd16;
            model_burst_last_r <= model_remaining_r <= 15'd16;
            model_boundary_addr_r <= model_boundary_addr_r + 32'd512;
            if (model_burst_last_r) begin
                if (model_state_r == S_MODEL_WEIGHT) begin
                    model_beats_r <= model_quant_beats_r;
                    model_burst_last_r <= model_quant_last_r;
                    model_boundary_addr_r <= model_quant_boundary_r;
                end else if ((model_state_r == S_MODEL_QUANT) && unused_flags_w[6]) begin
                    model_beats_r <= model_lut_beats_r;
                    model_burst_last_r <= model_lut_last_r;
                    model_boundary_addr_r <= model_lut_boundary_r;
                end else begin
                    model_quant_addr_r <= model_quant_addr_r + 32'd512;
                    model_quant_boundary_r <= model_quant_boundary_r + 32'd512;
                    model_lut_addr_r <= model_lut_addr_r + 32'd512;
                    model_lut_boundary_r <= model_lut_boundary_r + 32'd512;
                    model_weight_base_r <= model_next_weight_addr_r;
                    // Advance the count one block ahead of the burst planner.
                    model_next_weight_count_r <= model_future_weight_count_w;
                    model_beats_r <= (model_next_weight_count_r
                        < {10'd0, model_next_weight_boundary_beats_r})
                        ? model_next_weight_count_r[4:0] : model_next_weight_boundary_beats_r;
                    model_burst_last_r <= model_next_weight_count_r
                        <= {10'd0, model_next_weight_boundary_beats_r};
                    model_boundary_addr_r <= burst_boundary(model_next_weight_addr_r);
                end
            end
        end
    end

    // W1/W4b: a row occupies its slot until the last output block has passed A3.
    always @(posedge clk_i or negedge rst_n_i[2]) begin
        if (!rst_n_i[2]) begin
            line_valid_r <= 1'b0;
            completed_write_ptr_r <= 3'd0;
            completed_read_ptr_r <= 3'd0;
            slot_used_r <= 5'd0;
            slot_ready_r <= 5'd0;
            load_row_r <= 13'd0;
            load_slot_r <= 3'd0;
            load_plane_r <= 6'd0;
            load_pair_r <= 11'd0;
            retire_min_r <= 13'd0;
        end else if (cancel_i[2]) begin
            line_valid_r <= 1'b0;
            completed_write_ptr_r <= 3'd0;
            completed_read_ptr_r <= 3'd0;
            slot_used_r <= 5'd0;
            slot_ready_r <= 5'd0;
        end else begin
            if (!line_valid_r || dp_line_wr_ready_w) begin
                line_valid_r <= response_accept_w && (response_role_w == ROLE_LINE);
            end
            if (start_i[3]) begin
                slot_used_r <= 5'd0;
                slot_ready_r <= 5'd0;
                load_row_r <= 13'd0;
                load_slot_r <= 3'd0;
                load_plane_r <= 6'd0;
                load_pair_r <= 11'd0;
                retire_min_r <= 13'd0;
            end
            for (slot_idx = 0; slot_idx < 5; slot_idx = slot_idx + 1) begin
                if (slot_used_r[slot_idx] && ({1'b0, slot_row_r[slot_idx]} < retire_min_r)) begin
                    slot_used_r[slot_idx] <= 1'b0;
                    slot_ready_r[slot_idx] <= 1'b0;
                end
            end
            if (dp_cmd_read_done_w &&
                ({1'b0, dp_cmd_read_done_block_w} == cout_blocks_w - 4'd1)) begin
                retire_min_r <= (({1'b0, dp_cmd_read_done_row_w} + 13'd1) << unused_flags_w[5])
                    - (unused_flags_w[4] ? 13'd1 : 13'd0);
            end
            if (line_accept_w) begin
                slot_used_r[load_slot_r] <= 1'b1;
                if (load_pair_r + {6'd0, line_beats_w} == input_row_beats_w) begin
                    load_pair_r <= 11'd0;
                    if (load_plane_r == cin_blocks_w - 6'd1) begin
                        load_plane_r <= 6'd0;
                        load_row_r <= load_row_r
                            + ((!unused_flags_w[4] && unused_flags_w[5]) ? 13'd2 : 13'd1);
                        load_slot_r <= (load_slot_r == (unused_flags_w[4] ? 3'd4 : 3'd1))
                            ? 3'd0 : load_slot_r + 3'd1;
                    end else begin
                        load_plane_r <= load_plane_r + 6'd1;
                    end
                end else begin
                    load_pair_r <= load_pair_r + {6'd0, line_beats_w};
                end
            end
            if (line_take_w && line_last_r) begin
                completed_write_ptr_r <= completed_write_ptr_r + 3'd1;
            end
            if (dp_line_wr_row_done_w) begin
                slot_ready_r[completed_slot_r[completed_read_ptr_r]] <= 1'b1;
                completed_read_ptr_r <= completed_read_ptr_r + 3'd1;
            end
        end
    end
    // Descriptor shadow -> plane base -> load pointer: one addition per stage.
    // Independent plane/row bases also permit consecutive single-burst rows.
    assign load_next_plane_addr_w = load_plane_addr_r + desc_r[95:64];
    assign load_next_row_addr_w = load_row_addr_r
        + (input_row_bytes_w << (!unused_flags_w[4] && unused_flags_w[5]));
    always @(posedge clk_i) begin
        if (start_i[3]) begin
            for (slot_base_idx = 0; slot_base_idx < 5; slot_base_idx = slot_base_idx + 1) begin
                slot_base_r[slot_base_idx] <= slot_base_idx[9:0] * desc_i[361:352];
            end
            load_row_addr_r <= in_addr_i;
            load_addr_r <= in_addr_i;
            load_plane_addr_r <= in_addr_i;
            load_plane_base_r <= 10'd0;
        end
        if (line_accept_w) begin
            slot_row_r[load_slot_r] <= load_row_r[11:0];
            load_addr_r <= load_addr_r + {22'd0, line_beats_w, 5'd0};
            if (load_pair_r + {6'd0, line_beats_w} == input_row_beats_w) begin
                if (load_plane_r == cin_blocks_w - 6'd1) begin
                    load_row_addr_r <= load_next_row_addr_w;
                    load_addr_r <= load_next_row_addr_w;
                    load_plane_addr_r <= load_next_row_addr_w;
                    load_plane_base_r <= 10'd0;
                end else begin
                    load_addr_r <= load_next_plane_addr_w;
                    load_plane_addr_r <= load_next_plane_addr_w;
                    load_plane_base_r <= load_plane_base_r + in_w_w[11:2];
                end
            end
        end
        if (response_accept_w && (response_role_w == ROLE_LINE)) begin
            line_data_r <= read_data_i;
            line_bank_r <= !unused_flags_w[8] && response_line_pair_w[0];
            line_addr_r <= read_data_tag_i[9:0] + (unused_flags_w[8]
                ? {5'd0, read_data_index_i, 1'b0} : {6'd0, response_line_pair_w[4:1]});
            line_last_r <= read_data_tag_i[28] && read_data_last_i;
            line_slot_r <= read_data_tag_i[13:11];
        end
        if (line_take_w && line_last_r) begin
            completed_slot_r[completed_write_ptr_r] <= line_slot_r;
        end
    end

    // Prepare the next context before the current command retires; no WB/B barrier here.
    always @(*) begin
        rows_ready_w = 1'b1;
        schedule_row_valid_w = 3'd0;
        required_row_w = 14'sd0;
        row_found_w = 1'b0;
        for (row_idx = 0; row_idx < 3; row_idx = row_idx + 1) begin
            schedule_base_w[row_idx] = 10'd0;
            if (unused_flags_w[4] || (row_idx == 0)) begin
                required_row_w = $signed({2'd0, schedule_row_r} << unused_flags_w[5])
                    + $signed(row_idx[13:0]) - (unused_flags_w[4] ? 14'sd1 : 14'sd0);
                row_found_w = 1'b0;
                if ((required_row_w >= 14'sd0) && (required_row_w < $signed({2'd0, in_h_w}))) begin
                    for (scan_idx = 0; scan_idx < 5; scan_idx = scan_idx + 1) begin
                        if (slot_used_r[scan_idx] && slot_ready_r[scan_idx]
                            && (slot_row_r[scan_idx] == required_row_w[11:0])) begin
                            schedule_base_w[row_idx] = slot_base_r[scan_idx];
                            row_found_w = 1'b1;
                        end
                    end
                    schedule_row_valid_w[row_idx] = row_found_w;
                    rows_ready_w = rows_ready_w && row_found_w;
                end
            end
        end
    end
    assign cmd_prepare_w = active_r && !all_submitted_r && !stop_i
        && (!cmd_valid_r || dp_cmd_ready_w) && rows_ready_w && block_ready_r[schedule_block_r];
    always @(posedge clk_i or negedge rst_n_i[3]) begin
        if (!rst_n_i[3]) begin
            cmd_valid_r <= 1'b0;
            schedule_row_r <= 12'd0;
            schedule_block_r <= 3'd0;
            all_submitted_r <= 1'b0;
        end else if (cancel_i[3]) begin
            cmd_valid_r <= 1'b0;
            all_submitted_r <= 1'b0;
        end else begin
            if (dp_cmd_ready_w) begin
                cmd_valid_r <= 1'b0;
            end
            if (start_i[1]) begin
                schedule_row_r <= 12'd0;
                schedule_block_r <= 3'd0;
                all_submitted_r <= 1'b0;
            end
            if (cmd_prepare_w) begin
                cmd_valid_r <= 1'b1;
                if ({1'b0, schedule_block_r} == cout_blocks_w - 4'd1) begin
                    schedule_block_r <= 3'd0;
                    if (schedule_row_r == out_h_w - 12'd1) begin
                        all_submitted_r <= 1'b1;
                    end else begin
                        schedule_row_r <= schedule_row_r + 12'd1;
                    end
                end else begin
                    schedule_block_r <= schedule_block_r + 3'd1;
                end
            end
        end
    end
    always @(posedge clk_i) begin
        if (start_i[2]) begin
            schedule_weight_base_r <= 11'd0;
        end
        if (cmd_prepare_w) begin
            cmd_row_r <= schedule_row_r;
            cmd_block_r <= schedule_block_r;
            cmd_weight_base_r <= schedule_weight_base_r;
            cmd_base0_r <= schedule_base_w[0];
            cmd_base1_r <= schedule_base_w[1];
            cmd_base2_r <= schedule_base_w[2];
            cmd_row_valid_r <= schedule_row_valid_w;
            schedule_weight_base_r <= ({1'b0, schedule_block_r} == cout_blocks_w - 4'd1)
                ? 11'd0 : schedule_weight_base_r + weight_block_bytes_w[18:8];
        end
    end

    // W6: two committed half-regions, loaded in the same row/block/pair order as A1.
    assign dp_residual_begin_valid_w = active_r && unused_flags_w[7] && !stop_i
        && (residual_state_r == S_RES_BEGIN);
    assign dp_residual_begin_bank_w = residual_bank_r;
    assign dp_residual_begin_pairs_w = residual_pairs_r;
    assign dp_residual_begin_half_w = residual_half_r;
    assign dp_residual_wr_valid_w = residual_wr_valid_r;
    assign dp_residual_wr_bank_w = residual_wr_bank_r;
    assign dp_residual_wr_index_w = residual_wr_index_r;
    assign dp_residual_wr_data_w = residual_wr_data_r;
    assign dp_residual_commit_w = residual_commit_r;
    assign residual_finish_block_w = residual_finish_block_r;
    assign residual_next_half_w = unused_flags_w[9]
        && ({1'b0, residual_block_r} == cout_blocks_w - 4'd2);
    assign residual_next_pairs_w = residual_finish_block_w ? output_row_pairs_w
        : output_row_pairs_w - residual_pair_r - {6'd0, residual_pairs_r};
    always @(posedge clk_i or negedge rst_n_i[0]) begin
        if (!rst_n_i[0]) begin
            residual_state_r <= S_RES_DONE;
            residual_bank_r <= 1'b0;
            residual_row_r <= 12'd0;
            residual_block_r <= 3'd0;
            residual_pair_r <= 11'd0;
            residual_pairs_r <= 5'd0;
            residual_plane_r <= 1'b0;
            residual_sent_r <= 5'd0;
            residual_wr_valid_r <= 1'b0;
            residual_commit_r <= 1'b0;
        end else if (cancel_i[0]) begin
            residual_state_r <= S_RES_DONE;
            residual_wr_valid_r <= 1'b0;
            residual_commit_r <= 1'b0;
        end else begin
            residual_wr_valid_r <= response_accept_w && (response_role_w == ROLE_RESIDUAL);
            residual_commit_r <= response_accept_w && (response_role_w == ROLE_RESIDUAL)
                && read_data_tag_i[28] && read_data_last_i;
            if (start_i[3]) begin
                residual_state_r <= desc_i[7] ? S_RES_BEGIN : S_RES_DONE;
                residual_bank_r <= 1'b0;
                residual_row_r <= 12'd0;
                residual_block_r <= 3'd0;
                residual_pair_r <= 11'd0;
                residual_plane_r <= 1'b0;
                residual_sent_r <= 5'd0;
                residual_pairs_r <= (desc_i[299:289] <
                    ((desc_i[9] && (desc_i[331:328] == 4'd1)) ? 11'd16 : 11'd8))
                    ? desc_i[293:289]
                    : ((desc_i[9] && (desc_i[331:328] == 4'd1)) ? 5'd16 : 5'd8);
            end
            if (residual_begin_w) begin
                residual_state_r <= S_RES_READ;
            end
            if (residual_accept_w) begin
                residual_sent_r <= residual_sent_r + residual_beats_r;
                if (residual_burst_last_r) begin
                    residual_sent_r <= 5'd0;
                    if (residual_half_r || residual_plane_r) begin
                        residual_state_r <= S_RES_WAIT;
                    end else begin
                        residual_plane_r <= 1'b1;
                    end
                end
            end
            if (residual_commit_r) begin
                residual_bank_r <= !residual_bank_r;
                residual_plane_r <= 1'b0;
                residual_state_r <= S_RES_BEGIN;
                if (residual_finish_block_w) begin
                    residual_pair_r <= 11'd0;
                    if ({1'b0, residual_block_r} == cout_blocks_w - 4'd1) begin
                        residual_block_r <= 3'd0;
                        residual_row_r <= residual_row_r + 12'd1;
                        residual_pairs_r <= (output_row_pairs_w <
                            ((unused_flags_w[9] && (cout_blocks_w == 4'd1)) ? 11'd16 : 11'd8))
                            ? output_row_pairs_w[4:0]
                            : ((unused_flags_w[9] && (cout_blocks_w == 4'd1)) ? 5'd16 : 5'd8);
                        if (residual_row_r == out_h_w - 12'd1) begin
                            residual_state_r <= S_RES_DONE;
                        end
                    end else begin
                        residual_block_r <= residual_block_r + 3'd1;
                        residual_pairs_r <= (output_row_pairs_w <
                            (residual_next_half_w ? 11'd16 : 11'd8))
                            ? output_row_pairs_w[4:0] : (residual_next_half_w ? 5'd16 : 5'd8);
                    end
                end else begin
                    residual_pair_r <= residual_pair_r + {6'd0, residual_pairs_r};
                    residual_pairs_r <= (residual_next_pairs_w <
                        (residual_half_r ? 11'd16 : 11'd8)) ? residual_next_pairs_w[4:0]
                        : (residual_half_r ? 5'd16 : 5'd8);
                end
            end
        end
    end
    always @(posedge clk_i) begin
        if (start_i[0]) begin
            residual_half_r <= desc_i[9] && (desc_i[331:328] == 4'd1);
            residual_row_addr_r <= residual_addr_i;
            residual_block_addr_r <= residual_addr_i;
            residual_addr_r <= residual_addr_i;
        end else if (residual_accept_w) begin
            residual_addr_r <= residual_boundary_addr_r;
            if (residual_burst_last_r && !residual_half_r && !residual_plane_r) begin
                residual_addr_r <= residual_second_addr_r;
            end
        end
        if (residual_commit_r) begin
            if (residual_finish_block_w) begin
                if ({1'b0, residual_block_r} == cout_blocks_w - 4'd1) begin
                    residual_row_addr_r <= residual_next_row_addr_r;
                    residual_block_addr_r <= residual_next_row_addr_r;
                    residual_addr_r <= residual_next_row_addr_r;
                    residual_half_r <= unused_flags_w[9] && (cout_blocks_w == 4'd1);
                end else begin
                    residual_block_addr_r <= residual_next_block_addr_r;
                    residual_addr_r <= residual_next_block_addr_r;
                    residual_half_r <= residual_next_half_w;
                end
            end else begin
                residual_addr_r <= residual_next_chunk_addr_r;
            end
        end
        if (response_accept_w && (response_role_w == ROLE_RESIDUAL)) begin
            residual_wr_data_r <= read_data_i;
            residual_wr_bank_r <= read_data_tag_i[0];
            residual_wr_index_r <= read_data_tag_i[1] ? unused_response_residual_pair_w[3:0]
                : {unused_response_residual_pair_w[2:0], read_data_tag_i[2]};
        end
    end

    assign residual_begin_w = dp_residual_begin_valid_w && dp_residual_begin_ready_w;
    assign residual_second_addr_w = residual_addr_r + desc_r[159:128];
    // A half-region has at most 16 pairs, so each C16 plane needs at most two bursts.
    // BEGIN prepares plane zero and registers the plane-one address. The last
    // plane-zero acceptance prepares plane one's burst, keeping its address sum
    // out of the burst-length/remaining path without inserting request bubbles.
    always @(posedge clk_i) begin
        residual_next_row_addr_r <= residual_row_addr_r + output_row_bytes_w;
        residual_next_block_addr_r <= residual_block_addr_r + (desc_r[159:128] << 1);
        // The registered response cannot commit a half-region until after BEGIN.
        residual_finish_block_r <= residual_chunk_end_pair_r == output_row_pairs_w;
        if (residual_begin_w) begin
            residual_chunk_end_pair_r <= residual_pair_r + {6'd0, residual_pairs_r};
            residual_beats_r <= burst_beats(residual_addr_r, {10'd0, residual_pairs_r});
            residual_remaining_r <= residual_burst_remaining(residual_addr_r,
                residual_pairs_r);
            residual_burst_last_r <= burst_last(residual_addr_r, {10'd0, residual_pairs_r});
            residual_boundary_addr_r <= burst_boundary(residual_addr_r);
            residual_second_addr_r <= residual_second_addr_w;
            residual_next_chunk_addr_r <= residual_addr_r + {22'd0, residual_pairs_r, 5'd0};
        end else if (residual_accept_w) begin
            residual_beats_r <= residual_remaining_r;
            residual_remaining_r <= 5'd0;
            residual_burst_last_r <= 1'b1;
            if (residual_burst_last_r && !residual_half_r && !residual_plane_r) begin
                residual_beats_r <= burst_beats(residual_second_addr_r,
                    {10'd0, residual_pairs_r});
                residual_remaining_r <= residual_burst_remaining(residual_second_addr_r,
                    residual_pairs_r);
                residual_burst_last_r <= burst_last(residual_second_addr_r,
                    {10'd0, residual_pairs_r});
                residual_boundary_addr_r <= burst_boundary(residual_second_addr_r);
            end
        end
    end

    // Chunk DMA owns result entries until the last accepted stream beat.
    edrv32_npu_conv_write u_conv_write (
        // Clocks and domain-local resets.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i[2]),

        // Execution lifetime.
        .stop_i(stop_i),
        .cancel_i(cancel_i[1]),
        .start_i(start_i[1]),

        // Descriptor configuration and execution status.
        .out_addr_i(out_addr_i),
        .out_plane_stride_i(desc_r[159:128]),
        .out_w_i(out_w_w),
        .cout_blocks_i(cout_blocks_w),

        // Result chunks and synchronous RAM reads.
        .result_chunk_valid_i(dp_result_chunk_valid_w),
        .result_chunk_ready_o(dp_result_chunk_ready_w),
        .result_chunk_base_i(dp_result_chunk_base_w),
        .result_chunk_pairs_i(dp_result_chunk_pairs_w),
        .result_chunk_block_i(dp_result_chunk_block_w),
        .result_chunk_pair_i(dp_result_chunk_pair_w),
        .result_chunk_half_i(dp_result_chunk_half_w),
        .result_chunk_last_i(dp_result_chunk_last_w),
        .result_rd_en_o(dp_result_rd_en_w),
        .result_rd_index_o(dp_result_rd_index_w),
        .result_rd_plane_o(dp_result_rd_plane_w),
        .result_rd_valid_i(dp_result_rd_valid_w),
        .result_rd_data_i(dp_result_rd_data_w),
        .result_release_o(dp_result_release_w),

        // Write DMA requests and data.
        .write_req_valid_o(write_req_valid_o),
        .write_req_ready_i(write_req_ready_i),
        .write_req_addr_o(write_req_addr_o),
        .write_req_beats_o(write_req_beats_o),
        .write_data_valid_o(write_data_valid_o),
        .write_data_ready_i(write_data_ready_i),
        .write_data_o(write_data_o),
        .write_stream_idle_i(write_stream_idle_i),

        // Descriptor configuration and execution status.
        .idle_o(writer_idle_o)
    );
    edrv32_npu_datapath u_datapath (
        // Clocks and domain-local resets.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i[3]),

        // Execution lifetime.
        .cancel_i(cancel_i[2]),

        // Layer configuration.
        .cfg_k3_i(dp_cfg_k3_w),
        .cfg_s2_i(dp_cfg_s2_w),
        .cfg_in_c4_i(dp_cfg_in_c4_w),
        .cfg_half_tail_i(dp_cfg_half_tail_w),
        .cfg_lut_en_i(dp_cfg_lut_en_w),
        .cfg_res_en_i(dp_cfg_res_en_w),
        .cfg_out_zp_i(dp_cfg_out_zp_w),
        .cfg_in_w_i(dp_cfg_in_w_w),
        .cfg_out_w_i(dp_cfg_out_w_w),
        .cfg_cin_blocks_i(dp_cfg_cin_blocks_w),
        .cfg_cout_blocks_i(dp_cfg_cout_blocks_w),
        .cfg_k_count_i(dp_cfg_k_count_w),
        .cfg_valid_i(dp_cfg_valid_w),
        .cfg_ready_o(dp_cfg_ready_w),

        // Input row loading and completion.
        .line_wr_valid_i(dp_line_wr_valid_w),
        .line_wr_ready_o(dp_line_wr_ready_w),
        .line_wr_bank_i(dp_line_wr_bank_w),
        .line_wr_addr_i(dp_line_wr_addr_w),
        .line_wr_data_i(dp_line_wr_data_w),
        .line_wr_row_last_i(dp_line_wr_row_last_w),
        .line_wr_row_done_o(dp_line_wr_row_done_w),
        .line_wr_idle_o(unused_dp_line_wr_idle_w),

        // Resident weights.
        .weight_wr_valid_i(dp_weight_wr_valid_w),
        .weight_wr_addr_i(dp_weight_wr_addr_w),
        .weight_wr_data_i(dp_weight_wr_data_w),

        // Quantization parameter loading.
        .quant_wr_valid_i(dp_quant_wr_valid_w),
        .quant_wr_block_i(dp_quant_wr_block_w),
        .quant_wr_channel_i(dp_quant_wr_channel_w),
        .quant_wr_bias_i(dp_quant_wr_bias_w),
        .quant_wr_mult_i(dp_quant_wr_mult_w),
        .quant_wr_shift_i(dp_quant_wr_shift_w),

        // Activation table loading.
        .lut_wr_valid_i(dp_lut_wr_valid_w),
        .lut_wr_block_i(dp_lut_wr_block_w),
        .lut_wr_addr_i(dp_lut_wr_addr_w),
        .lut_wr_data_i(dp_lut_wr_data_w),

        // Ordered CONV commands and issue control.
        .cmd_valid_i(dp_cmd_valid_w),
        .cmd_row_i(dp_cmd_row_w),
        .cmd_block_i(dp_cmd_block_w),
        .cmd_weight_base_i(dp_cmd_weight_base_w),
        .cmd_row_base0_i(dp_cmd_row_base0_w),
        .cmd_row_base1_i(dp_cmd_row_base1_w),
        .cmd_row_base2_i(dp_cmd_row_base2_w),
        .cmd_row_valid_i(dp_cmd_row_valid_w),
        .cmd_ready_o(dp_cmd_ready_w),
        .issue_enable_i(dp_issue_enable_w),

        // Residual batches and scatter writes.
        .residual_begin_valid_i(dp_residual_begin_valid_w),
        .residual_begin_ready_o(dp_residual_begin_ready_w),
        .residual_begin_bank_i(dp_residual_begin_bank_w),
        .residual_begin_pairs_i(dp_residual_begin_pairs_w),
        .residual_begin_half_i(dp_residual_begin_half_w),
        .residual_wr_valid_i(dp_residual_wr_valid_w),
        .residual_wr_bank_i(dp_residual_wr_bank_w),
        .residual_wr_index_i(dp_residual_wr_index_w),
        .residual_wr_data_i(dp_residual_wr_data_w),
        .residual_commit_i(dp_residual_commit_w),

        // Result chunks and synchronous RAM reads.
        .result_credit_o(unused_dp_result_credit_w),
        .result_chunk_valid_o(dp_result_chunk_valid_w),
        .result_chunk_ready_i(dp_result_chunk_ready_w),
        .result_chunk_base_o(dp_result_chunk_base_w),
        .result_chunk_pairs_o(dp_result_chunk_pairs_w),
        .result_chunk_row_o(unused_dp_result_chunk_row_w),
        .result_chunk_block_o(dp_result_chunk_block_w),
        .result_chunk_pair_o(dp_result_chunk_pair_w),
        .result_chunk_half_o(dp_result_chunk_half_w),
        .result_chunk_last_o(dp_result_chunk_last_w),
        .result_release_i(dp_result_release_w),
        .result_rd_en_i(dp_result_rd_en_w),
        .result_rd_index_i(dp_result_rd_index_w),
        .result_rd_plane_i(dp_result_rd_plane_w),
        .result_rd_valid_o(dp_result_rd_valid_w),
        .result_rd_data_o(dp_result_rd_data_w),

        // Ordered CONV commands and issue control.
        .cmd_issued_o(unused_dp_cmd_issued_w),
        .cmd_issued_row_o(unused_dp_cmd_issued_row_w),
        .cmd_issued_block_o(unused_dp_cmd_issued_block_w),
        .cmd_read_done_o(dp_cmd_read_done_w),
        .cmd_read_done_row_o(dp_cmd_read_done_row_w),
        .cmd_read_done_block_o(dp_cmd_read_done_block_w),
        .cmd_done_o(unused_dp_cmd_done_w),
        .cmd_done_row_o(unused_dp_cmd_done_row_w),
        .cmd_done_block_o(unused_dp_cmd_done_block_w),

        // Descriptor configuration and execution status.
        .idle_o(dp_idle_w),
        .mac_beat_o(dp_mac_beat_w)
    );
endmodule
