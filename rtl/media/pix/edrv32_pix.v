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
    reg [31:0] frame_bc_r;
    reg [7:0] frame_thresh_r;
    wire [31:0] point_cfg_w;
    wire [31:0] point_bc_w;
    wire advance_w;
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

    assign advance_w = !pix_out_valid_o || pix_out_ready_i;
    // spec pix 2.6: completed input owns the pipeline until output EOF handshake.
    assign pix_in_ready_o = advance_w && !input_eof_r && !discard_w
        && !(soft_pending_w && (!busy_r || pix_in_sof_i));
    assign accept_w = pix_in_valid_i && pix_in_ready_o;
    assign discard_w = busy_r && !input_eof_r && pix_in_valid_i && pix_in_sof_i;
    assign clear_w = soft_reset_w || discard_w;
    assign frame_done_w = pix_out_valid_o && pix_out_ready_i && pix_out_eof_o;
    assign point_cfg_w = pix_in_sof_i ? (enable_w ? cfg_w : 32'd0) : frame_cfg_r;
    assign point_bc_w = pix_in_sof_i ? bc_w : frame_bc_r;
    assign unused_config_w = &{frame_cfg_r[31:19], frame_cfg_r[15:11],
        frame_cfg_r[7], frame_cfg_r[3], frame_bc_r[31:25], frame_bc_r[15:9],
        point_cfg_w[31:3], point_bc_w[31:25], point_bc_w[15:9]};

    always @(posedge clk_mem_i or negedge rst_mem_n_i) begin
        if (!rst_mem_n_i) begin
            busy_r <= 1'b0;
            input_eof_r <= 1'b0;
            frame_cfg_r <= 32'd0;
            frame_bc_r <= 32'h00000100;
            frame_thresh_r <= 8'd128;
        end else if (soft_reset_w) begin
            busy_r <= 1'b0;
            input_eof_r <= 1'b0;
            frame_cfg_r <= 32'd0;
            frame_bc_r <= 32'h00000100;
            frame_thresh_r <= 8'd128;
        end else begin
            if (frame_done_w || discard_w) begin
                busy_r <= 1'b0;
                input_eof_r <= 1'b0;
            end
            if (accept_w) begin
                if (pix_in_sof_i) begin
                    busy_r <= 1'b1;
                    frame_cfg_r <= enable_w ? cfg_w : 32'd0;
                    frame_bc_r <= bc_w;
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
        .discard_i(discard_w),
        .soft_pending_o(soft_pending_w),
        .soft_reset_o(soft_reset_w),

        .irq_o(irq_o)
    );

    edrv32_pix_point1 u_point1 (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),

        .valid_i(accept_w),
        .data_i(pix_in_data_i),
        .sof_i(pix_in_sof_i),
        .eol_i(pix_in_eol_i),
        .eof_i(pix_in_eof_i),

        .valid_o(point1_valid_w),
        .data_o(point1_data_w),
        .sof_o(point1_sof_w),
        .eol_o(point1_eol_w),
        .eof_o(point1_eof_w),

        .advance_i(advance_w),
        .clear_i(clear_w),
        .bc_en_i(point_cfg_w[0]),
        .gamma_en_i(point_cfg_w[1]),
        .gamma_bank_i(point_cfg_w[2]),
        .contrast_i(point_bc_w[8:0]),
        .brightness_i(point_bc_w[24:16]),
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

        .advance_i(advance_w),
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

        .advance_i(advance_w),
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

        .valid_o(pix_out_valid_o),
        .data_o(pix_out_data_o),
        .sof_o(pix_out_sof_o),
        .eol_o(pix_out_eol_o),
        .eof_o(pix_out_eof_o),

        .advance_i(advance_w),
        .clear_i(clear_w),
        .gray_en_i(frame_cfg_r[16]),
        .bin_en_i(frame_cfg_r[17]),
        .inv_en_i(frame_cfg_r[18]),
        .thresh_i(frame_thresh_r)
    );
endmodule
