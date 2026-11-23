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
    output reg [31:0] s_apb_prdata_o,
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

    always @(*) begin
        s_apb_prdata_o = 32'b0;
        case (apb_addr_r)
            12'h000: s_apb_prdata_o = 32'h00060001;
            12'h004: s_apb_prdata_o = {31'b0, enable_r};
            12'h008: s_apb_prdata_o = {29'b0, irq_stat_r[1], !busy_i, busy_i};
            12'h00c: s_apb_prdata_o = {30'b0, irq_en_r};
            12'h010: s_apb_prdata_o = {30'b0, irq_stat_r};
            12'h014: s_apb_prdata_o = err_code_r;
            12'h020: s_apb_prdata_o = desc_base_r;
            12'h024: s_apb_prdata_o = {16'b0, desc_count_r};
            12'h02c: s_apb_prdata_o = done_count_r;
            12'h100: s_apb_prdata_o = {31'b0, wide_r};
            12'h110: s_apb_prdata_o = object_live_r[31:0];
            12'h114: s_apb_prdata_o = object_live_r[63:32];
            12'h118: s_apb_prdata_o = object_hit_base_r;
            12'h11c: s_apb_prdata_o = {8'b0, object_hit_max_r};
            12'h120: s_apb_prdata_o = {8'b0, object_hit_count_r};
            12'h124: s_apb_prdata_o = object_free_base_r;
            12'h128: s_apb_prdata_o = {8'b0, object_free_max_r};
            12'h12c: s_apb_prdata_o = {8'b0, object_free_count_r};
            12'h130: s_apb_prdata_o = {8'b0, object_alive_count_r};
            12'h134: s_apb_prdata_o = {30'b0, object_overflow_r};
            12'h140: s_apb_prdata_o = object_targets_r[31:0];
            12'h144: s_apb_prdata_o = object_targets_r[63:32];
            12'h148: s_apb_prdata_o = object_targets_r[95:64];
            12'h14c: s_apb_prdata_o = object_targets_r[127:96];
            12'h150: s_apb_prdata_o = object_targets_r[159:128];
            12'h154: s_apb_prdata_o = object_targets_r[191:160];
            12'h158: s_apb_prdata_o = object_targets_r[223:192];
            12'h15c: s_apb_prdata_o = object_targets_r[255:224];
            12'h160: s_apb_prdata_o = object_targets_r[287:256];
            12'h164: s_apb_prdata_o = object_targets_r[319:288];
            12'h168: s_apb_prdata_o = object_targets_r[351:320];
            12'h16c: s_apb_prdata_o = object_targets_r[383:352];
            12'h170: s_apb_prdata_o = object_targets_r[415:384];
            12'h174: s_apb_prdata_o = object_targets_r[447:416];
            12'h178: s_apb_prdata_o = object_targets_r[479:448];
            12'h17c: s_apb_prdata_o = object_targets_r[511:480];
            12'h040: s_apb_prdata_o = perf_r[0];
            12'h044: s_apb_prdata_o = perf_r[1];
            12'h048: s_apb_prdata_o = perf_r[2];
            12'h04c: s_apb_prdata_o = perf_r[3];
            12'h050: s_apb_prdata_o = perf_r[4];
            12'h054: s_apb_prdata_o = perf_r[5];
            12'h058: s_apb_prdata_o = perf_r[6];
            12'h05c: s_apb_prdata_o = perf_r[7];
            12'h060: s_apb_prdata_o = perf_r[8];
            default: begin end
        endcase
    end
endmodule
