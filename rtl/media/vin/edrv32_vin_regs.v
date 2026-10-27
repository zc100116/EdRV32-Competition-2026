// File: edrv32_vin_regs.v
// Spec: vin 4, 6; SoC 4.3, 7.1.
// Description: Whole-word APB configuration, sticky interrupts and wrapping counters.
//              Unimplemented CH2 and reserved offsets read zero and ignore writes.
// Clock domain: clk_mem.
module edrv32_vin_regs (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Media APB slot.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output reg [31:0] apb_prdata_o,
    output wire apb_pslverr_o,

    // Engine configuration.
    output reg enable_o,
    output wire abort_o,
    output wire soft_rst_o,
    output reg [31:0] cam0_size_o,
    output reg [31:0] cam1_size_o,
    output reg [31:0] msrc_base_o,
    output reg [15:0] msrc_stride_o,
    output reg [31:0] msrc_size_o,
    output wire msrc_start_o,
    output wire [15:0] ch_ctrl_o,
    output wire [31:0] ch_stride_o,
    output wire [255:0] ch_bases_o,
    output wire [7:0] ch_slot_busy_o,

    // Live status and event inputs.
    input wire busy_i,
    input wire msrc_busy_i,
    input wire [11:0] ch_done_info_i,
    input wire [63:0] ch_done_frame_id_i,
    input wire [5:0] ch_wr_stat_i,
    input wire [31:0] irq_set_i,
    input wire [3:0] error_code_i,
    input wire [15:0] perf_event_i,
    input wire [3:0] cfg_errors_i,
    output wire irq_o
);
    reg [31:0] irq_en_r;
    reg [31:0] irq_stat_r;
    reg [3:0] error_code_r;
    reg [7:0] ch0_ctrl_r;
    reg [7:0] ch1_ctrl_r;
    reg [15:0] ch0_stride_r;
    reg [15:0] ch1_stride_r;
    reg [127:0] ch0_bases_r;
    reg [127:0] ch1_bases_r;
    reg [3:0] ch0_slot_busy_r;
    reg [3:0] ch1_slot_busy_r;
    reg [31:0] perf_r [0:15];
    wire write_w;
    wire [31:0] clear_w;
    wire unused_strb_w;
    integer index_r;
    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_i;
    assign clear_w = write_w && apb_paddr_i == 12'h010 ? apb_pwdata_i : 32'd0;
    assign abort_o = write_w && apb_paddr_i == 12'h004 && apb_pwdata_i[2];
    assign soft_rst_o = write_w && apb_paddr_i == 12'h004 && apb_pwdata_i[3];
    assign msrc_start_o = write_w && apb_paddr_i == 12'h11c && apb_pwdata_i[0];
    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    assign unused_strb_w = |apb_pstrb_i;
    assign irq_o = |(irq_stat_r & irq_en_r);
    assign ch_ctrl_o = {ch1_ctrl_r, ch0_ctrl_r};
    assign ch_stride_o = {ch1_stride_r, ch0_stride_r};
    assign ch_bases_o = {ch1_bases_r, ch0_bases_r};
    assign ch_slot_busy_o = {ch1_slot_busy_r, ch0_slot_busy_r};

    always @(*) begin
        apb_prdata_o = 32'd0;
        case (apb_paddr_i)
            12'h000: apb_prdata_o = 32'h0001_0001;
            12'h004: apb_prdata_o = {31'd0, enable_o};
            12'h008: apb_prdata_o = {29'd0, irq_stat_r[1], !busy_i, busy_i};
            12'h00c: apb_prdata_o = irq_en_r;
            12'h010: apb_prdata_o = irq_stat_r;
            12'h014: apb_prdata_o = {28'd0, error_code_r};
            12'h02c: apb_prdata_o = perf_r[3];
            12'h100: apb_prdata_o = cam0_size_o;
            12'h104: apb_prdata_o = cam1_size_o;
            12'h110: apb_prdata_o = msrc_base_o;
            12'h114: apb_prdata_o = {16'd0, msrc_stride_o};
            12'h118: apb_prdata_o = msrc_size_o;
            12'h120: apb_prdata_o = {31'd0, msrc_busy_i};
            12'h200: apb_prdata_o = {24'd0, ch0_ctrl_r};
            12'h204: apb_prdata_o = {16'd0, ch0_stride_r};
            12'h208: apb_prdata_o = ch0_bases_r[31:0];
            12'h20c: apb_prdata_o = ch0_bases_r[63:32];
            12'h210: apb_prdata_o = ch0_bases_r[95:64];
            12'h214: apb_prdata_o = ch0_bases_r[127:96];
            12'h218: apb_prdata_o = {28'd0, ch0_slot_busy_r};
            12'h220: apb_prdata_o = {26'd0, ch_done_info_i[5:0]};
            12'h224: apb_prdata_o = ch_done_frame_id_i[31:0];
            12'h228: apb_prdata_o = {29'd0, ch_wr_stat_i[2:0]};
            12'h280: apb_prdata_o = {24'd0, ch1_ctrl_r};
            12'h284: apb_prdata_o = {16'd0, ch1_stride_r};
            12'h288: apb_prdata_o = ch1_bases_r[31:0];
            12'h28c: apb_prdata_o = ch1_bases_r[63:32];
            12'h290: apb_prdata_o = ch1_bases_r[95:64];
            12'h294: apb_prdata_o = ch1_bases_r[127:96];
            12'h298: apb_prdata_o = {28'd0, ch1_slot_busy_r};
            12'h2a0: apb_prdata_o = {26'd0, ch_done_info_i[11:6]};
            12'h2a4: apb_prdata_o = ch_done_frame_id_i[63:32];
            12'h2a8: apb_prdata_o = {29'd0, ch_wr_stat_i[5:3]};
            default: begin
                if (apb_paddr_i >= 12'h040 && apb_paddr_i <= 12'h07c &&
                    apb_paddr_i[1:0] == 0)
                    apb_prdata_o = perf_r[apb_paddr_i[5:2]];
            end
        endcase
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            enable_o <= 1'b0;
            irq_en_r <= 32'd0;
            irq_stat_r <= 32'd0;
            error_code_r <= 4'd0;
            cam0_size_o <= 32'h02d0_0500;
            cam1_size_o <= 32'h02d0_0500;
            msrc_base_o <= 32'd0;
            msrc_stride_o <= 16'h0a00;
            msrc_size_o <= 32'h02d0_0500;
            ch0_ctrl_r <= 8'h30;
            ch1_ctrl_r <= 8'h30;
            ch0_stride_r <= 16'h0a00;
            ch1_stride_r <= 16'h0a00;
            ch0_bases_r <= 128'd0;
            ch1_bases_r <= 128'd0;
            ch0_slot_busy_r <= 4'd0;
            ch1_slot_busy_r <= 4'd0;
            for (index_r = 0; index_r < 16; index_r = index_r + 1)
                perf_r[index_r] <= 32'd0;
        end else begin
            irq_stat_r <= (irq_stat_r & ~clear_w) | irq_set_i;
            if (clear_w[1])
                error_code_r <= 4'd0;
            if (error_code_i != 0)
                error_code_r <= error_code_i;
            for (index_r = 0; index_r < 15; index_r = index_r + 1)
                if (perf_event_i[index_r])
                    perf_r[index_r] <= perf_r[index_r] + 32'd1;
            perf_r[15] <= perf_r[15] + {28'd0, cfg_errors_i};
            if (write_w) begin
                case (apb_paddr_i)
                    12'h004: enable_o <= apb_pwdata_i[0];
                    12'h00c: irq_en_r <= apb_pwdata_i & 32'h0000_0107;
                    12'h100: cam0_size_o <= apb_pwdata_i & 32'h0fff_07fe;
                    12'h104: cam1_size_o <= apb_pwdata_i & 32'h0fff_07fe;
                    12'h110: msrc_base_o <= {apb_pwdata_i[31:12], 12'd0};
                    12'h114: msrc_stride_o <= {apb_pwdata_i[15:5], 5'd0};
                    12'h118: msrc_size_o <= apb_pwdata_i & 32'h0fff_07fe;
                    12'h200: ch0_ctrl_r <= apb_pwdata_i[7:0] & 8'h77;
                    12'h204: ch0_stride_r <= {apb_pwdata_i[15:5], 5'd0};
                    12'h208: ch0_bases_r[31:0] <= {apb_pwdata_i[31:12], 12'd0};
                    12'h20c: ch0_bases_r[63:32] <= {apb_pwdata_i[31:12], 12'd0};
                    12'h210: ch0_bases_r[95:64] <= {apb_pwdata_i[31:12], 12'd0};
                    12'h214: ch0_bases_r[127:96] <= {apb_pwdata_i[31:12], 12'd0};
                    12'h218: ch0_slot_busy_r <= apb_pwdata_i[3:0];
                    12'h280: ch1_ctrl_r <= apb_pwdata_i[7:0] & 8'h77;
                    12'h284: ch1_stride_r <= {apb_pwdata_i[15:5], 5'd0};
                    12'h288: ch1_bases_r[31:0] <= {apb_pwdata_i[31:12], 12'd0};
                    12'h28c: ch1_bases_r[63:32] <= {apb_pwdata_i[31:12], 12'd0};
                    12'h290: ch1_bases_r[95:64] <= {apb_pwdata_i[31:12], 12'd0};
                    12'h294: ch1_bases_r[127:96] <= {apb_pwdata_i[31:12], 12'd0};
                    12'h298: ch1_slot_busy_r <= apb_pwdata_i[3:0];
                    default: begin end
                endcase
            end
        end
    end
endmodule
