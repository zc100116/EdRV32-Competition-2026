// File: edrv32_vin_regs.v
// Spec: vin 4, 6; SoC 4.3, 7.1.
// Description: Whole-word APB configuration, sticky interrupts and wrapping counters.
//              Reserved offsets read zero and ignore writes.
// Clock domain: clk_mem.
module edrv32_vin_regs (
    // Equal-edge reset copies for common/CH0/CH1/CH2 and four PERF banks.
    input wire clk_i,
    input wire [7:0] rst_n_i,

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
    output reg abort_o,
    output reg soft_rst_o,
    output reg [31:0] cam0_size_o,
    output reg [31:0] cam1_size_o,
    output reg [31:0] msrc_base_o,
    output reg [15:0] msrc_stride_o,
    output reg [31:0] msrc_size_o,
    output reg msrc_start_o,
    output wire [23:0] ch_ctrl_o,
    output wire [47:0] ch_stride_o,
    output wire [383:0] ch_bases_o,
    output wire [11:0] ch_slot_busy_o,

    // Live status and event inputs.
    input wire busy_i,
    input wire msrc_busy_i,
    input wire [17:0] ch_done_info_i,
    input wire [95:0] ch_done_frame_id_i,
    input wire [8:0] ch_wr_stat_i,
    input wire [31:0] irq_set_i,
    input wire [3:0] error_code_i,
    input wire [15:0] perf_event_i,
    input wire [3:0] cfg_errors_i,
    output wire irq_o
);
    reg [11:0] apb_paddr_r;
    reg apb_pwrite_r;
    reg [31:0] apb_pwdata_r;
    reg [3:0] apb_pstrb_r;

    // SoC 4.3: the shared APB payload terminates at the setup-phase registers.
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            apb_paddr_r <= apb_paddr_i;
            apb_pwrite_r <= apb_pwrite_i;
            apb_pwdata_r <= apb_pwdata_i;
            apb_pstrb_r <= apb_pstrb_i;
        end
    end

    reg [31:0] irq_en_r;
    reg [31:0] irq_stat_r;
    reg [3:0] error_code_r;
    reg [7:0] ch0_ctrl_r;
    reg [7:0] ch1_ctrl_r;
    reg [7:0] ch2_ctrl_r;
    reg [15:0] ch0_stride_r;
    reg [15:0] ch1_stride_r;
    reg [15:0] ch2_stride_r;
    reg [127:0] ch0_bases_r;
    reg [127:0] ch1_bases_r;
    reg [127:0] ch2_bases_r;
    reg [3:0] ch0_slot_busy_r;
    reg [3:0] ch1_slot_busy_r;
    reg [3:0] ch2_slot_busy_r;
    wire [31:0] perf_r [0:15];
    wire write_w;
    wire [31:0] clear_w;
    wire unused_strb_w;
    wire unused_perf_w;
    reg [14:0] perf_event_r;
    reg [3:0] cfg_errors_r;
    genvar counter;
    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_r;
    assign clear_w = write_w && apb_paddr_r == 12'h010 ? apb_pwdata_r : 32'd0;

    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    assign unused_perf_w = perf_event_i[15];
    assign unused_strb_w = |apb_pstrb_r;
    assign irq_o = |(irq_stat_r & irq_en_r);
    assign ch_ctrl_o = {ch2_ctrl_r, ch1_ctrl_r, ch0_ctrl_r};
    assign ch_stride_o = {ch2_stride_r, ch1_stride_r, ch0_stride_r};
    assign ch_bases_o = {ch2_bases_r, ch1_bases_r, ch0_bases_r};
    assign ch_slot_busy_o = {ch2_slot_busy_r, ch1_slot_busy_r, ch0_slot_busy_r};

    always @(*) begin
        apb_prdata_o = 32'd0;
        case (apb_paddr_r)
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
            12'h300: apb_prdata_o = {24'd0, ch2_ctrl_r};
            12'h304: apb_prdata_o = {16'd0, ch2_stride_r};
            12'h308: apb_prdata_o = ch2_bases_r[31:0];
            12'h30c: apb_prdata_o = ch2_bases_r[63:32];
            12'h310: apb_prdata_o = ch2_bases_r[95:64];
            12'h314: apb_prdata_o = ch2_bases_r[127:96];
            12'h318: apb_prdata_o = {28'd0, ch2_slot_busy_r};
            12'h320: apb_prdata_o = {26'd0, ch_done_info_i[17:12]};
            12'h324: apb_prdata_o = ch_done_frame_id_i[95:64];
            12'h328: apb_prdata_o = {29'd0, ch_wr_stat_i[8:6]};
            default: begin
                if (apb_paddr_r >= 12'h040 && apb_paddr_r <= 12'h07c &&
                    apb_paddr_r[1:0] == 0)
                    apb_prdata_o = perf_r[apb_paddr_r[5:2]];
            end
        endcase
    end

    // Independent control copies preserve the original D, enable and effective edge.
    always @(posedge clk_i or negedge rst_n_i[0]) begin
        if (!rst_n_i[0]) begin
            enable_o <= 1'b0;
            irq_en_r <= 32'd0;
            irq_stat_r <= 32'd0;
            error_code_r <= 4'd0;
            cam0_size_o <= 32'h02d0_0500;
            cam1_size_o <= 32'h02d0_0500;
            msrc_base_o <= 32'd0;
            msrc_stride_o <= 16'h0a00;
            msrc_size_o <= 32'h02d0_0500;
        end else begin
            irq_stat_r <= (irq_stat_r & ~clear_w) | irq_set_i;
            if (clear_w[1]) begin
                error_code_r <= 4'd0;
            end
            if (error_code_i != 0) begin
                error_code_r <= error_code_i;
            end
            if (write_w) begin
                case (apb_paddr_r)
                    12'h004: begin
                        enable_o <= apb_pwdata_r[0];
                    end
                    12'h00c: begin
                        irq_en_r <= apb_pwdata_r & 32'h0000_0307;
                    end
                    12'h100: begin
                        cam0_size_o <= apb_pwdata_r & 32'h0fff_07fe;
                    end
                    12'h104: begin
                        cam1_size_o <= apb_pwdata_r & 32'h0fff_07fe;
                    end
                    12'h110: begin
                        msrc_base_o <= {apb_pwdata_r[31:12], 12'd0};
                    end
                    12'h114: begin
                        msrc_stride_o <= {apb_pwdata_r[15:5], 5'd0};
                    end
                    12'h118: begin
                        msrc_size_o <= apb_pwdata_r & 32'h0fff_07fe;
                    end
                    default: begin end
                endcase
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i[1]) begin
        if (!rst_n_i[1]) begin
            ch0_ctrl_r <= 8'h30;
            ch0_stride_r <= 16'h0a00;
            ch0_bases_r <= 128'd0;
            ch0_slot_busy_r <= 4'd0;
        end else begin
            if (write_w) begin
                case (apb_paddr_r)
                    12'h200: begin
                        ch0_ctrl_r <= apb_pwdata_r[7:0] & 8'h77;
                    end
                    12'h204: begin
                        ch0_stride_r <= {apb_pwdata_r[15:5], 5'd0};
                    end
                    12'h208: begin
                        ch0_bases_r[31:0] <= {apb_pwdata_r[31:12], 12'd0};
                    end
                    12'h20c: begin
                        ch0_bases_r[63:32] <= {apb_pwdata_r[31:12], 12'd0};
                    end
                    12'h210: begin
                        ch0_bases_r[95:64] <= {apb_pwdata_r[31:12], 12'd0};
                    end
                    12'h214: begin
                        ch0_bases_r[127:96] <= {apb_pwdata_r[31:12], 12'd0};
                    end
                    12'h218: begin
                        ch0_slot_busy_r <= apb_pwdata_r[3:0];
                    end
                    default: begin end
                endcase
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i[2]) begin
        if (!rst_n_i[2]) begin
            ch1_ctrl_r <= 8'h30;
            ch1_stride_r <= 16'h0a00;
            ch1_bases_r <= 128'd0;
            ch1_slot_busy_r <= 4'd0;
        end else begin
            if (write_w) begin
                case (apb_paddr_r)
                    12'h280: begin
                        ch1_ctrl_r <= apb_pwdata_r[7:0] & 8'h77;
                    end
                    12'h284: begin
                        ch1_stride_r <= {apb_pwdata_r[15:5], 5'd0};
                    end
                    12'h288: begin
                        ch1_bases_r[31:0] <= {apb_pwdata_r[31:12], 12'd0};
                    end
                    12'h28c: begin
                        ch1_bases_r[63:32] <= {apb_pwdata_r[31:12], 12'd0};
                    end
                    12'h290: begin
                        ch1_bases_r[95:64] <= {apb_pwdata_r[31:12], 12'd0};
                    end
                    12'h294: begin
                        ch1_bases_r[127:96] <= {apb_pwdata_r[31:12], 12'd0};
                    end
                    12'h298: begin
                        ch1_slot_busy_r <= apb_pwdata_r[3:0];
                    end
                    default: begin end
                endcase
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i[3]) begin
        if (!rst_n_i[3]) begin
            ch2_ctrl_r <= 8'h30;
            ch2_stride_r <= 16'h0a00;
            ch2_bases_r <= 128'd0;
            ch2_slot_busy_r <= 4'd0;
        end else begin
            if (write_w) begin
                case (apb_paddr_r)
                    12'h300: begin
                        ch2_ctrl_r <= apb_pwdata_r[7:0] & 8'h77;
                    end
                    12'h304: begin
                        ch2_stride_r <= {apb_pwdata_r[15:5], 5'd0};
                    end
                    12'h308: begin
                        ch2_bases_r[31:0] <= {apb_pwdata_r[31:12], 12'd0};
                    end
                    12'h30c: begin
                        ch2_bases_r[63:32] <= {apb_pwdata_r[31:12], 12'd0};
                    end
                    12'h310: begin
                        ch2_bases_r[95:64] <= {apb_pwdata_r[31:12], 12'd0};
                    end
                    12'h314: begin
                        ch2_bases_r[127:96] <= {apb_pwdata_r[31:12], 12'd0};
                    end
                    12'h318: begin
                        ch2_slot_busy_r <= apb_pwdata_r[3:0];
                    end
                    default: begin end
                endcase
            end
        end
    end
    // Each elaborated counter owns its adder; event selection ends at a register.
    always @(posedge clk_i or negedge rst_n_i[0]) begin
        if (!rst_n_i[0]) begin
            perf_event_r <= 15'd0;
            cfg_errors_r <= 4'd0;
        end else begin
            perf_event_r <= perf_event_i[14:0];
            cfg_errors_r <= cfg_errors_i;
        end
    end
    generate
        for (counter = 0; counter < 16; counter = counter + 1) begin : g_perf
            reg [31:0] count_r;
            assign perf_r[counter] = count_r;
            wire [31:0] increment_w;
            if (counter == 15) begin : g_config
                assign increment_w = {28'd0, cfg_errors_r};
            end else begin : g_event
                assign increment_w = {31'd0, perf_event_r[counter]};
            end
            always @(posedge clk_i or negedge rst_n_i[4+counter/4]) begin
                if (!rst_n_i[4+counter/4])
                    count_r <= 32'd0;
                else
                    count_r <= count_r + increment_w;
            end
        end
    endgenerate
    // SoC 7.1: APB command decode ends at this register stage.
    // Independent control copies preserve the original D, enable and effective edge.
    always @(posedge clk_i or negedge rst_n_i[0]) begin
        if (!rst_n_i[0]) begin
            msrc_start_o <= 1'b0;
        end else begin
            msrc_start_o <= write_w && apb_paddr_r == 12'h11c && apb_pwdata_r[0];
        end
    end
    always @(posedge clk_i or negedge rst_n_i[1]) begin
        if (!rst_n_i[1]) begin
            abort_o <= 1'b0;
            soft_rst_o <= 1'b0;
        end else begin
            abort_o <= write_w && apb_paddr_r == 12'h004 && apb_pwdata_r[2];
            soft_rst_o <= write_w && apb_paddr_r == 12'h004 && apb_pwdata_r[3];
        end
    end

endmodule
