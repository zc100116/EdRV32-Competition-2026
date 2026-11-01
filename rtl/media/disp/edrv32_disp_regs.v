// File: edrv32_disp_regs.v
// Spec: disp-spec 4-6; edrv32-soc-spec 7.1.
// Description: APB frame handoff registers, sticky interrupts and performance counts.
//              Local software reset drains requested frames before clearing state.
// Clock domain: clk_mem (clk_i).
module edrv32_disp_regs (
    // Equal-edge reset copies for common, L0, L1 and performance register banks.
    input wire clk_i,
    input wire [3:0] rst_n_i,

    // Media APB slave; pstrb is ignored per spec 4.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output reg [31:0] apb_prdata_o,
    output wire apb_pslverr_o,

    // Reader controls and completion events.
    output wire enable_o,
    output wire [31:0] next_base_o,
    output wire [31:0] stride_o,
    output wire [31:0] l0_scroll_o,
    output wire [1:0] layer_ctrl_o,
    output wire [31:0] l1_next_base_o,
    output wire [31:0] l1_stride_o,
    output wire [31:0] l1_pos_o,
    output wire [31:0] l1_size_o,
    output wire [7:0] l1_opa_o,
    output reg soft_clear_o /* synthesis syn_preserve=1 */,
    input wire busy_i,
    input wire frame_start_i,
    input wire underflow_i,
    input wire underflow1_i,
    input wire dma_err_i,
    input wire urgent_i,
    input wire delayed_req_i,

    // Synchronized scan counts; raw counts survive a local SOFT_RST.
    input wire [31:0] perf0_i,
    input wire [31:0] perf1_i,
    input wire [31:0] perf2_i,
    input wire [31:0] perf5_i,
    input wire [31:0] perf6_i,
    output wire [31:0] scan_cnt_o,

    // Interrupt output.
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

    localparam [31:0] IRQ_MASK = 32'h0000_0306;
    reg enable_r;
    reg busy_r;
    reg soft_pending_d_r;
    reg soft_pending_r;
    reg [31:0] irq_en_r;
    reg [31:0] irq_stat_r;
    reg [1:0] err_code_r;
    reg [31:0] next_base_r;
    reg [31:0] stride_r;
    reg [31:0] cur_base_r;
    reg [31:0] rel_base_r;
    reg [31:0] frame_cnt_r;
    reg [31:0] l0_scroll_r;
    reg [1:0] layer_ctrl_r;
    reg [1:0] cur_layer_ctrl_r;
    reg [31:0] l1_next_base_r;
    reg [31:0] l1_stride_r;
    reg [31:0] l1_pos_r;
    reg [31:0] l1_size_r;
    reg [7:0] l1_opa_r;
    reg [31:0] l1_cur_base_r;
    reg [31:0] l1_rel_base_r;
    reg [31:0] perf0_r;
    reg [5:0] perf0_less_r;
    reg [5:1] perf0_equal_r;
    wire [23:0] perf0_base_w;
    reg [31:0] perf1_r;
    reg [5:0] perf1_less_r;
    reg [5:1] perf1_equal_r;
    wire [23:0] perf1_base_w;
    reg [31:0] perf2_r;
    reg [5:0] perf2_less_r;
    reg [5:1] perf2_equal_r;
    wire [23:0] perf2_base_w;
    reg [31:0] perf5_r;
    reg [5:0] perf5_less_r;
    reg [5:1] perf5_equal_r;
    wire [23:0] perf5_base_w;
    reg [31:0] perf6_r;
    reg [5:0] perf6_less_r;
    reg [5:1] perf6_equal_r;
    wire [23:0] perf6_base_w;
    reg urgent_r;
    reg delayed_req_r;
    reg [31:0] perf0_base_r;
    reg [31:0] perf1_base_r;
    reg [31:0] perf2_base_r;
    reg [31:0] perf5_base_r;
    reg [31:0] perf6_base_r;
    reg [31:0] perf3_r;
    reg [31:0] perf4_r;
    wire write_w;
    wire ctrl_write_w;
    wire switch_w;
    wire switch1_w;
    wire [31:0] irq_set_w;
    wire [31:0] irq_clear_w;
    wire [3:0] unused_pstrb_w;

    // spec 4.3: register nibble comparisons alongside the same raw count sample.
    // This separates Gray decoding/borrow detection from APB count subtraction.
    // On SOFT_RST the newly installed baseline is the previous raw count sample.
    assign perf0_base_w = soft_clear_o ? perf0_r[23:0] : perf0_base_r[23:0];
    assign perf1_base_w = soft_clear_o ? perf1_r[23:0] : perf1_base_r[23:0];
    assign perf2_base_w = soft_clear_o ? perf2_r[23:0] : perf2_base_r[23:0];
    assign perf5_base_w = soft_clear_o ? perf5_r[23:0] : perf5_base_r[23:0];
    assign perf6_base_w = soft_clear_o ? perf6_r[23:0] : perf6_base_r[23:0];

    function [31:0] count_delta;
        input [31:0] count_i;
        input [31:0] base_i;
        input [5:0] less_i;
        input [5:1] equal_i;
        reg [5:0] borrow_w;
        integer nibble;
        begin
            borrow_w[0] = less_i[0];
            for (nibble = 1; nibble < 6; nibble = nibble + 1) begin
                borrow_w[nibble] = less_i[nibble] ||
                    (equal_i[nibble] && borrow_w[nibble-1]);
            end
            count_delta[7:0] = count_i[7:0] - base_i[7:0];
            count_delta[15:8] = count_i[15:8] - base_i[15:8] - {7'd0, borrow_w[1]};
            count_delta[23:16] = count_i[23:16] - base_i[23:16] - {7'd0, borrow_w[3]};
            count_delta[31:24] = count_i[31:24] - base_i[31:24] - {7'd0, borrow_w[5]};
        end
    endfunction

    assign unused_pstrb_w = apb_pstrb_r;
    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_r;
    assign ctrl_write_w = write_w && apb_paddr_r == 12'h004;
    assign enable_o = enable_r;
    assign next_base_o = next_base_r;
    assign stride_o = stride_r;
    assign l0_scroll_o = l0_scroll_r;
    assign layer_ctrl_o = layer_ctrl_r;
    assign l1_next_base_o = l1_next_base_r;
    assign l1_stride_o = l1_stride_r;
    assign l1_pos_o = l1_pos_r;
    assign l1_size_o = l1_size_r;
    assign l1_opa_o = l1_opa_r;
    // spec 2.8, 4.1: register BUSY/IDLE before APB and the reset-drain decision.
    // Delay the reset request alongside BUSY so an old IDLE cannot skip disable ACK.
    // The stop handshake makes IDLE stable before the registered clear pulse.
    // Capture the CDC gray-to-binary outputs before subtraction and stop logic.
    always @(posedge clk_i or negedge rst_n_i[0]) begin
        if (!rst_n_i[0]) begin
            soft_clear_o <= 1'b0;
            busy_r <= 1'b0;
            soft_pending_d_r <= 1'b0;
            perf0_r <= 32'd0;
            perf0_less_r <= 6'd0;
            perf0_equal_r <= 5'b11111;
            perf1_r <= 32'd0;
            perf1_less_r <= 6'd0;
            perf1_equal_r <= 5'b11111;
            perf2_r <= 32'd0;
            perf2_less_r <= 6'd0;
            perf2_equal_r <= 5'b11111;
            perf5_r <= 32'd0;
            perf5_less_r <= 6'd0;
            perf5_equal_r <= 5'b11111;
            perf6_r <= 32'd0;
            perf6_less_r <= 6'd0;
            perf6_equal_r <= 5'b11111;
            urgent_r <= 1'b0;
            delayed_req_r <= 1'b0;
        end else begin
            busy_r <= busy_i;
            soft_pending_d_r <= soft_pending_r;
            soft_clear_o <= soft_pending_r && soft_pending_d_r && !busy_r && !soft_clear_o;
            perf0_r <= perf0_i;
            perf0_less_r <= {perf0_i[23:20] < perf0_base_w[23:20],
                perf0_i[19:16] < perf0_base_w[19:16],
                perf0_i[15:12] < perf0_base_w[15:12],
                perf0_i[11:8] < perf0_base_w[11:8],
                perf0_i[7:4] < perf0_base_w[7:4],
                perf0_i[3:0] < perf0_base_w[3:0]};
            perf0_equal_r <= {perf0_i[23:20] == perf0_base_w[23:20],
                perf0_i[19:16] == perf0_base_w[19:16],
                perf0_i[15:12] == perf0_base_w[15:12],
                perf0_i[11:8] == perf0_base_w[11:8],
                perf0_i[7:4] == perf0_base_w[7:4]};
            perf1_r <= perf1_i;
            perf1_less_r <= {perf1_i[23:20] < perf1_base_w[23:20],
                perf1_i[19:16] < perf1_base_w[19:16],
                perf1_i[15:12] < perf1_base_w[15:12],
                perf1_i[11:8] < perf1_base_w[11:8],
                perf1_i[7:4] < perf1_base_w[7:4],
                perf1_i[3:0] < perf1_base_w[3:0]};
            perf1_equal_r <= {perf1_i[23:20] == perf1_base_w[23:20],
                perf1_i[19:16] == perf1_base_w[19:16],
                perf1_i[15:12] == perf1_base_w[15:12],
                perf1_i[11:8] == perf1_base_w[11:8],
                perf1_i[7:4] == perf1_base_w[7:4]};
            perf2_r <= perf2_i;
            perf2_less_r <= {perf2_i[23:20] < perf2_base_w[23:20],
                perf2_i[19:16] < perf2_base_w[19:16],
                perf2_i[15:12] < perf2_base_w[15:12],
                perf2_i[11:8] < perf2_base_w[11:8],
                perf2_i[7:4] < perf2_base_w[7:4],
                perf2_i[3:0] < perf2_base_w[3:0]};
            perf2_equal_r <= {perf2_i[23:20] == perf2_base_w[23:20],
                perf2_i[19:16] == perf2_base_w[19:16],
                perf2_i[15:12] == perf2_base_w[15:12],
                perf2_i[11:8] == perf2_base_w[11:8],
                perf2_i[7:4] == perf2_base_w[7:4]};
            perf5_r <= perf5_i;
            perf5_less_r <= {perf5_i[23:20] < perf5_base_w[23:20],
                perf5_i[19:16] < perf5_base_w[19:16],
                perf5_i[15:12] < perf5_base_w[15:12],
                perf5_i[11:8] < perf5_base_w[11:8],
                perf5_i[7:4] < perf5_base_w[7:4],
                perf5_i[3:0] < perf5_base_w[3:0]};
            perf5_equal_r <= {perf5_i[23:20] == perf5_base_w[23:20],
                perf5_i[19:16] == perf5_base_w[19:16],
                perf5_i[15:12] == perf5_base_w[15:12],
                perf5_i[11:8] == perf5_base_w[11:8],
                perf5_i[7:4] == perf5_base_w[7:4]};
            perf6_r <= perf6_i;
            perf6_less_r <= {perf6_i[23:20] < perf6_base_w[23:20],
                perf6_i[19:16] < perf6_base_w[19:16],
                perf6_i[15:12] < perf6_base_w[15:12],
                perf6_i[11:8] < perf6_base_w[11:8],
                perf6_i[7:4] < perf6_base_w[7:4],
                perf6_i[3:0] < perf6_base_w[3:0]};
            perf6_equal_r <= {perf6_i[23:20] == perf6_base_w[23:20],
                perf6_i[19:16] == perf6_base_w[19:16],
                perf6_i[15:12] == perf6_base_w[15:12],
                perf6_i[11:8] == perf6_base_w[11:8],
                perf6_i[7:4] == perf6_base_w[7:4]};
            urgent_r <= urgent_i && !soft_clear_o;
            delayed_req_r <= delayed_req_i && !soft_clear_o;
        end
    end
    assign scan_cnt_o = count_delta(perf0_r, perf0_base_r, perf0_less_r, perf0_equal_r);
    assign switch_w = frame_start_i && cur_layer_ctrl_r[0] &&
        (!layer_ctrl_r[0] || next_base_r != cur_base_r);
    assign switch1_w = frame_start_i && cur_layer_ctrl_r[1] &&
        (!layer_ctrl_r[1] || l1_next_base_r != l1_cur_base_r);
    assign irq_set_w = {22'd0, switch1_w, switch_w, 5'd0, frame_start_i,
                        (underflow_i || underflow1_i || dma_err_i), 1'b0};
    assign irq_clear_w = write_w && apb_paddr_r == 12'h010 ? apb_pwdata_r : 32'd0;
    assign irq_o = |(irq_en_r & irq_stat_r);

    // SoC 4.3: setup captures group and local addresses together; no wait state.
    reg [4:0] read_addr0_r /* synthesis syn_preserve=1 */;
    reg read_select0_r;
    reg [31:0] read_group0_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr0_r <= apb_paddr_i[4:0];
            read_select0_r <= apb_paddr_i[11:5] == 7'd0;
        end
    end
    always @(*) begin
        read_group0_w = 32'd0;
        case (read_addr0_r)
            5'h00: read_group0_w = 32'h0005_0002;
            5'h04: read_group0_w = {31'd0, enable_r};
            5'h08: read_group0_w = {29'd0, irq_stat_r[1], !busy_r, busy_r};
            5'h0c: read_group0_w = irq_en_r;
            5'h10: read_group0_w = irq_stat_r;
            5'h14: read_group0_w = {30'd0, err_code_r};
            default: begin end
        endcase
    end
    reg [4:0] read_addr1_r /* synthesis syn_preserve=1 */;
    reg read_select1_r;
    reg [31:0] read_group1_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr1_r <= apb_paddr_i[4:0];
            read_select1_r <= apb_paddr_i[11:5] == 7'd1;
        end
    end
    always @(*) begin
        read_group1_w = 32'd0;
        case (read_addr1_r)
            5'h0c: read_group1_w = frame_cnt_r;
            default: begin end
        endcase
    end
    reg [4:0] read_addr2_r /* synthesis syn_preserve=1 */;
    reg read_select2_r;
    reg [31:0] read_group2_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr2_r <= apb_paddr_i[4:0];
            read_select2_r <= apb_paddr_i[11:5] == 7'd2;
        end
    end
    always @(*) begin
        read_group2_w = 32'd0;
        case (read_addr2_r)
            5'h00: read_group2_w = scan_cnt_o;
            5'h04: read_group2_w = count_delta(perf1_r, perf1_base_r, perf1_less_r, perf1_equal_r);
            5'h08: read_group2_w = count_delta(perf2_r, perf2_base_r, perf2_less_r, perf2_equal_r);
            5'h0c: read_group2_w = perf3_r;
            5'h10: read_group2_w = perf4_r;
            5'h14: read_group2_w = count_delta(perf5_r, perf5_base_r, perf5_less_r, perf5_equal_r);
            5'h18: read_group2_w = count_delta(perf6_r, perf6_base_r, perf6_less_r, perf6_equal_r);
            default: begin end
        endcase
    end
    reg [4:0] read_addr3_r /* synthesis syn_preserve=1 */;
    reg read_select3_r;
    reg [31:0] read_group3_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr3_r <= apb_paddr_i[4:0];
            read_select3_r <= apb_paddr_i[11:5] == 7'd8;
        end
    end
    always @(*) begin
        read_group3_w = 32'd0;
        case (read_addr3_r)
            5'h00: read_group3_w = next_base_r;
            5'h04: read_group3_w = stride_r;
            5'h08: read_group3_w = cur_base_r;
            5'h0c: read_group3_w = rel_base_r;
            5'h10: read_group3_w = frame_cnt_r;
            5'h14: read_group3_w = l0_scroll_r;
            5'h18: read_group3_w = {30'd0, layer_ctrl_r};
            default: begin end
        endcase
    end
    reg [4:0] read_addr4_r /* synthesis syn_preserve=1 */;
    reg read_select4_r;
    reg [31:0] read_group4_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr4_r <= apb_paddr_i[4:0];
            read_select4_r <= apb_paddr_i[11:5] == 7'd9;
        end
    end
    always @(*) begin
        read_group4_w = 32'd0;
        case (read_addr4_r)
            5'h00: read_group4_w = l1_next_base_r;
            5'h04: read_group4_w = l1_stride_r;
            5'h08: read_group4_w = l1_pos_r;
            5'h0c: read_group4_w = l1_size_r;
            5'h10: read_group4_w = {24'd0, l1_opa_r};
            5'h14: read_group4_w = l1_cur_base_r;
            5'h18: read_group4_w = l1_rel_base_r;
            default: begin end
        endcase
    end
    always @(*) begin
        apb_prdata_o = 32'd0;
        apb_prdata_o = apb_prdata_o | (read_group0_w & {32{read_select0_r}});
        apb_prdata_o = apb_prdata_o | (read_group1_w & {32{read_select1_r}});
        apb_prdata_o = apb_prdata_o | (read_group2_w & {32{read_select2_r}});
        apb_prdata_o = apb_prdata_o | (read_group3_w & {32{read_select3_r}});
        apb_prdata_o = apb_prdata_o | (read_group4_w & {32{read_select4_r}});
    end

    // Independent control copies preserve the original D, enable and effective edge.
    always @(posedge clk_i or negedge rst_n_i[0]) begin
        if (!rst_n_i[0]) begin
            enable_r <= 1'b0;
            soft_pending_r <= 1'b0;
            irq_en_r <= 32'd0;
            irq_stat_r <= 32'd0;
            err_code_r <= 2'd0;
            frame_cnt_r <= 32'd0;
        end else begin
            if (clear_local_r[0]) begin
                enable_r <= 1'b0;
                soft_pending_r <= 1'b0;
                irq_en_r <= 32'd0;
                irq_stat_r <= 32'd0;
                err_code_r <= 2'd0;
                frame_cnt_r <= 32'd0;
            end else begin
                if (ctrl_write_w) begin
                    enable_r <= apb_pwdata_r[0] && !apb_pwdata_r[2] && !apb_pwdata_r[3];
                    if (apb_pwdata_r[3]) begin
                        soft_pending_r <= 1'b1;
                    end
                end
                if (soft_pending_r) begin
                    enable_r <= 1'b0;
                end
                if (write_w && apb_paddr_r == 12'h00c) begin
                    irq_en_r <= apb_pwdata_r & IRQ_MASK;
                end
                irq_stat_r <= (irq_stat_r & ~irq_clear_w) | irq_set_w;
                if (irq_clear_w[1]) begin
                    err_code_r <= 2'd0;
                end
                if (underflow_i) begin
                    err_code_r <= 2'd1;
                end
                if (underflow1_i) begin
                    err_code_r <= 2'd3;
                end
                if (dma_err_i) begin
                    err_code_r <= 2'd2;
                end
                if (frame_start_i) begin
                    frame_cnt_r[15:0] <= frame_cnt_r[15:0] + 16'd1;
                    if (frame_cnt_r[15:0] == 16'hffff) begin
                        frame_cnt_r[31:16] <= frame_cnt_r[31:16] + 16'd1;
                    end
                end
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i[1]) begin
        if (!rst_n_i[1]) begin
            next_base_r <= 32'd0;
            stride_r <= 32'h0000_0a00;
            cur_base_r <= 32'd0;
            rel_base_r <= 32'd0;
            l0_scroll_r <= 32'd0;
            layer_ctrl_r <= 2'd1;
            cur_layer_ctrl_r <= 2'd0;
        end else begin
            if (clear_local_r[1]) begin
                next_base_r <= 32'd0;
                stride_r <= 32'h0000_0a00;
                cur_base_r <= 32'd0;
                rel_base_r <= 32'd0;
                l0_scroll_r <= 32'd0;
                layer_ctrl_r <= 2'd1;
                cur_layer_ctrl_r <= 2'd0;
            end else begin
                if (write_w && apb_paddr_r == 12'h100) begin
                    next_base_r <= {apb_pwdata_r[31:12], 12'd0};
                end
                if (write_w && apb_paddr_r == 12'h104) begin
                    stride_r <= {16'd0, apb_pwdata_r[15:5], 5'd0};
                end
                if (write_w) begin
                    case (apb_paddr_r)
                        12'h114: begin
                            l0_scroll_r <= apb_pwdata_r & 32'h0fff_7fff;
                        end
                        12'h118: begin
                            layer_ctrl_r <= apb_pwdata_r[1:0];
                        end
                        default: begin end
                    endcase
                end
                if (frame_start_i) begin
                    cur_layer_ctrl_r <= layer_ctrl_r;
                    if (layer_ctrl_r[0]) begin
                        cur_base_r <= next_base_r;
                    end
                end
                if (switch_w) begin
                    rel_base_r <= cur_base_r;
                end
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i[2]) begin
        if (!rst_n_i[2]) begin
            l1_next_base_r <= 32'd0;
            l1_stride_r <= 32'h0000_1400;
            l1_pos_r <= 32'd0;
            l1_size_r <= 32'h02d0_0500;
            l1_opa_r <= 8'd255;
            l1_cur_base_r <= 32'd0;
            l1_rel_base_r <= 32'd0;
        end else begin
            if (clear_local_r[2]) begin
                l1_next_base_r <= 32'd0;
                l1_stride_r <= 32'h0000_1400;
                l1_pos_r <= 32'd0;
                l1_size_r <= 32'h02d0_0500;
                l1_opa_r <= 8'd255;
                l1_cur_base_r <= 32'd0;
                l1_rel_base_r <= 32'd0;
            end else begin
                if (write_w) begin
                    case (apb_paddr_r)
                        12'h120: begin
                            l1_next_base_r <= {apb_pwdata_r[31:12], 12'd0};
                        end
                        12'h124: begin
                            l1_stride_r <= {16'd0, apb_pwdata_r[15:5], 5'd0};
                        end
                        12'h128: begin
                            l1_pos_r <= apb_pwdata_r & 32'h03ff_07f8;
                        end
                        12'h12c: begin
                            l1_size_r <= apb_pwdata_r & 32'h03ff_07f8;
                        end
                        12'h130: begin
                            l1_opa_r <= apb_pwdata_r[7:0];
                        end
                        default: begin end
                    endcase
                end
                if (frame_start_i) begin
                    if (layer_ctrl_r[1]) begin
                        l1_cur_base_r <= l1_next_base_r;
                    end
                end
                if (switch1_w) begin
                    l1_rel_base_r <= l1_cur_base_r;
                end
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i[3]) begin
        if (!rst_n_i[3]) begin
            perf0_base_r <= 32'd0;
            perf1_base_r <= 32'd0;
            perf2_base_r <= 32'd0;
            perf5_base_r <= 32'd0;
            perf6_base_r <= 32'd0;
            perf3_r <= 32'd0;
            perf4_r <= 32'd0;
        end else begin
            if (clear_local_r[3]) begin
                perf0_base_r <= perf0_r;
                perf1_base_r <= perf1_r;
                perf2_base_r <= perf2_r;
                perf5_base_r <= perf5_r;
                perf6_base_r <= perf6_r;
                perf3_r <= 32'd0;
                perf4_r <= 32'd0;
            end else begin
                if (urgent_r) begin
                    perf3_r[15:0] <= perf3_r[15:0] + 16'd1;
                    if (perf3_r[15:0] == 16'hffff) begin
                        perf3_r[31:16] <= perf3_r[31:16] + 16'd1;
                    end
                end
                if (delayed_req_r) begin
                    perf4_r[15:0] <= perf4_r[15:0] + 16'd1;
                    if (perf4_r[15:0] == 16'hffff) begin
                        perf4_r[31:16] <= perf4_r[31:16] + 16'd1;
                    end
                end
            end
        end
    end
    reg [3:0] clear_local_r /* synthesis syn_preserve=1 */;
    always @(posedge clk_i or negedge rst_n_i[0]) begin
        if (!rst_n_i[0])
            clear_local_r <= 4'd0;
        else
            clear_local_r <= {4{soft_pending_r && soft_pending_d_r && !busy_r &&
                !soft_clear_o}};
    end
endmodule
