// File: edrv32_gpu_unpack.v
// Spec: gpu-spec 2.3; gpu-microarch 4.5.
// Description: Two-slot DMA return buffers split vertices, quads and palette entries.
// Matrix assembly and linear texture addresses use the command snapshot.
// Clock: clk_gpu.
module edrv32_gpu_unpack (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Current serial command.
    input wire unpack_valid_i,
    output wire unpack_ready_o,
    input wire [255:0] unpack_command_i,
    input wire matrix_read_data_valid_i,
    output wire matrix_read_data_ready_o,
    input wire [255:0] matrix_read_data_data_i,
    input wire [31:0] matrix_read_data_keep_i,
    input wire matrix_read_data_last_i,
    input wire vertex_read_data_valid_i,
    output wire vertex_read_data_ready_o,
    input wire [255:0] vertex_read_data_data_i,
    input wire [31:0] vertex_read_data_keep_i,
    input wire vertex_read_data_last_i,
    input wire quad_read_data_valid_i,
    output wire quad_read_data_ready_o,
    input wire [255:0] quad_read_data_data_i,
    input wire [31:0] quad_read_data_keep_i,
    input wire quad_read_data_last_i,
    input wire texture_read_data_valid_i,
    output wire texture_read_data_ready_o,
    input wire [255:0] texture_read_data_data_i,
    input wire [31:0] texture_read_data_keep_i,
    input wire texture_read_data_last_i,
    input wire palette_read_data_valid_i,
    output wire palette_read_data_ready_o,
    input wire [255:0] palette_read_data_data_i,
    input wire [31:0] palette_read_data_keep_i,
    input wire palette_read_data_last_i,

    // Unpacked consumers.
    output wire matrix_valid_o,
    input wire matrix_ready_i,
    output wire [511:0] matrix_data_o,
    output wire vertex_valid_o,
    input wire vertex_ready_i,
    output wire [127:0] vertex_data_o,
    output wire quad_record_valid_o,
    input wire quad_record_ready_i,
    output wire [127:0] quad_record_data_o,
    output wire texture_load_valid_o,
    input wire texture_load_ready_i,
    output wire [17:0] texture_load_addr_o,
    output wire [255:0] texture_load_data_o,
    output wire [31:0] texture_load_keep_o,
    output wire palette_load_valid_o,
    input wire palette_load_ready_i,
    output wire [11:0] palette_load_idx_o,
    output wire [19:0] palette_load_data_o,

    // Lifecycle.
    input wire stop_i,
    output wire unit_done_o
);
    reg busy_r;
    reg done_r;
    wire [4:0] valid_w;
    wire [255:0] data_w [0:4];
    wire [31:0] keep_w [0:4];
    wire [4:0] last_w;
    wire [4:0] push_w;
    wire [4:0] pop_w;
    wire [255:0] head_data_w [0:4];
    wire [31:0] head_keep_w [1:3];
    wire [4:1] head_last_w;
    wire [255:0] matrix_second_w;
    wire unused_matrix_w;
    reg [4:0] head_r;
    reg [4:0] tail_r;
    reg [1:0] count_r [0:4];
    reg vertex_half_r;
    reg quad_half_r;
    reg [2:0] palette_word_r;
    reg [11:0] palette_idx_r;
    reg [17:0] texture_addr_r;
    wire vertex_fire_w;
    wire quad_fire_w;
    wire texture_fire_w;
    wire palette_fire_w;
    wire palette_end_w;
    wire [7:0] palette_end_flags_w;
    wire unused_command_w;
    assign unused_command_w = ^{unpack_command_i[255:114], unpack_command_i[100:36],
        unpack_command_i[31:0]};
    assign unpack_ready_o = !busy_r;
    assign unit_done_o = done_r;
    assign valid_w[0] = matrix_read_data_valid_i;
    assign data_w[0] = matrix_read_data_data_i;
    assign keep_w[0] = matrix_read_data_keep_i;
    assign last_w[0] = matrix_read_data_last_i;
    assign matrix_read_data_ready_o = stop_i || count_r[0] < 2;
    assign push_w[0] = valid_w[0] && matrix_read_data_ready_o && !stop_i;
    assign valid_w[1] = vertex_read_data_valid_i;
    assign data_w[1] = vertex_read_data_data_i;
    assign keep_w[1] = vertex_read_data_keep_i;
    assign last_w[1] = vertex_read_data_last_i;
    assign vertex_read_data_ready_o = stop_i || count_r[1] < 2;
    assign push_w[1] = valid_w[1] && vertex_read_data_ready_o && !stop_i;
    assign valid_w[2] = quad_read_data_valid_i;
    assign data_w[2] = quad_read_data_data_i;
    assign keep_w[2] = quad_read_data_keep_i;
    assign last_w[2] = quad_read_data_last_i;
    assign quad_read_data_ready_o = stop_i || count_r[2] < 2;
    assign push_w[2] = valid_w[2] && quad_read_data_ready_o && !stop_i;
    assign valid_w[3] = texture_read_data_valid_i;
    assign data_w[3] = texture_read_data_data_i;
    assign keep_w[3] = texture_read_data_keep_i;
    assign last_w[3] = texture_read_data_last_i;
    assign texture_read_data_ready_o = stop_i || count_r[3] < 2;
    assign push_w[3] = valid_w[3] && texture_read_data_ready_o && !stop_i;
    assign valid_w[4] = palette_read_data_valid_i;
    assign data_w[4] = palette_read_data_data_i;
    assign keep_w[4] = palette_read_data_keep_i;
    assign last_w[4] = palette_read_data_last_i;
    assign palette_read_data_ready_o = stop_i || count_r[4] < 2;
    assign push_w[4] = valid_w[4] && palette_read_data_ready_o && !stop_i;
    assign matrix_valid_o = busy_r && count_r[0] == 2 && !stop_i;
    assign matrix_data_o = {matrix_second_w, head_data_w[0]};
    assign vertex_valid_o = busy_r && count_r[1] != 0 && !stop_i;
    assign vertex_data_o = head_data_w[1][vertex_half_r*128 +: 128];
    assign vertex_fire_w = vertex_valid_o && vertex_ready_i;
    assign quad_record_valid_o = busy_r && count_r[2] != 0 && !stop_i;
    assign quad_record_data_o = head_data_w[2][quad_half_r*128 +: 128];
    assign quad_fire_w = quad_record_valid_o && quad_record_ready_i;
    assign texture_load_valid_o = busy_r && count_r[3] != 0 && !stop_i;
    assign texture_load_addr_o = texture_addr_r;
    assign texture_load_data_o = head_data_w[3];
    assign texture_load_keep_o = head_keep_w[3];
    assign texture_fire_w = texture_load_valid_o && texture_load_ready_i;
    assign palette_load_valid_o = busy_r && count_r[4] != 0 && !stop_i;
    assign palette_load_idx_o = palette_idx_r;
    reg [19:0] palette_data_w;
    assign palette_load_data_o = palette_data_w;
    always @(*) begin
        palette_data_w = 0;
        case (palette_word_r)
            3'd0: palette_data_w = head_data_w[4][0 +: 20];
            3'd1: palette_data_w = head_data_w[4][32 +: 20];
            3'd2: palette_data_w = head_data_w[4][64 +: 20];
            3'd3: palette_data_w = head_data_w[4][96 +: 20];
            3'd4: palette_data_w = head_data_w[4][128 +: 20];
            3'd5: palette_data_w = head_data_w[4][160 +: 20];
            3'd6: palette_data_w = head_data_w[4][192 +: 20];
            3'd7: palette_data_w = head_data_w[4][224 +: 20];
            default: palette_data_w = 0;
        endcase
    end
    assign palette_fire_w = palette_load_valid_o && palette_load_ready_i;
    assign palette_end_w = palette_end_flags_w[palette_word_r];
    assign pop_w[0] = matrix_valid_o && matrix_ready_i;
    assign pop_w[1] = vertex_fire_w && (vertex_half_r
        || !head_keep_w[1][16]);
    assign pop_w[2] = quad_fire_w && (quad_half_r
        || !head_keep_w[2][16]);
    assign pop_w[3] = texture_fire_w;
    assign pop_w[4] = palette_fire_w && palette_end_w;

    genvar c;
    generate
        for (c = 0; c < 5; c = c + 1) begin : g_return
            // Two-slot return buffer per client in plain registers: a shared array
            // written by five processes crashes PDS RAM inference (card 109).
            reg [255:0] slot0_data_r;
            reg [255:0] slot1_data_r;
            always @(posedge clk_i) begin
                if (push_w[c] && !tail_r[c]) slot0_data_r <= data_w[c];
                if (push_w[c] && tail_r[c]) slot1_data_r <= data_w[c];
            end
            assign head_data_w[c] = head_r[c] ? slot1_data_r : slot0_data_r;
            if (c == 0) begin : g_matrix
                // The matrix client consumes both slots and never uses keep or last.
                assign matrix_second_w = head_r[c] ? slot0_data_r : slot1_data_r;
                assign unused_matrix_w = ^{keep_w[c], last_w[c]};
            end else begin : g_tag
                localparam PALETTE_CLIENT = 4;
                if (c == PALETTE_CLIENT)
                begin : g_palette_keep
                    reg [7:0] slot0_end_r;
                    reg [7:0] slot1_end_r;
                    wire [7:0] end_flags_w;
                    wire [31:0] unused_palette_keep_w;
                    assign unused_palette_keep_w = keep_w[c];
                    assign palette_end_flags_w = head_r[c] ? slot1_end_r : slot0_end_r;
                    assign end_flags_w[0] = !(|unused_palette_keep_w[31:4]);
                    assign end_flags_w[1] = !(|unused_palette_keep_w[31:8]);
                    assign end_flags_w[2] = !(|unused_palette_keep_w[31:12]);
                    assign end_flags_w[3] = !(|unused_palette_keep_w[31:16]);
                    assign end_flags_w[4] = !(|unused_palette_keep_w[31:20]);
                    assign end_flags_w[5] = !(|unused_palette_keep_w[31:24]);
                    assign end_flags_w[6] = !(|unused_palette_keep_w[31:28]);
                    assign end_flags_w[7] = 1'b1;
                    always @(posedge clk_i) begin
                        if (push_w[c] && !tail_r[c]) slot0_end_r <= end_flags_w;
                        if (push_w[c] && tail_r[c]) slot1_end_r <= end_flags_w;
                    end
                end else begin : g_other_keep
                    reg [31:0] slot0_keep_r;
                    reg [31:0] slot1_keep_r;
                    assign head_keep_w[c] = head_r[c] ? slot1_keep_r : slot0_keep_r;
                    always @(posedge clk_i) begin
                        if (push_w[c] && !tail_r[c]) slot0_keep_r <= keep_w[c];
                        if (push_w[c] && tail_r[c]) slot1_keep_r <= keep_w[c];
                    end
                end
                reg slot0_last_r;
                reg slot1_last_r;
                always @(posedge clk_i) begin
                    if (push_w[c] && !tail_r[c]) begin
                        slot0_last_r <= last_w[c];
                    end
                    if (push_w[c] && tail_r[c]) begin
                        slot1_last_r <= last_w[c];
                    end
                end
                assign head_last_w[c] = head_r[c] ? slot1_last_r : slot0_last_r;
            end
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    head_r[c] <= 1'b0;
                    tail_r[c] <= 1'b0;
                    count_r[c] <= 2'b0;
                end else if (stop_i || (unpack_valid_i && unpack_ready_o)) begin
                    head_r[c] <= 1'b0;
                    tail_r[c] <= 1'b0;
                    count_r[c] <= 2'b0;
                end else begin
                    if (push_w[c]) tail_r[c] <= !tail_r[c];
                    if (pop_w[c]) head_r[c] <= !head_r[c];
                    if (c == 0 && pop_w[c]) count_r[c] <= 2'b0;
                    else begin
                        case ({push_w[c], pop_w[c]})
                            2'b10: count_r[c] <= count_r[c] + 2'd1;
                            2'b01: count_r[c] <= count_r[c] - 2'd1;
                            default: begin end
                        endcase
                    end
                end
            end
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            busy_r <= 1'b0;
            done_r <= 1'b1;
            vertex_half_r <= 1'b0;
            quad_half_r <= 1'b0;
            palette_word_r <= 3'b0;
            palette_idx_r <= 12'b0;
            texture_addr_r <= 18'b0;
        end else begin
            if (unpack_valid_i && unpack_ready_o) begin
                busy_r <= 1'b1;
                done_r <= 1'b0;
                vertex_half_r <= 1'b0;
                quad_half_r <= 1'b0;
                palette_word_r <= 3'b0;
                palette_idx_r <= {unpack_command_i[35:32], 8'b0};
                texture_addr_r <= {unpack_command_i[113:101], 5'b0};
            end
            if (vertex_fire_w) vertex_half_r <= !vertex_half_r && !pop_w[1];
            if (quad_fire_w) quad_half_r <= !quad_half_r && !pop_w[2];
            if (texture_fire_w) texture_addr_r <= texture_addr_r + 18'd32;
            if (palette_fire_w) begin
                palette_word_r <= palette_end_w ? 3'b0 : palette_word_r + 3'd1;
                palette_idx_r <= palette_idx_r + 12'd1;
            end
            if (stop_i || pop_w[0]
                || (pop_w[1] && head_last_w[1])
                || (pop_w[2] && head_last_w[2])
                || (pop_w[3] && head_last_w[3])
                || (pop_w[4] && head_last_w[4])) begin
                busy_r <= 1'b0;
                done_r <= 1'b1;
            end
        end
    end
endmodule
