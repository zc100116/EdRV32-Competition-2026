// File: edrv32_gpu_regs.v
// Spec: gpu-spec 4; edrv32-soc-spec 4.3, 7.1, 7.2.
// Description: Local APB setup capture, GPU configuration, IRQ and event counters.
// Clock: clk_gpu.
module edrv32_gpu_regs (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // APB control interface.
    input wire [11:0] s_apb_paddr_i,
    input wire s_apb_psel_i,
    input wire s_apb_penable_i,
    input wire s_apb_pwrite_i,
    input wire [31:0] s_apb_pwdata_i,
    input wire [3:0] s_apb_pstrb_i,
    output wire s_apb_pready_o,
    output wire [31:0] s_apb_prdata_o,
    output wire s_apb_pslverr_o,

    // Command control and completion.
    output wire enable_o,
    output reg start_o,
    output reg abort_o,
    output reg soft_rst_o,
    output wire [31:0] desc_base_o,
    output wire [15:0] desc_count_o,
    output wire wide_o,
    input wire busy_i,
    input wire done_i,
    input wire error_i,
    input wire [31:0] err_code_i,

    // Object configuration snapshot and result publication.
    input wire object_cfg_request_i,
    output reg object_cfg_valid_o,
    input wire object_cfg_ready_i,
    output reg [63:0] object_cfg_live_o,
    output reg [511:0] object_cfg_targets_o,
    output reg [31:0] object_cfg_hit_base_o,
    output reg [23:0] object_cfg_hit_max_o,
    output reg [31:0] object_cfg_free_base_o,
    output reg [23:0] object_cfg_free_max_o,
    input wire object_result_valid_i,
    output wire object_result_ready_o,
    input wire [23:0] object_result_hit_count_i,
    input wire [23:0] object_result_free_count_i,
    input wire [23:0] object_result_alive_count_i,
    input wire [1:0] object_result_overflow_i,

    // Performance events and interrupt.
    input wire perf_vertex_i,
    input wire perf_triangle_i,
    input wire perf_quad_i,
    input wire [2:0] perf_pixel_count_i,
    input wire perf_texture_stall_i,
    input wire perf_read_wait_i,
    input wire perf_resolve_busy_i,
    input wire perf_object_busy_i,
    output wire irq_o
);
    reg [11:0] apb_addr_r;
    reg apb_write_r;
    reg [31:0] apb_data_r;
    reg [3:0] apb_strb_r;
    wire write_w;
    wire [31:0] write_mask_w;
    reg enable_r;
    reg [1:0] irq_en_r;
    reg [1:0] irq_stat_r;
    reg [31:0] err_code_r;
    reg [31:0] desc_base_r;
    reg [15:0] desc_count_r;
    reg [31:0] done_count_r;
    reg wide_r;
    reg [63:0] object_live_r;
    reg [511:0] object_targets_r;
    reg [31:0] object_hit_base_r;
    reg [23:0] object_hit_max_r;
    reg [31:0] object_free_base_r;
    reg [23:0] object_free_max_r;
    reg [23:0] object_hit_count_r;
    reg [23:0] object_free_count_r;
    reg [23:0] object_alive_count_r;
    reg [1:0] object_overflow_r;
    reg [2:0] perf_event_r [0:8];
    reg [31:0] perf_r [0:8];
    integer idx_r;

    assign s_apb_pready_o = 1'b1;
    assign s_apb_pslverr_o = 1'b0;
    assign write_w = s_apb_psel_i && s_apb_penable_i && apb_write_r;
    assign write_mask_w = {{8{apb_strb_r[3]}}, {8{apb_strb_r[2]}},
                            {8{apb_strb_r[1]}}, {8{apb_strb_r[0]}}};
    assign enable_o = enable_r;
    assign desc_base_o = desc_base_r;
    assign desc_count_o = desc_count_r;
    assign wide_o = wide_r;
    assign irq_o = |(irq_en_r & irq_stat_r);
    assign object_result_ready_o = 1'b1;

    always @(posedge clk_i) begin
        if (s_apb_psel_i && !s_apb_penable_i) begin
            apb_addr_r <= s_apb_paddr_i;
            apb_write_r <= s_apb_pwrite_i;
            apb_data_r <= s_apb_pwdata_i;
            apb_strb_r <= s_apb_pstrb_i;
        end
        if (object_cfg_request_i) begin
            object_cfg_live_o <= object_live_r;
            object_cfg_targets_o <= object_targets_r;
            object_cfg_hit_base_o <= object_hit_base_r;
            object_cfg_hit_max_o <= object_hit_max_r;
            object_cfg_free_base_o <= object_free_base_r;
            object_cfg_free_max_o <= object_free_max_r;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            enable_r <= 1'b0;
            start_o <= 1'b0;
            abort_o <= 1'b0;
            soft_rst_o <= 1'b0;
            irq_en_r <= 2'b0;
            irq_stat_r <= 2'b0;
            err_code_r <= 32'b0;
            desc_base_r <= 32'b0;
            desc_count_r <= 16'b0;
            done_count_r <= 32'b0;
            wide_r <= 1'b0;
            object_live_r <= 64'b0;
            object_targets_r <= 512'b0;
            object_hit_base_r <= 32'b0;
            object_hit_max_r <= 24'b0;
            object_free_base_r <= 32'b0;
            object_free_max_r <= 24'b0;
            object_hit_count_r <= 24'b0;
            object_free_count_r <= 24'b0;
            object_alive_count_r <= 24'b0;
            object_overflow_r <= 2'b0;
            object_cfg_valid_o <= 1'b0;
        end else begin
            start_o <= 1'b0;
            abort_o <= 1'b0;
            soft_rst_o <= 1'b0;
            if (object_cfg_valid_o && object_cfg_ready_i) object_cfg_valid_o <= 1'b0;
            if (object_cfg_request_i) begin
                object_cfg_valid_o <= 1'b1;
                object_overflow_r <= 2'b0;
            end
            if (write_w) begin
                case (apb_addr_r)
                    12'h004: begin
                        if (apb_strb_r[0]) begin
                            enable_r <= apb_data_r[0];
                            start_o <= apb_data_r[1];
                            abort_o <= apb_data_r[2];
                            soft_rst_o <= apb_data_r[3];
                        end
                    end
                    12'h00c: if (apb_strb_r[0]) irq_en_r <= apb_data_r[1:0];
                    12'h010: begin
                        if (apb_strb_r[0]) begin
                            irq_stat_r <= irq_stat_r & ~apb_data_r[1:0];
                            if (apb_data_r[1]) err_code_r <= 32'b0;
                        end
                    end
                    12'h020: desc_base_r <= ((desc_base_r & ~write_mask_w)
                        | (apb_data_r & write_mask_w)) & 32'hffffffe0;
                    12'h024: desc_count_r <= (desc_count_r & ~write_mask_w[15:0])
                        | (apb_data_r[15:0] & write_mask_w[15:0]);
                    12'h028: start_o <= 1'b1;
                    12'h100: if (apb_strb_r[0]) wide_r <= apb_data_r[0];
                    12'h110: object_live_r[31:0] <= ((object_live_r[31:0] & ~write_mask_w)
                        | (apb_data_r & write_mask_w));
                    12'h114: object_live_r[63:32] <= ((object_live_r[63:32] & ~write_mask_w)
                        | (apb_data_r & write_mask_w));
                    12'h118: object_hit_base_r <= ((object_hit_base_r & ~write_mask_w)
                        | (apb_data_r & write_mask_w)) & 32'hffffffe0;
                    12'h11c: object_hit_max_r <= ((object_hit_max_r & ~write_mask_w[23:0])
                        | (apb_data_r[23:0] & write_mask_w[23:0]));
                    12'h124: object_free_base_r <= ((object_free_base_r & ~write_mask_w)
                        | (apb_data_r & write_mask_w)) & 32'hffffffe0;
                    12'h128: object_free_max_r <= ((object_free_max_r & ~write_mask_w[23:0])
                        | (apb_data_r[23:0] & write_mask_w[23:0]));
                    12'h140: object_targets_r[31:0] <=
                        ((object_targets_r[31:0] & ~write_mask_w)
                        | (apb_data_r & write_mask_w));
                    12'h144: object_targets_r[63:32] <=
                        ((object_targets_r[63:32] & ~write_mask_w)
                        | (apb_data_r & write_mask_w));
                    12'h148: object_targets_r[95:64] <=
                        ((object_targets_r[95:64] & ~write_mask_w)
                        | (apb_data_r & write_mask_w));
                    12'h14c: object_targets_r[127:96] <=
                        ((object_targets_r[127:96] & ~write_mask_w)
                        | (apb_data_r & write_mask_w));
                    12'h150: object_targets_r[159:128] <=
                        ((object_targets_r[159:128] & ~write_mask_w)
                        | (apb_data_r & write_mask_w));
                    12'h154: object_targets_r[191:160] <=
                        ((object_targets_r[191:160] & ~write_mask_w)
                        | (apb_data_r & write_mask_w));
                    12'h158: object_targets_r[223:192] <=
                        ((object_targets_r[223:192] & ~write_mask_w)
                        | (apb_data_r & write_mask_w));
                    12'h15c: object_targets_r[255:224] <=
                        ((object_targets_r[255:224] & ~write_mask_w)
                        | (apb_data_r & write_mask_w));
                    12'h160: object_targets_r[287:256] <=
                        ((object_targets_r[287:256] & ~write_mask_w)
                        | (apb_data_r & write_mask_w));
                    12'h164: object_targets_r[319:288] <=
                        ((object_targets_r[319:288] & ~write_mask_w)
                        | (apb_data_r & write_mask_w));
                    12'h168: object_targets_r[351:320] <=
                        ((object_targets_r[351:320] & ~write_mask_w)
                        | (apb_data_r & write_mask_w));
                    12'h16c: object_targets_r[383:352] <=
                        ((object_targets_r[383:352] & ~write_mask_w)
                        | (apb_data_r & write_mask_w));
                    12'h170: object_targets_r[415:384] <=
                        ((object_targets_r[415:384] & ~write_mask_w)
                        | (apb_data_r & write_mask_w));
                    12'h174: object_targets_r[447:416] <=
                        ((object_targets_r[447:416] & ~write_mask_w)
                        | (apb_data_r & write_mask_w));
                    12'h178: object_targets_r[479:448] <=
                        ((object_targets_r[479:448] & ~write_mask_w)
                        | (apb_data_r & write_mask_w));
                    12'h17c: object_targets_r[511:480] <=
                        ((object_targets_r[511:480] & ~write_mask_w)
                        | (apb_data_r & write_mask_w));
                    default: begin end
                endcase
            end
            // New events win a simultaneous RW1C, so no completion is lost.
            if (done_i) begin
                irq_stat_r[0] <= 1'b1;
                done_count_r <= done_count_r + 32'd1;
            end
            if (error_i) begin
                irq_stat_r[1] <= 1'b1;
                err_code_r <= err_code_i;
            end
            if (object_result_valid_i) begin
                object_hit_count_r <= object_result_hit_count_i;
                object_free_count_r <= object_result_free_count_i;
                object_alive_count_r <= object_result_alive_count_i;
                object_overflow_r <= object_result_overflow_i;
            end
        end
    end

    // SoC 7.1: register statistics events before accumulation.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            for (idx_r = 0; idx_r < 9; idx_r = idx_r + 1) begin
                perf_event_r[idx_r] <= 3'b0;
                perf_r[idx_r] <= 32'b0;
            end
        end else begin
            perf_event_r[0] <= {2'b0, busy_i};
            perf_event_r[1] <= {2'b0, perf_vertex_i};
            perf_event_r[2] <= {2'b0, perf_triangle_i};
            perf_event_r[3] <= {2'b0, perf_quad_i};
            perf_event_r[4] <= perf_pixel_count_i;
            perf_event_r[5] <= {2'b0, perf_texture_stall_i};
            perf_event_r[6] <= {2'b0, perf_read_wait_i};
            perf_event_r[7] <= {2'b0, perf_resolve_busy_i};
            perf_event_r[8] <= {2'b0, perf_object_busy_i};
            for (idx_r = 0; idx_r < 9; idx_r = idx_r + 1)
                perf_r[idx_r] <= perf_r[idx_r] + {29'b0, perf_event_r[idx_r]};
        end
    end

    reg [44:0] read_select_r;
    wire [31:0] read_term_w [0:44];
    assign read_term_w[0] = {32{read_select_r[0]}} & (32'h00060001);
    assign read_term_w[1] = {32{read_select_r[1]}} & ({31'b0, enable_r});
    assign read_term_w[2] = {32{read_select_r[2]}} & ({29'b0, irq_stat_r[1], !busy_i, busy_i});
    assign read_term_w[3] = {32{read_select_r[3]}} & ({30'b0, irq_en_r});
    assign read_term_w[4] = {32{read_select_r[4]}} & ({30'b0, irq_stat_r});
    assign read_term_w[5] = {32{read_select_r[5]}} & (err_code_r);
    assign read_term_w[6] = {32{read_select_r[6]}} & (desc_base_r);
    assign read_term_w[7] = {32{read_select_r[7]}} & ({16'b0, desc_count_r});
    assign read_term_w[8] = {32{read_select_r[8]}} & (done_count_r);
    assign read_term_w[9] = {32{read_select_r[9]}} & ({31'b0, wide_r});
    assign read_term_w[10] = {32{read_select_r[10]}} & (object_live_r[31:0]);
    assign read_term_w[11] = {32{read_select_r[11]}} & (object_live_r[63:32]);
    assign read_term_w[12] = {32{read_select_r[12]}} & (object_hit_base_r);
    assign read_term_w[13] = {32{read_select_r[13]}} & ({8'b0, object_hit_max_r});
    assign read_term_w[14] = {32{read_select_r[14]}} & ({8'b0, object_hit_count_r});
    assign read_term_w[15] = {32{read_select_r[15]}} & (object_free_base_r);
    assign read_term_w[16] = {32{read_select_r[16]}} & ({8'b0, object_free_max_r});
    assign read_term_w[17] = {32{read_select_r[17]}} & ({8'b0, object_free_count_r});
    assign read_term_w[18] = {32{read_select_r[18]}} & ({8'b0, object_alive_count_r});
    assign read_term_w[19] = {32{read_select_r[19]}} & ({30'b0, object_overflow_r});
    assign read_term_w[20] = {32{read_select_r[20]}} & (object_targets_r[31:0]);
    assign read_term_w[21] = {32{read_select_r[21]}} & (object_targets_r[63:32]);
    assign read_term_w[22] = {32{read_select_r[22]}} & (object_targets_r[95:64]);
    assign read_term_w[23] = {32{read_select_r[23]}} & (object_targets_r[127:96]);
    assign read_term_w[24] = {32{read_select_r[24]}} & (object_targets_r[159:128]);
    assign read_term_w[25] = {32{read_select_r[25]}} & (object_targets_r[191:160]);
    assign read_term_w[26] = {32{read_select_r[26]}} & (object_targets_r[223:192]);
    assign read_term_w[27] = {32{read_select_r[27]}} & (object_targets_r[255:224]);
    assign read_term_w[28] = {32{read_select_r[28]}} & (object_targets_r[287:256]);
    assign read_term_w[29] = {32{read_select_r[29]}} & (object_targets_r[319:288]);
    assign read_term_w[30] = {32{read_select_r[30]}} & (object_targets_r[351:320]);
    assign read_term_w[31] = {32{read_select_r[31]}} & (object_targets_r[383:352]);
    assign read_term_w[32] = {32{read_select_r[32]}} & (object_targets_r[415:384]);
    assign read_term_w[33] = {32{read_select_r[33]}} & (object_targets_r[447:416]);
    assign read_term_w[34] = {32{read_select_r[34]}} & (object_targets_r[479:448]);
    assign read_term_w[35] = {32{read_select_r[35]}} & (object_targets_r[511:480]);
    assign read_term_w[36] = {32{read_select_r[36]}} & (perf_r[0]);
    assign read_term_w[37] = {32{read_select_r[37]}} & (perf_r[1]);
    assign read_term_w[38] = {32{read_select_r[38]}} & (perf_r[2]);
    assign read_term_w[39] = {32{read_select_r[39]}} & (perf_r[3]);
    assign read_term_w[40] = {32{read_select_r[40]}} & (perf_r[4]);
    assign read_term_w[41] = {32{read_select_r[41]}} & (perf_r[5]);
    assign read_term_w[42] = {32{read_select_r[42]}} & (perf_r[6]);
    assign read_term_w[43] = {32{read_select_r[43]}} & (perf_r[7]);
    assign read_term_w[44] = {32{read_select_r[44]}} & (perf_r[8]);
    (* keep = "true" *) wire [31:0] read_tree_0_w [0:14];
    assign read_tree_0_w[0] = read_term_w[0] |
        read_term_w[1] |
        read_term_w[2];
    assign read_tree_0_w[1] = read_term_w[3] |
        read_term_w[4] |
        read_term_w[5];
    assign read_tree_0_w[2] = read_term_w[6] |
        read_term_w[7] |
        read_term_w[8];
    assign read_tree_0_w[3] = read_term_w[9] |
        read_term_w[10] |
        read_term_w[11];
    assign read_tree_0_w[4] = read_term_w[12] |
        read_term_w[13] |
        read_term_w[14];
    assign read_tree_0_w[5] = read_term_w[15] |
        read_term_w[16] |
        read_term_w[17];
    assign read_tree_0_w[6] = read_term_w[18] |
        read_term_w[19] |
        read_term_w[20];
    assign read_tree_0_w[7] = read_term_w[21] |
        read_term_w[22] |
        read_term_w[23];
    assign read_tree_0_w[8] = read_term_w[24] |
        read_term_w[25] |
        read_term_w[26];
    assign read_tree_0_w[9] = read_term_w[27] |
        read_term_w[28] |
        read_term_w[29];
    assign read_tree_0_w[10] = read_term_w[30] |
        read_term_w[31] |
        read_term_w[32];
    assign read_tree_0_w[11] = read_term_w[33] |
        read_term_w[34] |
        read_term_w[35];
    assign read_tree_0_w[12] = read_term_w[36] |
        read_term_w[37] |
        read_term_w[38];
    assign read_tree_0_w[13] = read_term_w[39] |
        read_term_w[40] |
        read_term_w[41];
    assign read_tree_0_w[14] = read_term_w[42] |
        read_term_w[43] |
        read_term_w[44];
    (* keep = "true" *) wire [31:0] read_tree_1_w [0:4];
    assign read_tree_1_w[0] = read_tree_0_w[0] |
        read_tree_0_w[1] |
        read_tree_0_w[2];
    assign read_tree_1_w[1] = read_tree_0_w[3] |
        read_tree_0_w[4] |
        read_tree_0_w[5];
    assign read_tree_1_w[2] = read_tree_0_w[6] |
        read_tree_0_w[7] |
        read_tree_0_w[8];
    assign read_tree_1_w[3] = read_tree_0_w[9] |
        read_tree_0_w[10] |
        read_tree_0_w[11];
    assign read_tree_1_w[4] = read_tree_0_w[12] |
        read_tree_0_w[13] |
        read_tree_0_w[14];
    (* keep = "true" *) wire [31:0] read_tree_2_w [0:1];
    assign read_tree_2_w[0] = read_tree_1_w[0] |
        read_tree_1_w[1] |
        read_tree_1_w[2];
    assign read_tree_2_w[1] = read_tree_1_w[3] |
        read_tree_1_w[4];
    (* keep = "true" *) wire [31:0] read_tree_3_w [0:0];
    assign read_tree_3_w[0] = read_tree_2_w[0] |
        read_tree_2_w[1];
    assign s_apb_prdata_o = read_tree_3_w[0];
    always @(posedge clk_i) begin
        if (s_apb_psel_i && !s_apb_penable_i) begin
            read_select_r <= {
                s_apb_paddr_i == 12'h060,
                s_apb_paddr_i == 12'h05c,
                s_apb_paddr_i == 12'h058,
                s_apb_paddr_i == 12'h054,
                s_apb_paddr_i == 12'h050,
                s_apb_paddr_i == 12'h04c,
                s_apb_paddr_i == 12'h048,
                s_apb_paddr_i == 12'h044,
                s_apb_paddr_i == 12'h040,
                s_apb_paddr_i == 12'h17c,
                s_apb_paddr_i == 12'h178,
                s_apb_paddr_i == 12'h174,
                s_apb_paddr_i == 12'h170,
                s_apb_paddr_i == 12'h16c,
                s_apb_paddr_i == 12'h168,
                s_apb_paddr_i == 12'h164,
                s_apb_paddr_i == 12'h160,
                s_apb_paddr_i == 12'h15c,
                s_apb_paddr_i == 12'h158,
                s_apb_paddr_i == 12'h154,
                s_apb_paddr_i == 12'h150,
                s_apb_paddr_i == 12'h14c,
                s_apb_paddr_i == 12'h148,
                s_apb_paddr_i == 12'h144,
                s_apb_paddr_i == 12'h140,
                s_apb_paddr_i == 12'h134,
                s_apb_paddr_i == 12'h130,
                s_apb_paddr_i == 12'h12c,
                s_apb_paddr_i == 12'h128,
                s_apb_paddr_i == 12'h124,
                s_apb_paddr_i == 12'h120,
                s_apb_paddr_i == 12'h11c,
                s_apb_paddr_i == 12'h118,
                s_apb_paddr_i == 12'h114,
                s_apb_paddr_i == 12'h110,
                s_apb_paddr_i == 12'h100,
                s_apb_paddr_i == 12'h02c,
                s_apb_paddr_i == 12'h024,
                s_apb_paddr_i == 12'h020,
                s_apb_paddr_i == 12'h014,
                s_apb_paddr_i == 12'h010,
                s_apb_paddr_i == 12'h00c,
                s_apb_paddr_i == 12'h008,
                s_apb_paddr_i == 12'h004,
                s_apb_paddr_i == 12'h000
            };
        end
    end
endmodule
