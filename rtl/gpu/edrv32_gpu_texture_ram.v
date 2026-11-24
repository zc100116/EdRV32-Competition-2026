// File: edrv32_gpu_texture_ram.v
// Spec: gpu-spec 2.6; GPU microarchitecture 4.2, 4.5, 4.8.
// Description: 192 KiB four-bank texture storage and four-cycle beat loader.
// Clock: clk_gpu.
module edrv32_gpu_texture_ram (
    // Clock and command lifetime.
    input wire clk_i,
    input wire rst_n_i,
    input wire finish_i,
    input wire stop_i,
    output reg unit_done_o,

    // Linear, offline-interleaved byte stream.
    input wire texture_load_valid_i,
    output wire texture_load_ready_o,
    input wire [17:0] texture_load_addr_i,
    input wire [255:0] texture_load_data_i,
    input wire [31:0] texture_load_keep_i,

    // Internal sampling: two independent row addresses per bank, fixed five cycles.
    input wire [7:0] read_en_i,
    input wire [119:0] read_addr_i,
    output wire [127:0] read_data_o
);
    wire unused_load_addr_w;
    assign unused_load_addr_w = ^texture_load_addr_i[2:0];
    reg load_active_r;
    reg [1:0] load_step_r;
    reg [14:0] load_row_r;
    reg [255:0] load_data_r;
    reg [31:0] load_keep_r;
    assign texture_load_ready_o = !load_active_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            load_active_r <= 1'b0;
            load_step_r <= 2'b0;
            unit_done_o <= 1'b0;
        end else begin
            if (!finish_i) begin
                unit_done_o <= 1'b0;
            end else if (!load_active_r && !texture_load_valid_i) begin
                unit_done_o <= 1'b1;
            end
            if (load_active_r) begin
                if (load_step_r == 2'd3) begin
                    load_active_r <= 1'b0;
                end
                load_step_r <= load_step_r + 1'b1;
            end else if (texture_load_valid_i && !stop_i) begin
                load_active_r <= 1'b1;
                load_step_r <= 2'b0;
            end
        end
    end
    always @(posedge clk_i) begin
        if (texture_load_valid_i && texture_load_ready_o && !stop_i) begin
            load_row_r <= texture_load_addr_i[17:3];
            load_data_r <= texture_load_data_i;
            load_keep_r <= texture_load_keep_i;
        end
    end
    genvar bank;
    genvar segment;
    genvar group_idx;
    generate
        for (bank = 0; bank < 4; bank = bank + 1) begin : g_bank
            wire [14:0] wr_row_w;
            reg [1:0] read_en_r;
            reg [29:0] read_addr_r;
            reg [7:0] segment_a_r;
            reg [7:0] segment_b_r;
            wire [15:0] segment_a_w [0:11];
            wire [15:0] segment_b_w [0:11];
            wire [15:0] group_a_w [0:2];
            wire [15:0] group_b_w [0:2];
            reg [15:0] wr_data_w;
            reg [1:0] wr_keep_w;
            reg [15:0] final_a_w;
            reg [15:0] final_b_w;
            reg [3:0] final_select_r;
            reg [31:0] read_data_r;
            assign wr_row_w = load_row_r + {13'b0, load_step_r};
            assign read_data_o[bank*32 +: 32] = read_data_r;
            always @(posedge clk_i) begin
                read_en_r <= read_en_i[bank*2 +: 2];
                read_addr_r <= read_addr_i[bank*30 +: 30];
                segment_a_r <= {segment_a_r[3:0], read_addr_r[14:11]};
                segment_b_r <= {segment_b_r[3:0], read_addr_r[29:26]};
                final_select_r <= {segment_b_r[7:6], segment_a_r[7:6]};
            end
            // Load stage: four independent 4:1 halfword/byte-enable selectors.
            always @(*) begin
                wr_data_w = 0;
                wr_keep_w = 0;
                case (load_step_r)
                    2'd0: begin
                        wr_data_w = load_data_r[0+bank*16 +: 16];
                        wr_keep_w = load_keep_r[0+bank*2 +: 2];
                    end
                    2'd1: begin
                        wr_data_w = load_data_r[64+bank*16 +: 16];
                        wr_keep_w = load_keep_r[8+bank*2 +: 2];
                    end
                    2'd2: begin
                        wr_data_w = load_data_r[128+bank*16 +: 16];
                        wr_keep_w = load_keep_r[16+bank*2 +: 2];
                    end
                    2'd3: begin
                        wr_data_w = load_data_r[192+bank*16 +: 16];
                        wr_keep_w = load_keep_r[24+bank*2 +: 2];
                    end
                    default: begin
                        wr_data_w = 0;
                        wr_keep_w = 0;
                    end
                endcase
            end
            for (segment = 0; segment < 12; segment = segment + 1) begin : g_segment
                edrv32_ram_gpu_texture_segment u_ram (
                    .clk_i(clk_i),
                    .wr_en_i(load_active_r && wr_row_w[14:11] == segment),
                    .wr_addr_i(wr_row_w[10:0]),
                    .wr_data_i(wr_data_w),
                    .wr_keep_i(wr_keep_w),
                    .rd_a_en_i(read_en_r[0] && read_addr_r[14:11] == segment),
                    .rd_b_en_i(read_en_r[1] && read_addr_r[29:26] == segment),
                    .rd_a_addr_i(read_addr_r[10:0]),
                    .rd_b_addr_i(read_addr_r[25:15]),
                    .rd_a_data_o(segment_a_w[segment]),
                    .rd_b_data_o(segment_b_w[segment])
                );
            end
            // Read stage 4: three pairs of 4:1 selectors per bank, then stage 5: 3:1.
            for (group_idx = 0; group_idx < 3; group_idx = group_idx + 1) begin : g_group
                reg [15:0] a_r;
                reg [15:0] b_r;
                reg [15:0] a_w;
                reg [15:0] b_w;
                assign group_a_w[group_idx] = a_r;
                assign group_b_w[group_idx] = b_r;
                always @(*) begin
                    a_w = 0;
                    case (segment_a_r[5:4])
                        2'd0: a_w = segment_a_w[group_idx*4+0];
                        2'd1: a_w = segment_a_w[group_idx*4+1];
                        2'd2: a_w = segment_a_w[group_idx*4+2];
                        2'd3: a_w = segment_a_w[group_idx*4+3];
                        default: a_w = 0;
                    endcase
                end
                always @(*) begin
                    b_w = 0;
                    case (segment_b_r[5:4])
                        2'd0: b_w = segment_b_w[group_idx*4+0];
                        2'd1: b_w = segment_b_w[group_idx*4+1];
                        2'd2: b_w = segment_b_w[group_idx*4+2];
                        2'd3: b_w = segment_b_w[group_idx*4+3];
                        default: b_w = 0;
                    endcase
                end
                always @(posedge clk_i) begin
                    a_r <= a_w;
                    b_r <= b_w;
                end
            end
            always @(*) begin
                final_a_w = 16'bx;
                case (final_select_r[1:0])
                    2'd0: final_a_w = group_a_w[0];
                    2'd1: final_a_w = group_a_w[1];
                    2'd2: final_a_w = group_a_w[2];
                    default: final_a_w = 16'bx;
                endcase
            end
            always @(*) begin
                final_b_w = 16'bx;
                case (final_select_r[3:2])
                    2'd0: final_b_w = group_b_w[0];
                    2'd1: final_b_w = group_b_w[1];
                    2'd2: final_b_w = group_b_w[2];
                    default: final_b_w = 16'bx;
                endcase
            end
            always @(posedge clk_i) begin
                read_data_r <= {final_b_w, final_a_w};
            end
        end
    endgenerate
endmodule
