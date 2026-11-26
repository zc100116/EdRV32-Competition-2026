// File: edrv32_gpu_texture.v
// Spec: gpu-spec 2.6, 2.12; GPU microarchitecture 4.2, 4.4, 4.6, 4.8.
// Description: Per-lane LOD, ordered bank scheduling, palette expansion, filtering
// and vertex modulation. Reserved contexts retain all in-flight RAM results.
// Clock: clk_gpu.
module edrv32_gpu_texture (
    // Clock and command lifetime.
    input wire clk_i,
    input wire rst_n_i,
    input wire finish_i,
    input wire stop_i,
    output reg unit_done_o,

    // Frozen render state snapshot.
    input wire render_state_valid_i,
    output wire render_state_ready_o,
    input wire [255:0] render_state_tex_i,
    input wire [255:0] render_state_pixel_i,
    input wire [255:0] render_state_target_i,
    input wire render_state_wide_i,

    // Four ordered pixels from perspective.
    input wire sample_valid_i,
    output wire sample_ready_o,
    input wire [15:0] sample_x_i,
    input wire [15:0] sample_y_i,
    input wire [3:0] sample_mask_i,
    input wire sample_quad_i,
    input wire [127:0] sample_u_i,
    input wire [127:0] sample_v_i,
    input wire [383:0] sample_span_i,
    input wire [63:0] sample_depth_i,
    input wire [95:0] sample_color_i,
    input wire [3:0] sample_palette_i,
    input wire [7:0] sample_alpha_i,

    // Ordered group after filtering and shading.
    output wire shaded_valid_o,
    input wire shaded_ready_i,
    output wire [15:0] shaded_x_o,
    output wire [15:0] shaded_y_o,
    output wire [3:0] shaded_mask_o,
    output wire [63:0] shaded_depth_o,
    output wire [95:0] shaded_color_o,
    output wire [31:0] shaded_alpha_o,

    // Internal RAM ports: bank-major, two ports per bank, five-cycle reads.
    output wire [7:0] texture_read_en_o,
    output reg [119:0] texture_read_addr_o,
    input wire [127:0] texture_read_data_i,

    // Internal full/current palette ports, four-cycle reads.
    output wire full_read_en_o,
    output reg [47:0] full_read_idx_o,
    input wire [79:0] full_read_data_i,
    output wire current_read_en_o,
    output reg [63:0] current_read_idx_o,
    input wire [159:0] current_read_data_i,
    output wire perf_texture_stall_o
);
    wire [31:0] unused_address_scaled_u0_0_wide_w;
    wire [31:0] unused_address_scaled_v0_0_wide_w;
    wire [31:0] unused_address_scaled_u0_1_wide_w;
    wire [31:0] unused_address_scaled_v0_1_wide_w;
    wire [31:0] unused_address_scaled_u1_0_wide_w;
    wire [31:0] unused_address_scaled_v1_0_wide_w;
    wire [31:0] unused_address_scaled_u1_1_wide_w;
    wire [31:0] unused_address_scaled_v1_1_wide_w;
    wire [31:0] unused_address_scaled_u2_0_wide_w;
    wire [31:0] unused_address_scaled_v2_0_wide_w;
    wire [31:0] unused_address_scaled_u2_1_wide_w;
    wire [31:0] unused_address_scaled_v2_1_wide_w;
    wire [31:0] unused_address_scaled_u3_0_wide_w;
    wire [31:0] unused_address_scaled_v3_0_wide_w;
    wire [31:0] unused_address_scaled_u3_1_wide_w;
    wire [31:0] unused_address_scaled_v3_1_wide_w;
    reg [4:0] address_slot_0_r;
    reg [31:0] address_u0_r;
    reg [31:0] address_v0_r;
    reg [3:0] address_level0_r;
    reg [3:0] address_next_level0_r;
    reg [16:0] address_scaled_u0_0_r;
    reg [16:0] address_scaled_v0_0_r;
    reg [8:0] address_mask_x0_0_r;
    reg [8:0] address_mask_y0_0_r;
    reg [16:0] address_offset0_0_r;
    reg [3:0] address_row_shift0_0_r;
    reg [15:0] address_fraction0_0_r;
    reg [8:0] address_x0_0_0_r;
    reg [8:0] address_y0_0_0_r;
    wire [8:0] address_block_x0_0_0_w;
    wire [8:0] address_block_y0_0_0_w;
    reg [3:0] address_row_shift0_0_d2_r;
    reg [16:0] unused_address_row0_0_0_r;
    wire [7:0] address_column0_0_0_w;
    reg [1:0] address_bank0_0_0_r;
    reg [3:0] address_subword0_0_0_r;
    reg [16:0] address_offset0_0_d2_r;
    reg [16:0] unused_address_offset0_0_d3_r;
    reg [7:0] address_column0_0_0_w_d3_r;
    reg [16:0] address_halfword0_0_0_r;
    reg [3:0] address_subword0_0_0_d4_r;
    wire [20:0] address_record0_0_0_w;
    reg [8:0] address_x0_0_1_r;
    reg [8:0] address_y0_0_1_r;
    wire [8:0] address_block_x0_0_1_w;
    wire [8:0] address_block_y0_0_1_w;
    reg [16:0] unused_address_row0_0_1_r;
    wire [7:0] address_column0_0_1_w;
    reg [1:0] address_bank0_0_1_r;
    reg [3:0] address_subword0_0_1_r;
    reg [7:0] address_column0_0_1_w_d3_r;
    reg [16:0] address_halfword0_0_1_r;
    reg [3:0] address_subword0_0_1_d4_r;
    wire [20:0] address_record0_0_1_w;
    reg [8:0] address_x0_0_2_r;
    reg [8:0] address_y0_0_2_r;
    wire [8:0] address_block_x0_0_2_w;
    wire [8:0] address_block_y0_0_2_w;
    reg [16:0] unused_address_row0_0_2_r;
    wire [7:0] address_column0_0_2_w;
    reg [1:0] address_bank0_0_2_r;
    reg [3:0] address_subword0_0_2_r;
    reg [7:0] address_column0_0_2_w_d3_r;
    reg [16:0] address_halfword0_0_2_r;
    reg [3:0] address_subword0_0_2_d4_r;
    wire [20:0] address_record0_0_2_w;
    reg [8:0] address_x0_0_3_r;
    reg [8:0] address_y0_0_3_r;
    wire [8:0] address_block_x0_0_3_w;
    wire [8:0] address_block_y0_0_3_w;
    reg [16:0] unused_address_row0_0_3_r;
    wire [7:0] address_column0_0_3_w;
    reg [1:0] address_bank0_0_3_r;
    reg [3:0] address_subword0_0_3_r;
    reg [7:0] address_column0_0_3_w_d3_r;
    reg [16:0] address_halfword0_0_3_r;
    reg [3:0] address_subword0_0_3_d4_r;
    wire [20:0] address_record0_0_3_w;
    reg [8:0] address_x0_0_4_r;
    reg [8:0] address_y0_0_4_r;
    wire [8:0] address_block_x0_0_4_w;
    wire [8:0] address_block_y0_0_4_w;
    reg [16:0] unused_address_row0_0_4_r;
    wire [7:0] address_column0_0_4_w;
    reg [1:0] address_bank0_0_4_r;
    reg [3:0] address_subword0_0_4_r;
    reg [7:0] address_column0_0_4_w_d3_r;
    reg [16:0] address_halfword0_0_4_r;
    reg [3:0] address_subword0_0_4_d4_r;
    wire [20:0] address_record0_0_4_w;
    reg [31:0] address_u0_r_d1_r;
    reg [16:0] address_scaled_u0_1_r;
    reg [31:0] address_v0_r_d1_r;
    reg [16:0] address_scaled_v0_1_r;
    reg [8:0] address_mask_x0_1_r;
    reg [8:0] address_mask_y0_1_r;
    reg [16:0] address_offset0_1_r;
    reg [3:0] address_row_shift0_1_r;
    reg [15:0] address_fraction0_1_r;
    reg [8:0] address_x0_1_0_r;
    reg [8:0] address_y0_1_0_r;
    wire [8:0] address_block_x0_1_0_w;
    wire [8:0] address_block_y0_1_0_w;
    reg [3:0] address_row_shift0_1_d3_r;
    reg [16:0] unused_address_row0_1_0_r;
    wire [7:0] address_column0_1_0_w;
    reg [1:0] address_bank0_1_0_r;
    reg [3:0] address_subword0_1_0_r;
    reg [16:0] address_offset0_1_d3_r;
    reg [16:0] unused_address_offset0_1_d4_r;
    reg [7:0] address_column0_1_0_w_d4_r;
    reg [16:0] address_halfword0_1_0_r;
    reg [3:0] address_subword0_1_0_d5_r;
    wire [20:0] address_record0_1_0_w;
    reg [8:0] address_x0_1_1_r;
    reg [8:0] address_y0_1_1_r;
    wire [8:0] address_block_x0_1_1_w;
    wire [8:0] address_block_y0_1_1_w;
    reg [16:0] unused_address_row0_1_1_r;
    wire [7:0] address_column0_1_1_w;
    reg [1:0] address_bank0_1_1_r;
    reg [3:0] address_subword0_1_1_r;
    reg [7:0] address_column0_1_1_w_d4_r;
    reg [16:0] address_halfword0_1_1_r;
    reg [3:0] address_subword0_1_1_d5_r;
    wire [20:0] address_record0_1_1_w;
    reg [8:0] address_x0_1_2_r;
    reg [8:0] address_y0_1_2_r;
    wire [8:0] address_block_x0_1_2_w;
    wire [8:0] address_block_y0_1_2_w;
    reg [16:0] unused_address_row0_1_2_r;
    wire [7:0] address_column0_1_2_w;
    reg [1:0] address_bank0_1_2_r;
    reg [3:0] address_subword0_1_2_r;
    reg [7:0] address_column0_1_2_w_d4_r;
    reg [16:0] address_halfword0_1_2_r;
    reg [3:0] address_subword0_1_2_d5_r;
    wire [20:0] address_record0_1_2_w;
    reg [8:0] address_x0_1_3_r;
    reg [8:0] address_y0_1_3_r;
    wire [8:0] address_block_x0_1_3_w;
    wire [8:0] address_block_y0_1_3_w;
    reg [16:0] unused_address_row0_1_3_r;
    wire [7:0] address_column0_1_3_w;
    reg [1:0] address_bank0_1_3_r;
    reg [3:0] address_subword0_1_3_r;
    reg [7:0] address_column0_1_3_w_d4_r;
    reg [16:0] address_halfword0_1_3_r;
    reg [3:0] address_subword0_1_3_d5_r;
    wire [20:0] address_record0_1_3_w;
    reg [31:0] address_u1_r;
    reg [31:0] address_v1_r;
    reg [3:0] address_level1_r;
    reg [3:0] address_next_level1_r;
    reg [16:0] address_scaled_u1_0_r;
    reg [16:0] address_scaled_v1_0_r;
    reg [8:0] address_mask_x1_0_r;
    reg [8:0] address_mask_y1_0_r;
    reg [16:0] address_offset1_0_r;
    reg [3:0] address_row_shift1_0_r;
    reg [15:0] address_fraction1_0_r;
    reg [8:0] address_x1_0_0_r;
    reg [8:0] address_y1_0_0_r;
    wire [8:0] address_block_x1_0_0_w;
    wire [8:0] address_block_y1_0_0_w;
    reg [3:0] address_row_shift1_0_d2_r;
    reg [16:0] unused_address_row1_0_0_r;
    wire [7:0] address_column1_0_0_w;
    reg [1:0] address_bank1_0_0_r;
    reg [3:0] address_subword1_0_0_r;
    reg [16:0] address_offset1_0_d2_r;
    reg [16:0] unused_address_offset1_0_d3_r;
    reg [7:0] address_column1_0_0_w_d3_r;
    reg [16:0] address_halfword1_0_0_r;
    reg [3:0] address_subword1_0_0_d4_r;
    wire [20:0] address_record1_0_0_w;
    reg [8:0] address_x1_0_1_r;
    reg [8:0] address_y1_0_1_r;
    wire [8:0] address_block_x1_0_1_w;
    wire [8:0] address_block_y1_0_1_w;
    reg [16:0] unused_address_row1_0_1_r;
    wire [7:0] address_column1_0_1_w;
    reg [1:0] address_bank1_0_1_r;
    reg [3:0] address_subword1_0_1_r;
    reg [7:0] address_column1_0_1_w_d3_r;
    reg [16:0] address_halfword1_0_1_r;
    reg [3:0] address_subword1_0_1_d4_r;
    wire [20:0] address_record1_0_1_w;
    reg [8:0] address_x1_0_2_r;
    reg [8:0] address_y1_0_2_r;
    wire [8:0] address_block_x1_0_2_w;
    wire [8:0] address_block_y1_0_2_w;
    reg [16:0] unused_address_row1_0_2_r;
    wire [7:0] address_column1_0_2_w;
    reg [1:0] address_bank1_0_2_r;
    reg [3:0] address_subword1_0_2_r;
    reg [7:0] address_column1_0_2_w_d3_r;
    reg [16:0] address_halfword1_0_2_r;
    reg [3:0] address_subword1_0_2_d4_r;
    wire [20:0] address_record1_0_2_w;
    reg [8:0] address_x1_0_3_r;
    reg [8:0] address_y1_0_3_r;
    wire [8:0] address_block_x1_0_3_w;
    wire [8:0] address_block_y1_0_3_w;
    reg [16:0] unused_address_row1_0_3_r;
    wire [7:0] address_column1_0_3_w;
    reg [1:0] address_bank1_0_3_r;
    reg [3:0] address_subword1_0_3_r;
    reg [7:0] address_column1_0_3_w_d3_r;
    reg [16:0] address_halfword1_0_3_r;
    reg [3:0] address_subword1_0_3_d4_r;
    wire [20:0] address_record1_0_3_w;
    reg [8:0] address_x1_0_4_r;
    reg [8:0] address_y1_0_4_r;
    wire [8:0] address_block_x1_0_4_w;
    wire [8:0] address_block_y1_0_4_w;
    reg [16:0] unused_address_row1_0_4_r;
    wire [7:0] address_column1_0_4_w;
    reg [1:0] address_bank1_0_4_r;
    reg [3:0] address_subword1_0_4_r;
    reg [7:0] address_column1_0_4_w_d3_r;
    reg [16:0] address_halfword1_0_4_r;
    reg [3:0] address_subword1_0_4_d4_r;
    wire [20:0] address_record1_0_4_w;
    reg [31:0] address_u1_r_d1_r;
    reg [16:0] address_scaled_u1_1_r;
    reg [31:0] address_v1_r_d1_r;
    reg [16:0] address_scaled_v1_1_r;
    reg [8:0] address_mask_x1_1_r;
    reg [8:0] address_mask_y1_1_r;
    reg [16:0] address_offset1_1_r;
    reg [3:0] address_row_shift1_1_r;
    reg [15:0] address_fraction1_1_r;
    reg [8:0] address_x1_1_0_r;
    reg [8:0] address_y1_1_0_r;
    wire [8:0] address_block_x1_1_0_w;
    wire [8:0] address_block_y1_1_0_w;
    reg [3:0] address_row_shift1_1_d3_r;
    reg [16:0] unused_address_row1_1_0_r;
    wire [7:0] address_column1_1_0_w;
    reg [1:0] address_bank1_1_0_r;
    reg [3:0] address_subword1_1_0_r;
    reg [16:0] address_offset1_1_d3_r;
    reg [16:0] unused_address_offset1_1_d4_r;
    reg [7:0] address_column1_1_0_w_d4_r;
    reg [16:0] address_halfword1_1_0_r;
    reg [3:0] address_subword1_1_0_d5_r;
    wire [20:0] address_record1_1_0_w;
    reg [8:0] address_x1_1_1_r;
    reg [8:0] address_y1_1_1_r;
    wire [8:0] address_block_x1_1_1_w;
    wire [8:0] address_block_y1_1_1_w;
    reg [16:0] unused_address_row1_1_1_r;
    wire [7:0] address_column1_1_1_w;
    reg [1:0] address_bank1_1_1_r;
    reg [3:0] address_subword1_1_1_r;
    reg [7:0] address_column1_1_1_w_d4_r;
    reg [16:0] address_halfword1_1_1_r;
    reg [3:0] address_subword1_1_1_d5_r;
    wire [20:0] address_record1_1_1_w;
    reg [8:0] address_x1_1_2_r;
    reg [8:0] address_y1_1_2_r;
    wire [8:0] address_block_x1_1_2_w;
    wire [8:0] address_block_y1_1_2_w;
    reg [16:0] unused_address_row1_1_2_r;
    wire [7:0] address_column1_1_2_w;
    reg [1:0] address_bank1_1_2_r;
    reg [3:0] address_subword1_1_2_r;
    reg [7:0] address_column1_1_2_w_d4_r;
    reg [16:0] address_halfword1_1_2_r;
    reg [3:0] address_subword1_1_2_d5_r;
    wire [20:0] address_record1_1_2_w;
    reg [8:0] address_x1_1_3_r;
    reg [8:0] address_y1_1_3_r;
    wire [8:0] address_block_x1_1_3_w;
    wire [8:0] address_block_y1_1_3_w;
    reg [16:0] unused_address_row1_1_3_r;
    wire [7:0] address_column1_1_3_w;
    reg [1:0] address_bank1_1_3_r;
    reg [3:0] address_subword1_1_3_r;
    reg [7:0] address_column1_1_3_w_d4_r;
    reg [16:0] address_halfword1_1_3_r;
    reg [3:0] address_subword1_1_3_d5_r;
    wire [20:0] address_record1_1_3_w;
    reg [31:0] address_u2_r;
    reg [31:0] address_v2_r;
    reg [3:0] address_level2_r;
    reg [3:0] address_next_level2_r;
    reg [16:0] address_scaled_u2_0_r;
    reg [16:0] address_scaled_v2_0_r;
    reg [8:0] address_mask_x2_0_r;
    reg [8:0] address_mask_y2_0_r;
    reg [16:0] address_offset2_0_r;
    reg [3:0] address_row_shift2_0_r;
    reg [15:0] address_fraction2_0_r;
    reg [8:0] address_x2_0_0_r;
    reg [8:0] address_y2_0_0_r;
    wire [8:0] address_block_x2_0_0_w;
    wire [8:0] address_block_y2_0_0_w;
    reg [3:0] address_row_shift2_0_d2_r;
    reg [16:0] unused_address_row2_0_0_r;
    wire [7:0] address_column2_0_0_w;
    reg [1:0] address_bank2_0_0_r;
    reg [3:0] address_subword2_0_0_r;
    reg [16:0] address_offset2_0_d2_r;
    reg [16:0] unused_address_offset2_0_d3_r;
    reg [7:0] address_column2_0_0_w_d3_r;
    reg [16:0] address_halfword2_0_0_r;
    reg [3:0] address_subword2_0_0_d4_r;
    wire [20:0] address_record2_0_0_w;
    reg [8:0] address_x2_0_1_r;
    reg [8:0] address_y2_0_1_r;
    wire [8:0] address_block_x2_0_1_w;
    wire [8:0] address_block_y2_0_1_w;
    reg [16:0] unused_address_row2_0_1_r;
    wire [7:0] address_column2_0_1_w;
    reg [1:0] address_bank2_0_1_r;
    reg [3:0] address_subword2_0_1_r;
    reg [7:0] address_column2_0_1_w_d3_r;
    reg [16:0] address_halfword2_0_1_r;
    reg [3:0] address_subword2_0_1_d4_r;
    wire [20:0] address_record2_0_1_w;
    reg [8:0] address_x2_0_2_r;
    reg [8:0] address_y2_0_2_r;
    wire [8:0] address_block_x2_0_2_w;
    wire [8:0] address_block_y2_0_2_w;
    reg [16:0] unused_address_row2_0_2_r;
    wire [7:0] address_column2_0_2_w;
    reg [1:0] address_bank2_0_2_r;
    reg [3:0] address_subword2_0_2_r;
    reg [7:0] address_column2_0_2_w_d3_r;
    reg [16:0] address_halfword2_0_2_r;
    reg [3:0] address_subword2_0_2_d4_r;
    wire [20:0] address_record2_0_2_w;
    reg [8:0] address_x2_0_3_r;
    reg [8:0] address_y2_0_3_r;
    wire [8:0] address_block_x2_0_3_w;
    wire [8:0] address_block_y2_0_3_w;
    reg [16:0] unused_address_row2_0_3_r;
    wire [7:0] address_column2_0_3_w;
    reg [1:0] address_bank2_0_3_r;
    reg [3:0] address_subword2_0_3_r;
    reg [7:0] address_column2_0_3_w_d3_r;
    reg [16:0] address_halfword2_0_3_r;
    reg [3:0] address_subword2_0_3_d4_r;
    wire [20:0] address_record2_0_3_w;
    reg [8:0] address_x2_0_4_r;
    reg [8:0] address_y2_0_4_r;
    wire [8:0] address_block_x2_0_4_w;
    wire [8:0] address_block_y2_0_4_w;
    reg [16:0] unused_address_row2_0_4_r;
    wire [7:0] address_column2_0_4_w;
    reg [1:0] address_bank2_0_4_r;
    reg [3:0] address_subword2_0_4_r;
    reg [7:0] address_column2_0_4_w_d3_r;
    reg [16:0] address_halfword2_0_4_r;
    reg [3:0] address_subword2_0_4_d4_r;
    wire [20:0] address_record2_0_4_w;
    reg [31:0] address_u2_r_d1_r;
    reg [16:0] address_scaled_u2_1_r;
    reg [31:0] address_v2_r_d1_r;
    reg [16:0] address_scaled_v2_1_r;
    reg [8:0] address_mask_x2_1_r;
    reg [8:0] address_mask_y2_1_r;
    reg [16:0] address_offset2_1_r;
    reg [3:0] address_row_shift2_1_r;
    reg [15:0] address_fraction2_1_r;
    reg [8:0] address_x2_1_0_r;
    reg [8:0] address_y2_1_0_r;
    wire [8:0] address_block_x2_1_0_w;
    wire [8:0] address_block_y2_1_0_w;
    reg [3:0] address_row_shift2_1_d3_r;
    reg [16:0] unused_address_row2_1_0_r;
    wire [7:0] address_column2_1_0_w;
    reg [1:0] address_bank2_1_0_r;
    reg [3:0] address_subword2_1_0_r;
    reg [16:0] address_offset2_1_d3_r;
    reg [16:0] unused_address_offset2_1_d4_r;
    reg [7:0] address_column2_1_0_w_d4_r;
    reg [16:0] address_halfword2_1_0_r;
    reg [3:0] address_subword2_1_0_d5_r;
    wire [20:0] address_record2_1_0_w;
    reg [8:0] address_x2_1_1_r;
    reg [8:0] address_y2_1_1_r;
    wire [8:0] address_block_x2_1_1_w;
    wire [8:0] address_block_y2_1_1_w;
    reg [16:0] unused_address_row2_1_1_r;
    wire [7:0] address_column2_1_1_w;
    reg [1:0] address_bank2_1_1_r;
    reg [3:0] address_subword2_1_1_r;
    reg [7:0] address_column2_1_1_w_d4_r;
    reg [16:0] address_halfword2_1_1_r;
    reg [3:0] address_subword2_1_1_d5_r;
    wire [20:0] address_record2_1_1_w;
    reg [8:0] address_x2_1_2_r;
    reg [8:0] address_y2_1_2_r;
    wire [8:0] address_block_x2_1_2_w;
    wire [8:0] address_block_y2_1_2_w;
    reg [16:0] unused_address_row2_1_2_r;
    wire [7:0] address_column2_1_2_w;
    reg [1:0] address_bank2_1_2_r;
    reg [3:0] address_subword2_1_2_r;
    reg [7:0] address_column2_1_2_w_d4_r;
    reg [16:0] address_halfword2_1_2_r;
    reg [3:0] address_subword2_1_2_d5_r;
    wire [20:0] address_record2_1_2_w;
    reg [8:0] address_x2_1_3_r;
    reg [8:0] address_y2_1_3_r;
    wire [8:0] address_block_x2_1_3_w;
    wire [8:0] address_block_y2_1_3_w;
    reg [16:0] unused_address_row2_1_3_r;
    wire [7:0] address_column2_1_3_w;
    reg [1:0] address_bank2_1_3_r;
    reg [3:0] address_subword2_1_3_r;
    reg [7:0] address_column2_1_3_w_d4_r;
    reg [16:0] address_halfword2_1_3_r;
    reg [3:0] address_subword2_1_3_d5_r;
    wire [20:0] address_record2_1_3_w;
    reg [31:0] address_u3_r;
    reg [31:0] address_v3_r;
    reg [3:0] address_level3_r;
    reg [3:0] address_next_level3_r;
    reg [16:0] address_scaled_u3_0_r;
    reg [16:0] address_scaled_v3_0_r;
    reg [8:0] address_mask_x3_0_r;
    reg [8:0] address_mask_y3_0_r;
    reg [16:0] address_offset3_0_r;
    reg [3:0] address_row_shift3_0_r;
    reg [15:0] address_fraction3_0_r;
    reg [8:0] address_x3_0_0_r;
    reg [8:0] address_y3_0_0_r;
    wire [8:0] address_block_x3_0_0_w;
    wire [8:0] address_block_y3_0_0_w;
    reg [3:0] address_row_shift3_0_d2_r;
    reg [16:0] unused_address_row3_0_0_r;
    wire [7:0] address_column3_0_0_w;
    reg [1:0] address_bank3_0_0_r;
    reg [3:0] address_subword3_0_0_r;
    reg [16:0] address_offset3_0_d2_r;
    reg [16:0] unused_address_offset3_0_d3_r;
    reg [7:0] address_column3_0_0_w_d3_r;
    reg [16:0] address_halfword3_0_0_r;
    reg [3:0] address_subword3_0_0_d4_r;
    wire [20:0] address_record3_0_0_w;
    reg [8:0] address_x3_0_1_r;
    reg [8:0] address_y3_0_1_r;
    wire [8:0] address_block_x3_0_1_w;
    wire [8:0] address_block_y3_0_1_w;
    reg [16:0] unused_address_row3_0_1_r;
    wire [7:0] address_column3_0_1_w;
    reg [1:0] address_bank3_0_1_r;
    reg [3:0] address_subword3_0_1_r;
    reg [7:0] address_column3_0_1_w_d3_r;
    reg [16:0] address_halfword3_0_1_r;
    reg [3:0] address_subword3_0_1_d4_r;
    wire [20:0] address_record3_0_1_w;
    reg [8:0] address_x3_0_2_r;
    reg [8:0] address_y3_0_2_r;
    wire [8:0] address_block_x3_0_2_w;
    wire [8:0] address_block_y3_0_2_w;
    reg [16:0] unused_address_row3_0_2_r;
    wire [7:0] address_column3_0_2_w;
    reg [1:0] address_bank3_0_2_r;
    reg [3:0] address_subword3_0_2_r;
    reg [7:0] address_column3_0_2_w_d3_r;
    reg [16:0] address_halfword3_0_2_r;
    reg [3:0] address_subword3_0_2_d4_r;
    wire [20:0] address_record3_0_2_w;
    reg [8:0] address_x3_0_3_r;
    reg [8:0] address_y3_0_3_r;
    wire [8:0] address_block_x3_0_3_w;
    wire [8:0] address_block_y3_0_3_w;
    reg [16:0] unused_address_row3_0_3_r;
    wire [7:0] address_column3_0_3_w;
    reg [1:0] address_bank3_0_3_r;
    reg [3:0] address_subword3_0_3_r;
    reg [7:0] address_column3_0_3_w_d3_r;
    reg [16:0] address_halfword3_0_3_r;
    reg [3:0] address_subword3_0_3_d4_r;
    wire [20:0] address_record3_0_3_w;
    reg [8:0] address_x3_0_4_r;
    reg [8:0] address_y3_0_4_r;
    wire [8:0] address_block_x3_0_4_w;
    wire [8:0] address_block_y3_0_4_w;
    reg [16:0] unused_address_row3_0_4_r;
    wire [7:0] address_column3_0_4_w;
    reg [1:0] address_bank3_0_4_r;
    reg [3:0] address_subword3_0_4_r;
    reg [7:0] address_column3_0_4_w_d3_r;
    reg [16:0] address_halfword3_0_4_r;
    reg [3:0] address_subword3_0_4_d4_r;
    wire [20:0] address_record3_0_4_w;
    reg [31:0] address_u3_r_d1_r;
    reg [16:0] address_scaled_u3_1_r;
    reg [31:0] address_v3_r_d1_r;
    reg [16:0] address_scaled_v3_1_r;
    reg [8:0] address_mask_x3_1_r;
    reg [8:0] address_mask_y3_1_r;
    reg [16:0] address_offset3_1_r;
    reg [3:0] address_row_shift3_1_r;
    reg [15:0] address_fraction3_1_r;
    reg [8:0] address_x3_1_0_r;
    reg [8:0] address_y3_1_0_r;
    wire [8:0] address_block_x3_1_0_w;
    wire [8:0] address_block_y3_1_0_w;
    reg [3:0] address_row_shift3_1_d3_r;
    reg [16:0] unused_address_row3_1_0_r;
    wire [7:0] address_column3_1_0_w;
    reg [1:0] address_bank3_1_0_r;
    reg [3:0] address_subword3_1_0_r;
    reg [16:0] address_offset3_1_d3_r;
    reg [16:0] unused_address_offset3_1_d4_r;
    reg [7:0] address_column3_1_0_w_d4_r;
    reg [16:0] address_halfword3_1_0_r;
    reg [3:0] address_subword3_1_0_d5_r;
    wire [20:0] address_record3_1_0_w;
    reg [8:0] address_x3_1_1_r;
    reg [8:0] address_y3_1_1_r;
    wire [8:0] address_block_x3_1_1_w;
    wire [8:0] address_block_y3_1_1_w;
    reg [16:0] unused_address_row3_1_1_r;
    wire [7:0] address_column3_1_1_w;
    reg [1:0] address_bank3_1_1_r;
    reg [3:0] address_subword3_1_1_r;
    reg [7:0] address_column3_1_1_w_d4_r;
    reg [16:0] address_halfword3_1_1_r;
    reg [3:0] address_subword3_1_1_d5_r;
    wire [20:0] address_record3_1_1_w;
    reg [8:0] address_x3_1_2_r;
    reg [8:0] address_y3_1_2_r;
    wire [8:0] address_block_x3_1_2_w;
    wire [8:0] address_block_y3_1_2_w;
    reg [16:0] unused_address_row3_1_2_r;
    wire [7:0] address_column3_1_2_w;
    reg [1:0] address_bank3_1_2_r;
    reg [3:0] address_subword3_1_2_r;
    reg [7:0] address_column3_1_2_w_d4_r;
    reg [16:0] address_halfword3_1_2_r;
    reg [3:0] address_subword3_1_2_d5_r;
    wire [20:0] address_record3_1_2_w;
    reg [8:0] address_x3_1_3_r;
    reg [8:0] address_y3_1_3_r;
    wire [8:0] address_block_x3_1_3_w;
    wire [8:0] address_block_y3_1_3_w;
    reg [16:0] unused_address_row3_1_3_r;
    wire [7:0] address_column3_1_3_w;
    reg [1:0] address_bank3_1_3_r;
    reg [3:0] address_subword3_1_3_r;
    reg [7:0] address_column3_1_3_w_d4_r;
    reg [16:0] address_halfword3_1_3_r;
    reg [3:0] address_subword3_1_3_d5_r;
    wire [20:0] address_record3_1_3_w;
    reg [4:0] address_slot_0_r_d1_r;
    reg [4:0] address_slot_0_r_d2_r;
    reg [4:0] address_slot_0_r_d3_r;
    reg [4:0] address_slot_0_r_d4_r;
    reg [4:0] address_slot_0_r_d5_r;
    reg [4:0] address_slot_0_r_d6_r;
    reg [20:0] address_record0_0_0_w_d5_r;
    reg [20:0] address_record0_0_1_w_d5_r;
    reg [20:0] address_record0_0_2_w_d5_r;
    reg [20:0] address_record0_0_3_w_d5_r;
    reg [20:0] address_record0_0_4_w_d5_r;
    reg [15:0] address_fraction0_0_d3_r;
    reg [15:0] address_fraction0_0_d4_r;
    reg [15:0] address_fraction0_0_d5_r;
    reg [15:0] address_fraction0_1_d4_r;
    reg [15:0] address_fraction0_1_d5_r;
    reg [20:0] address_record1_0_0_w_d5_r;
    reg [20:0] address_record1_0_1_w_d5_r;
    reg [20:0] address_record1_0_2_w_d5_r;
    reg [20:0] address_record1_0_3_w_d5_r;
    reg [20:0] address_record1_0_4_w_d5_r;
    reg [15:0] address_fraction1_0_d3_r;
    reg [15:0] address_fraction1_0_d4_r;
    reg [15:0] address_fraction1_0_d5_r;
    reg [15:0] address_fraction1_1_d4_r;
    reg [15:0] address_fraction1_1_d5_r;
    reg [20:0] address_record2_0_0_w_d5_r;
    reg [20:0] address_record2_0_1_w_d5_r;
    reg [20:0] address_record2_0_2_w_d5_r;
    reg [20:0] address_record2_0_3_w_d5_r;
    reg [20:0] address_record2_0_4_w_d5_r;
    reg [15:0] address_fraction2_0_d3_r;
    reg [15:0] address_fraction2_0_d4_r;
    reg [15:0] address_fraction2_0_d5_r;
    reg [15:0] address_fraction2_1_d4_r;
    reg [15:0] address_fraction2_1_d5_r;
    reg [20:0] address_record3_0_0_w_d5_r;
    reg [20:0] address_record3_0_1_w_d5_r;
    reg [20:0] address_record3_0_2_w_d5_r;
    reg [20:0] address_record3_0_3_w_d5_r;
    reg [20:0] address_record3_0_4_w_d5_r;
    reg [15:0] address_fraction3_0_d3_r;
    reg [15:0] address_fraction3_0_d4_r;
    reg [15:0] address_fraction3_0_d5_r;
    reg [15:0] address_fraction3_1_d4_r;
    reg [15:0] address_fraction3_1_d5_r;
    reg [6:0] address_valid_r;
    // The snapshot fields used by this unit are SET_TEX bits [91:64], [49:37].
    // The other frozen fields belong to raster/pixel and are deliberately unused.
    wire unused_state_w;
    assign unused_state_w = ^{render_state_pixel_i, render_state_target_i,
                                render_state_wide_i, render_state_tex_i[255:92],
                                render_state_tex_i[63:50], render_state_tex_i[36:0]};
    reg [3:0] log2_w_r;
    reg [3:0] log2_h_r;
    reg [1:0] format_r;
    reg [3:0] levels_r;
    reg [3:0] group_r;
    reg [1:0] mode_r;
    reg signed [7:0] bias_r;
    reg [17:0] offset_r;
    reg [5:0] allocate_r;
    reg [5:0] schedule_r;
    reg [5:0] retire_r;
    wire [5:0] occupancy_w;
    wire accept_w;
    wire retire_w;
    wire schedule_ready_w;
    wire schedule_valid_w;
    wire [4:0] schedule_slot_w;
    wire [31:0] lod_ready_w;
    wire [3:0] completed_w [0:31];

    reg [3:0] mask_r [0:31];

    reg quad_r [0:31];
    reg [3:0] palette_r [0:31];
    reg [4:0] cfg_wait_r;
    reg [1:0] batch_r;
    reg [3:0] nearest_pending_r;
    assign occupancy_w = allocate_r - retire_r;
    assign sample_ready_o = occupancy_w < 6'd32 && cfg_wait_r == 0 && !stop_i;
    assign accept_w = sample_valid_i && sample_ready_o;
    assign render_state_ready_o = occupancy_w == 0 && cfg_wait_r == 0;
    assign shaded_valid_o = occupancy_w != 0 && completed_w[retire_r[4:0]] == 4'hf
                            && !stop_i;
    assign retire_w = shaded_valid_o && shaded_ready_i;
    assign shaded_x_o = unused_retire_context_read0_w[0 +: 16];
    assign shaded_y_o = unused_retire_context_read0_w[16 +: 16];
    assign shaded_depth_o = unused_retire_context_read0_w[32 +: 64];
    assign schedule_slot_w = schedule_r[4:0];
    assign schedule_valid_w = schedule_r != allocate_r
                                && schedule_ready_w && !stop_i;

    function [8:0] log_fraction;
        input [7:0] index_i;
        begin
            case (index_i)
                8'd0: log_fraction = 9'd0;
                8'd1: log_fraction = 9'd1;
                8'd2: log_fraction = 9'd3;
                8'd3: log_fraction = 9'd4;
                8'd4: log_fraction = 9'd6;
                8'd5: log_fraction = 9'd7;
                8'd6: log_fraction = 9'd9;
                8'd7: log_fraction = 9'd10;
                8'd8: log_fraction = 9'd11;
                8'd9: log_fraction = 9'd13;
                8'd10: log_fraction = 9'd14;
                8'd11: log_fraction = 9'd16;
                8'd12: log_fraction = 9'd17;
                8'd13: log_fraction = 9'd18;
                8'd14: log_fraction = 9'd20;
                8'd15: log_fraction = 9'd21;
                8'd16: log_fraction = 9'd22;
                8'd17: log_fraction = 9'd24;
                8'd18: log_fraction = 9'd25;
                8'd19: log_fraction = 9'd26;
                8'd20: log_fraction = 9'd28;
                8'd21: log_fraction = 9'd29;
                8'd22: log_fraction = 9'd30;
                8'd23: log_fraction = 9'd32;
                8'd24: log_fraction = 9'd33;
                8'd25: log_fraction = 9'd34;
                8'd26: log_fraction = 9'd36;
                8'd27: log_fraction = 9'd37;
                8'd28: log_fraction = 9'd38;
                8'd29: log_fraction = 9'd40;
                8'd30: log_fraction = 9'd41;
                8'd31: log_fraction = 9'd42;
                8'd32: log_fraction = 9'd44;
                8'd33: log_fraction = 9'd45;
                8'd34: log_fraction = 9'd46;
                8'd35: log_fraction = 9'd47;
                8'd36: log_fraction = 9'd49;
                8'd37: log_fraction = 9'd50;
                8'd38: log_fraction = 9'd51;
                8'd39: log_fraction = 9'd52;
                8'd40: log_fraction = 9'd54;
                8'd41: log_fraction = 9'd55;
                8'd42: log_fraction = 9'd56;
                8'd43: log_fraction = 9'd57;
                8'd44: log_fraction = 9'd59;
                8'd45: log_fraction = 9'd60;
                8'd46: log_fraction = 9'd61;
                8'd47: log_fraction = 9'd62;
                8'd48: log_fraction = 9'd63;
                8'd49: log_fraction = 9'd65;
                8'd50: log_fraction = 9'd66;
                8'd51: log_fraction = 9'd67;
                8'd52: log_fraction = 9'd68;
                8'd53: log_fraction = 9'd69;
                8'd54: log_fraction = 9'd71;
                8'd55: log_fraction = 9'd72;
                8'd56: log_fraction = 9'd73;
                8'd57: log_fraction = 9'd74;
                8'd58: log_fraction = 9'd75;
                8'd59: log_fraction = 9'd77;
                8'd60: log_fraction = 9'd78;
                8'd61: log_fraction = 9'd79;
                8'd62: log_fraction = 9'd80;
                8'd63: log_fraction = 9'd81;
                8'd64: log_fraction = 9'd82;
                8'd65: log_fraction = 9'd84;
                8'd66: log_fraction = 9'd85;
                8'd67: log_fraction = 9'd86;
                8'd68: log_fraction = 9'd87;
                8'd69: log_fraction = 9'd88;
                8'd70: log_fraction = 9'd89;
                8'd71: log_fraction = 9'd90;
                8'd72: log_fraction = 9'd92;
                8'd73: log_fraction = 9'd93;
                8'd74: log_fraction = 9'd94;
                8'd75: log_fraction = 9'd95;
                8'd76: log_fraction = 9'd96;
                8'd77: log_fraction = 9'd97;
                8'd78: log_fraction = 9'd98;
                8'd79: log_fraction = 9'd99;
                8'd80: log_fraction = 9'd100;
                8'd81: log_fraction = 9'd102;
                8'd82: log_fraction = 9'd103;
                8'd83: log_fraction = 9'd104;
                8'd84: log_fraction = 9'd105;
                8'd85: log_fraction = 9'd106;
                8'd86: log_fraction = 9'd107;
                8'd87: log_fraction = 9'd108;
                8'd88: log_fraction = 9'd109;
                8'd89: log_fraction = 9'd110;
                8'd90: log_fraction = 9'd111;
                8'd91: log_fraction = 9'd112;
                8'd92: log_fraction = 9'd113;
                8'd93: log_fraction = 9'd114;
                8'd94: log_fraction = 9'd116;
                8'd95: log_fraction = 9'd117;
                8'd96: log_fraction = 9'd118;
                8'd97: log_fraction = 9'd119;
                8'd98: log_fraction = 9'd120;
                8'd99: log_fraction = 9'd121;
                8'd100: log_fraction = 9'd122;
                8'd101: log_fraction = 9'd123;
                8'd102: log_fraction = 9'd124;
                8'd103: log_fraction = 9'd125;
                8'd104: log_fraction = 9'd126;
                8'd105: log_fraction = 9'd127;
                8'd106: log_fraction = 9'd128;
                8'd107: log_fraction = 9'd129;
                8'd108: log_fraction = 9'd130;
                8'd109: log_fraction = 9'd131;
                8'd110: log_fraction = 9'd132;
                8'd111: log_fraction = 9'd133;
                8'd112: log_fraction = 9'd134;
                8'd113: log_fraction = 9'd135;
                8'd114: log_fraction = 9'd136;
                8'd115: log_fraction = 9'd137;
                8'd116: log_fraction = 9'd138;
                8'd117: log_fraction = 9'd139;
                8'd118: log_fraction = 9'd140;
                8'd119: log_fraction = 9'd141;
                8'd120: log_fraction = 9'd142;
                8'd121: log_fraction = 9'd143;
                8'd122: log_fraction = 9'd144;
                8'd123: log_fraction = 9'd145;
                8'd124: log_fraction = 9'd146;
                8'd125: log_fraction = 9'd147;
                8'd126: log_fraction = 9'd148;
                8'd127: log_fraction = 9'd149;
                8'd128: log_fraction = 9'd150;
                8'd129: log_fraction = 9'd151;
                8'd130: log_fraction = 9'd152;
                8'd131: log_fraction = 9'd153;
                8'd132: log_fraction = 9'd154;
                8'd133: log_fraction = 9'd155;
                8'd134: log_fraction = 9'd155;
                8'd135: log_fraction = 9'd156;
                8'd136: log_fraction = 9'd157;
                8'd137: log_fraction = 9'd158;
                8'd138: log_fraction = 9'd159;
                8'd139: log_fraction = 9'd160;
                8'd140: log_fraction = 9'd161;
                8'd141: log_fraction = 9'd162;
                8'd142: log_fraction = 9'd163;
                8'd143: log_fraction = 9'd164;
                8'd144: log_fraction = 9'd165;
                8'd145: log_fraction = 9'd166;
                8'd146: log_fraction = 9'd167;
                8'd147: log_fraction = 9'd168;
                8'd148: log_fraction = 9'd169;
                8'd149: log_fraction = 9'd169;
                8'd150: log_fraction = 9'd170;
                8'd151: log_fraction = 9'd171;
                8'd152: log_fraction = 9'd172;
                8'd153: log_fraction = 9'd173;
                8'd154: log_fraction = 9'd174;
                8'd155: log_fraction = 9'd175;
                8'd156: log_fraction = 9'd176;
                8'd157: log_fraction = 9'd177;
                8'd158: log_fraction = 9'd178;
                8'd159: log_fraction = 9'd178;
                8'd160: log_fraction = 9'd179;
                8'd161: log_fraction = 9'd180;
                8'd162: log_fraction = 9'd181;
                8'd163: log_fraction = 9'd182;
                8'd164: log_fraction = 9'd183;
                8'd165: log_fraction = 9'd184;
                8'd166: log_fraction = 9'd185;
                8'd167: log_fraction = 9'd185;
                8'd168: log_fraction = 9'd186;
                8'd169: log_fraction = 9'd187;
                8'd170: log_fraction = 9'd188;
                8'd171: log_fraction = 9'd189;
                8'd172: log_fraction = 9'd190;
                8'd173: log_fraction = 9'd191;
                8'd174: log_fraction = 9'd192;
                8'd175: log_fraction = 9'd192;
                8'd176: log_fraction = 9'd193;
                8'd177: log_fraction = 9'd194;
                8'd178: log_fraction = 9'd195;
                8'd179: log_fraction = 9'd196;
                8'd180: log_fraction = 9'd197;
                8'd181: log_fraction = 9'd198;
                8'd182: log_fraction = 9'd198;
                8'd183: log_fraction = 9'd199;
                8'd184: log_fraction = 9'd200;
                8'd185: log_fraction = 9'd201;
                8'd186: log_fraction = 9'd202;
                8'd187: log_fraction = 9'd203;
                8'd188: log_fraction = 9'd203;
                8'd189: log_fraction = 9'd204;
                8'd190: log_fraction = 9'd205;
                8'd191: log_fraction = 9'd206;
                8'd192: log_fraction = 9'd207;
                8'd193: log_fraction = 9'd208;
                8'd194: log_fraction = 9'd208;
                8'd195: log_fraction = 9'd209;
                8'd196: log_fraction = 9'd210;
                8'd197: log_fraction = 9'd211;
                8'd198: log_fraction = 9'd212;
                8'd199: log_fraction = 9'd212;
                8'd200: log_fraction = 9'd213;
                8'd201: log_fraction = 9'd214;
                8'd202: log_fraction = 9'd215;
                8'd203: log_fraction = 9'd216;
                8'd204: log_fraction = 9'd216;
                8'd205: log_fraction = 9'd217;
                8'd206: log_fraction = 9'd218;
                8'd207: log_fraction = 9'd219;
                8'd208: log_fraction = 9'd220;
                8'd209: log_fraction = 9'd220;
                8'd210: log_fraction = 9'd221;
                8'd211: log_fraction = 9'd222;
                8'd212: log_fraction = 9'd223;
                8'd213: log_fraction = 9'd224;
                8'd214: log_fraction = 9'd224;
                8'd215: log_fraction = 9'd225;
                8'd216: log_fraction = 9'd226;
                8'd217: log_fraction = 9'd227;
                8'd218: log_fraction = 9'd228;
                8'd219: log_fraction = 9'd228;
                8'd220: log_fraction = 9'd229;
                8'd221: log_fraction = 9'd230;
                8'd222: log_fraction = 9'd231;
                8'd223: log_fraction = 9'd231;
                8'd224: log_fraction = 9'd232;
                8'd225: log_fraction = 9'd233;
                8'd226: log_fraction = 9'd234;
                8'd227: log_fraction = 9'd234;
                8'd228: log_fraction = 9'd235;
                8'd229: log_fraction = 9'd236;
                8'd230: log_fraction = 9'd237;
                8'd231: log_fraction = 9'd238;
                8'd232: log_fraction = 9'd238;
                8'd233: log_fraction = 9'd239;
                8'd234: log_fraction = 9'd240;
                8'd235: log_fraction = 9'd241;
                8'd236: log_fraction = 9'd241;
                8'd237: log_fraction = 9'd242;
                8'd238: log_fraction = 9'd243;
                8'd239: log_fraction = 9'd244;
                8'd240: log_fraction = 9'd244;
                8'd241: log_fraction = 9'd245;
                8'd242: log_fraction = 9'd246;
                8'd243: log_fraction = 9'd247;
                8'd244: log_fraction = 9'd247;
                8'd245: log_fraction = 9'd248;
                8'd246: log_fraction = 9'd249;
                8'd247: log_fraction = 9'd249;
                8'd248: log_fraction = 9'd250;
                8'd249: log_fraction = 9'd251;
                8'd250: log_fraction = 9'd252;
                8'd251: log_fraction = 9'd252;
                8'd252: log_fraction = 9'd253;
                8'd253: log_fraction = 9'd254;
                8'd254: log_fraction = 9'd255;
                8'd255: log_fraction = 9'd255;
                default: log_fraction = 9'd0;
            endcase
        end
    endfunction
    // Four lanes: leading-one count, grouped shift, logarithm ROM and clamp.
    // Four-stage LOD path; only the eight fraction bits cross the shift boundary.
    reg [3:0] lod_valid_r;
    wire [4:0] lod_slot_r [0:3];
    reg [7:0] filter_valid_r;
    wire [4:0] filter_slot_r [0:7];
    wire [3:0] filter_done_r [0:7];
    wire [95:0] modulated_color_w;
    wire [31:0] modulated_alpha_w;
    reg [3:0] shade_mask_r;
    wire [127:0] address_input_u_w;
    wire [127:0] address_input_v_w;
    wire [15:0] unused_address_input_lod_w;
    wire [20:0] address_cache_w [0:35];
    wire [15:0] fraction_cache_w [0:7];
    wire [3:0] schedule_even_index_w;
    wire [3:0] schedule_odd_index_w;
    reg quad_even_r;
    reg quad_odd_r;
    wire launch_quad_w;
    wire [3:0] ready_quarter_w;
    assign ready_quarter_w[0] = (schedule_slot_w[2] ? (schedule_slot_w[1] ? (schedule_slot_w[0]
        ? lod_ready_w[7] :
        lod_ready_w[6]) :
        (schedule_slot_w[0] ? lod_ready_w[5] :
        lod_ready_w[4])) :
        (schedule_slot_w[1] ? (schedule_slot_w[0] ? lod_ready_w[3] :
        lod_ready_w[2]) :
        (schedule_slot_w[0] ? lod_ready_w[1] :
        lod_ready_w[0])));
    assign ready_quarter_w[1] = (schedule_slot_w[2] ? (schedule_slot_w[1] ? (schedule_slot_w[0]
        ? lod_ready_w[15] :
        lod_ready_w[14]) :
        (schedule_slot_w[0] ? lod_ready_w[13] :
        lod_ready_w[12])) :
        (schedule_slot_w[1] ? (schedule_slot_w[0] ? lod_ready_w[11] :
        lod_ready_w[10]) :
        (schedule_slot_w[0] ? lod_ready_w[9] :
        lod_ready_w[8])));
    assign ready_quarter_w[2] = (schedule_slot_w[2] ? (schedule_slot_w[1] ? (schedule_slot_w[0]
        ? lod_ready_w[23] :
        lod_ready_w[22]) :
        (schedule_slot_w[0] ? lod_ready_w[21] :
        lod_ready_w[20])) :
        (schedule_slot_w[1] ? (schedule_slot_w[0] ? lod_ready_w[19] :
        lod_ready_w[18]) :
        (schedule_slot_w[0] ? lod_ready_w[17] :
        lod_ready_w[16])));
    assign ready_quarter_w[3] = (schedule_slot_w[2] ? (schedule_slot_w[1] ? (schedule_slot_w[0]
        ? lod_ready_w[31] :
        lod_ready_w[30]) :
        (schedule_slot_w[0] ? lod_ready_w[29] :
        lod_ready_w[28])) :
        (schedule_slot_w[1] ? (schedule_slot_w[0] ? lod_ready_w[27] :
        lod_ready_w[26]) :
        (schedule_slot_w[0] ? lod_ready_w[25] :
        lod_ready_w[24])));
    assign schedule_ready_w = schedule_slot_w[4] ?
        (schedule_slot_w[3] ? ready_quarter_w[3] : ready_quarter_w[2]) :
        (schedule_slot_w[3] ? ready_quarter_w[1] : ready_quarter_w[0]);
    assign schedule_even_index_w = schedule_slot_w[4:1] + {3'b0, schedule_slot_w[0]};
    assign schedule_odd_index_w = schedule_slot_w[4:1];
    assign launch_quad_w = schedule_slot_w[0] ? quad_odd_r : quad_even_r;
    always @(posedge clk_i) begin
        quad_even_r <= quad_r[{schedule_even_index_w, 1'b0}];
        quad_odd_r <= quad_r[{schedule_odd_index_w, 1'b1}];
    end
    wire [11:0] lane_lod_w [0:3];
    genvar lane;
    generate
        for (lane = 0; lane < 4; lane = lane + 1) begin : g_lod

            reg result_mask_r [0:31];
            // Explicit LUTRAM uv_context: 1 slice(s) per combinational read port.
            wire [71:0] uv_context_input_w;
            assign uv_context_input_w =
                {8'b0, sample_v_i[lane*32 +: 32], sample_u_i[lane*32 +: 32]};
            wire [71:0] unused_uv_context_read0_w;
            edrv32_ram_gpu_table u_uv_context_p0_b0 (
                .clk_i(clk_i),
                .wr_en_i(accept_w),
                .wr_addr_i({1'b0, allocate_r[4:0]}),
                .wr_data_i(uv_context_input_w[0 +: 72]),
                .rd_addr_i({1'b0, lod_slot_r[2]}),
                .rd_data_o(unused_uv_context_read0_w[0 +: 72])
            );
            // Explicit LUTRAM lod_context: 1 slice(s) per combinational read port.
            wire [71:0] lod_context_input_w;
            assign lod_context_input_w = {60'b0, clamped_w};
            wire [71:0] unused_lod_context_read0_w;
            edrv32_ram_gpu_table u_lod_context_p0_b0 (
                .clk_i(clk_i),
                .wr_en_i(lod_valid_r[2]),
                .wr_addr_i({1'b0, lod_slot_r[2]}),
                .wr_data_i(lod_context_input_w[0 +: 72]),
                .rd_addr_i({1'b0, schedule_even_index_w, 1'b0}),
                .rd_data_o(unused_lod_context_read0_w[0 +: 72])
            );
            wire [71:0] unused_lod_context_read1_w;
            edrv32_ram_gpu_table u_lod_context_p1_b0 (
                .clk_i(clk_i),
                .wr_en_i(lod_valid_r[2]),
                .wr_addr_i({1'b0, lod_slot_r[2]}),
                .wr_data_i(lod_context_input_w[0 +: 72]),
                .rd_addr_i({1'b0, schedule_odd_index_w, 1'b1}),
                .rd_data_o(unused_lod_context_read1_w[0 +: 72])
            );
            // Explicit LUTRAM result_context: 1 slice(s) per combinational read port.
            wire [71:0] result_context_input_w;
            assign result_context_input_w =
                {40'b0, modulated_alpha_w[lane*8 +: 8], modulated_color_w[lane*24 +: 24]};
            wire [71:0] unused_result_context_read0_w;
            edrv32_ram_gpu_table u_result_context_p0_b0 (
                .clk_i(clk_i),
                .wr_en_i(filter_valid_r[7] && filter_done_r[7][lane]),
                .wr_addr_i({1'b0, filter_slot_r[7]}),
                .wr_data_i(result_context_input_w[0 +: 72]),
                .rd_addr_i({1'b0, retire_r[4:0]}),
                .rd_data_o(unused_result_context_read0_w[0 +: 72])
            );
            reg [11:0] lod_even_r;
            reg [11:0] lod_odd_r;
            assign lane_lod_w[lane] = schedule_slot_w[0] ? lod_odd_r : lod_even_r;
            assign address_input_u_w[lane*32 +: 32] = unused_uv_context_read0_w[0 +: 32];
            assign address_input_v_w[lane*32 +: 32] = unused_uv_context_read0_w[32 +: 32];
            always @(posedge clk_i) begin
                lod_even_r <= unused_lod_context_read0_w[0 +: 12];
                lod_odd_r <= unused_lod_context_read1_w[0 +: 12];
            end
            assign shaded_color_o[lane*24 +: 24] = unused_result_context_read0_w[0 +: 24];
            assign shaded_alpha_o[lane*8 +: 8] = unused_result_context_read0_w[24 +: 8];
            assign shaded_mask_o[lane] = result_mask_r[retire_r[4:0]];
            always @(posedge clk_i) begin
                if (filter_valid_r[7] && filter_done_r[7][lane]) begin

                    result_mask_r[filter_slot_r[7]] <= shade_mask_r[lane];
                end
            end
            wire high_w;
            wire [63:0] count_value_w;
            wire [7:0] group_w;
            wire [23:0] position_w;
            reg [5:0] leading_w;
            reg [63:0] count_value_r;
            reg [5:0] amount_r;
            reg [6:0] shift_r;
            reg [6:0] shift_last_r;
            reg zero_r;
            reg zero_last_r;
            wire [63:0] unused_shifted_w;
            reg [7:0] fraction_r;
            assign high_w = |sample_span_i[lane*96+64 +: 32];
            assign count_value_w = high_w ? sample_span_i[lane*96+32 +: 64]
                : sample_span_i[lane*96 +: 64];
            assign unused_shifted_w = count_value_r << amount_r;
            genvar group_idx;
                // Eight parallel 8-bit encoders and an eight-way group encoder.
                for (group_idx = 0; group_idx < 8; group_idx = group_idx + 1) begin : g_count
                    reg [2:0] position_select_w;
                    assign group_w[group_idx] = |count_value_w[group_idx*8 +: 8];
                    assign position_w[group_idx*3 +: 3] = position_select_w;
                    always @(*) begin
                        position_select_w = 0;
                        casez (count_value_w[group_idx*8 +: 8])
                            8'b1???????: position_select_w = 7;
                            8'b01??????: position_select_w = 6;
                            8'b001?????: position_select_w = 5;
                            8'b0001????: position_select_w = 4;
                            8'b00001???: position_select_w = 3;
                            8'b000001??: position_select_w = 2;
                            8'b0000001?: position_select_w = 1;
                            default: begin end
                        endcase
                    end
                end
            always @(*) begin
                leading_w = 0;
                casez (group_w)
                    8'b1???????: leading_w = {3'd7, position_w[21 +: 3]};
                    8'b01??????: leading_w = {3'd6, position_w[18 +: 3]};
                    8'b001?????: leading_w = {3'd5, position_w[15 +: 3]};
                    8'b0001????: leading_w = {3'd4, position_w[12 +: 3]};
                    8'b00001???: leading_w = {3'd3, position_w[9 +: 3]};
                    8'b000001??: leading_w = {3'd2, position_w[6 +: 3]};
                    8'b0000001?: leading_w = {3'd1, position_w[3 +: 3]};
                    8'b00000001: leading_w = {3'd0, position_w[0 +: 3]};
                    default: begin end
                endcase
            end
            reg signed [15:0] logarithm_r;
            wire signed [15:0] biased_w;
            wire signed [15:0] maximum_w;
            wire [11:0] clamped_w;
            assign biased_w = logarithm_r + ($signed({{8{bias_r[7]}}, bias_r}) <<< 4);
            assign maximum_w = $signed({4'b0, levels_r - 4'd1, 8'b0});
            assign clamped_w = biased_w < 0 ? 12'd0 :
                                biased_w > maximum_w ? maximum_w[11:0] : biased_w[11:0];
            assign unused_address_input_lod_w[lane*4 +: 4] = clamped_w[11:8];
            always @(posedge clk_i) begin
                count_value_r <= count_value_w;
                amount_r <= 6'd63 - leading_w;
                shift_r <= (high_w ? 7'd0 : 7'd32) + 7'd63 - {1'b0, leading_w};
                zero_r <= sample_span_i[lane*96 +: 96] == 0;
                fraction_r <= unused_shifted_w[62:55];
                shift_last_r <= shift_r;
                zero_last_r <= zero_r;
                logarithm_r <= zero_last_r ? 16'sd0 :
                    (16'sd79 - $signed({9'b0, shift_last_r})) * 16'sd256
                    + $signed({7'b0, log_fraction(fraction_r)});

            end
        end
    endgenerate

    // SET_TEX constants settle before sampling: dimensions take one stage per level,
    // sizes and prefix offsets take two. No mip prefix arithmetic lies on a tap path.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) cfg_wait_r <= 0;
        else if (render_state_valid_i && render_state_ready_o) cfg_wait_r <= 20;
        else if (cfg_wait_r != 0) cfg_wait_r <= cfg_wait_r - 1'b1;
    end
    wire [16:0] offset_base_w;
    assign offset_base_w = offset_r[17:1];
    wire [8:0] mip_mask_x_w [0:9];
    wire [8:0] mip_mask_y_w [0:9];
    wire [3:0] mip_row_shift_w [0:9];
    wire [16:0] mip_offset_w [0:9];
    wire [80:0] mip_width_chain_w;
    wire [80:0] mip_height_chain_w;
    wire [80:0] mip_groups_x_chain_w;
    wire [80:0] mip_groups_y_chain_w;
    wire [152:0] mip_offset_chain_w;
    genvar mip;
    generate
        for (mip = 0; mip < 10; mip = mip + 1) begin : g_mip
            localparam [3:0] RGB_ROW_LEVEL = mip + 1;
            localparam [3:0] INDEX_ROW_LEVEL = mip + 2;
            reg [8:0] mask_x_r;
            reg [8:0] mask_y_r;
            reg [3:0] row_shift_r;
            reg [8:0] unused_width_r;
            reg [8:0] unused_height_r;
            reg [8:0] unused_groups_x_r;
            reg [8:0] unused_groups_y_r;
            reg [16:0] level_offset_r;
            wire [8:0] width_w;
            wire [8:0] height_w;
            wire [8:0] groups_x_w;
            wire [8:0] groups_y_w;
            assign mip_mask_x_w[mip] = mask_x_r;
            assign mip_mask_y_w[mip] = mask_y_r;
            assign mip_row_shift_w[mip] = row_shift_r;
            assign mip_offset_w[mip] = level_offset_r;
            if (mip < 9) begin : g_chain
                assign mip_width_chain_w[mip*9 +: 9] = unused_width_r;
                assign mip_height_chain_w[mip*9 +: 9] = unused_height_r;
                assign mip_groups_x_chain_w[mip*9 +: 9] = unused_groups_x_r;
                assign mip_groups_y_chain_w[mip*9 +: 9] = unused_groups_y_r;
                assign mip_offset_chain_w[mip*17 +: 17] = level_offset_r;
            end
            // All dimensions are powers of two, including padded one-block levels.
            assign groups_x_w = format_r == 2 ?
                (width_w > 1 ? width_w >> 1 : 9'd1) :
                (width_w > 2 ? width_w >> 2 : 9'd1);
            assign groups_y_w = format_r == 0 ?
                (height_w > 2 ? height_w >> 2 : 9'd1) :
                (height_w > 1 ? height_w >> 1 : 9'd1);
            always @(posedge clk_i) begin
                mask_x_r <= width_w - 9'd1;
                mask_y_r <= height_w - 9'd1;
                row_shift_r <= format_r == 2 ?
                    (log2_w_r > RGB_ROW_LEVEL ? log2_w_r - RGB_ROW_LEVEL : 4'd0) :
                    (log2_w_r > INDEX_ROW_LEVEL ? log2_w_r - INDEX_ROW_LEVEL : 4'd0);
                unused_width_r <= width_w;
                unused_height_r <= height_w;
                unused_groups_x_r <= groups_x_w;
                unused_groups_y_r <= groups_y_w;
            end
            if (mip == 0) begin : g_first
                assign width_w = 9'd1 << log2_w_r;
                assign height_w = 9'd1 << log2_h_r;
                always @(posedge clk_i) begin
                    level_offset_r <= offset_base_w;
                end
            end else begin : g_next
                reg [16:0] size_r;
                reg [16:0] base_r;
                assign width_w = mip_width_chain_w[(mip-1)*9 +: 9] > 1 ?
                    mip_width_chain_w[(mip-1)*9 +: 9] >> 1 : 9'd1;
                assign height_w = mip_height_chain_w[(mip-1)*9 +: 9] > 1 ?
                    mip_height_chain_w[(mip-1)*9 +: 9] >> 1 : 9'd1;
                always @(posedge clk_i) begin
                    size_r <= (mip_groups_x_chain_w[(mip-1)*9 +: 9] *
                        mip_groups_y_chain_w[(mip-1)*9 +: 9]) << 2;
                    base_r <= mip_offset_chain_w[(mip-1)*17 +: 17];
                    level_offset_r <= base_r + size_r;
                end
            end
        end
    endgenerate
    wire [7:0] port_en_w;
    wire [119:0] port_row_w;
    wire [23:0] tap_port_w;
    wire [31:0] tap_subword_w;
    wire [135:0] tap_weight_w;
    wire [20:0] tap_address_w [0:7];
    wire [20:0] nearest_address_w [0:3];
    wire [20:0] filtered_tap_address_w [0:7];
    assign nearest_address_w[0] = address_cache_w[8];
    assign nearest_address_w[1] = address_cache_w[17];
    assign nearest_address_w[2] = address_cache_w[26];
    assign nearest_address_w[3] = address_cache_w[35];
    (* keep = 1 *) reg [4:0] address_read_slot0_r /* synthesis syn_preserve=1 */;
    wire [3:0] address_even_index0_w;
    wire [3:0] address_odd_index0_w;
    wire [5:0] nearest_same_w;
    wire [15:0] nearest_triple_w;
    wire [21:0] nearest_compare_w;
    wire [21:0] nearest_compare_input_w;
    assign nearest_compare_input_w[0] = address_record0_0_4_w_d5_r[16:2]
        == address_record1_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[1] = address_record0_0_4_w_d5_r[16:2]
        == address_record2_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[2] = address_record0_0_4_w_d5_r[16:2]
        == address_record3_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[3] = address_record1_0_4_w_d5_r[16:2]
        == address_record2_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[4] = address_record1_0_4_w_d5_r[16:2]
        == address_record3_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[5] = address_record2_0_4_w_d5_r[16:2]
        == address_record3_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[6] =
        address_record0_0_4_w_d5_r[1:0] == 2'd0 &&
        address_record1_0_4_w_d5_r[1:0] == 2'd0 &&
        address_record2_0_4_w_d5_r[1:0] == 2'd0 &&
        address_record0_0_4_w_d5_r[16:2] != address_record1_0_4_w_d5_r[16:2] &&
        address_record0_0_4_w_d5_r[16:2] != address_record2_0_4_w_d5_r[16:2] &&
        address_record1_0_4_w_d5_r[16:2] != address_record2_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[7] =
        address_record0_0_4_w_d5_r[1:0] == 2'd0 &&
        address_record1_0_4_w_d5_r[1:0] == 2'd0 &&
        address_record3_0_4_w_d5_r[1:0] == 2'd0 &&
        address_record0_0_4_w_d5_r[16:2] != address_record1_0_4_w_d5_r[16:2] &&
        address_record0_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2] &&
        address_record1_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[8] =
        address_record0_0_4_w_d5_r[1:0] == 2'd0 &&
        address_record2_0_4_w_d5_r[1:0] == 2'd0 &&
        address_record3_0_4_w_d5_r[1:0] == 2'd0 &&
        address_record0_0_4_w_d5_r[16:2] != address_record2_0_4_w_d5_r[16:2] &&
        address_record0_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2] &&
        address_record2_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[9] =
        address_record1_0_4_w_d5_r[1:0] == 2'd0 &&
        address_record2_0_4_w_d5_r[1:0] == 2'd0 &&
        address_record3_0_4_w_d5_r[1:0] == 2'd0 &&
        address_record1_0_4_w_d5_r[16:2] != address_record2_0_4_w_d5_r[16:2] &&
        address_record1_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2] &&
        address_record2_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[10] =
        address_record0_0_4_w_d5_r[1:0] == 2'd1 &&
        address_record1_0_4_w_d5_r[1:0] == 2'd1 &&
        address_record2_0_4_w_d5_r[1:0] == 2'd1 &&
        address_record0_0_4_w_d5_r[16:2] != address_record1_0_4_w_d5_r[16:2] &&
        address_record0_0_4_w_d5_r[16:2] != address_record2_0_4_w_d5_r[16:2] &&
        address_record1_0_4_w_d5_r[16:2] != address_record2_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[11] =
        address_record0_0_4_w_d5_r[1:0] == 2'd1 &&
        address_record1_0_4_w_d5_r[1:0] == 2'd1 &&
        address_record3_0_4_w_d5_r[1:0] == 2'd1 &&
        address_record0_0_4_w_d5_r[16:2] != address_record1_0_4_w_d5_r[16:2] &&
        address_record0_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2] &&
        address_record1_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[12] =
        address_record0_0_4_w_d5_r[1:0] == 2'd1 &&
        address_record2_0_4_w_d5_r[1:0] == 2'd1 &&
        address_record3_0_4_w_d5_r[1:0] == 2'd1 &&
        address_record0_0_4_w_d5_r[16:2] != address_record2_0_4_w_d5_r[16:2] &&
        address_record0_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2] &&
        address_record2_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[13] =
        address_record1_0_4_w_d5_r[1:0] == 2'd1 &&
        address_record2_0_4_w_d5_r[1:0] == 2'd1 &&
        address_record3_0_4_w_d5_r[1:0] == 2'd1 &&
        address_record1_0_4_w_d5_r[16:2] != address_record2_0_4_w_d5_r[16:2] &&
        address_record1_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2] &&
        address_record2_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[14] =
        address_record0_0_4_w_d5_r[1:0] == 2'd2 &&
        address_record1_0_4_w_d5_r[1:0] == 2'd2 &&
        address_record2_0_4_w_d5_r[1:0] == 2'd2 &&
        address_record0_0_4_w_d5_r[16:2] != address_record1_0_4_w_d5_r[16:2] &&
        address_record0_0_4_w_d5_r[16:2] != address_record2_0_4_w_d5_r[16:2] &&
        address_record1_0_4_w_d5_r[16:2] != address_record2_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[15] =
        address_record0_0_4_w_d5_r[1:0] == 2'd2 &&
        address_record1_0_4_w_d5_r[1:0] == 2'd2 &&
        address_record3_0_4_w_d5_r[1:0] == 2'd2 &&
        address_record0_0_4_w_d5_r[16:2] != address_record1_0_4_w_d5_r[16:2] &&
        address_record0_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2] &&
        address_record1_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[16] =
        address_record0_0_4_w_d5_r[1:0] == 2'd2 &&
        address_record2_0_4_w_d5_r[1:0] == 2'd2 &&
        address_record3_0_4_w_d5_r[1:0] == 2'd2 &&
        address_record0_0_4_w_d5_r[16:2] != address_record2_0_4_w_d5_r[16:2] &&
        address_record0_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2] &&
        address_record2_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[17] =
        address_record1_0_4_w_d5_r[1:0] == 2'd2 &&
        address_record2_0_4_w_d5_r[1:0] == 2'd2 &&
        address_record3_0_4_w_d5_r[1:0] == 2'd2 &&
        address_record1_0_4_w_d5_r[16:2] != address_record2_0_4_w_d5_r[16:2] &&
        address_record1_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2] &&
        address_record2_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[18] =
        address_record0_0_4_w_d5_r[1:0] == 2'd3 &&
        address_record1_0_4_w_d5_r[1:0] == 2'd3 &&
        address_record2_0_4_w_d5_r[1:0] == 2'd3 &&
        address_record0_0_4_w_d5_r[16:2] != address_record1_0_4_w_d5_r[16:2] &&
        address_record0_0_4_w_d5_r[16:2] != address_record2_0_4_w_d5_r[16:2] &&
        address_record1_0_4_w_d5_r[16:2] != address_record2_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[19] =
        address_record0_0_4_w_d5_r[1:0] == 2'd3 &&
        address_record1_0_4_w_d5_r[1:0] == 2'd3 &&
        address_record3_0_4_w_d5_r[1:0] == 2'd3 &&
        address_record0_0_4_w_d5_r[16:2] != address_record1_0_4_w_d5_r[16:2] &&
        address_record0_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2] &&
        address_record1_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[20] =
        address_record0_0_4_w_d5_r[1:0] == 2'd3 &&
        address_record2_0_4_w_d5_r[1:0] == 2'd3 &&
        address_record3_0_4_w_d5_r[1:0] == 2'd3 &&
        address_record0_0_4_w_d5_r[16:2] != address_record2_0_4_w_d5_r[16:2] &&
        address_record0_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2] &&
        address_record2_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2];
    assign nearest_compare_input_w[21] =
        address_record1_0_4_w_d5_r[1:0] == 2'd3 &&
        address_record2_0_4_w_d5_r[1:0] == 2'd3 &&
        address_record3_0_4_w_d5_r[1:0] == 2'd3 &&
        address_record1_0_4_w_d5_r[16:2] != address_record2_0_4_w_d5_r[16:2] &&
        address_record1_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2] &&
        address_record2_0_4_w_d5_r[16:2] != address_record3_0_4_w_d5_r[16:2];
    assign nearest_same_w = nearest_compare_w[5:0];
    assign nearest_triple_w = nearest_compare_w[21:6];
    generate
        begin : g_nearest_compare
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [21:0] even_cache_r;
            reg [21:0] odd_cache_r;
            assign nearest_compare_w = address_read_slot0_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({50'b0, nearest_compare_input_w}),
                .rd_addr_i({2'b0, address_even_index0_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({50'b0, nearest_compare_input_w}),
                .rd_addr_i({2'b0, address_odd_index0_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[21:0];
                odd_cache_r <= unused_odd_data_w[21:0];
            end
        end
    endgenerate
    wire [15:0] nearest_port_b_w;
    wire [3:0] bank_overflow_w;
    reg [1:0] request_valid_r;
    reg [4:0] request_slot_0_r;
    reg [4:0] request_slot_1_r;
    reg [1:0] request_mode_0_r;
    reg [1:0] request_mode_1_r;
    reg [1:0] request_lane_0_r;
    reg [1:0] request_lane_1_r;
    reg [3:0] request_done_0_r;
    reg [3:0] request_done_1_r;
    reg [31:0] request_subword_0_r;
    reg [31:0] request_subword_1_r;
    wire [7:0] unused_tap_accepted_w;
    wire [7:0] bank_accepted_w [0:3];
    wire [3:0] lane_done_w;
    wire [3:0] pending_w;
    wire [1:0] launch_mode_w;
    wire [1:0] launch_lane_w;
    wire [7:0] launch_fraction_w;
    wire group_issued_w;
    reg [7:0] weight_mode_pipe_r;
    reg [31:0] weight_fraction_pipe_r;
    always @(posedge clk_i) begin
        weight_mode_pipe_r <= {weight_mode_pipe_r[5:0], launch_mode_w};
        weight_fraction_pipe_r <= {weight_fraction_pipe_r[23:0], launch_fraction_w};
    end
    assign launch_mode_w = launch_quad_w ? 2'b0 : mode_r;
    assign launch_lane_w = launch_mode_w == 1 ? {batch_r[0], 1'b0} : batch_r;
    assign launch_fraction_w = lane_lod_w[launch_lane_w][7:0];
    assign lane_done_w = launch_mode_w == 0 ? unused_tap_accepted_w[3:0] :
        launch_mode_w == 1 ? 4'b0011 << launch_lane_w : 4'b0001 << launch_lane_w;
    assign pending_w = nearest_pending_r & ~lane_done_w;
    assign group_issued_w = launch_mode_w == 0 ? !(|bank_overflow_w) :
        launch_mode_w == 1 ? batch_r[0] : batch_r == 3;
    always @(*) begin
        texture_read_addr_o = port_row_w;
    end
    assign texture_read_en_o = port_en_w & {8{request_valid_r[1] && !stop_i}};
    assign perf_texture_stall_o = schedule_valid_w && launch_mode_w == 0 &&
        (|bank_overflow_w);
    genvar tap;
    genvar bank;
    generate
        for (tap = 0; tap < 8; tap = tap + 1) begin : g_tap
            localparam [1:0] NEAREST_PIXEL = tap[1:0];
            wire [1:0] pixel_w;
            wire [20:0] primary_w [0:3];
            reg [20:0] filtered_address_w;
            wire [15:0] fraction_w [0:3];
            reg [15:0] selected_fraction_w;
            genvar cache_lane;
            for (cache_lane = 0; cache_lane < 4; cache_lane = cache_lane + 1) begin : g_cache
                assign primary_w[cache_lane] = mode_r == 2 && tap >= 4 ?
                    address_cache_w[cache_lane*9+4+(tap%4)] :
                    address_cache_w[cache_lane*9+(tap%4)];
                assign fraction_w[cache_lane] = mode_r == 2 && tap >= 4 ?
                    fraction_cache_w[cache_lane*2+1] : fraction_cache_w[cache_lane*2];
            end
            assign pixel_w = mode_r == 2 ? batch_r : {batch_r[0], tap[2]};
            always @(*) begin
                filtered_address_w = primary_w[0];
                selected_fraction_w = fraction_w[0];
                case (pixel_w)
                    2'd0: begin
                        filtered_address_w = primary_w[0];
                        selected_fraction_w = fraction_w[0];
                    end
                    2'd1: begin
                        filtered_address_w = primary_w[1];
                        selected_fraction_w = fraction_w[1];
                    end
                    2'd2: begin
                        filtered_address_w = primary_w[2];
                        selected_fraction_w = fraction_w[2];
                    end
                    2'd3: begin
                        filtered_address_w = primary_w[3];
                        selected_fraction_w = fraction_w[3];
                    end
                    default: begin end
                endcase
            end
            assign filtered_tap_address_w[tap] = filtered_address_w;
            assign tap_address_w[tap] = launch_mode_w == 0 ?
                address_cache_w[NEAREST_PIXEL*9+8] : filtered_address_w;
            assign tap_subword_w[tap*4 +: 4] = tap_address_w[tap][20:17];
            wire [8:0] weight_x_w;
            wire [8:0] weight_y_w;
            wire [17:0] unused_weight_w;
            assign weight_x_w = (tap % 2) == 0 ?
                9'd256 - {1'b0, selected_fraction_w[7:0]} :
                {1'b0, selected_fraction_w[7:0]};
            assign weight_y_w = ((tap/2) % 2) == 0 ?
                9'd256 - {1'b0, selected_fraction_w[15:8]} :
                {1'b0, selected_fraction_w[15:8]};
            reg [8:0] weight_x_r;
            reg [8:0] weight_y_r;
            reg [17:0] weight_product_0_r;
            reg [17:0] weight_product_1_r;
            reg [17:0] weight_product_2_r;
            always @(posedge clk_i) begin
                weight_x_r <= weight_x_w;
                weight_y_r <= weight_y_w;
                weight_product_0_r <= weight_x_r * weight_y_r;
                weight_product_1_r <= weight_product_0_r;
                weight_product_2_r <= weight_product_1_r;
            end
            assign unused_weight_w = weight_product_2_r;
            assign tap_weight_w[tap*17 +: 17] = weight_mode_pipe_r[6 +: 2] == 0 ?
                17'd65536 : unused_weight_w[16:0];
        end
        // Nearest uses the first two distinct rows in tap order; all comparisons are parallel.
        // A bilinear footprint contains only one row per bank, so each footprint owns a port.
        for (bank = 0; bank < 4; bank = bank + 1) begin : g_bank
            wire [3:0] request_w;
            wire [3:0] first_w;
            wire [3:0] second_w;
            wire [3:0] accepted_w;
            wire [3:0] overflow_w;
            wire [5:0] same_w;
            reg [3:0] first_r;
            reg [3:0] second_r;
            wire [7:0] filter_request_r;
            reg [1:0] bank_mode_r;
            reg [14:0] row_0_r;
            reg [14:0] row_1_r;
            wire [119:0] saved_row_w;
            reg [14:0] nearest_a_w;
            reg [14:0] nearest_b_w;
            reg [14:0] filter_a_w;
            reg [14:0] filter_b_w;
            reg [1:0] en_r;
            assign port_row_w[bank*30 +: 30] = {row_1_r, row_0_r};
            assign port_en_w[bank*2 +: 2] = en_r;
            assign request_w[0] = nearest_address_w[0][1:0] == bank && nearest_pending_r[0];
            assign request_w[1] = nearest_address_w[1][1:0] == bank && nearest_pending_r[1];
            assign request_w[2] = nearest_address_w[2][1:0] == bank && nearest_pending_r[2];
            assign request_w[3] = nearest_address_w[3][1:0] == bank && nearest_pending_r[3];
            assign same_w[0] = nearest_same_w[0];
            assign same_w[1] = nearest_same_w[1];
            assign same_w[2] = nearest_same_w[2];
            assign same_w[3] = nearest_same_w[3];
            assign same_w[4] = nearest_same_w[4];
            assign same_w[5] = nearest_same_w[5];
            assign first_w[0] = request_w[0];
            assign first_w[1] = request_w[1] && !request_w[0];
            assign first_w[2] = request_w[2] && !(|request_w[1:0]);
            assign first_w[3] = request_w[3] && !(|request_w[2:0]);
            assign second_w[0] = 0;
            assign second_w[1] = request_w[1] && first_w[0] && !same_w[0];
            assign second_w[2] = request_w[2] &&
                ((first_w[0] && !same_w[1] && (!request_w[1] || same_w[0])) ||
                    (first_w[1] && !same_w[3]));
            assign second_w[3] = request_w[3] &&
                ((first_w[0] && !same_w[2] && (!request_w[1] || same_w[0]) &&
                    (!request_w[2] || same_w[1])) ||
                (first_w[1] && !same_w[4] && (!request_w[2] || same_w[3])) ||
                (first_w[2] && !same_w[5]));
            assign overflow_w[0] = nearest_pending_r[0] && nearest_pending_r[1] &&
                nearest_pending_r[2] && nearest_triple_w[bank*4+0];
            assign overflow_w[1] = nearest_pending_r[0] && nearest_pending_r[1] &&
                nearest_pending_r[3] && nearest_triple_w[bank*4+1];
            assign overflow_w[2] = nearest_pending_r[0] && nearest_pending_r[2] &&
                nearest_pending_r[3] && nearest_triple_w[bank*4+2];
            assign overflow_w[3] = nearest_pending_r[1] && nearest_pending_r[2] &&
                nearest_pending_r[3] && nearest_triple_w[bank*4+3];
            assign bank_overflow_w[bank] = |overflow_w;
            assign accepted_w[0] = request_w[0];
            assign accepted_w[1] = request_w[1];
            assign accepted_w[2] = request_w[2] && !overflow_w[0];
            assign accepted_w[3] = request_w[3] && !(overflow_w[1] ||
                (overflow_w[2] && (!request_w[1] || same_w[0] || same_w[3])) ||
                (overflow_w[3] && (!request_w[0] || same_w[0] || same_w[1])));
            assign bank_accepted_w[bank] = {4'b0, accepted_w};
            assign nearest_port_b_w[bank*4+0] = request_w[0] &&
                !((first_w[0] && 1'b1) || (first_w[1] && same_w[0]) || (first_w[2] &&
            same_w[1]) || (first_w[3] && same_w[2]));
            assign nearest_port_b_w[bank*4+1] = request_w[1] &&
                !((first_w[0] && same_w[0]) || (first_w[1] && 1'b1) || (first_w[2] &&
            same_w[3]) || (first_w[3] && same_w[4]));
            assign nearest_port_b_w[bank*4+2] = request_w[2] &&
                !((first_w[0] && same_w[1]) || (first_w[1] && same_w[3]) || (first_w[2] &&
            1'b1) || (first_w[3] && same_w[5]));
            assign nearest_port_b_w[bank*4+3] = request_w[3] &&
                !((first_w[0] && same_w[2]) || (first_w[1] && same_w[4]) || (first_w[2] &&
            same_w[5]) || (first_w[3] && 1'b1));
            always @(posedge clk_i) begin
                first_r <= first_w;
                second_r <= second_w;
                bank_mode_r <= launch_mode_w;
            end
            genvar saved_tap;
            for (saved_tap = 0; saved_tap < 8; saved_tap = saved_tap + 1) begin : g_saved
                reg [14:0] row_r;
                reg request_r;
                assign saved_row_w[saved_tap*15 +: 15] = row_r;
                always @(posedge clk_i) begin
                    row_r <= tap_address_w[saved_tap][16:2];
                    request_r <= filtered_tap_address_w[saved_tap][1:0] == bank;
                end
                assign filter_request_r[saved_tap] = request_r;
            end
            always @(*) begin
                nearest_a_w = 0;
                nearest_b_w = 0;
                filter_a_w = 0;
                filter_b_w = 0;
                nearest_a_w = nearest_a_w | ({15{first_r[0]}} & saved_row_w[0 +: 15]);
                nearest_b_w = nearest_b_w | ({15{second_r[0]}} & saved_row_w[0 +: 15]);
                filter_a_w = filter_a_w | ({15{filter_request_r[0]}} & saved_row_w[0 +: 15]);
                filter_b_w = filter_b_w | ({15{filter_request_r[4]}} & saved_row_w[60 +: 15]);
                nearest_a_w = nearest_a_w | ({15{first_r[1]}} & saved_row_w[15 +: 15]);
                nearest_b_w = nearest_b_w | ({15{second_r[1]}} & saved_row_w[15 +: 15]);
                filter_a_w = filter_a_w | ({15{filter_request_r[1]}} & saved_row_w[15 +: 15]);
                filter_b_w = filter_b_w | ({15{filter_request_r[5]}} & saved_row_w[75 +: 15]);
                nearest_a_w = nearest_a_w | ({15{first_r[2]}} & saved_row_w[30 +: 15]);
                nearest_b_w = nearest_b_w | ({15{second_r[2]}} & saved_row_w[30 +: 15]);
                filter_a_w = filter_a_w | ({15{filter_request_r[2]}} & saved_row_w[30 +: 15]);
                filter_b_w = filter_b_w | ({15{filter_request_r[6]}} & saved_row_w[90 +: 15]);
                nearest_a_w = nearest_a_w | ({15{first_r[3]}} & saved_row_w[45 +: 15]);
                nearest_b_w = nearest_b_w | ({15{second_r[3]}} & saved_row_w[45 +: 15]);
                filter_a_w = filter_a_w | ({15{filter_request_r[3]}} & saved_row_w[45 +: 15]);
                filter_b_w = filter_b_w | ({15{filter_request_r[7]}} & saved_row_w[105 +: 15]);
            end
            always @(posedge clk_i) begin
                row_0_r <= bank_mode_r == 0 ? nearest_a_w : filter_a_w;
                row_1_r <= bank_mode_r == 0 ? nearest_b_w : filter_b_w;
                en_r <= bank_mode_r == 0 ? {|second_r, |first_r} :
                    {|filter_request_r[7:4], |filter_request_r[3:0]};
            end
        end
        for (tap = 0; tap < 8; tap = tap + 1) begin : g_accepted
            assign unused_tap_accepted_w[tap] = launch_mode_w != 0 ? 1'b1 :
                bank_accepted_w[0][tap] |
                bank_accepted_w[1][tap] | bank_accepted_w[2][tap] |
                bank_accepted_w[3][tap];
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) request_valid_r <= 0;
        else if (stop_i) request_valid_r <= 0;
        else request_valid_r <= {request_valid_r[0], schedule_valid_w};
    end
    always @(posedge clk_i) begin
        request_slot_0_r <= schedule_slot_w;
        request_slot_1_r <= request_slot_0_r;
        request_mode_0_r <= launch_mode_w;
        request_mode_1_r <= request_mode_0_r;
        request_lane_0_r <= launch_lane_w;
        request_lane_1_r <= request_lane_0_r;
        request_done_0_r <= lane_done_w;
        request_done_1_r <= request_done_0_r;
        request_subword_0_r <= tap_subword_w;
        request_subword_1_r <= request_subword_0_r;
    end
    genvar request_tap;
    generate
        for (request_tap = 0; request_tap < 8;
            request_tap = request_tap + 1) begin : g_request_port
            reg [1:0] bank_r;
            reg nearest_b_r;
            reg [2:0] port_r;
            assign tap_port_w[request_tap*3 +: 3] = port_r;
            always @(posedge clk_i) begin
                bank_r <= tap_address_w[request_tap][1:0];
                nearest_b_r <= nearest_port_b_w[0+(request_tap%4)] |
                    nearest_port_b_w[4+(request_tap%4)] |
                    nearest_port_b_w[8+(request_tap%4)] |
                    nearest_port_b_w[12+(request_tap%4)];
                port_r <= {bank_r, request_mode_0_r == 0 ? nearest_b_r : request_tap[2]};
            end
        end
    endgenerate

    // Tap metadata accompanies the five-cycle RAM and four-cycle palette paths.
    reg [8:0] return_valid_r;
    wire [4:0] return_slot_r [0:8];
    wire [1:0] return_mode_r [0:8];
    wire [1:0] return_lane_r [0:8];
    wire [3:0] return_done_r [0:8];
    wire [23:0] return_port_r [0:4];
    wire [31:0] return_subword_r [0:4];
    wire [135:0] return_weight_w;
    wire [7:0] return_fraction_w;
    // Nine-cycle filter metadata: one 144-bit circular table, split into two LUTRAM slices.
    reg [5:0] metadata_write_r;
    wire [5:0] metadata_read_w;
    wire [143:0] metadata_input_w;
    wire [143:0] metadata_data_w;
    assign metadata_read_w = metadata_write_r - 6'd5;
    assign metadata_input_w = {weight_fraction_pipe_r[24 +: 8], tap_weight_w};
    reg [143:0] metadata_input_r;
    always @(posedge clk_i) begin
        metadata_input_r <= metadata_input_w;
    end
    assign return_weight_w = metadata_data_w[135:0];
    assign return_fraction_w = metadata_data_w[143:136];
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) metadata_write_r <= 0;
        else metadata_write_r <= metadata_write_r + 1'b1;
    end
    genvar metadata_bank;
    generate
        for (metadata_bank = 0; metadata_bank < 2;
            metadata_bank = metadata_bank + 1) begin : g_delay
            wire [71:0] u_metadata_data_w;
            reg [71:0] u_metadata_data_r;
            assign metadata_data_w[metadata_bank*72 +: 72] = u_metadata_data_r;
            always @(posedge clk_i) begin
                if (1'b1) u_metadata_data_r <= u_metadata_data_w;
            end
            edrv32_ram_gpu_table u_metadata (
                .clk_i(clk_i),
                .wr_en_i(1'b1),
                .wr_addr_i(metadata_write_r),
                .wr_data_i(metadata_input_r[metadata_bank*72 +: 72]),
                .rd_addr_i(metadata_read_w),
                .rd_data_o(u_metadata_data_w)
            );
        end
    endgenerate
    wire [127:0] direct_r [0:3];
    wire [127:0] direct_w;
    generate
        for (tap = 0; tap < 8; tap = tap + 1) begin : g_lookup
            reg [15:0] word_w;
            wire [15:0] shifted_w;
            wire [7:0] index_w;
            wire unused_shifted_w;
            always @(*) begin
                word_w = 0;
                case (return_port_r[4][tap*3 +: 3])
                    3'd0: word_w = texture_read_data_i[0 +: 16];
                    3'd1: word_w = texture_read_data_i[16 +: 16];
                    3'd2: word_w = texture_read_data_i[32 +: 16];
                    3'd3: word_w = texture_read_data_i[48 +: 16];
                    3'd4: word_w = texture_read_data_i[64 +: 16];
                    3'd5: word_w = texture_read_data_i[80 +: 16];
                    3'd6: word_w = texture_read_data_i[96 +: 16];
                    3'd7: word_w = texture_read_data_i[112 +: 16];
                    default: word_w = 0;
                endcase
            end
            assign shifted_w = word_w >> return_subword_r[4][tap*4 +: 4];
            assign unused_shifted_w = ^shifted_w[15:8];
            assign index_w = format_r == 0 ? {4'b0, shifted_w[3:0]} : shifted_w[7:0];
            always @(*) begin
                current_read_idx_o[tap*8 +: 8] = index_w;
            end
            if (tap < 4) begin : g_full
                always @(*) begin
                    full_read_idx_o[tap*12 +: 12] = {palette_r[return_slot_r[4]], index_w};
                end
            end
            assign direct_w[tap*16 +: 16] = word_w;
        end
    endgenerate
    assign full_read_en_o = return_valid_r[4] && return_mode_r[4] == 0 && !stop_i;
    assign current_read_en_o = return_valid_r[4] && return_mode_r[4] != 0 && !stop_i;

    // Palette expansion, tap products, pair sums, 2-D rounding, LOD products,
    // LOD rounding and shading are distinct stages. Horizontal sums never round.
    wire [31:0] expanded_w [0:7];
    wire [1:0] filter_mode_r [0:7];
    wire [1:0] filter_lane_r [0:7];
    wire [7:0] filter_fraction_r [0:3];
    reg [135:0] filter_weight_r;
    reg [255:0] expanded_r;
    wire [24:0] product_w [0:31];
    wire [25:0] pair_w [0:15];
    wire [127:0] nearest_r [0:2];
    reg [127:0] bilinear_r;
    reg [127:0] bypass_r;
    reg [135:0] lod_products_r;
    reg [127:0] filtered_r;
    reg [191:0] shade_products_r;
    reg [63:0] alpha_products_r;
    reg [31:0] unmodulated_alpha_r;
    reg shade_quad_r;
    reg shade_quad_input_r;
    reg [7:0] global_alpha_input_r;
    reg [31:0] unmodulated_alpha_input_r;
    reg [3:0] shade_mask_input_r;
    wire [3:0] shade_enabled_input_w;
    reg [3:0] shade_enabled_r;
    wire [127:0] bilinear_w;
    wire [127:0] filtered_w;
    wire [191:0] shade_products_w;
    wire [63:0] alpha_products_w;
    wire [3:0] shade_mask_w;
    wire [31:0] unmodulated_alpha_w;
    wire unused_offset_w;
    assign unused_offset_w = offset_r[0];
    genvar filter_pixel;
    genvar channel;
    genvar pair;
    generate
        // Expansion stage: eight RGB565 wiring networks and alpha selectors, no arithmetic.
        for (tap = 0; tap < 8; tap = tap + 1) begin : g_expand
            wire [19:0] entry_w;
            wire [15:0] rgb_w;
            wire [7:0] alpha_w;
            wire unused_entry_w;
            assign entry_w = return_mode_r[8] == 0 ?
                full_read_data_i[(tap%4)*20 +: 20] : current_read_data_i[tap*20 +: 20];
            assign rgb_w = format_r == 2 ? direct_r[3][tap*16 +: 16] : entry_w[15:0];
            assign alpha_w = format_r == 2 ? 8'd255 : {entry_w[19:16], entry_w[19:16]};
            assign unused_entry_w = ^entry_w;
            assign expanded_w[tap] = {alpha_w, rgb_w[4:0], rgb_w[4:2],
                rgb_w[10:5], rgb_w[10:9], rgb_w[15:11], rgb_w[15:13]};
            // Product stage: 8 taps x 4 channels = 32 independent 8x17 multipliers.
            for (channel = 0; channel < 4; channel = channel + 1) begin : g_product
                reg [24:0] product_r;
                assign product_w[tap*4+channel] = product_r;
                always @(posedge clk_i) begin
                    product_r <= expanded_r[tap*32+channel*8 +: 8] *
                        filter_weight_r[tap*17 +: 17];
                end
            end
        end
        // Pair stage: 2 footprints x 4 channels x 2 rows = sixteen 26-bit sums.
        for (filter_pixel = 0; filter_pixel < 2; filter_pixel = filter_pixel + 1) begin : g_pair
            localparam PIXEL_BASE = filter_pixel*8;
            for (channel = 0; channel < 4; channel = channel + 1) begin : g_channel
                localparam CHANNEL_BASE = channel*2;
                for (pair = 0; pair < 2; pair = pair + 1) begin : g_row
                    reg [25:0] pair_r;
                    assign pair_w[PIXEL_BASE+CHANNEL_BASE+pair] = pair_r;
                    always @(posedge clk_i) begin
                        pair_r <= {1'b0, product_w[(filter_pixel*4+pair*2)*4+channel]} +
                            {1'b0, product_w[(filter_pixel*4+pair*2+1)*4+channel]};
                    end
                end
            end
        end
        // Bilinear rounding stage: eight 27-bit vertical sums shared by duplicate outputs.
        for (filter_pixel = 0; filter_pixel < 2;
                filter_pixel = filter_pixel + 1) begin : g_bilinear
            localparam PIXEL_BASE = filter_pixel*8;
            for (channel = 0; channel < 4; channel = channel + 1) begin : g_channel
                wire [26:0] rounded_w;
                wire unused_rounded_w;
                assign rounded_w = {1'b0, pair_w[PIXEL_BASE+channel*2]} +
                    {1'b0, pair_w[PIXEL_BASE+channel*2+1]} + 27'd32768;
                assign unused_rounded_w = ^{rounded_w[26:24], rounded_w[15:0]};
                assign bilinear_w[filter_pixel*32+channel*8 +: 8] = filter_mode_r[2] != 0 ?
                    rounded_w[23:16] : nearest_r[2][filter_pixel*32+channel*8 +: 8];
                assign bilinear_w[(filter_pixel+2)*32+channel*8 +: 8] = filter_mode_r[2] != 0 ?
                    rounded_w[23:16] : nearest_r[2][(filter_pixel+2)*32+channel*8 +: 8];
            end
        end
        // LOD stages: eight 8x9 products, then four 18-bit rounding sums.
        for (channel = 0; channel < 4; channel = channel + 1) begin : g_lod_filter
            wire [8:0] inverse_fraction_w;
            wire [17:0] rounded_w;
            wire unused_rounded_w;
            reg [8:0] inverse_fraction_r;
            always @(posedge clk_i) begin
                inverse_fraction_r <= 9'd256 - {1'b0, filter_fraction_r[2]};
            end
            assign inverse_fraction_w = inverse_fraction_r;
            assign rounded_w = {1'b0, lod_products_r[channel*34 +: 17]} +
                {1'b0, lod_products_r[channel*34+17 +: 17]} + 18'd128;
            assign unused_rounded_w = ^{rounded_w[17:16], rounded_w[7:0]};
            assign filtered_w[channel*8 +: 8] = filter_mode_r[4] == 2 ?
                rounded_w[15:8] : bypass_r[channel*8 +: 8];
            always @(posedge clk_i) begin
                lod_products_r[channel*34 +: 17] <= bilinear_r[channel*8 +: 8] *
                    inverse_fraction_w;
                lod_products_r[channel*34+17 +: 17] <=
                    bilinear_r[32+channel*8 +: 8] * filter_fraction_r[3];
            end
        end
    endgenerate
    assign filtered_w[127:32] = bypass_r[127:32];
    generate
        // Shade product stage: four fixed output lanes, each with 3 RGB and 1 alpha product.
        // Registered filter lane selects a source word before the sixteen 8x8 multipliers.
        for (filter_pixel = 0; filter_pixel < 4; filter_pixel = filter_pixel + 1) begin : g_shade
            reg [31:0] source_w;
            reg [31:0] selected_input_r;
            reg [23:0] color_input_r;
            reg enabled_input_r;
            assign shade_enabled_input_w[filter_pixel] = enabled_input_r;
            wire enabled_w;
            wire [31:0] selected_w;
            wire [7:0] alpha_w;
            wire [16:0] alpha_temp_w;
            wire [17:0] alpha_total_w;
            wire unused_alpha_w;
            if (filter_pixel == 3) begin : g_all_sources
                assign enabled_w = 1'b1;
            end else begin : g_source_range
                assign enabled_w = filter_mode_r[5] == 0 || filter_lane_r[5] <= filter_pixel;
            end
            always @(*) begin
                source_w = 0;
                case (filter_lane_r[5])
                    2'd0: source_w = filtered_r[(filter_pixel-0)*32 +: 32];
                    2'd1: source_w = filter_pixel >= 1 ?
                        filtered_r[((filter_pixel+4-1)%4)*32 +: 32] : 32'd0;
                    2'd2: source_w = filter_pixel >= 2 ?
                        filtered_r[((filter_pixel+4-2)%4)*32 +: 32] : 32'd0;
                    2'd3: source_w = filter_pixel >= 3 ?
                        filtered_r[((filter_pixel+4-3)%4)*32 +: 32] : 32'd0;
                    default: source_w = 0;
                endcase
            end
            assign selected_w = filter_mode_r[5] == 0 ?
                filtered_r[filter_pixel*32 +: 32] : source_w;
            assign alpha_w = selected_w[31:24];
            always @(posedge clk_i) begin
                selected_input_r <= selected_w;
                color_input_r <= unused_shade_context_read0_w[filter_pixel*24 +: 24];
                enabled_input_r <= enabled_w;
            end
            assign alpha_products_w[filter_pixel*16 +: 16] =
                selected_input_r[31:24] * global_alpha_input_r;
            assign unmodulated_alpha_w[filter_pixel*8 +: 8] = enabled_w ? alpha_w : 8'd0;
            assign shade_mask_w[filter_pixel] = enabled_w &&
                mask_r[filter_slot_r[5]][filter_pixel] && alpha_w != 0;
            // Shade rounding stage: sixteen explicit 17/18-bit divide-by-255 networks.
            assign alpha_temp_w = {1'b0, (shade_enabled_r[filter_pixel] ?
                alpha_products_r[filter_pixel*16 +: 16] : 16'b0)} + 17'd128;
            assign alpha_total_w = {1'b0, alpha_temp_w} + {9'b0, alpha_temp_w[16:8]};
            assign unused_alpha_w = ^{alpha_total_w[17:16], alpha_total_w[7:0]};
            assign modulated_alpha_w[filter_pixel*8 +: 8] = shade_quad_r ?
                alpha_total_w[15:8] : unmodulated_alpha_r[filter_pixel*8 +: 8];
            for (channel = 0; channel < 3; channel = channel + 1) begin : g_channel
                wire [16:0] temp_w;
                wire [17:0] total_w;
                wire unused_total_w;
                assign shade_products_w[filter_pixel*48+channel*16 +: 16] =
                    selected_input_r[channel*8 +: 8] * color_input_r[channel*8 +: 8];
                assign temp_w =
                    {1'b0, (shade_enabled_r[filter_pixel] ?
                    shade_products_r[filter_pixel*48+channel*16 +: 16] : 16'b0)} + 17'd128;
                assign total_w = {1'b0, temp_w} + {9'b0, temp_w[16:8]};
                assign unused_total_w = ^{total_w[17:16], total_w[7:0]};
                assign modulated_color_w[filter_pixel*24+channel*8 +: 8] = total_w[15:8];
            end
        end
    endgenerate
    always @(posedge clk_i) begin
        filter_weight_r <= return_weight_w;
        expanded_r <= {expanded_w[7], expanded_w[6], expanded_w[5], expanded_w[4],
            expanded_w[3], expanded_w[2], expanded_w[1], expanded_w[0]};
        bilinear_r <= bilinear_w;
        bypass_r <= bilinear_r;
        filtered_r <= filtered_w;
        shade_products_r <= shade_products_w;
        alpha_products_r <= alpha_products_w;
        global_alpha_input_r <= unused_shade_context_read0_w[96 +: 8];
        shade_enabled_r <= shade_enabled_input_w;
        unmodulated_alpha_input_r <= unmodulated_alpha_w;
        unmodulated_alpha_r <= unmodulated_alpha_input_r;
        shade_mask_input_r <= shade_mask_w;
        shade_mask_r <= shade_mask_input_r;
        shade_quad_input_r <= quad_r[filter_slot_r[5]];
        shade_quad_r <= shade_quad_input_r;
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            allocate_r <= 0;
            schedule_r <= 0;
            retire_r <= 0;
            batch_r <= 0;
            nearest_pending_r <= 4'hf;
            lod_valid_r <= 0;
            return_valid_r <= 0;
            filter_valid_r <= 0;
            unit_done_o <= 1'b0;
        end else begin
            lod_valid_r <= {lod_valid_r[2:0], accept_w};
            return_valid_r <= {return_valid_r[7:0], request_valid_r[1]};
            filter_valid_r <= {filter_valid_r[6:0], return_valid_r[8]};
            if (accept_w) begin
                allocate_r <= allocate_r + 1'b1;
            end
            if (retire_w) begin
                retire_r <= retire_r + 1'b1;
            end
            if (schedule_valid_w) begin
                if (group_issued_w) begin
                    schedule_r <= schedule_r + 1'b1;
                    batch_r <= 0;
                    nearest_pending_r <= 4'hf;
                end else if (launch_mode_w == 0) begin
                    nearest_pending_r <= pending_w;
                end else begin
                    batch_r <= batch_r + 1'b1;
                end
            end
            if (stop_i) begin
                allocate_r <= 0;
                schedule_r <= 0;
                retire_r <= 0;
                batch_r <= 0;
                nearest_pending_r <= 4'hf;
                lod_valid_r <= 0;
                return_valid_r <= 0;
                filter_valid_r <= 0;
            end
            if (!finish_i) begin
                unit_done_o <= 1'b0;
            end else if (occupancy_w == 0 && lod_valid_r == 0 && return_valid_r == 0
                            && filter_valid_r == 0) begin
                unit_done_o <= 1'b1;
            end
        end
    end
    always @(posedge clk_i) begin
        if (render_state_valid_i && render_state_ready_o) begin
            log2_w_r <= render_state_tex_i[67:64];
            log2_h_r <= render_state_tex_i[71:68];
            format_r <= render_state_tex_i[73:72];
            levels_r <= render_state_tex_i[77:74];
            group_r <= render_state_tex_i[81:78];
            mode_r <= render_state_tex_i[83:82];
            bias_r <= render_state_tex_i[91:84];
            offset_r <= {render_state_tex_i[49:37], 5'b0};
        end
        if (accept_w) begin

            mask_r[allocate_r[4:0]] <= sample_mask_i;

            quad_r[allocate_r[4:0]] <= sample_quad_i;
            palette_r[allocate_r[4:0]] <= sample_quad_i ? sample_palette_i : group_r;
        end
    end
    // Thirty-two context completion registers: one whole-element update per clock.
    genvar context_idx;
    generate
        for (context_idx = 0; context_idx < 32; context_idx = context_idx + 1) begin : g_context
            reg [3:0] completed_r;
            reg lod_ready_r;
            wire [3:0] completed_next_w;
            assign completed_next_w =
                filter_valid_r[7] && filter_slot_r[7] == context_idx ?
                    completed_r | filter_done_r[7] : 4'd0;
            // Reset holds the uninitialized context data, matching the command-control process.
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                end else begin
                    if ((accept_w && allocate_r[4:0] == context_idx) ||
                            (filter_valid_r[7] && filter_slot_r[7] == context_idx))
                        completed_r <= completed_next_w;
                    if ((accept_w && allocate_r[4:0] == context_idx) ||
                            (address_valid_r[6] && address_slot_0_r_d6_r == context_idx))
                        lod_ready_r <= address_valid_r[6] && address_slot_0_r_d6_r == context_idx;
                end
            end
            assign completed_w[context_idx] = completed_r;
            assign lod_ready_w[context_idx] = lod_ready_r;
        end
    endgenerate
    // Metadata stages: independent local registers, one assignment per register.
    genvar pipe_stage;
    generate
        for (pipe_stage = 0; pipe_stage < 4; pipe_stage = pipe_stage + 1) begin : g_lod_slot
            reg [4:0] data_r;
            wire [4:0] data_w;
            assign lod_slot_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = allocate_r[4:0];
            end else begin : g_previous
                assign data_w = lod_slot_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 9; pipe_stage = pipe_stage + 1) begin : g_return_slot
            reg [4:0] data_r;
            wire [4:0] data_w;
            assign return_slot_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = request_slot_1_r;
            end else begin : g_previous
                assign data_w = return_slot_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 9; pipe_stage = pipe_stage + 1) begin : g_return_mode
            reg [1:0] data_r;
            wire [1:0] data_w;
            assign return_mode_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = request_mode_1_r;
            end else begin : g_previous
                assign data_w = return_mode_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 9; pipe_stage = pipe_stage + 1) begin : g_return_lane
            reg [1:0] data_r;
            wire [1:0] data_w;
            assign return_lane_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = request_lane_1_r;
            end else begin : g_previous
                assign data_w = return_lane_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 9; pipe_stage = pipe_stage + 1) begin : g_return_done
            reg [3:0] data_r;
            wire [3:0] data_w;
            assign return_done_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = request_done_1_r;
            end else begin : g_previous
                assign data_w = return_done_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 5; pipe_stage = pipe_stage + 1) begin : g_return_port
            reg [23:0] data_r;
            wire [23:0] data_w;
            assign return_port_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = tap_port_w;
            end else begin : g_previous
                assign data_w = return_port_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 5; pipe_stage = pipe_stage + 1) begin : g_return_subword
            reg [31:0] data_r;
            wire [31:0] data_w;
            assign return_subword_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = request_subword_1_r;
            end else begin : g_previous
                assign data_w = return_subword_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 4; pipe_stage = pipe_stage + 1) begin : g_direct
            reg [127:0] data_r;
            wire [127:0] data_w;
            assign direct_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = direct_w;
            end else begin : g_previous
                assign data_w = direct_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 8; pipe_stage = pipe_stage + 1) begin : g_filter_slot
            reg [4:0] data_r;
            wire [4:0] data_w;
            assign filter_slot_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = return_slot_r[8];
            end else begin : g_previous
                assign data_w = filter_slot_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 8; pipe_stage = pipe_stage + 1) begin : g_filter_mode
            reg [1:0] data_r;
            wire [1:0] data_w;
            assign filter_mode_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = return_mode_r[8];
            end else begin : g_previous
                assign data_w = filter_mode_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 8; pipe_stage = pipe_stage + 1) begin : g_filter_lane
            reg [1:0] data_r;
            wire [1:0] data_w;
            assign filter_lane_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = return_lane_r[8];
            end else begin : g_previous
                assign data_w = filter_lane_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 8; pipe_stage = pipe_stage + 1) begin : g_filter_done
            reg [3:0] data_r;
            wire [3:0] data_w;
            assign filter_done_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = return_done_r[8];
            end else begin : g_previous
                assign data_w = filter_done_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 4; pipe_stage = pipe_stage + 1) begin : g_filter_fraction
            reg [7:0] data_r;
            wire [7:0] data_w;
            assign filter_fraction_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = return_fraction_w;
            end else begin : g_previous
                assign data_w = filter_fraction_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 3; pipe_stage = pipe_stage + 1) begin : g_nearest
            reg [127:0] data_r;
            wire [127:0] data_w;
            assign nearest_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = {expanded_w[3], expanded_w[2], expanded_w[1], expanded_w[0]};
            end else begin : g_previous
                assign data_w = nearest_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
    endgenerate
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) address_valid_r <= 0;
        else if (stop_i) address_valid_r <= 0;
        else address_valid_r <= {address_valid_r[5:0], lod_valid_r[2]};
    end
    assign address_block_x0_0_0_w = format_r == 2 ? address_x0_0_0_r : address_x0_0_0_r >> 1;
    assign address_block_y0_0_0_w = format_r == 0 ? address_y0_0_0_r >> 1 : address_y0_0_0_r;
    assign address_column0_0_0_w = address_block_x0_0_0_w[8:1];
    assign address_record0_0_0_w = {address_subword0_0_0_d4_r, address_halfword0_0_0_r};
    assign address_block_x0_0_1_w = format_r == 2 ? address_x0_0_1_r : address_x0_0_1_r >> 1;
    assign address_block_y0_0_1_w = format_r == 0 ? address_y0_0_1_r >> 1 : address_y0_0_1_r;
    assign address_column0_0_1_w = address_block_x0_0_1_w[8:1];
    assign address_record0_0_1_w = {address_subword0_0_1_d4_r, address_halfword0_0_1_r};
    assign address_block_x0_0_2_w = format_r == 2 ? address_x0_0_2_r : address_x0_0_2_r >> 1;
    assign address_block_y0_0_2_w = format_r == 0 ? address_y0_0_2_r >> 1 : address_y0_0_2_r;
    assign address_column0_0_2_w = address_block_x0_0_2_w[8:1];
    assign address_record0_0_2_w = {address_subword0_0_2_d4_r, address_halfword0_0_2_r};
    assign address_block_x0_0_3_w = format_r == 2 ? address_x0_0_3_r : address_x0_0_3_r >> 1;
    assign address_block_y0_0_3_w = format_r == 0 ? address_y0_0_3_r >> 1 : address_y0_0_3_r;
    assign address_column0_0_3_w = address_block_x0_0_3_w[8:1];
    assign address_record0_0_3_w = {address_subword0_0_3_d4_r, address_halfword0_0_3_r};
    assign address_block_x0_0_4_w = format_r == 2 ? address_x0_0_4_r : address_x0_0_4_r >> 1;
    assign address_block_y0_0_4_w = format_r == 0 ? address_y0_0_4_r >> 1 : address_y0_0_4_r;
    assign address_column0_0_4_w = address_block_x0_0_4_w[8:1];
    assign address_record0_0_4_w = {address_subword0_0_4_d4_r, address_halfword0_0_4_r};
    assign address_block_x0_1_0_w = format_r == 2 ? address_x0_1_0_r : address_x0_1_0_r >> 1;
    assign address_block_y0_1_0_w = format_r == 0 ? address_y0_1_0_r >> 1 : address_y0_1_0_r;
    assign address_column0_1_0_w = address_block_x0_1_0_w[8:1];
    assign address_record0_1_0_w = {address_subword0_1_0_d5_r, address_halfword0_1_0_r};
    assign address_block_x0_1_1_w = format_r == 2 ? address_x0_1_1_r : address_x0_1_1_r >> 1;
    assign address_block_y0_1_1_w = format_r == 0 ? address_y0_1_1_r >> 1 : address_y0_1_1_r;
    assign address_column0_1_1_w = address_block_x0_1_1_w[8:1];
    assign address_record0_1_1_w = {address_subword0_1_1_d5_r, address_halfword0_1_1_r};
    assign address_block_x0_1_2_w = format_r == 2 ? address_x0_1_2_r : address_x0_1_2_r >> 1;
    assign address_block_y0_1_2_w = format_r == 0 ? address_y0_1_2_r >> 1 : address_y0_1_2_r;
    assign address_column0_1_2_w = address_block_x0_1_2_w[8:1];
    assign address_record0_1_2_w = {address_subword0_1_2_d5_r, address_halfword0_1_2_r};
    assign address_block_x0_1_3_w = format_r == 2 ? address_x0_1_3_r : address_x0_1_3_r >> 1;
    assign address_block_y0_1_3_w = format_r == 0 ? address_y0_1_3_r >> 1 : address_y0_1_3_r;
    assign address_column0_1_3_w = address_block_x0_1_3_w[8:1];
    assign address_record0_1_3_w = {address_subword0_1_3_d5_r, address_halfword0_1_3_r};
    assign address_block_x1_0_0_w = format_r == 2 ? address_x1_0_0_r : address_x1_0_0_r >> 1;
    assign address_block_y1_0_0_w = format_r == 0 ? address_y1_0_0_r >> 1 : address_y1_0_0_r;
    assign address_column1_0_0_w = address_block_x1_0_0_w[8:1];
    assign address_record1_0_0_w = {address_subword1_0_0_d4_r, address_halfword1_0_0_r};
    assign address_block_x1_0_1_w = format_r == 2 ? address_x1_0_1_r : address_x1_0_1_r >> 1;
    assign address_block_y1_0_1_w = format_r == 0 ? address_y1_0_1_r >> 1 : address_y1_0_1_r;
    assign address_column1_0_1_w = address_block_x1_0_1_w[8:1];
    assign address_record1_0_1_w = {address_subword1_0_1_d4_r, address_halfword1_0_1_r};
    assign address_block_x1_0_2_w = format_r == 2 ? address_x1_0_2_r : address_x1_0_2_r >> 1;
    assign address_block_y1_0_2_w = format_r == 0 ? address_y1_0_2_r >> 1 : address_y1_0_2_r;
    assign address_column1_0_2_w = address_block_x1_0_2_w[8:1];
    assign address_record1_0_2_w = {address_subword1_0_2_d4_r, address_halfword1_0_2_r};
    assign address_block_x1_0_3_w = format_r == 2 ? address_x1_0_3_r : address_x1_0_3_r >> 1;
    assign address_block_y1_0_3_w = format_r == 0 ? address_y1_0_3_r >> 1 : address_y1_0_3_r;
    assign address_column1_0_3_w = address_block_x1_0_3_w[8:1];
    assign address_record1_0_3_w = {address_subword1_0_3_d4_r, address_halfword1_0_3_r};
    assign address_block_x1_0_4_w = format_r == 2 ? address_x1_0_4_r : address_x1_0_4_r >> 1;
    assign address_block_y1_0_4_w = format_r == 0 ? address_y1_0_4_r >> 1 : address_y1_0_4_r;
    assign address_column1_0_4_w = address_block_x1_0_4_w[8:1];
    assign address_record1_0_4_w = {address_subword1_0_4_d4_r, address_halfword1_0_4_r};
    assign address_block_x1_1_0_w = format_r == 2 ? address_x1_1_0_r : address_x1_1_0_r >> 1;
    assign address_block_y1_1_0_w = format_r == 0 ? address_y1_1_0_r >> 1 : address_y1_1_0_r;
    assign address_column1_1_0_w = address_block_x1_1_0_w[8:1];
    assign address_record1_1_0_w = {address_subword1_1_0_d5_r, address_halfword1_1_0_r};
    assign address_block_x1_1_1_w = format_r == 2 ? address_x1_1_1_r : address_x1_1_1_r >> 1;
    assign address_block_y1_1_1_w = format_r == 0 ? address_y1_1_1_r >> 1 : address_y1_1_1_r;
    assign address_column1_1_1_w = address_block_x1_1_1_w[8:1];
    assign address_record1_1_1_w = {address_subword1_1_1_d5_r, address_halfword1_1_1_r};
    assign address_block_x1_1_2_w = format_r == 2 ? address_x1_1_2_r : address_x1_1_2_r >> 1;
    assign address_block_y1_1_2_w = format_r == 0 ? address_y1_1_2_r >> 1 : address_y1_1_2_r;
    assign address_column1_1_2_w = address_block_x1_1_2_w[8:1];
    assign address_record1_1_2_w = {address_subword1_1_2_d5_r, address_halfword1_1_2_r};
    assign address_block_x1_1_3_w = format_r == 2 ? address_x1_1_3_r : address_x1_1_3_r >> 1;
    assign address_block_y1_1_3_w = format_r == 0 ? address_y1_1_3_r >> 1 : address_y1_1_3_r;
    assign address_column1_1_3_w = address_block_x1_1_3_w[8:1];
    assign address_record1_1_3_w = {address_subword1_1_3_d5_r, address_halfword1_1_3_r};
    assign address_block_x2_0_0_w = format_r == 2 ? address_x2_0_0_r : address_x2_0_0_r >> 1;
    assign address_block_y2_0_0_w = format_r == 0 ? address_y2_0_0_r >> 1 : address_y2_0_0_r;
    assign address_column2_0_0_w = address_block_x2_0_0_w[8:1];
    assign address_record2_0_0_w = {address_subword2_0_0_d4_r, address_halfword2_0_0_r};
    assign address_block_x2_0_1_w = format_r == 2 ? address_x2_0_1_r : address_x2_0_1_r >> 1;
    assign address_block_y2_0_1_w = format_r == 0 ? address_y2_0_1_r >> 1 : address_y2_0_1_r;
    assign address_column2_0_1_w = address_block_x2_0_1_w[8:1];
    assign address_record2_0_1_w = {address_subword2_0_1_d4_r, address_halfword2_0_1_r};
    assign address_block_x2_0_2_w = format_r == 2 ? address_x2_0_2_r : address_x2_0_2_r >> 1;
    assign address_block_y2_0_2_w = format_r == 0 ? address_y2_0_2_r >> 1 : address_y2_0_2_r;
    assign address_column2_0_2_w = address_block_x2_0_2_w[8:1];
    assign address_record2_0_2_w = {address_subword2_0_2_d4_r, address_halfword2_0_2_r};
    assign address_block_x2_0_3_w = format_r == 2 ? address_x2_0_3_r : address_x2_0_3_r >> 1;
    assign address_block_y2_0_3_w = format_r == 0 ? address_y2_0_3_r >> 1 : address_y2_0_3_r;
    assign address_column2_0_3_w = address_block_x2_0_3_w[8:1];
    assign address_record2_0_3_w = {address_subword2_0_3_d4_r, address_halfword2_0_3_r};
    assign address_block_x2_0_4_w = format_r == 2 ? address_x2_0_4_r : address_x2_0_4_r >> 1;
    assign address_block_y2_0_4_w = format_r == 0 ? address_y2_0_4_r >> 1 : address_y2_0_4_r;
    assign address_column2_0_4_w = address_block_x2_0_4_w[8:1];
    assign address_record2_0_4_w = {address_subword2_0_4_d4_r, address_halfword2_0_4_r};
    assign address_block_x2_1_0_w = format_r == 2 ? address_x2_1_0_r : address_x2_1_0_r >> 1;
    assign address_block_y2_1_0_w = format_r == 0 ? address_y2_1_0_r >> 1 : address_y2_1_0_r;
    assign address_column2_1_0_w = address_block_x2_1_0_w[8:1];
    assign address_record2_1_0_w = {address_subword2_1_0_d5_r, address_halfword2_1_0_r};
    assign address_block_x2_1_1_w = format_r == 2 ? address_x2_1_1_r : address_x2_1_1_r >> 1;
    assign address_block_y2_1_1_w = format_r == 0 ? address_y2_1_1_r >> 1 : address_y2_1_1_r;
    assign address_column2_1_1_w = address_block_x2_1_1_w[8:1];
    assign address_record2_1_1_w = {address_subword2_1_1_d5_r, address_halfword2_1_1_r};
    assign address_block_x2_1_2_w = format_r == 2 ? address_x2_1_2_r : address_x2_1_2_r >> 1;
    assign address_block_y2_1_2_w = format_r == 0 ? address_y2_1_2_r >> 1 : address_y2_1_2_r;
    assign address_column2_1_2_w = address_block_x2_1_2_w[8:1];
    assign address_record2_1_2_w = {address_subword2_1_2_d5_r, address_halfword2_1_2_r};
    assign address_block_x2_1_3_w = format_r == 2 ? address_x2_1_3_r : address_x2_1_3_r >> 1;
    assign address_block_y2_1_3_w = format_r == 0 ? address_y2_1_3_r >> 1 : address_y2_1_3_r;
    assign address_column2_1_3_w = address_block_x2_1_3_w[8:1];
    assign address_record2_1_3_w = {address_subword2_1_3_d5_r, address_halfword2_1_3_r};
    assign address_block_x3_0_0_w = format_r == 2 ? address_x3_0_0_r : address_x3_0_0_r >> 1;
    assign address_block_y3_0_0_w = format_r == 0 ? address_y3_0_0_r >> 1 : address_y3_0_0_r;
    assign address_column3_0_0_w = address_block_x3_0_0_w[8:1];
    assign address_record3_0_0_w = {address_subword3_0_0_d4_r, address_halfword3_0_0_r};
    assign address_block_x3_0_1_w = format_r == 2 ? address_x3_0_1_r : address_x3_0_1_r >> 1;
    assign address_block_y3_0_1_w = format_r == 0 ? address_y3_0_1_r >> 1 : address_y3_0_1_r;
    assign address_column3_0_1_w = address_block_x3_0_1_w[8:1];
    assign address_record3_0_1_w = {address_subword3_0_1_d4_r, address_halfword3_0_1_r};
    assign address_block_x3_0_2_w = format_r == 2 ? address_x3_0_2_r : address_x3_0_2_r >> 1;
    assign address_block_y3_0_2_w = format_r == 0 ? address_y3_0_2_r >> 1 : address_y3_0_2_r;
    assign address_column3_0_2_w = address_block_x3_0_2_w[8:1];
    assign address_record3_0_2_w = {address_subword3_0_2_d4_r, address_halfword3_0_2_r};
    assign address_block_x3_0_3_w = format_r == 2 ? address_x3_0_3_r : address_x3_0_3_r >> 1;
    assign address_block_y3_0_3_w = format_r == 0 ? address_y3_0_3_r >> 1 : address_y3_0_3_r;
    assign address_column3_0_3_w = address_block_x3_0_3_w[8:1];
    assign address_record3_0_3_w = {address_subword3_0_3_d4_r, address_halfword3_0_3_r};
    assign address_block_x3_0_4_w = format_r == 2 ? address_x3_0_4_r : address_x3_0_4_r >> 1;
    assign address_block_y3_0_4_w = format_r == 0 ? address_y3_0_4_r >> 1 : address_y3_0_4_r;
    assign address_column3_0_4_w = address_block_x3_0_4_w[8:1];
    assign address_record3_0_4_w = {address_subword3_0_4_d4_r, address_halfword3_0_4_r};
    assign address_block_x3_1_0_w = format_r == 2 ? address_x3_1_0_r : address_x3_1_0_r >> 1;
    assign address_block_y3_1_0_w = format_r == 0 ? address_y3_1_0_r >> 1 : address_y3_1_0_r;
    assign address_column3_1_0_w = address_block_x3_1_0_w[8:1];
    assign address_record3_1_0_w = {address_subword3_1_0_d5_r, address_halfword3_1_0_r};
    assign address_block_x3_1_1_w = format_r == 2 ? address_x3_1_1_r : address_x3_1_1_r >> 1;
    assign address_block_y3_1_1_w = format_r == 0 ? address_y3_1_1_r >> 1 : address_y3_1_1_r;
    assign address_column3_1_1_w = address_block_x3_1_1_w[8:1];
    assign address_record3_1_1_w = {address_subword3_1_1_d5_r, address_halfword3_1_1_r};
    assign address_block_x3_1_2_w = format_r == 2 ? address_x3_1_2_r : address_x3_1_2_r >> 1;
    assign address_block_y3_1_2_w = format_r == 0 ? address_y3_1_2_r >> 1 : address_y3_1_2_r;
    assign address_column3_1_2_w = address_block_x3_1_2_w[8:1];
    assign address_record3_1_2_w = {address_subword3_1_2_d5_r, address_halfword3_1_2_r};
    assign address_block_x3_1_3_w = format_r == 2 ? address_x3_1_3_r : address_x3_1_3_r >> 1;
    assign address_block_y3_1_3_w = format_r == 0 ? address_y3_1_3_r >> 1 : address_y3_1_3_r;
    assign address_column3_1_3_w = address_block_x3_1_3_w[8:1];
    assign address_record3_1_3_w = {address_subword3_1_3_d5_r, address_halfword3_1_3_r};
    assign address_even_index0_w = address_read_slot0_r[4:1] +
        {3'b0, address_read_slot0_r[0]};
    assign address_odd_index0_w = address_read_slot0_r[4:1];
    (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) address_read_slot0_r <= 0;
        else if (stop_i) address_read_slot0_r <= 0;
        else if (schedule_valid_w && group_issued_w)
            address_read_slot0_r <= address_read_slot0_r + 1'b1;
    end
    generate
        begin : g_address_pool_tap_0_0
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[0] = address_read_slot0_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record0_0_0_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index0_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record0_0_0_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index0_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_0_1
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[1] = address_read_slot0_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record0_0_1_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index0_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record0_0_1_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index0_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_0_2
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[2] = address_read_slot0_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record0_0_2_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index0_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record0_0_2_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index0_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_0_3
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[3] = address_read_slot0_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record0_0_3_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index0_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record0_0_3_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index0_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_0_4
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[4] = address_read_slot0_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record0_1_0_w}),
                .rd_addr_i({2'b0, address_even_index0_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record0_1_0_w}),
                .rd_addr_i({2'b0, address_odd_index0_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_0_5
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[5] = address_read_slot0_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record0_1_1_w}),
                .rd_addr_i({2'b0, address_even_index0_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record0_1_1_w}),
                .rd_addr_i({2'b0, address_odd_index0_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_0_6
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[6] = address_read_slot0_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record0_1_2_w}),
                .rd_addr_i({2'b0, address_even_index0_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record0_1_2_w}),
                .rd_addr_i({2'b0, address_odd_index0_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_0_7
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[7] = address_read_slot0_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record0_1_3_w}),
                .rd_addr_i({2'b0, address_even_index0_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record0_1_3_w}),
                .rd_addr_i({2'b0, address_odd_index0_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_0_8
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[8] = address_read_slot0_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record0_0_4_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index0_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record0_0_4_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index0_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_fraction_0_0
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [15:0] even_cache_r;
            reg [15:0] odd_cache_r;
            assign fraction_cache_w[0] = address_read_slot0_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({56'b0, address_fraction0_0_d5_r}),
                .rd_addr_i({2'b0, address_even_index0_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({56'b0, address_fraction0_0_d5_r}),
                .rd_addr_i({2'b0, address_odd_index0_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[15:0];
                odd_cache_r <= unused_odd_data_w[15:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_fraction_0_1
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [15:0] even_cache_r;
            reg [15:0] odd_cache_r;
            assign fraction_cache_w[1] = address_read_slot0_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({56'b0, address_fraction0_1_d5_r}),
                .rd_addr_i({2'b0, address_even_index0_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({56'b0, address_fraction0_1_d5_r}),
                .rd_addr_i({2'b0, address_odd_index0_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[15:0];
                odd_cache_r <= unused_odd_data_w[15:0];
            end
        end
    endgenerate
    (* keep = 1 *) reg [4:0] address_read_slot1_r /* synthesis syn_preserve=1 */;
    wire [3:0] address_even_index1_w;
    wire [3:0] address_odd_index1_w;
    assign address_even_index1_w = address_read_slot1_r[4:1] +
        {3'b0, address_read_slot1_r[0]};
    assign address_odd_index1_w = address_read_slot1_r[4:1];
    (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) address_read_slot1_r <= 0;
        else if (stop_i) address_read_slot1_r <= 0;
        else if (schedule_valid_w && group_issued_w)
            address_read_slot1_r <= address_read_slot1_r + 1'b1;
    end
    generate
        begin : g_address_pool_tap_1_0
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[9] = address_read_slot1_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record1_0_0_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index1_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record1_0_0_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index1_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_1_1
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[10] = address_read_slot1_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record1_0_1_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index1_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record1_0_1_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index1_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_1_2
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[11] = address_read_slot1_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record1_0_2_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index1_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record1_0_2_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index1_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_1_3
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[12] = address_read_slot1_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record1_0_3_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index1_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record1_0_3_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index1_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_1_4
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[13] = address_read_slot1_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record1_1_0_w}),
                .rd_addr_i({2'b0, address_even_index1_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record1_1_0_w}),
                .rd_addr_i({2'b0, address_odd_index1_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_1_5
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[14] = address_read_slot1_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record1_1_1_w}),
                .rd_addr_i({2'b0, address_even_index1_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record1_1_1_w}),
                .rd_addr_i({2'b0, address_odd_index1_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_1_6
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[15] = address_read_slot1_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record1_1_2_w}),
                .rd_addr_i({2'b0, address_even_index1_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record1_1_2_w}),
                .rd_addr_i({2'b0, address_odd_index1_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_1_7
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[16] = address_read_slot1_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record1_1_3_w}),
                .rd_addr_i({2'b0, address_even_index1_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record1_1_3_w}),
                .rd_addr_i({2'b0, address_odd_index1_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_1_8
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[17] = address_read_slot1_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record1_0_4_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index1_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record1_0_4_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index1_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_fraction_1_0
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [15:0] even_cache_r;
            reg [15:0] odd_cache_r;
            assign fraction_cache_w[2] = address_read_slot1_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({56'b0, address_fraction1_0_d5_r}),
                .rd_addr_i({2'b0, address_even_index1_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({56'b0, address_fraction1_0_d5_r}),
                .rd_addr_i({2'b0, address_odd_index1_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[15:0];
                odd_cache_r <= unused_odd_data_w[15:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_fraction_1_1
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [15:0] even_cache_r;
            reg [15:0] odd_cache_r;
            assign fraction_cache_w[3] = address_read_slot1_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({56'b0, address_fraction1_1_d5_r}),
                .rd_addr_i({2'b0, address_even_index1_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({56'b0, address_fraction1_1_d5_r}),
                .rd_addr_i({2'b0, address_odd_index1_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[15:0];
                odd_cache_r <= unused_odd_data_w[15:0];
            end
        end
    endgenerate
    (* keep = 1 *) reg [4:0] address_read_slot2_r /* synthesis syn_preserve=1 */;
    wire [3:0] address_even_index2_w;
    wire [3:0] address_odd_index2_w;
    assign address_even_index2_w = address_read_slot2_r[4:1] +
        {3'b0, address_read_slot2_r[0]};
    assign address_odd_index2_w = address_read_slot2_r[4:1];
    (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) address_read_slot2_r <= 0;
        else if (stop_i) address_read_slot2_r <= 0;
        else if (schedule_valid_w && group_issued_w)
            address_read_slot2_r <= address_read_slot2_r + 1'b1;
    end
    generate
        begin : g_address_pool_tap_2_0
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[18] = address_read_slot2_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record2_0_0_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index2_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record2_0_0_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index2_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_2_1
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[19] = address_read_slot2_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record2_0_1_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index2_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record2_0_1_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index2_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_2_2
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[20] = address_read_slot2_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record2_0_2_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index2_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record2_0_2_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index2_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_2_3
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[21] = address_read_slot2_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record2_0_3_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index2_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record2_0_3_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index2_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_2_4
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[22] = address_read_slot2_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record2_1_0_w}),
                .rd_addr_i({2'b0, address_even_index2_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record2_1_0_w}),
                .rd_addr_i({2'b0, address_odd_index2_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_2_5
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[23] = address_read_slot2_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record2_1_1_w}),
                .rd_addr_i({2'b0, address_even_index2_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record2_1_1_w}),
                .rd_addr_i({2'b0, address_odd_index2_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_2_6
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[24] = address_read_slot2_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record2_1_2_w}),
                .rd_addr_i({2'b0, address_even_index2_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record2_1_2_w}),
                .rd_addr_i({2'b0, address_odd_index2_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_2_7
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[25] = address_read_slot2_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record2_1_3_w}),
                .rd_addr_i({2'b0, address_even_index2_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record2_1_3_w}),
                .rd_addr_i({2'b0, address_odd_index2_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_2_8
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[26] = address_read_slot2_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record2_0_4_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index2_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record2_0_4_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index2_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_fraction_2_0
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [15:0] even_cache_r;
            reg [15:0] odd_cache_r;
            assign fraction_cache_w[4] = address_read_slot2_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({56'b0, address_fraction2_0_d5_r}),
                .rd_addr_i({2'b0, address_even_index2_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({56'b0, address_fraction2_0_d5_r}),
                .rd_addr_i({2'b0, address_odd_index2_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[15:0];
                odd_cache_r <= unused_odd_data_w[15:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_fraction_2_1
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [15:0] even_cache_r;
            reg [15:0] odd_cache_r;
            assign fraction_cache_w[5] = address_read_slot2_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({56'b0, address_fraction2_1_d5_r}),
                .rd_addr_i({2'b0, address_even_index2_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({56'b0, address_fraction2_1_d5_r}),
                .rd_addr_i({2'b0, address_odd_index2_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[15:0];
                odd_cache_r <= unused_odd_data_w[15:0];
            end
        end
    endgenerate
    (* keep = 1 *) reg [4:0] address_read_slot3_r /* synthesis syn_preserve=1 */;
    wire [3:0] address_even_index3_w;
    wire [3:0] address_odd_index3_w;
    assign address_even_index3_w = address_read_slot3_r[4:1] +
        {3'b0, address_read_slot3_r[0]};
    assign address_odd_index3_w = address_read_slot3_r[4:1];
    (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) address_read_slot3_r <= 0;
        else if (stop_i) address_read_slot3_r <= 0;
        else if (schedule_valid_w && group_issued_w)
            address_read_slot3_r <= address_read_slot3_r + 1'b1;
    end
    generate
        begin : g_address_pool_tap_3_0
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[27] = address_read_slot3_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record3_0_0_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index3_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record3_0_0_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index3_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_3_1
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[28] = address_read_slot3_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record3_0_1_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index3_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record3_0_1_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index3_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_3_2
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[29] = address_read_slot3_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record3_0_2_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index3_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record3_0_2_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index3_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_3_3
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[30] = address_read_slot3_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record3_0_3_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index3_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record3_0_3_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index3_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_3_4
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[31] = address_read_slot3_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record3_1_0_w}),
                .rd_addr_i({2'b0, address_even_index3_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record3_1_0_w}),
                .rd_addr_i({2'b0, address_odd_index3_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_3_5
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[32] = address_read_slot3_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record3_1_1_w}),
                .rd_addr_i({2'b0, address_even_index3_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record3_1_1_w}),
                .rd_addr_i({2'b0, address_odd_index3_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_3_6
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[33] = address_read_slot3_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record3_1_2_w}),
                .rd_addr_i({2'b0, address_even_index3_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record3_1_2_w}),
                .rd_addr_i({2'b0, address_odd_index3_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_3_7
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[34] = address_read_slot3_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record3_1_3_w}),
                .rd_addr_i({2'b0, address_even_index3_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record3_1_3_w}),
                .rd_addr_i({2'b0, address_odd_index3_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_tap_3_8
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [20:0] even_cache_r;
            reg [20:0] odd_cache_r;
            assign address_cache_w[35] = address_read_slot3_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record3_0_4_w_d5_r}),
                .rd_addr_i({2'b0, address_even_index3_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({51'b0, address_record3_0_4_w_d5_r}),
                .rd_addr_i({2'b0, address_odd_index3_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[20:0];
                odd_cache_r <= unused_odd_data_w[20:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_fraction_3_0
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [15:0] even_cache_r;
            reg [15:0] odd_cache_r;
            assign fraction_cache_w[6] = address_read_slot3_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({56'b0, address_fraction3_0_d5_r}),
                .rd_addr_i({2'b0, address_even_index3_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({56'b0, address_fraction3_0_d5_r}),
                .rd_addr_i({2'b0, address_odd_index3_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[15:0];
                odd_cache_r <= unused_odd_data_w[15:0];
            end
        end
    endgenerate
    generate
        begin : g_address_pool_fraction_3_1
            wire [71:0] unused_even_data_w;
            wire [71:0] unused_odd_data_w;
            reg [15:0] even_cache_r;
            reg [15:0] odd_cache_r;
            assign fraction_cache_w[7] = address_read_slot3_r[0] ? odd_cache_r : even_cache_r;
            edrv32_ram_gpu_table u_even (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && !address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({56'b0, address_fraction3_1_d5_r}),
                .rd_addr_i({2'b0, address_even_index3_w}),
                .rd_data_o(unused_even_data_w)
            );
            edrv32_ram_gpu_table u_odd (
                .clk_i(clk_i),
                .wr_en_i(address_valid_r[5] && address_slot_0_r_d5_r[0]),
                .wr_addr_i({2'b0, address_slot_0_r_d5_r[4:1]}),
                .wr_data_i({56'b0, address_fraction3_1_d5_r}),
                .rd_addr_i({2'b0, address_odd_index3_w}),
                .rd_data_o(unused_odd_data_w)
            );
            always @(posedge clk_i) begin
                even_cache_r <= unused_even_data_w[15:0];
                odd_cache_r <= unused_odd_data_w[15:0];
            end
        end
    endgenerate
    always @(posedge clk_i) begin
    address_slot_0_r <= lod_slot_r[2];
    address_u0_r <= address_input_u_w[0 +: 32];
    address_v0_r <= address_input_v_w[0 +: 32];
    address_level0_r <= quad_r[lod_slot_r[2]] ? 4'b0 : unused_address_input_lod_w[0 +: 4];
    address_next_level0_r <= address_level0_r < levels_r - 4'd1 ? address_level0_r + 4'd1 :
            address_level0_r;
    address_scaled_u0_0_r <= unused_address_scaled_u0_0_wide_w[16:0];
    address_scaled_v0_0_r <= unused_address_scaled_v0_0_wide_w[16:0];
    address_mask_x0_0_r <= mip_mask_x_w[address_level0_r];
    address_mask_y0_0_r <= mip_mask_y_w[address_level0_r];
    address_offset0_0_r <= mip_offset_w[address_level0_r];
    address_row_shift0_0_r <= mip_row_shift_w[address_level0_r];
    address_fraction0_0_r <= {address_scaled_v0_0_r[7:0] ^ 8'h80, address_scaled_u0_0_r[7:0] ^
        8'h80};
    address_x0_0_0_r <= (address_scaled_u0_0_r[16:8] - {8'b0, !address_scaled_u0_0_r[7]}) &
            address_mask_x0_0_r;
    address_y0_0_0_r <= (address_scaled_v0_0_r[16:8] - {8'b0, !address_scaled_v0_0_r[7]}) &
            address_mask_y0_0_r;
    address_row_shift0_0_d2_r <= address_row_shift0_0_r;
    unused_address_row0_0_0_r <= {9'b0, address_block_y0_0_0_w[8:1]} << address_row_shift0_0_d2_r;
    address_bank0_0_0_r <= {address_block_y0_0_0_w[0], address_block_x0_0_0_w[0]};
    address_subword0_0_0_r <= format_r == 0 ? {address_y0_0_0_r[0], address_x0_0_0_r[0], 2'b0} :
            format_r == 1 ? {address_x0_0_0_r[0], 3'b0} : 4'b0;
    address_offset0_0_d2_r <= address_offset0_0_r;
    unused_address_offset0_0_d3_r <= address_offset0_0_d2_r;
    address_column0_0_0_w_d3_r <= address_column0_0_0_w;
    address_halfword0_0_0_r <= {unused_address_offset0_0_d3_r[16:2] +
            (unused_address_row0_0_0_r[14:0] | {7'b0, address_column0_0_0_w_d3_r}),
                address_bank0_0_0_r};
    address_subword0_0_0_d4_r <= address_subword0_0_0_r;
    address_x0_0_1_r <= (address_scaled_u0_0_r[16:8] + {8'b0, address_scaled_u0_0_r[7]}) &
            address_mask_x0_0_r;
    address_y0_0_1_r <= (address_scaled_v0_0_r[16:8] - {8'b0, !address_scaled_v0_0_r[7]}) &
            address_mask_y0_0_r;
    unused_address_row0_0_1_r <= {9'b0, address_block_y0_0_1_w[8:1]} << address_row_shift0_0_d2_r;
    address_bank0_0_1_r <= {address_block_y0_0_1_w[0], address_block_x0_0_1_w[0]};
    address_subword0_0_1_r <= format_r == 0 ? {address_y0_0_1_r[0], address_x0_0_1_r[0], 2'b0} :
            format_r == 1 ? {address_x0_0_1_r[0], 3'b0} : 4'b0;
    address_column0_0_1_w_d3_r <= address_column0_0_1_w;
    address_halfword0_0_1_r <= {unused_address_offset0_0_d3_r[16:2] +
            (unused_address_row0_0_1_r[14:0] | {7'b0, address_column0_0_1_w_d3_r}),
                address_bank0_0_1_r};
    address_subword0_0_1_d4_r <= address_subword0_0_1_r;
    address_x0_0_2_r <= (address_scaled_u0_0_r[16:8] - {8'b0, !address_scaled_u0_0_r[7]}) &
            address_mask_x0_0_r;
    address_y0_0_2_r <= (address_scaled_v0_0_r[16:8] + {8'b0, address_scaled_v0_0_r[7]}) &
            address_mask_y0_0_r;
    unused_address_row0_0_2_r <= {9'b0, address_block_y0_0_2_w[8:1]} << address_row_shift0_0_d2_r;
    address_bank0_0_2_r <= {address_block_y0_0_2_w[0], address_block_x0_0_2_w[0]};
    address_subword0_0_2_r <= format_r == 0 ? {address_y0_0_2_r[0], address_x0_0_2_r[0], 2'b0} :
            format_r == 1 ? {address_x0_0_2_r[0], 3'b0} : 4'b0;
    address_column0_0_2_w_d3_r <= address_column0_0_2_w;
    address_halfword0_0_2_r <= {unused_address_offset0_0_d3_r[16:2] +
            (unused_address_row0_0_2_r[14:0] | {7'b0, address_column0_0_2_w_d3_r}),
                address_bank0_0_2_r};
    address_subword0_0_2_d4_r <= address_subword0_0_2_r;
    address_x0_0_3_r <= (address_scaled_u0_0_r[16:8] + {8'b0, address_scaled_u0_0_r[7]}) &
            address_mask_x0_0_r;
    address_y0_0_3_r <= (address_scaled_v0_0_r[16:8] + {8'b0, address_scaled_v0_0_r[7]}) &
            address_mask_y0_0_r;
    unused_address_row0_0_3_r <= {9'b0, address_block_y0_0_3_w[8:1]} << address_row_shift0_0_d2_r;
    address_bank0_0_3_r <= {address_block_y0_0_3_w[0], address_block_x0_0_3_w[0]};
    address_subword0_0_3_r <= format_r == 0 ? {address_y0_0_3_r[0], address_x0_0_3_r[0], 2'b0} :
            format_r == 1 ? {address_x0_0_3_r[0], 3'b0} : 4'b0;
    address_column0_0_3_w_d3_r <= address_column0_0_3_w;
    address_halfword0_0_3_r <= {unused_address_offset0_0_d3_r[16:2] +
            (unused_address_row0_0_3_r[14:0] | {7'b0, address_column0_0_3_w_d3_r}),
                address_bank0_0_3_r};
    address_subword0_0_3_d4_r <= address_subword0_0_3_r;
    address_x0_0_4_r <= address_scaled_u0_0_r[16:8] & address_mask_x0_0_r;
    address_y0_0_4_r <= address_scaled_v0_0_r[16:8] & address_mask_y0_0_r;
    unused_address_row0_0_4_r <= {9'b0, address_block_y0_0_4_w[8:1]} << address_row_shift0_0_d2_r;
    address_bank0_0_4_r <= {address_block_y0_0_4_w[0], address_block_x0_0_4_w[0]};
    address_subword0_0_4_r <= format_r == 0 ? {address_y0_0_4_r[0], address_x0_0_4_r[0], 2'b0} :
            format_r == 1 ? {address_x0_0_4_r[0], 3'b0} : 4'b0;
    address_column0_0_4_w_d3_r <= address_column0_0_4_w;
    address_halfword0_0_4_r <= {unused_address_offset0_0_d3_r[16:2] +
            (unused_address_row0_0_4_r[14:0] | {7'b0, address_column0_0_4_w_d3_r}),
                address_bank0_0_4_r};
    address_subword0_0_4_d4_r <= address_subword0_0_4_r;
    address_u0_r_d1_r <= address_u0_r;
    address_scaled_u0_1_r <= unused_address_scaled_u0_1_wide_w[16:0];
    address_v0_r_d1_r <= address_v0_r;
    address_scaled_v0_1_r <= unused_address_scaled_v0_1_wide_w[16:0];
    address_mask_x0_1_r <= mip_mask_x_w[address_next_level0_r];
    address_mask_y0_1_r <= mip_mask_y_w[address_next_level0_r];
    address_offset0_1_r <= mip_offset_w[address_next_level0_r];
    address_row_shift0_1_r <= mip_row_shift_w[address_next_level0_r];
    address_fraction0_1_r <= {address_scaled_v0_1_r[7:0] ^ 8'h80, address_scaled_u0_1_r[7:0] ^
        8'h80};
    address_x0_1_0_r <= (address_scaled_u0_1_r[16:8] - {8'b0, !address_scaled_u0_1_r[7]}) &
            address_mask_x0_1_r;
    address_y0_1_0_r <= (address_scaled_v0_1_r[16:8] - {8'b0, !address_scaled_v0_1_r[7]}) &
            address_mask_y0_1_r;
    address_row_shift0_1_d3_r <= address_row_shift0_1_r;
    unused_address_row0_1_0_r <= {9'b0, address_block_y0_1_0_w[8:1]} << address_row_shift0_1_d3_r;
    address_bank0_1_0_r <= {address_block_y0_1_0_w[0], address_block_x0_1_0_w[0]};
    address_subword0_1_0_r <= format_r == 0 ? {address_y0_1_0_r[0], address_x0_1_0_r[0], 2'b0} :
            format_r == 1 ? {address_x0_1_0_r[0], 3'b0} : 4'b0;
    address_offset0_1_d3_r <= address_offset0_1_r;
    unused_address_offset0_1_d4_r <= address_offset0_1_d3_r;
    address_column0_1_0_w_d4_r <= address_column0_1_0_w;
    address_halfword0_1_0_r <= {unused_address_offset0_1_d4_r[16:2] +
            (unused_address_row0_1_0_r[14:0] | {7'b0, address_column0_1_0_w_d4_r}),
                address_bank0_1_0_r};
    address_subword0_1_0_d5_r <= address_subword0_1_0_r;
    address_x0_1_1_r <= (address_scaled_u0_1_r[16:8] + {8'b0, address_scaled_u0_1_r[7]}) &
            address_mask_x0_1_r;
    address_y0_1_1_r <= (address_scaled_v0_1_r[16:8] - {8'b0, !address_scaled_v0_1_r[7]}) &
            address_mask_y0_1_r;
    unused_address_row0_1_1_r <= {9'b0, address_block_y0_1_1_w[8:1]} << address_row_shift0_1_d3_r;
    address_bank0_1_1_r <= {address_block_y0_1_1_w[0], address_block_x0_1_1_w[0]};
    address_subword0_1_1_r <= format_r == 0 ? {address_y0_1_1_r[0], address_x0_1_1_r[0], 2'b0} :
            format_r == 1 ? {address_x0_1_1_r[0], 3'b0} : 4'b0;
    address_column0_1_1_w_d4_r <= address_column0_1_1_w;
    address_halfword0_1_1_r <= {unused_address_offset0_1_d4_r[16:2] +
            (unused_address_row0_1_1_r[14:0] | {7'b0, address_column0_1_1_w_d4_r}),
                address_bank0_1_1_r};
    address_subword0_1_1_d5_r <= address_subword0_1_1_r;
    address_x0_1_2_r <= (address_scaled_u0_1_r[16:8] - {8'b0, !address_scaled_u0_1_r[7]}) &
            address_mask_x0_1_r;
    address_y0_1_2_r <= (address_scaled_v0_1_r[16:8] + {8'b0, address_scaled_v0_1_r[7]}) &
            address_mask_y0_1_r;
    unused_address_row0_1_2_r <= {9'b0, address_block_y0_1_2_w[8:1]} << address_row_shift0_1_d3_r;
    address_bank0_1_2_r <= {address_block_y0_1_2_w[0], address_block_x0_1_2_w[0]};
    address_subword0_1_2_r <= format_r == 0 ? {address_y0_1_2_r[0], address_x0_1_2_r[0], 2'b0} :
            format_r == 1 ? {address_x0_1_2_r[0], 3'b0} : 4'b0;
    address_column0_1_2_w_d4_r <= address_column0_1_2_w;
    address_halfword0_1_2_r <= {unused_address_offset0_1_d4_r[16:2] +
            (unused_address_row0_1_2_r[14:0] | {7'b0, address_column0_1_2_w_d4_r}),
                address_bank0_1_2_r};
    address_subword0_1_2_d5_r <= address_subword0_1_2_r;
    address_x0_1_3_r <= (address_scaled_u0_1_r[16:8] + {8'b0, address_scaled_u0_1_r[7]}) &
            address_mask_x0_1_r;
    address_y0_1_3_r <= (address_scaled_v0_1_r[16:8] + {8'b0, address_scaled_v0_1_r[7]}) &
            address_mask_y0_1_r;
    unused_address_row0_1_3_r <= {9'b0, address_block_y0_1_3_w[8:1]} << address_row_shift0_1_d3_r;
    address_bank0_1_3_r <= {address_block_y0_1_3_w[0], address_block_x0_1_3_w[0]};
    address_subword0_1_3_r <= format_r == 0 ? {address_y0_1_3_r[0], address_x0_1_3_r[0], 2'b0} :
            format_r == 1 ? {address_x0_1_3_r[0], 3'b0} : 4'b0;
    address_column0_1_3_w_d4_r <= address_column0_1_3_w;
    address_halfword0_1_3_r <= {unused_address_offset0_1_d4_r[16:2] +
            (unused_address_row0_1_3_r[14:0] | {7'b0, address_column0_1_3_w_d4_r}),
                address_bank0_1_3_r};
    address_subword0_1_3_d5_r <= address_subword0_1_3_r;
    address_u1_r <= address_input_u_w[32 +: 32];
    address_v1_r <= address_input_v_w[32 +: 32];
    address_level1_r <= quad_r[lod_slot_r[2]] ? 4'b0 : unused_address_input_lod_w[4 +: 4];
    address_next_level1_r <= address_level1_r < levels_r - 4'd1 ? address_level1_r + 4'd1 :
            address_level1_r;
    address_scaled_u1_0_r <= unused_address_scaled_u1_0_wide_w[16:0];
    address_scaled_v1_0_r <= unused_address_scaled_v1_0_wide_w[16:0];
    address_mask_x1_0_r <= mip_mask_x_w[address_level1_r];
    address_mask_y1_0_r <= mip_mask_y_w[address_level1_r];
    address_offset1_0_r <= mip_offset_w[address_level1_r];
    address_row_shift1_0_r <= mip_row_shift_w[address_level1_r];
    address_fraction1_0_r <= {address_scaled_v1_0_r[7:0] ^ 8'h80, address_scaled_u1_0_r[7:0] ^
        8'h80};
    address_x1_0_0_r <= (address_scaled_u1_0_r[16:8] - {8'b0, !address_scaled_u1_0_r[7]}) &
            address_mask_x1_0_r;
    address_y1_0_0_r <= (address_scaled_v1_0_r[16:8] - {8'b0, !address_scaled_v1_0_r[7]}) &
            address_mask_y1_0_r;
    address_row_shift1_0_d2_r <= address_row_shift1_0_r;
    unused_address_row1_0_0_r <= {9'b0, address_block_y1_0_0_w[8:1]} << address_row_shift1_0_d2_r;
    address_bank1_0_0_r <= {address_block_y1_0_0_w[0], address_block_x1_0_0_w[0]};
    address_subword1_0_0_r <= format_r == 0 ? {address_y1_0_0_r[0], address_x1_0_0_r[0], 2'b0} :
            format_r == 1 ? {address_x1_0_0_r[0], 3'b0} : 4'b0;
    address_offset1_0_d2_r <= address_offset1_0_r;
    unused_address_offset1_0_d3_r <= address_offset1_0_d2_r;
    address_column1_0_0_w_d3_r <= address_column1_0_0_w;
    address_halfword1_0_0_r <= {unused_address_offset1_0_d3_r[16:2] +
            (unused_address_row1_0_0_r[14:0] | {7'b0, address_column1_0_0_w_d3_r}),
                address_bank1_0_0_r};
    address_subword1_0_0_d4_r <= address_subword1_0_0_r;
    address_x1_0_1_r <= (address_scaled_u1_0_r[16:8] + {8'b0, address_scaled_u1_0_r[7]}) &
            address_mask_x1_0_r;
    address_y1_0_1_r <= (address_scaled_v1_0_r[16:8] - {8'b0, !address_scaled_v1_0_r[7]}) &
            address_mask_y1_0_r;
    unused_address_row1_0_1_r <= {9'b0, address_block_y1_0_1_w[8:1]} << address_row_shift1_0_d2_r;
    address_bank1_0_1_r <= {address_block_y1_0_1_w[0], address_block_x1_0_1_w[0]};
    address_subword1_0_1_r <= format_r == 0 ? {address_y1_0_1_r[0], address_x1_0_1_r[0], 2'b0} :
            format_r == 1 ? {address_x1_0_1_r[0], 3'b0} : 4'b0;
    address_column1_0_1_w_d3_r <= address_column1_0_1_w;
    address_halfword1_0_1_r <= {unused_address_offset1_0_d3_r[16:2] +
            (unused_address_row1_0_1_r[14:0] | {7'b0, address_column1_0_1_w_d3_r}),
                address_bank1_0_1_r};
    address_subword1_0_1_d4_r <= address_subword1_0_1_r;
    address_x1_0_2_r <= (address_scaled_u1_0_r[16:8] - {8'b0, !address_scaled_u1_0_r[7]}) &
            address_mask_x1_0_r;
    address_y1_0_2_r <= (address_scaled_v1_0_r[16:8] + {8'b0, address_scaled_v1_0_r[7]}) &
            address_mask_y1_0_r;
    unused_address_row1_0_2_r <= {9'b0, address_block_y1_0_2_w[8:1]} << address_row_shift1_0_d2_r;
    address_bank1_0_2_r <= {address_block_y1_0_2_w[0], address_block_x1_0_2_w[0]};
    address_subword1_0_2_r <= format_r == 0 ? {address_y1_0_2_r[0], address_x1_0_2_r[0], 2'b0} :
            format_r == 1 ? {address_x1_0_2_r[0], 3'b0} : 4'b0;
    address_column1_0_2_w_d3_r <= address_column1_0_2_w;
    address_halfword1_0_2_r <= {unused_address_offset1_0_d3_r[16:2] +
            (unused_address_row1_0_2_r[14:0] | {7'b0, address_column1_0_2_w_d3_r}),
                address_bank1_0_2_r};
    address_subword1_0_2_d4_r <= address_subword1_0_2_r;
    address_x1_0_3_r <= (address_scaled_u1_0_r[16:8] + {8'b0, address_scaled_u1_0_r[7]}) &
            address_mask_x1_0_r;
    address_y1_0_3_r <= (address_scaled_v1_0_r[16:8] + {8'b0, address_scaled_v1_0_r[7]}) &
            address_mask_y1_0_r;
    unused_address_row1_0_3_r <= {9'b0, address_block_y1_0_3_w[8:1]} << address_row_shift1_0_d2_r;
    address_bank1_0_3_r <= {address_block_y1_0_3_w[0], address_block_x1_0_3_w[0]};
    address_subword1_0_3_r <= format_r == 0 ? {address_y1_0_3_r[0], address_x1_0_3_r[0], 2'b0} :
            format_r == 1 ? {address_x1_0_3_r[0], 3'b0} : 4'b0;
    address_column1_0_3_w_d3_r <= address_column1_0_3_w;
    address_halfword1_0_3_r <= {unused_address_offset1_0_d3_r[16:2] +
            (unused_address_row1_0_3_r[14:0] | {7'b0, address_column1_0_3_w_d3_r}),
                address_bank1_0_3_r};
    address_subword1_0_3_d4_r <= address_subword1_0_3_r;
    address_x1_0_4_r <= address_scaled_u1_0_r[16:8] & address_mask_x1_0_r;
    address_y1_0_4_r <= address_scaled_v1_0_r[16:8] & address_mask_y1_0_r;
    unused_address_row1_0_4_r <= {9'b0, address_block_y1_0_4_w[8:1]} << address_row_shift1_0_d2_r;
    address_bank1_0_4_r <= {address_block_y1_0_4_w[0], address_block_x1_0_4_w[0]};
    address_subword1_0_4_r <= format_r == 0 ? {address_y1_0_4_r[0], address_x1_0_4_r[0], 2'b0} :
            format_r == 1 ? {address_x1_0_4_r[0], 3'b0} : 4'b0;
    address_column1_0_4_w_d3_r <= address_column1_0_4_w;
    address_halfword1_0_4_r <= {unused_address_offset1_0_d3_r[16:2] +
            (unused_address_row1_0_4_r[14:0] | {7'b0, address_column1_0_4_w_d3_r}),
                address_bank1_0_4_r};
    address_subword1_0_4_d4_r <= address_subword1_0_4_r;
    address_u1_r_d1_r <= address_u1_r;
    address_scaled_u1_1_r <= unused_address_scaled_u1_1_wide_w[16:0];
    address_v1_r_d1_r <= address_v1_r;
    address_scaled_v1_1_r <= unused_address_scaled_v1_1_wide_w[16:0];
    address_mask_x1_1_r <= mip_mask_x_w[address_next_level1_r];
    address_mask_y1_1_r <= mip_mask_y_w[address_next_level1_r];
    address_offset1_1_r <= mip_offset_w[address_next_level1_r];
    address_row_shift1_1_r <= mip_row_shift_w[address_next_level1_r];
    address_fraction1_1_r <= {address_scaled_v1_1_r[7:0] ^ 8'h80, address_scaled_u1_1_r[7:0] ^
        8'h80};
    address_x1_1_0_r <= (address_scaled_u1_1_r[16:8] - {8'b0, !address_scaled_u1_1_r[7]}) &
            address_mask_x1_1_r;
    address_y1_1_0_r <= (address_scaled_v1_1_r[16:8] - {8'b0, !address_scaled_v1_1_r[7]}) &
            address_mask_y1_1_r;
    address_row_shift1_1_d3_r <= address_row_shift1_1_r;
    unused_address_row1_1_0_r <= {9'b0, address_block_y1_1_0_w[8:1]} << address_row_shift1_1_d3_r;
    address_bank1_1_0_r <= {address_block_y1_1_0_w[0], address_block_x1_1_0_w[0]};
    address_subword1_1_0_r <= format_r == 0 ? {address_y1_1_0_r[0], address_x1_1_0_r[0], 2'b0} :
            format_r == 1 ? {address_x1_1_0_r[0], 3'b0} : 4'b0;
    address_offset1_1_d3_r <= address_offset1_1_r;
    unused_address_offset1_1_d4_r <= address_offset1_1_d3_r;
    address_column1_1_0_w_d4_r <= address_column1_1_0_w;
    address_halfword1_1_0_r <= {unused_address_offset1_1_d4_r[16:2] +
            (unused_address_row1_1_0_r[14:0] | {7'b0, address_column1_1_0_w_d4_r}),
                address_bank1_1_0_r};
    address_subword1_1_0_d5_r <= address_subword1_1_0_r;
    address_x1_1_1_r <= (address_scaled_u1_1_r[16:8] + {8'b0, address_scaled_u1_1_r[7]}) &
            address_mask_x1_1_r;
    address_y1_1_1_r <= (address_scaled_v1_1_r[16:8] - {8'b0, !address_scaled_v1_1_r[7]}) &
            address_mask_y1_1_r;
    unused_address_row1_1_1_r <= {9'b0, address_block_y1_1_1_w[8:1]} << address_row_shift1_1_d3_r;
    address_bank1_1_1_r <= {address_block_y1_1_1_w[0], address_block_x1_1_1_w[0]};
    address_subword1_1_1_r <= format_r == 0 ? {address_y1_1_1_r[0], address_x1_1_1_r[0], 2'b0} :
            format_r == 1 ? {address_x1_1_1_r[0], 3'b0} : 4'b0;
    address_column1_1_1_w_d4_r <= address_column1_1_1_w;
    address_halfword1_1_1_r <= {unused_address_offset1_1_d4_r[16:2] +
            (unused_address_row1_1_1_r[14:0] | {7'b0, address_column1_1_1_w_d4_r}),
                address_bank1_1_1_r};
    address_subword1_1_1_d5_r <= address_subword1_1_1_r;
    address_x1_1_2_r <= (address_scaled_u1_1_r[16:8] - {8'b0, !address_scaled_u1_1_r[7]}) &
            address_mask_x1_1_r;
    address_y1_1_2_r <= (address_scaled_v1_1_r[16:8] + {8'b0, address_scaled_v1_1_r[7]}) &
            address_mask_y1_1_r;
    unused_address_row1_1_2_r <= {9'b0, address_block_y1_1_2_w[8:1]} << address_row_shift1_1_d3_r;
    address_bank1_1_2_r <= {address_block_y1_1_2_w[0], address_block_x1_1_2_w[0]};
    address_subword1_1_2_r <= format_r == 0 ? {address_y1_1_2_r[0], address_x1_1_2_r[0], 2'b0} :
            format_r == 1 ? {address_x1_1_2_r[0], 3'b0} : 4'b0;
    address_column1_1_2_w_d4_r <= address_column1_1_2_w;
    address_halfword1_1_2_r <= {unused_address_offset1_1_d4_r[16:2] +
            (unused_address_row1_1_2_r[14:0] | {7'b0, address_column1_1_2_w_d4_r}),
                address_bank1_1_2_r};
    address_subword1_1_2_d5_r <= address_subword1_1_2_r;
    address_x1_1_3_r <= (address_scaled_u1_1_r[16:8] + {8'b0, address_scaled_u1_1_r[7]}) &
            address_mask_x1_1_r;
    address_y1_1_3_r <= (address_scaled_v1_1_r[16:8] + {8'b0, address_scaled_v1_1_r[7]}) &
            address_mask_y1_1_r;
    unused_address_row1_1_3_r <= {9'b0, address_block_y1_1_3_w[8:1]} << address_row_shift1_1_d3_r;
    address_bank1_1_3_r <= {address_block_y1_1_3_w[0], address_block_x1_1_3_w[0]};
    address_subword1_1_3_r <= format_r == 0 ? {address_y1_1_3_r[0], address_x1_1_3_r[0], 2'b0} :
            format_r == 1 ? {address_x1_1_3_r[0], 3'b0} : 4'b0;
    address_column1_1_3_w_d4_r <= address_column1_1_3_w;
    address_halfword1_1_3_r <= {unused_address_offset1_1_d4_r[16:2] +
            (unused_address_row1_1_3_r[14:0] | {7'b0, address_column1_1_3_w_d4_r}),
                address_bank1_1_3_r};
    address_subword1_1_3_d5_r <= address_subword1_1_3_r;
    address_u2_r <= address_input_u_w[64 +: 32];
    address_v2_r <= address_input_v_w[64 +: 32];
    address_level2_r <= quad_r[lod_slot_r[2]] ? 4'b0 : unused_address_input_lod_w[8 +: 4];
    address_next_level2_r <= address_level2_r < levels_r - 4'd1 ? address_level2_r + 4'd1 :
            address_level2_r;
    address_scaled_u2_0_r <= unused_address_scaled_u2_0_wide_w[16:0];
    address_scaled_v2_0_r <= unused_address_scaled_v2_0_wide_w[16:0];
    address_mask_x2_0_r <= mip_mask_x_w[address_level2_r];
    address_mask_y2_0_r <= mip_mask_y_w[address_level2_r];
    address_offset2_0_r <= mip_offset_w[address_level2_r];
    address_row_shift2_0_r <= mip_row_shift_w[address_level2_r];
    address_fraction2_0_r <= {address_scaled_v2_0_r[7:0] ^ 8'h80, address_scaled_u2_0_r[7:0] ^
        8'h80};
    address_x2_0_0_r <= (address_scaled_u2_0_r[16:8] - {8'b0, !address_scaled_u2_0_r[7]}) &
            address_mask_x2_0_r;
    address_y2_0_0_r <= (address_scaled_v2_0_r[16:8] - {8'b0, !address_scaled_v2_0_r[7]}) &
            address_mask_y2_0_r;
    address_row_shift2_0_d2_r <= address_row_shift2_0_r;
    unused_address_row2_0_0_r <= {9'b0, address_block_y2_0_0_w[8:1]} << address_row_shift2_0_d2_r;
    address_bank2_0_0_r <= {address_block_y2_0_0_w[0], address_block_x2_0_0_w[0]};
    address_subword2_0_0_r <= format_r == 0 ? {address_y2_0_0_r[0], address_x2_0_0_r[0], 2'b0} :
            format_r == 1 ? {address_x2_0_0_r[0], 3'b0} : 4'b0;
    address_offset2_0_d2_r <= address_offset2_0_r;
    unused_address_offset2_0_d3_r <= address_offset2_0_d2_r;
    address_column2_0_0_w_d3_r <= address_column2_0_0_w;
    address_halfword2_0_0_r <= {unused_address_offset2_0_d3_r[16:2] +
            (unused_address_row2_0_0_r[14:0] | {7'b0, address_column2_0_0_w_d3_r}),
                address_bank2_0_0_r};
    address_subword2_0_0_d4_r <= address_subword2_0_0_r;
    address_x2_0_1_r <= (address_scaled_u2_0_r[16:8] + {8'b0, address_scaled_u2_0_r[7]}) &
            address_mask_x2_0_r;
    address_y2_0_1_r <= (address_scaled_v2_0_r[16:8] - {8'b0, !address_scaled_v2_0_r[7]}) &
            address_mask_y2_0_r;
    unused_address_row2_0_1_r <= {9'b0, address_block_y2_0_1_w[8:1]} << address_row_shift2_0_d2_r;
    address_bank2_0_1_r <= {address_block_y2_0_1_w[0], address_block_x2_0_1_w[0]};
    address_subword2_0_1_r <= format_r == 0 ? {address_y2_0_1_r[0], address_x2_0_1_r[0], 2'b0} :
            format_r == 1 ? {address_x2_0_1_r[0], 3'b0} : 4'b0;
    address_column2_0_1_w_d3_r <= address_column2_0_1_w;
    address_halfword2_0_1_r <= {unused_address_offset2_0_d3_r[16:2] +
            (unused_address_row2_0_1_r[14:0] | {7'b0, address_column2_0_1_w_d3_r}),
                address_bank2_0_1_r};
    address_subword2_0_1_d4_r <= address_subword2_0_1_r;
    address_x2_0_2_r <= (address_scaled_u2_0_r[16:8] - {8'b0, !address_scaled_u2_0_r[7]}) &
            address_mask_x2_0_r;
    address_y2_0_2_r <= (address_scaled_v2_0_r[16:8] + {8'b0, address_scaled_v2_0_r[7]}) &
            address_mask_y2_0_r;
    unused_address_row2_0_2_r <= {9'b0, address_block_y2_0_2_w[8:1]} << address_row_shift2_0_d2_r;
    address_bank2_0_2_r <= {address_block_y2_0_2_w[0], address_block_x2_0_2_w[0]};
    address_subword2_0_2_r <= format_r == 0 ? {address_y2_0_2_r[0], address_x2_0_2_r[0], 2'b0} :
            format_r == 1 ? {address_x2_0_2_r[0], 3'b0} : 4'b0;
    address_column2_0_2_w_d3_r <= address_column2_0_2_w;
    address_halfword2_0_2_r <= {unused_address_offset2_0_d3_r[16:2] +
            (unused_address_row2_0_2_r[14:0] | {7'b0, address_column2_0_2_w_d3_r}),
                address_bank2_0_2_r};
    address_subword2_0_2_d4_r <= address_subword2_0_2_r;
    address_x2_0_3_r <= (address_scaled_u2_0_r[16:8] + {8'b0, address_scaled_u2_0_r[7]}) &
            address_mask_x2_0_r;
    address_y2_0_3_r <= (address_scaled_v2_0_r[16:8] + {8'b0, address_scaled_v2_0_r[7]}) &
            address_mask_y2_0_r;
    unused_address_row2_0_3_r <= {9'b0, address_block_y2_0_3_w[8:1]} << address_row_shift2_0_d2_r;
    address_bank2_0_3_r <= {address_block_y2_0_3_w[0], address_block_x2_0_3_w[0]};
    address_subword2_0_3_r <= format_r == 0 ? {address_y2_0_3_r[0], address_x2_0_3_r[0], 2'b0} :
            format_r == 1 ? {address_x2_0_3_r[0], 3'b0} : 4'b0;
    address_column2_0_3_w_d3_r <= address_column2_0_3_w;
    address_halfword2_0_3_r <= {unused_address_offset2_0_d3_r[16:2] +
            (unused_address_row2_0_3_r[14:0] | {7'b0, address_column2_0_3_w_d3_r}),
                address_bank2_0_3_r};
    address_subword2_0_3_d4_r <= address_subword2_0_3_r;
    address_x2_0_4_r <= address_scaled_u2_0_r[16:8] & address_mask_x2_0_r;
    address_y2_0_4_r <= address_scaled_v2_0_r[16:8] & address_mask_y2_0_r;
    unused_address_row2_0_4_r <= {9'b0, address_block_y2_0_4_w[8:1]} << address_row_shift2_0_d2_r;
    address_bank2_0_4_r <= {address_block_y2_0_4_w[0], address_block_x2_0_4_w[0]};
    address_subword2_0_4_r <= format_r == 0 ? {address_y2_0_4_r[0], address_x2_0_4_r[0], 2'b0} :
            format_r == 1 ? {address_x2_0_4_r[0], 3'b0} : 4'b0;
    address_column2_0_4_w_d3_r <= address_column2_0_4_w;
    address_halfword2_0_4_r <= {unused_address_offset2_0_d3_r[16:2] +
            (unused_address_row2_0_4_r[14:0] | {7'b0, address_column2_0_4_w_d3_r}),
                address_bank2_0_4_r};
    address_subword2_0_4_d4_r <= address_subword2_0_4_r;
    address_u2_r_d1_r <= address_u2_r;
    address_scaled_u2_1_r <= unused_address_scaled_u2_1_wide_w[16:0];
    address_v2_r_d1_r <= address_v2_r;
    address_scaled_v2_1_r <= unused_address_scaled_v2_1_wide_w[16:0];
    address_mask_x2_1_r <= mip_mask_x_w[address_next_level2_r];
    address_mask_y2_1_r <= mip_mask_y_w[address_next_level2_r];
    address_offset2_1_r <= mip_offset_w[address_next_level2_r];
    address_row_shift2_1_r <= mip_row_shift_w[address_next_level2_r];
    address_fraction2_1_r <= {address_scaled_v2_1_r[7:0] ^ 8'h80, address_scaled_u2_1_r[7:0] ^
        8'h80};
    address_x2_1_0_r <= (address_scaled_u2_1_r[16:8] - {8'b0, !address_scaled_u2_1_r[7]}) &
            address_mask_x2_1_r;
    address_y2_1_0_r <= (address_scaled_v2_1_r[16:8] - {8'b0, !address_scaled_v2_1_r[7]}) &
            address_mask_y2_1_r;
    address_row_shift2_1_d3_r <= address_row_shift2_1_r;
    unused_address_row2_1_0_r <= {9'b0, address_block_y2_1_0_w[8:1]} << address_row_shift2_1_d3_r;
    address_bank2_1_0_r <= {address_block_y2_1_0_w[0], address_block_x2_1_0_w[0]};
    address_subword2_1_0_r <= format_r == 0 ? {address_y2_1_0_r[0], address_x2_1_0_r[0], 2'b0} :
            format_r == 1 ? {address_x2_1_0_r[0], 3'b0} : 4'b0;
    address_offset2_1_d3_r <= address_offset2_1_r;
    unused_address_offset2_1_d4_r <= address_offset2_1_d3_r;
    address_column2_1_0_w_d4_r <= address_column2_1_0_w;
    address_halfword2_1_0_r <= {unused_address_offset2_1_d4_r[16:2] +
            (unused_address_row2_1_0_r[14:0] | {7'b0, address_column2_1_0_w_d4_r}),
                address_bank2_1_0_r};
    address_subword2_1_0_d5_r <= address_subword2_1_0_r;
    address_x2_1_1_r <= (address_scaled_u2_1_r[16:8] + {8'b0, address_scaled_u2_1_r[7]}) &
            address_mask_x2_1_r;
    address_y2_1_1_r <= (address_scaled_v2_1_r[16:8] - {8'b0, !address_scaled_v2_1_r[7]}) &
            address_mask_y2_1_r;
    unused_address_row2_1_1_r <= {9'b0, address_block_y2_1_1_w[8:1]} << address_row_shift2_1_d3_r;
    address_bank2_1_1_r <= {address_block_y2_1_1_w[0], address_block_x2_1_1_w[0]};
    address_subword2_1_1_r <= format_r == 0 ? {address_y2_1_1_r[0], address_x2_1_1_r[0], 2'b0} :
            format_r == 1 ? {address_x2_1_1_r[0], 3'b0} : 4'b0;
    address_column2_1_1_w_d4_r <= address_column2_1_1_w;
    address_halfword2_1_1_r <= {unused_address_offset2_1_d4_r[16:2] +
            (unused_address_row2_1_1_r[14:0] | {7'b0, address_column2_1_1_w_d4_r}),
                address_bank2_1_1_r};
    address_subword2_1_1_d5_r <= address_subword2_1_1_r;
    address_x2_1_2_r <= (address_scaled_u2_1_r[16:8] - {8'b0, !address_scaled_u2_1_r[7]}) &
            address_mask_x2_1_r;
    address_y2_1_2_r <= (address_scaled_v2_1_r[16:8] + {8'b0, address_scaled_v2_1_r[7]}) &
            address_mask_y2_1_r;
    unused_address_row2_1_2_r <= {9'b0, address_block_y2_1_2_w[8:1]} << address_row_shift2_1_d3_r;
    address_bank2_1_2_r <= {address_block_y2_1_2_w[0], address_block_x2_1_2_w[0]};
    address_subword2_1_2_r <= format_r == 0 ? {address_y2_1_2_r[0], address_x2_1_2_r[0], 2'b0} :
            format_r == 1 ? {address_x2_1_2_r[0], 3'b0} : 4'b0;
    address_column2_1_2_w_d4_r <= address_column2_1_2_w;
    address_halfword2_1_2_r <= {unused_address_offset2_1_d4_r[16:2] +
            (unused_address_row2_1_2_r[14:0] | {7'b0, address_column2_1_2_w_d4_r}),
                address_bank2_1_2_r};
    address_subword2_1_2_d5_r <= address_subword2_1_2_r;
    address_x2_1_3_r <= (address_scaled_u2_1_r[16:8] + {8'b0, address_scaled_u2_1_r[7]}) &
            address_mask_x2_1_r;
    address_y2_1_3_r <= (address_scaled_v2_1_r[16:8] + {8'b0, address_scaled_v2_1_r[7]}) &
            address_mask_y2_1_r;
    unused_address_row2_1_3_r <= {9'b0, address_block_y2_1_3_w[8:1]} << address_row_shift2_1_d3_r;
    address_bank2_1_3_r <= {address_block_y2_1_3_w[0], address_block_x2_1_3_w[0]};
    address_subword2_1_3_r <= format_r == 0 ? {address_y2_1_3_r[0], address_x2_1_3_r[0], 2'b0} :
            format_r == 1 ? {address_x2_1_3_r[0], 3'b0} : 4'b0;
    address_column2_1_3_w_d4_r <= address_column2_1_3_w;
    address_halfword2_1_3_r <= {unused_address_offset2_1_d4_r[16:2] +
            (unused_address_row2_1_3_r[14:0] | {7'b0, address_column2_1_3_w_d4_r}),
                address_bank2_1_3_r};
    address_subword2_1_3_d5_r <= address_subword2_1_3_r;
    address_u3_r <= address_input_u_w[96 +: 32];
    address_v3_r <= address_input_v_w[96 +: 32];
    address_level3_r <= quad_r[lod_slot_r[2]] ? 4'b0 : unused_address_input_lod_w[12 +: 4];
    address_next_level3_r <= address_level3_r < levels_r - 4'd1 ? address_level3_r + 4'd1 :
            address_level3_r;
    address_scaled_u3_0_r <= unused_address_scaled_u3_0_wide_w[16:0];
    address_scaled_v3_0_r <= unused_address_scaled_v3_0_wide_w[16:0];
    address_mask_x3_0_r <= mip_mask_x_w[address_level3_r];
    address_mask_y3_0_r <= mip_mask_y_w[address_level3_r];
    address_offset3_0_r <= mip_offset_w[address_level3_r];
    address_row_shift3_0_r <= mip_row_shift_w[address_level3_r];
    address_fraction3_0_r <= {address_scaled_v3_0_r[7:0] ^ 8'h80, address_scaled_u3_0_r[7:0] ^
        8'h80};
    address_x3_0_0_r <= (address_scaled_u3_0_r[16:8] - {8'b0, !address_scaled_u3_0_r[7]}) &
            address_mask_x3_0_r;
    address_y3_0_0_r <= (address_scaled_v3_0_r[16:8] - {8'b0, !address_scaled_v3_0_r[7]}) &
            address_mask_y3_0_r;
    address_row_shift3_0_d2_r <= address_row_shift3_0_r;
    unused_address_row3_0_0_r <= {9'b0, address_block_y3_0_0_w[8:1]} << address_row_shift3_0_d2_r;
    address_bank3_0_0_r <= {address_block_y3_0_0_w[0], address_block_x3_0_0_w[0]};
    address_subword3_0_0_r <= format_r == 0 ? {address_y3_0_0_r[0], address_x3_0_0_r[0], 2'b0} :
            format_r == 1 ? {address_x3_0_0_r[0], 3'b0} : 4'b0;
    address_offset3_0_d2_r <= address_offset3_0_r;
    unused_address_offset3_0_d3_r <= address_offset3_0_d2_r;
    address_column3_0_0_w_d3_r <= address_column3_0_0_w;
    address_halfword3_0_0_r <= {unused_address_offset3_0_d3_r[16:2] +
            (unused_address_row3_0_0_r[14:0] | {7'b0, address_column3_0_0_w_d3_r}),
                address_bank3_0_0_r};
    address_subword3_0_0_d4_r <= address_subword3_0_0_r;
    address_x3_0_1_r <= (address_scaled_u3_0_r[16:8] + {8'b0, address_scaled_u3_0_r[7]}) &
            address_mask_x3_0_r;
    address_y3_0_1_r <= (address_scaled_v3_0_r[16:8] - {8'b0, !address_scaled_v3_0_r[7]}) &
            address_mask_y3_0_r;
    unused_address_row3_0_1_r <= {9'b0, address_block_y3_0_1_w[8:1]} << address_row_shift3_0_d2_r;
    address_bank3_0_1_r <= {address_block_y3_0_1_w[0], address_block_x3_0_1_w[0]};
    address_subword3_0_1_r <= format_r == 0 ? {address_y3_0_1_r[0], address_x3_0_1_r[0], 2'b0} :
            format_r == 1 ? {address_x3_0_1_r[0], 3'b0} : 4'b0;
    address_column3_0_1_w_d3_r <= address_column3_0_1_w;
    address_halfword3_0_1_r <= {unused_address_offset3_0_d3_r[16:2] +
            (unused_address_row3_0_1_r[14:0] | {7'b0, address_column3_0_1_w_d3_r}),
                address_bank3_0_1_r};
    address_subword3_0_1_d4_r <= address_subword3_0_1_r;
    address_x3_0_2_r <= (address_scaled_u3_0_r[16:8] - {8'b0, !address_scaled_u3_0_r[7]}) &
            address_mask_x3_0_r;
    address_y3_0_2_r <= (address_scaled_v3_0_r[16:8] + {8'b0, address_scaled_v3_0_r[7]}) &
            address_mask_y3_0_r;
    unused_address_row3_0_2_r <= {9'b0, address_block_y3_0_2_w[8:1]} << address_row_shift3_0_d2_r;
    address_bank3_0_2_r <= {address_block_y3_0_2_w[0], address_block_x3_0_2_w[0]};
    address_subword3_0_2_r <= format_r == 0 ? {address_y3_0_2_r[0], address_x3_0_2_r[0], 2'b0} :
            format_r == 1 ? {address_x3_0_2_r[0], 3'b0} : 4'b0;
    address_column3_0_2_w_d3_r <= address_column3_0_2_w;
    address_halfword3_0_2_r <= {unused_address_offset3_0_d3_r[16:2] +
            (unused_address_row3_0_2_r[14:0] | {7'b0, address_column3_0_2_w_d3_r}),
                address_bank3_0_2_r};
    address_subword3_0_2_d4_r <= address_subword3_0_2_r;
    address_x3_0_3_r <= (address_scaled_u3_0_r[16:8] + {8'b0, address_scaled_u3_0_r[7]}) &
            address_mask_x3_0_r;
    address_y3_0_3_r <= (address_scaled_v3_0_r[16:8] + {8'b0, address_scaled_v3_0_r[7]}) &
            address_mask_y3_0_r;
    unused_address_row3_0_3_r <= {9'b0, address_block_y3_0_3_w[8:1]} << address_row_shift3_0_d2_r;
    address_bank3_0_3_r <= {address_block_y3_0_3_w[0], address_block_x3_0_3_w[0]};
    address_subword3_0_3_r <= format_r == 0 ? {address_y3_0_3_r[0], address_x3_0_3_r[0], 2'b0} :
            format_r == 1 ? {address_x3_0_3_r[0], 3'b0} : 4'b0;
    address_column3_0_3_w_d3_r <= address_column3_0_3_w;
    address_halfword3_0_3_r <= {unused_address_offset3_0_d3_r[16:2] +
            (unused_address_row3_0_3_r[14:0] | {7'b0, address_column3_0_3_w_d3_r}),
                address_bank3_0_3_r};
    address_subword3_0_3_d4_r <= address_subword3_0_3_r;
    address_x3_0_4_r <= address_scaled_u3_0_r[16:8] & address_mask_x3_0_r;
    address_y3_0_4_r <= address_scaled_v3_0_r[16:8] & address_mask_y3_0_r;
    unused_address_row3_0_4_r <= {9'b0, address_block_y3_0_4_w[8:1]} << address_row_shift3_0_d2_r;
    address_bank3_0_4_r <= {address_block_y3_0_4_w[0], address_block_x3_0_4_w[0]};
    address_subword3_0_4_r <= format_r == 0 ? {address_y3_0_4_r[0], address_x3_0_4_r[0], 2'b0} :
            format_r == 1 ? {address_x3_0_4_r[0], 3'b0} : 4'b0;
    address_column3_0_4_w_d3_r <= address_column3_0_4_w;
    address_halfword3_0_4_r <= {unused_address_offset3_0_d3_r[16:2] +
            (unused_address_row3_0_4_r[14:0] | {7'b0, address_column3_0_4_w_d3_r}),
                address_bank3_0_4_r};
    address_subword3_0_4_d4_r <= address_subword3_0_4_r;
    address_u3_r_d1_r <= address_u3_r;
    address_scaled_u3_1_r <= unused_address_scaled_u3_1_wide_w[16:0];
    address_v3_r_d1_r <= address_v3_r;
    address_scaled_v3_1_r <= unused_address_scaled_v3_1_wide_w[16:0];
    address_mask_x3_1_r <= mip_mask_x_w[address_next_level3_r];
    address_mask_y3_1_r <= mip_mask_y_w[address_next_level3_r];
    address_offset3_1_r <= mip_offset_w[address_next_level3_r];
    address_row_shift3_1_r <= mip_row_shift_w[address_next_level3_r];
    address_fraction3_1_r <= {address_scaled_v3_1_r[7:0] ^ 8'h80, address_scaled_u3_1_r[7:0] ^
        8'h80};
    address_x3_1_0_r <= (address_scaled_u3_1_r[16:8] - {8'b0, !address_scaled_u3_1_r[7]}) &
            address_mask_x3_1_r;
    address_y3_1_0_r <= (address_scaled_v3_1_r[16:8] - {8'b0, !address_scaled_v3_1_r[7]}) &
            address_mask_y3_1_r;
    address_row_shift3_1_d3_r <= address_row_shift3_1_r;
    unused_address_row3_1_0_r <= {9'b0, address_block_y3_1_0_w[8:1]} << address_row_shift3_1_d3_r;
    address_bank3_1_0_r <= {address_block_y3_1_0_w[0], address_block_x3_1_0_w[0]};
    address_subword3_1_0_r <= format_r == 0 ? {address_y3_1_0_r[0], address_x3_1_0_r[0], 2'b0} :
            format_r == 1 ? {address_x3_1_0_r[0], 3'b0} : 4'b0;
    address_offset3_1_d3_r <= address_offset3_1_r;
    unused_address_offset3_1_d4_r <= address_offset3_1_d3_r;
    address_column3_1_0_w_d4_r <= address_column3_1_0_w;
    address_halfword3_1_0_r <= {unused_address_offset3_1_d4_r[16:2] +
            (unused_address_row3_1_0_r[14:0] | {7'b0, address_column3_1_0_w_d4_r}),
                address_bank3_1_0_r};
    address_subword3_1_0_d5_r <= address_subword3_1_0_r;
    address_x3_1_1_r <= (address_scaled_u3_1_r[16:8] + {8'b0, address_scaled_u3_1_r[7]}) &
            address_mask_x3_1_r;
    address_y3_1_1_r <= (address_scaled_v3_1_r[16:8] - {8'b0, !address_scaled_v3_1_r[7]}) &
            address_mask_y3_1_r;
    unused_address_row3_1_1_r <= {9'b0, address_block_y3_1_1_w[8:1]} << address_row_shift3_1_d3_r;
    address_bank3_1_1_r <= {address_block_y3_1_1_w[0], address_block_x3_1_1_w[0]};
    address_subword3_1_1_r <= format_r == 0 ? {address_y3_1_1_r[0], address_x3_1_1_r[0], 2'b0} :
            format_r == 1 ? {address_x3_1_1_r[0], 3'b0} : 4'b0;
    address_column3_1_1_w_d4_r <= address_column3_1_1_w;
    address_halfword3_1_1_r <= {unused_address_offset3_1_d4_r[16:2] +
            (unused_address_row3_1_1_r[14:0] | {7'b0, address_column3_1_1_w_d4_r}),
                address_bank3_1_1_r};
    address_subword3_1_1_d5_r <= address_subword3_1_1_r;
    address_x3_1_2_r <= (address_scaled_u3_1_r[16:8] - {8'b0, !address_scaled_u3_1_r[7]}) &
            address_mask_x3_1_r;
    address_y3_1_2_r <= (address_scaled_v3_1_r[16:8] + {8'b0, address_scaled_v3_1_r[7]}) &
            address_mask_y3_1_r;
    unused_address_row3_1_2_r <= {9'b0, address_block_y3_1_2_w[8:1]} << address_row_shift3_1_d3_r;
    address_bank3_1_2_r <= {address_block_y3_1_2_w[0], address_block_x3_1_2_w[0]};
    address_subword3_1_2_r <= format_r == 0 ? {address_y3_1_2_r[0], address_x3_1_2_r[0], 2'b0} :
            format_r == 1 ? {address_x3_1_2_r[0], 3'b0} : 4'b0;
    address_column3_1_2_w_d4_r <= address_column3_1_2_w;
    address_halfword3_1_2_r <= {unused_address_offset3_1_d4_r[16:2] +
            (unused_address_row3_1_2_r[14:0] | {7'b0, address_column3_1_2_w_d4_r}),
                address_bank3_1_2_r};
    address_subword3_1_2_d5_r <= address_subword3_1_2_r;
    address_x3_1_3_r <= (address_scaled_u3_1_r[16:8] + {8'b0, address_scaled_u3_1_r[7]}) &
            address_mask_x3_1_r;
    address_y3_1_3_r <= (address_scaled_v3_1_r[16:8] + {8'b0, address_scaled_v3_1_r[7]}) &
            address_mask_y3_1_r;
    unused_address_row3_1_3_r <= {9'b0, address_block_y3_1_3_w[8:1]} << address_row_shift3_1_d3_r;
    address_bank3_1_3_r <= {address_block_y3_1_3_w[0], address_block_x3_1_3_w[0]};
    address_subword3_1_3_r <= format_r == 0 ? {address_y3_1_3_r[0], address_x3_1_3_r[0], 2'b0} :
            format_r == 1 ? {address_x3_1_3_r[0], 3'b0} : 4'b0;
    address_column3_1_3_w_d4_r <= address_column3_1_3_w;
    address_halfword3_1_3_r <= {unused_address_offset3_1_d4_r[16:2] +
            (unused_address_row3_1_3_r[14:0] | {7'b0, address_column3_1_3_w_d4_r}),
                address_bank3_1_3_r};
    address_subword3_1_3_d5_r <= address_subword3_1_3_r;
    address_slot_0_r_d1_r <= address_slot_0_r;
    address_slot_0_r_d2_r <= address_slot_0_r_d1_r;
    address_slot_0_r_d3_r <= address_slot_0_r_d2_r;
    address_slot_0_r_d4_r <= address_slot_0_r_d3_r;
    address_slot_0_r_d5_r <= address_slot_0_r_d4_r;
    address_slot_0_r_d6_r <= address_slot_0_r_d5_r;
    address_record0_0_0_w_d5_r <= address_record0_0_0_w;
    address_record0_0_1_w_d5_r <= address_record0_0_1_w;
    address_record0_0_2_w_d5_r <= address_record0_0_2_w;
    address_record0_0_3_w_d5_r <= address_record0_0_3_w;
    address_record0_0_4_w_d5_r <= address_record0_0_4_w;
    address_fraction0_0_d3_r <= address_fraction0_0_r;
    address_fraction0_0_d4_r <= address_fraction0_0_d3_r;
    address_fraction0_0_d5_r <= address_fraction0_0_d4_r;
    address_fraction0_1_d4_r <= address_fraction0_1_r;
    address_fraction0_1_d5_r <= address_fraction0_1_d4_r;
    address_record1_0_0_w_d5_r <= address_record1_0_0_w;
    address_record1_0_1_w_d5_r <= address_record1_0_1_w;
    address_record1_0_2_w_d5_r <= address_record1_0_2_w;
    address_record1_0_3_w_d5_r <= address_record1_0_3_w;
    address_record1_0_4_w_d5_r <= address_record1_0_4_w;
    address_fraction1_0_d3_r <= address_fraction1_0_r;
    address_fraction1_0_d4_r <= address_fraction1_0_d3_r;
    address_fraction1_0_d5_r <= address_fraction1_0_d4_r;
    address_fraction1_1_d4_r <= address_fraction1_1_r;
    address_fraction1_1_d5_r <= address_fraction1_1_d4_r;
    address_record2_0_0_w_d5_r <= address_record2_0_0_w;
    address_record2_0_1_w_d5_r <= address_record2_0_1_w;
    address_record2_0_2_w_d5_r <= address_record2_0_2_w;
    address_record2_0_3_w_d5_r <= address_record2_0_3_w;
    address_record2_0_4_w_d5_r <= address_record2_0_4_w;
    address_fraction2_0_d3_r <= address_fraction2_0_r;
    address_fraction2_0_d4_r <= address_fraction2_0_d3_r;
    address_fraction2_0_d5_r <= address_fraction2_0_d4_r;
    address_fraction2_1_d4_r <= address_fraction2_1_r;
    address_fraction2_1_d5_r <= address_fraction2_1_d4_r;
    address_record3_0_0_w_d5_r <= address_record3_0_0_w;
    address_record3_0_1_w_d5_r <= address_record3_0_1_w;
    address_record3_0_2_w_d5_r <= address_record3_0_2_w;
    address_record3_0_3_w_d5_r <= address_record3_0_3_w;
    address_record3_0_4_w_d5_r <= address_record3_0_4_w;
    address_fraction3_0_d3_r <= address_fraction3_0_r;
    address_fraction3_0_d4_r <= address_fraction3_0_d3_r;
    address_fraction3_0_d5_r <= address_fraction3_0_d4_r;
    address_fraction3_1_d4_r <= address_fraction3_1_r;
    address_fraction3_1_d5_r <= address_fraction3_1_d4_r;
    end
    assign unused_address_scaled_u0_0_wide_w = $signed(address_u0_r) >>> address_level0_r;
    assign unused_address_scaled_v0_0_wide_w = $signed(address_v0_r) >>> address_level0_r;
    assign unused_address_scaled_u0_1_wide_w = $signed(address_u0_r_d1_r) >>> address_next_level0_r;
    assign unused_address_scaled_v0_1_wide_w = $signed(address_v0_r_d1_r) >>> address_next_level0_r;
    assign unused_address_scaled_u1_0_wide_w = $signed(address_u1_r) >>> address_level1_r;
    assign unused_address_scaled_v1_0_wide_w = $signed(address_v1_r) >>> address_level1_r;
    assign unused_address_scaled_u1_1_wide_w = $signed(address_u1_r_d1_r) >>> address_next_level1_r;
    assign unused_address_scaled_v1_1_wide_w = $signed(address_v1_r_d1_r) >>> address_next_level1_r;
    assign unused_address_scaled_u2_0_wide_w = $signed(address_u2_r) >>> address_level2_r;
    assign unused_address_scaled_v2_0_wide_w = $signed(address_v2_r) >>> address_level2_r;
    assign unused_address_scaled_u2_1_wide_w = $signed(address_u2_r_d1_r) >>> address_next_level2_r;
    assign unused_address_scaled_v2_1_wide_w = $signed(address_v2_r_d1_r) >>> address_next_level2_r;
    assign unused_address_scaled_u3_0_wide_w = $signed(address_u3_r) >>> address_level3_r;
    assign unused_address_scaled_v3_0_wide_w = $signed(address_v3_r) >>> address_level3_r;
    assign unused_address_scaled_u3_1_wide_w = $signed(address_u3_r_d1_r) >>> address_next_level3_r;
    assign unused_address_scaled_v3_1_wide_w = $signed(address_v3_r_d1_r) >>> address_next_level3_r;
    // Explicit LUTRAM retire_context: 2 slice(s) per combinational read port.
    wire [143:0] retire_context_input_w;
    assign retire_context_input_w = {48'b0, sample_depth_i, sample_y_i, sample_x_i};
    wire [143:0] unused_retire_context_read0_w;
    edrv32_ram_gpu_table u_retire_context_p0_b0 (
        .clk_i(clk_i),
        .wr_en_i(accept_w),
        .wr_addr_i({1'b0, allocate_r[4:0]}),
        .wr_data_i(retire_context_input_w[0 +: 72]),
        .rd_addr_i({1'b0, retire_r[4:0]}),
        .rd_data_o(unused_retire_context_read0_w[0 +: 72])
    );
    edrv32_ram_gpu_table u_retire_context_p0_b1 (
        .clk_i(clk_i),
        .wr_en_i(accept_w),
        .wr_addr_i({1'b0, allocate_r[4:0]}),
        .wr_data_i(retire_context_input_w[72 +: 72]),
        .rd_addr_i({1'b0, retire_r[4:0]}),
        .rd_data_o(unused_retire_context_read0_w[72 +: 72])
    );
    // Explicit LUTRAM shade_context: 2 slice(s) per combinational read port.
    wire [143:0] shade_context_input_w;
    assign shade_context_input_w = {40'b0, sample_alpha_i, sample_color_i};
    wire [143:0] unused_shade_context_read0_w;
    edrv32_ram_gpu_table u_shade_context_p0_b0 (
        .clk_i(clk_i),
        .wr_en_i(accept_w),
        .wr_addr_i({1'b0, allocate_r[4:0]}),
        .wr_data_i(shade_context_input_w[0 +: 72]),
        .rd_addr_i({1'b0, filter_slot_r[5]}),
        .rd_data_o(unused_shade_context_read0_w[0 +: 72])
    );
    edrv32_ram_gpu_table u_shade_context_p0_b1 (
        .clk_i(clk_i),
        .wr_en_i(accept_w),
        .wr_addr_i({1'b0, allocate_r[4:0]}),
        .wr_data_i(shade_context_input_w[72 +: 72]),
        .rd_addr_i({1'b0, filter_slot_r[5]}),
        .rd_data_o(unused_shade_context_read0_w[72 +: 72])
    );
endmodule
