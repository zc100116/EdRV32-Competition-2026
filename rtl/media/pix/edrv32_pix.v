// File: edrv32_pix.v
// Spec: pix-spec 2.1-2.9, 3, 5.1-5.2.
// Description: Single-frame RGB888 pipeline with two independent spatial stages.
// All stages freeze together on backpressure; SOF snapshots shadow controls.
// Clock: clk_mem.
module edrv32_pix (
    // Clock and reset.
    input wire clk_mem_i,
    input wire rst_mem_n_i,

    // VIN input stream.
    input wire pix_in_valid_i,
    output wire pix_in_ready_o,
    input wire [31:0] pix_in_data_i,
    input wire pix_in_sof_i,
    input wire pix_in_eol_i,
    input wire pix_in_eof_i,

    // VIN output stream.
    output wire pix_out_valid_o,
    input wire pix_out_ready_i,
    output wire [31:0] pix_out_data_o,
    output wire pix_out_sof_o,
    output wire pix_out_eol_o,
    output wire pix_out_eof_o,

    // Media APB slave.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output wire [31:0] apb_prdata_o,
    output wire apb_pslverr_o,

    // Frame interrupt.
    output wire irq_o
);
    wire enable_w;
    wire [31:0] cfg_w;
    wire [31:0] bc_w;
    wire [7:0] thresh_w;
    wire gamma_wr_w;
    wire [8:0] gamma_addr_w;
    wire [7:0] gamma_data_w;
    wire soft_pending_w;
    wire soft_reset_w;
    reg busy_r;
    reg input_eof_r;
    reg [31:0] frame_cfg_r;
    reg [8:0] frame_contrast_r;
    reg [9:0] frame_bias_r;
    reg [7:0] frame_thresh_r;
    reg input_valid_r;
    reg [47:0] input_data_r;
    reg [8:0] input_contrast_r;
    reg [9:0] input_bias_r;
    reg input_sof_r;
    reg input_eol_r;
    reg input_eof_tag_r;
    reg discard_r;
    wire input_fire_w;
    wire advance_next_w;
    reg advance_input_r /* synthesis syn_preserve=1 */;
    reg [6:0] advance_point1_r /* synthesis syn_preserve=1 */;
    reg [2:0] advance_point2_r /* synthesis syn_preserve=1 */;
    reg [3:0] advance_filter1_r /* synthesis syn_preserve=1 */;
    reg [3:0] advance_filter2_r /* synthesis syn_preserve=1 */;
    reg [20:0] advance_kernel10_r /* synthesis syn_preserve=1 */;
    reg [20:0] advance_kernel11_r /* synthesis syn_preserve=1 */;
    reg [20:0] advance_kernel20_r /* synthesis syn_preserve=1 */;
    reg [20:0] advance_kernel21_r /* synthesis syn_preserve=1 */;
    wire tail_valid_w;
    wire [31:0] tail_data_w;
    wire tail_sof_w;
    wire tail_eol_w;
    wire tail_eof_w;
    reg [34:0] output_data_r [0:1];
    reg [1:0] output_count_r;
    reg output_read_r;
    reg output_write_r;
    wire output_push_w;
    wire output_pop_w;
    reg [1:0] output_count_w;
    wire accept_w;
    wire discard_w;
    wire clear_w;
    wire frame_done_w;
    wire unused_config_w;
    wire point1_valid_w;
    wire [47:0] point1_data_w;
    wire point1_sof_w;
    wire point1_eol_w;
    wire point1_eof_w;
    wire stage1_valid_w;
    wire [47:0] stage1_data_w;
    wire stage1_sof_w;
    wire stage1_eol_w;
    wire stage1_eof_w;
    wire stage2_valid_w;
    wire [47:0] stage2_data_w;
    wire stage2_sof_w;
    wire stage2_eol_w;
    wire stage2_eof_w;

    // Two output slots absorb the last advance after READY falls. The next
    // advance is registered at every local consumer, including all kernel groups.
    assign output_push_w = advance_input_r && tail_valid_w;
    assign output_pop_w = pix_out_valid_o && pix_out_ready_i;
    always @(*) begin
        output_count_w = output_count_r;
        case ({output_push_w, output_pop_w})
            2'b10: output_count_w = output_count_r + 2'd1;
            2'b01: output_count_w = output_count_r - 2'd1;
            default: begin end
        endcase
    end
    assign advance_next_w = output_count_w < 2'd2;
    assign pix_out_valid_o = output_count_r != 0 && !clear_w;
    assign {pix_out_eof_o, pix_out_eol_o, pix_out_sof_o, pix_out_data_o} =
        output_data_r[output_read_r];
    // The input slot snapshots data and controls at the external SOF handshake.
    assign pix_in_ready_o = advance_input_r && !input_eof_r
        && !discard_w && !(soft_pending_w && (!busy_r || pix_in_sof_i));
    assign input_fire_w = pix_in_valid_i && pix_in_ready_o;
    assign accept_w = input_valid_r && advance_input_r;
    assign discard_w = busy_r && !input_eof_r && pix_in_valid_i && pix_in_sof_i;
    assign clear_w = soft_reset_w || discard_r;
    assign frame_done_w = output_pop_w && pix_out_eof_o;
    assign unused_config_w = &{frame_cfg_r[31:19], frame_cfg_r[15:11],
        frame_cfg_r[7], frame_cfg_r[3], bc_w[31:25], bc_w[15:9]};

    always @(posedge clk_mem_i or negedge rst_mem_n_i) begin
        if (!rst_mem_n_i) begin
            advance_input_r <= 1'b1;
            advance_point1_r <= 7'h7f;
            advance_point2_r <= 3'h7;
            advance_filter1_r <= 4'hf;
            advance_filter2_r <= 4'hf;
            advance_kernel10_r <= 21'h1fffff;
            advance_kernel11_r <= 21'h1fffff;
            advance_kernel20_r <= 21'h1fffff;
            advance_kernel21_r <= 21'h1fffff;
            output_count_r <= 2'd0;
            output_read_r <= 1'b0;
            output_write_r <= 1'b0;
            input_valid_r <= 1'b0;
            discard_r <= 1'b0;
        end else begin
            advance_input_r <= clear_w || advance_next_w;
            advance_point1_r <= {7{clear_w || advance_next_w}};
            advance_point2_r <= {3{clear_w || advance_next_w}};
            advance_filter1_r <= {4{clear_w || advance_next_w}};
            advance_filter2_r <= {4{clear_w || advance_next_w}};
            advance_kernel10_r <= {21{clear_w || advance_next_w}};
            advance_kernel11_r <= {21{clear_w || advance_next_w}};
            advance_kernel20_r <= {21{clear_w || advance_next_w}};
            advance_kernel21_r <= {21{clear_w || advance_next_w}};
            discard_r <= discard_w;
            if (clear_w) begin
                output_count_r <= 2'd0;
                output_read_r <= 1'b0;
                output_write_r <= 1'b0;
                input_valid_r <= input_fire_w;
            end else begin
                output_count_r <= output_count_w;
                if (output_push_w)
                    output_write_r <= !output_write_r;
                if (output_pop_w)
                    output_read_r <= !output_read_r;
                if (advance_input_r || input_fire_w)
                    input_valid_r <= input_fire_w;
            end
        end
    end
    always @(posedge clk_mem_i) begin
        if (advance_input_r) begin
            // Centered RGB888 is registered here, directly feeding APM operands.
            input_data_r <= {
                !pix_in_data_i[31], pix_in_data_i[30:27], pix_in_data_i[31:29],
                !pix_in_data_i[26], pix_in_data_i[25:21], pix_in_data_i[26:25],
                !pix_in_data_i[20], pix_in_data_i[19:16], pix_in_data_i[20:18],
                !pix_in_data_i[15], pix_in_data_i[14:11], pix_in_data_i[15:13],
                !pix_in_data_i[10], pix_in_data_i[9:5], pix_in_data_i[10:9],
                !pix_in_data_i[4], pix_in_data_i[3:0], pix_in_data_i[4:2]};
            input_contrast_r <= pix_in_sof_i ? bc_w[8:0] : frame_contrast_r;
            input_bias_r <= pix_in_sof_i
                ? ($signed({bc_w[24], bc_w[24:16]}) + 10'sd128) : frame_bias_r;
            input_sof_r <= pix_in_sof_i;
            input_eol_r <= pix_in_eol_i;
            input_eof_tag_r <= pix_in_eof_i;
        end
        if (output_push_w)
            output_data_r[output_write_r] <= {tail_eof_w, tail_eol_w, tail_sof_w, tail_data_w};
    end

    always @(posedge clk_mem_i or negedge rst_mem_n_i) begin
        if (!rst_mem_n_i) begin
            busy_r <= 1'b0;
            input_eof_r <= 1'b0;
            frame_cfg_r <= 32'd0;
            frame_contrast_r <= 9'd256;
            frame_bias_r <= 10'd128;
            frame_thresh_r <= 8'd128;
        end else if (soft_reset_w) begin
            busy_r <= 1'b0;
            input_eof_r <= 1'b0;
            frame_cfg_r <= 32'd0;
            frame_contrast_r <= 9'd256;
            frame_bias_r <= 10'd128;
            frame_thresh_r <= 8'd128;
        end else begin
            if (frame_done_w || discard_w) begin
                busy_r <= 1'b0;
                input_eof_r <= 1'b0;
            end
            if (input_fire_w) begin
                if (pix_in_sof_i) begin
                    busy_r <= 1'b1;
                    frame_cfg_r <= enable_w ? cfg_w : 32'd0;
                    frame_contrast_r <= bc_w[8:0];
                    frame_bias_r <= $signed({bc_w[24], bc_w[24:16]}) + 10'sd128;
                    frame_thresh_r <= thresh_w;
                end
                input_eof_r <= pix_in_eof_i;
            end
        end
    end

    edrv32_pix_regs u_regs (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),

        .apb_paddr_i(apb_paddr_i),
        .apb_psel_i(apb_psel_i),
        .apb_penable_i(apb_penable_i),
        .apb_pwrite_i(apb_pwrite_i),
        .apb_pwdata_i(apb_pwdata_i),
        .apb_pstrb_i(apb_pstrb_i),
        .apb_pready_o(apb_pready_o),
        .apb_prdata_o(apb_prdata_o),
        .apb_pslverr_o(apb_pslverr_o),

        .enable_o(enable_w),
        .cfg_o(cfg_w),
        .bc_o(bc_w),
        .thresh_o(thresh_w),
        .gamma_wr_o(gamma_wr_w),
        .gamma_addr_o(gamma_addr_w),
        .gamma_data_o(gamma_data_w),

        .busy_i(busy_r),
        .frame_done_i(frame_done_w),
        .input_stall_i(pix_in_valid_i && !pix_in_ready_o),
        .output_stall_i(pix_out_valid_o && !pix_out_ready_i),
        .discard_i(discard_r),
        .soft_pending_o(soft_pending_w),
        .soft_reset_o(soft_reset_w),

        .irq_o(irq_o)
    );

    edrv32_pix_point1 u_point1 (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),

        .valid_i(accept_w),
        .data_i(input_data_r),
        .sof_i(input_sof_r),
        .eol_i(input_eol_r),
        .eof_i(input_eof_tag_r),

        .valid_o(point1_valid_w),
        .data_o(point1_data_w),
        .sof_o(point1_sof_w),
        .eol_o(point1_eol_w),
        .eof_o(point1_eof_w),

        .advance_i(advance_point1_r),
        .clear_i(clear_w),
        .bc_en_i(frame_cfg_r[0]),
        .gamma_en_i(frame_cfg_r[1]),
        .gamma_bank_i(frame_cfg_r[2]),
        .contrast_i(input_contrast_r),
        .bias_i(input_bias_r),
        .gamma_wr_i(gamma_wr_w),
        .gamma_addr_i(gamma_addr_w),
        .gamma_data_i(gamma_data_w)
    );

    edrv32_pix_filter u_stage1 (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),

        .valid_i(point1_valid_w),
        .data_i(point1_data_w),
        .sof_i(point1_sof_w),
        .eol_i(point1_eol_w),
        .eof_i(point1_eof_w),

        .valid_o(stage1_valid_w),
        .data_o(stage1_data_w),
        .sof_o(stage1_sof_w),
        .eol_o(stage1_eol_w),
        .eof_o(stage1_eof_w),

        .advance_i(advance_filter1_r),
        .advance_kernel0_i(advance_kernel10_r),
        .advance_kernel1_i(advance_kernel11_r),
        .clear_i(clear_w),
        .op_i(frame_cfg_r[6:4])
    );

    edrv32_pix_filter u_stage2 (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),

        .valid_i(stage1_valid_w),
        .data_i(stage1_data_w),
        .sof_i(stage1_sof_w),
        .eol_i(stage1_eol_w),
        .eof_i(stage1_eof_w),

        .valid_o(stage2_valid_w),
        .data_o(stage2_data_w),
        .sof_o(stage2_sof_w),
        .eol_o(stage2_eol_w),
        .eof_o(stage2_eof_w),

        .advance_i(advance_filter2_r),
        .advance_kernel0_i(advance_kernel20_r),
        .advance_kernel1_i(advance_kernel21_r),
        .clear_i(clear_w),
        .op_i(frame_cfg_r[10:8])
    );

    edrv32_pix_point2 u_point2 (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),

        .valid_i(stage2_valid_w),
        .data_i(stage2_data_w),
        .sof_i(stage2_sof_w),
        .eol_i(stage2_eol_w),
        .eof_i(stage2_eof_w),

        .valid_o(tail_valid_w),
        .data_o(tail_data_w),
        .sof_o(tail_sof_w),
        .eol_o(tail_eol_w),
        .eof_o(tail_eof_w),

        .advance_i(advance_point2_r),
        .clear_i(clear_w),
        .gray_en_i(frame_cfg_r[16]),
        .bin_en_i(frame_cfg_r[17]),
        .inv_en_i(frame_cfg_r[18]),
        .thresh_i(frame_thresh_r)
    );
endmodule
