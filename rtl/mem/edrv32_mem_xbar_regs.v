// File: edrv32_mem_xbar_regs.v
// Spec: mem-subsys-spec 4.1, 6; edrv32-soc-spec 7.1.
// Description: APB parameters, sticky violation interrupt and atomic statistics snapshots.
// Statistics use downstream AW/AR handshakes. Snapshot captures before the registered command takes effect.
// Event counters saturate; simultaneous SNAPSHOT/CLEAR captures before clearing.
// APB writes ignore PSTRB and update complete words (coordinator clarification).
// CTRL and unused common registers read zero; ERR_CODE aliases ERR_TYPE.
// Private parameters retain only their specified low bits; readback zero-extends.
// Clock: clk_mem.
module edrv32_mem_xbar_regs (
    // Parallel regional resets: configuration/global counters/commands; 3 banks per port.
    input wire clk_i,
    input wire [2:0] rst_n_i,
    input wire [20:0] rst_mem_stat_n_i,

    // APB control interface.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output reg [31:0] apb_prdata_o,
    output wire apb_pslverr_o,

    // Scheduler configuration and events.
    output reg [3:0] outst_total_o,
    output reg [7:0] urg_max_o,
    output reg [15:0] starve_cyc_o,
    output reg [7:0] dir_batch_o,
    output wire [27:0] outst_rd_o,
    output wire [27:0] outst_wr_o,
    output wire [27:0] weight_o,
    output wire [62:0] rate_o,
    input wire grant_i,
    input wire grant_write_i,
    input wire [2:0] grant_port_i,
    input wire [4:0] grant_beats_i,
    input wire [15:0] grant_wait_i,
    input wire grant_urgent_i,
    input wire dir_switch_i,
    input wire ds_busy_i,
    input wire busy_i,
    input wire err_valid_i,
    input wire [2:0] err_port_i,
    input wire [31:0] err_addr_i,
    input wire [2:0] err_type_i,

    // Configuration write invalidates uncommitted scheduler eligibility.
    output wire cfg_write_o,

    // Interrupt.
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

    reg [3:0] outst_rd_r [0:6];
    reg [3:0] outst_wr_r [0:6];
    reg [3:0] weight_r [0:6];
    reg [8:0] rate_r [0:6];
    reg irq_en_r;
    reg irq_stat_r;
    reg [2:0] err_port_r;
    reg [31:0] err_addr_r;
    reg [2:0] err_type_r;
    wire [31:0] rd_txn_r [0:6];
    wire [31:0] wr_txn_r [0:6];
    wire [31:0] urg_cnt_r [0:6];
    wire [31:0] rd_txn_snapshot_r [0:6];
    wire [31:0] wr_txn_snapshot_r [0:6];
    wire [31:0] rd_beat_snapshot_r [0:6];
    wire [31:0] wr_beat_snapshot_r [0:6];
    wire [15:0] max_snapshot_r [0:6];
    wire [31:0] sum_snapshot_r [0:6];
    wire [31:0] urg_snapshot_r [0:6];
    reg [31:0] dir_switch_r;
    reg [31:0] ds_busy_r;
    reg [31:0] window_cyc_r;
    reg [31:0] dir_snapshot_r;
    reg [31:0] busy_snapshot_r;
    reg [31:0] window_snapshot_r;
    wire [3:0] rd_txn_carry_r [0:6];
    wire [3:0] wr_txn_carry_r [0:6];
    wire [3:0] urg_cnt_carry_r [0:6];
    reg [3:0] dir_switch_carry_r;
    reg [3:0] ds_busy_carry_r;
    reg [3:0] window_cyc_carry_r;
    wire unused_pstrb_w;
    assign unused_pstrb_w = &apb_pstrb_r;
    wire unused_pwdata_w;
    assign unused_pwdata_w = &apb_pwdata_r[31:16];
    // SoC 7.1: statistics consume only the preceding cycle event.
    reg grant_event_r;
    reg grant_write_event_r;
    reg [2:0] grant_port_event_r;
    reg [4:0] grant_beats_event_r;
    reg [15:0] grant_wait_event_r;
    reg grant_urgent_event_r;
    reg dir_switch_event_r;
    reg ds_busy_event_r;
    reg window_event_r;
    wire [7:0] snapshot_cmd_w;
    wire [6:0] clear_cmd_w;
    wire [23:0] clear_group_w;
    wire write_w;
    wire snapshot_w;
    wire clear_w;
    wire irq_clear_w;
    integer idx;
    genvar p;

    function [31:0] sat_add;
        input [31:0] value_i;
        input [31:0] increment_i;
        begin
            sat_add = ({1'b0, value_i} + {1'b0, increment_i}) > 33'h0_ffff_ffff ?
                32'hffff_ffff : value_i + increment_i;
        end
    endfunction

    // X-F1 path 7: cache the carry predicates of each +1 counter on the prior edge.
    // Parallel byte increments retain registered event counting and snapshot/CLEAR semantics.
    function [31:0] count_inc;
        input [31:0] value_i;
        input [3:0] carry_i;
        begin
            count_inc = carry_i[3] ? value_i :
                {(value_i[31:24] + {7'b0, carry_i[2]}),
                    (value_i[23:16] + {7'b0, carry_i[1]}),
                    (value_i[15:8] + {7'b0, carry_i[0]}), (value_i[7:0] + 8'd1)};
        end
    endfunction

    function [3:0] count_carry;
        input [31:0] value_i;
        input update_i;
        input full_i;
        begin
            count_carry = update_i && !full_i ?
                {value_i == 32'hffff_fffe, value_i[23:0] == 24'hffff_fe,
                    value_i[15:0] == 16'hfffe, value_i[7:0] == 8'hfe} :
                {(&value_i), (&value_i[23:0]), (&value_i[15:0]), (&value_i[7:0])};
        end
    endfunction

    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_r;
    assign snapshot_w = write_w && apb_paddr_r == 12'h110 &&
                        apb_pwdata_r[0];
    assign clear_w = write_w && apb_paddr_r == 12'h110 &&
                        apb_pwdata_r[1];
    assign irq_clear_w = write_w && apb_paddr_r == 12'h010 &&
                            apb_pwdata_r[1];
    assign cfg_write_o = write_w && apb_paddr_r[1:0] == 0 &&
        ((apb_paddr_r[11:4] == 8'h10) ||
            (apb_paddr_r[11:8] == 4'h2 && apb_paddr_r[7:5] != 3'd7 && !apb_paddr_r[4]));
    assign irq_o = irq_en_r && irq_stat_r;

    generate
        for (p = 0; p < 7; p = p + 1) begin : g_config
            assign outst_rd_o[p*4 +: 4] = outst_rd_r[p];
            assign outst_wr_o[p*4 +: 4] = outst_wr_r[p];
            assign weight_o[p*4 +: 4] = weight_r[p];
            assign rate_o[p*9 +: 9] = rate_r[p];
        end
    endgenerate

    // Independent control copies preserve the original D, enable and effective edge.
    always @(posedge clk_i or negedge rst_n_i[1]) begin
        if (!rst_n_i[1]) begin
            dir_switch_carry_r <= 4'b0;
        end else begin
            dir_switch_carry_r <= clear_group_w[21 + 0] ? 4'b0 :
                count_carry(dir_switch_r, dir_switch_event_r, dir_switch_carry_r[3]);
        end
    end
    always @(posedge clk_i or negedge rst_n_i[1]) begin
        if (!rst_n_i[1]) begin
            ds_busy_carry_r <= 4'b0;
        end else begin
            ds_busy_carry_r <= clear_group_w[21 + 1] ? 4'b0 :
                count_carry(ds_busy_r, ds_busy_event_r, ds_busy_carry_r[3]);
        end
    end
    always @(posedge clk_i or negedge rst_n_i[1]) begin
        if (!rst_n_i[1]) begin
            window_cyc_carry_r <= 4'b0;
        end else begin
            window_cyc_carry_r <= clear_group_w[21 + 2] ? 4'b0 :
                count_carry(window_cyc_r, window_event_r, window_cyc_carry_r[3]);
        end
    end
    genvar carry_idx;
    generate
        for (carry_idx = 0; carry_idx < 7; carry_idx = carry_idx + 1) begin : g_carry_idx
            reg [3:0] bank_rd_txn_carry_r;
            reg [3:0] bank_wr_txn_carry_r;
            reg [3:0] bank_urg_cnt_carry_r;
            assign rd_txn_carry_r[carry_idx] = bank_rd_txn_carry_r;
            assign wr_txn_carry_r[carry_idx] = bank_wr_txn_carry_r;
            assign urg_cnt_carry_r[carry_idx] = bank_urg_cnt_carry_r;
            // Independent control copies preserve the original D, enable and effective edge.
    always @(posedge clk_i or negedge rst_mem_stat_n_i[carry_idx*3 + 0]) begin
        if (!rst_mem_stat_n_i[carry_idx*3 + 0]) begin
            bank_rd_txn_carry_r <= 4'b0;
        end else begin
            bank_rd_txn_carry_r <= clear_cmd_w[carry_idx] ? 4'b0 :
                count_carry(rd_txn_r[carry_idx],
                grant_event_r && grant_port_event_r == carry_idx[2:0] &&
                !grant_write_event_r,
                bank_rd_txn_carry_r[3]);
        end
    end
    always @(posedge clk_i or negedge rst_mem_stat_n_i[carry_idx*3 + 1]) begin
        if (!rst_mem_stat_n_i[carry_idx*3 + 1]) begin
            bank_wr_txn_carry_r <= 4'b0;
        end else begin
            bank_wr_txn_carry_r <= clear_cmd_w[carry_idx] ? 4'b0 :
                count_carry(wr_txn_r[carry_idx],
                grant_event_r && grant_port_event_r == carry_idx[2:0] &&
                grant_write_event_r,
                bank_wr_txn_carry_r[3]);
        end
    end
    always @(posedge clk_i or negedge rst_mem_stat_n_i[carry_idx*3 + 2]) begin
        if (!rst_mem_stat_n_i[carry_idx*3 + 2]) begin
            bank_urg_cnt_carry_r <= 4'b0;
        end else begin
            bank_urg_cnt_carry_r <= clear_cmd_w[carry_idx] ? 4'b0 :
                count_carry(urg_cnt_r[carry_idx],
                grant_event_r && grant_port_event_r == carry_idx[2:0] &&
                grant_urgent_event_r,
                bank_urg_cnt_carry_r[3]);
        end
    end
        end
    endgenerate

    // Disjoint address cases infer a parallel read mux, without a priority chain.
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
            5'h00: read_group0_w = 32'h0008_0001;
            5'h08: read_group0_w = {29'b0, irq_stat_r, !busy_i, busy_i};
            5'h0c: read_group0_w = {30'b0, irq_en_r, 1'b0};
            5'h10: read_group0_w = {30'b0, irq_stat_r, 1'b0};
            5'h14: read_group0_w = {29'b0, err_type_r};
            default: begin end
        endcase
    end
    reg [4:0] read_addr1_r /* synthesis syn_preserve=1 */;
    reg read_select1_r;
    reg [31:0] read_group1_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr1_r <= apb_paddr_i[4:0];
            read_select1_r <= apb_paddr_i[11:5] == 7'd8;
        end
    end
    always @(*) begin
        read_group1_w = 32'd0;
        case (read_addr1_r)
            5'h00: read_group1_w = {28'b0, outst_total_o};
            5'h04: read_group1_w = {24'b0, urg_max_o};
            5'h08: read_group1_w = {16'b0, starve_cyc_o};
            5'h0c: read_group1_w = {24'b0, dir_batch_o};
            default: begin end
        endcase
    end
    reg [4:0] read_addr2_r /* synthesis syn_preserve=1 */;
    reg read_select2_r;
    reg [31:0] read_group2_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr2_r <= apb_paddr_i[4:0];
            read_select2_r <= apb_paddr_i[11:5] == 7'd9;
        end
    end
    always @(*) begin
        read_group2_w = 32'd0;
        case (read_addr2_r)
            5'h00: read_group2_w = {29'b0, err_port_r};
            5'h04: read_group2_w = err_addr_r;
            5'h08: read_group2_w = {29'b0, err_type_r};
            default: begin end
        endcase
    end
    reg [4:0] read_addr3_r /* synthesis syn_preserve=1 */;
    reg read_select3_r;
    reg [31:0] read_group3_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr3_r <= apb_paddr_i[4:0];
            read_select3_r <= apb_paddr_i[11:5] == 7'd16;
        end
    end
    always @(*) begin
        read_group3_w = 32'd0;
        case (read_addr3_r)
            5'h00: read_group3_w = {28'b0, outst_rd_r[0]};
            5'h04: read_group3_w = {28'b0, outst_wr_r[0]};
            5'h08: read_group3_w = {28'b0, weight_r[0]};
            5'h0c: read_group3_w = {23'b0, rate_r[0]};
            default: begin end
        endcase
    end
    reg [4:0] read_addr4_r /* synthesis syn_preserve=1 */;
    reg read_select4_r;
    reg [31:0] read_group4_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr4_r <= apb_paddr_i[4:0];
            read_select4_r <= apb_paddr_i[11:5] == 7'd17;
        end
    end
    always @(*) begin
        read_group4_w = 32'd0;
        case (read_addr4_r)
            5'h00: read_group4_w = {28'b0, outst_rd_r[1]};
            5'h04: read_group4_w = {28'b0, outst_wr_r[1]};
            5'h08: read_group4_w = {28'b0, weight_r[1]};
            5'h0c: read_group4_w = {23'b0, rate_r[1]};
            default: begin end
        endcase
    end
    reg [4:0] read_addr5_r /* synthesis syn_preserve=1 */;
    reg read_select5_r;
    reg [31:0] read_group5_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr5_r <= apb_paddr_i[4:0];
            read_select5_r <= apb_paddr_i[11:5] == 7'd18;
        end
    end
    always @(*) begin
        read_group5_w = 32'd0;
        case (read_addr5_r)
            5'h00: read_group5_w = {28'b0, outst_rd_r[2]};
            5'h04: read_group5_w = {28'b0, outst_wr_r[2]};
            5'h08: read_group5_w = {28'b0, weight_r[2]};
            5'h0c: read_group5_w = {23'b0, rate_r[2]};
            default: begin end
        endcase
    end
    reg [4:0] read_addr6_r /* synthesis syn_preserve=1 */;
    reg read_select6_r;
    reg [31:0] read_group6_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr6_r <= apb_paddr_i[4:0];
            read_select6_r <= apb_paddr_i[11:5] == 7'd19;
        end
    end
    always @(*) begin
        read_group6_w = 32'd0;
        case (read_addr6_r)
            5'h00: read_group6_w = {28'b0, outst_rd_r[3]};
            5'h04: read_group6_w = {28'b0, outst_wr_r[3]};
            5'h08: read_group6_w = {28'b0, weight_r[3]};
            5'h0c: read_group6_w = {23'b0, rate_r[3]};
            default: begin end
        endcase
    end
    reg [4:0] read_addr7_r /* synthesis syn_preserve=1 */;
    reg read_select7_r;
    reg [31:0] read_group7_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr7_r <= apb_paddr_i[4:0];
            read_select7_r <= apb_paddr_i[11:5] == 7'd20;
        end
    end
    always @(*) begin
        read_group7_w = 32'd0;
        case (read_addr7_r)
            5'h00: read_group7_w = {28'b0, outst_rd_r[4]};
            5'h04: read_group7_w = {28'b0, outst_wr_r[4]};
            5'h08: read_group7_w = {28'b0, weight_r[4]};
            5'h0c: read_group7_w = {23'b0, rate_r[4]};
            default: begin end
        endcase
    end
    reg [4:0] read_addr8_r /* synthesis syn_preserve=1 */;
    reg read_select8_r;
    reg [31:0] read_group8_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr8_r <= apb_paddr_i[4:0];
            read_select8_r <= apb_paddr_i[11:5] == 7'd21;
        end
    end
    always @(*) begin
        read_group8_w = 32'd0;
        case (read_addr8_r)
            5'h00: read_group8_w = {28'b0, outst_rd_r[5]};
            5'h04: read_group8_w = {28'b0, outst_wr_r[5]};
            5'h08: read_group8_w = {28'b0, weight_r[5]};
            5'h0c: read_group8_w = {23'b0, rate_r[5]};
            default: begin end
        endcase
    end
    reg [4:0] read_addr9_r /* synthesis syn_preserve=1 */;
    reg read_select9_r;
    reg [31:0] read_group9_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr9_r <= apb_paddr_i[4:0];
            read_select9_r <= apb_paddr_i[11:5] == 7'd22;
        end
    end
    always @(*) begin
        read_group9_w = 32'd0;
        case (read_addr9_r)
            5'h00: read_group9_w = {28'b0, outst_rd_r[6]};
            5'h04: read_group9_w = {28'b0, outst_wr_r[6]};
            5'h08: read_group9_w = {28'b0, weight_r[6]};
            5'h0c: read_group9_w = {23'b0, rate_r[6]};
            default: begin end
        endcase
    end
    reg [4:0] read_addr10_r /* synthesis syn_preserve=1 */;
    reg read_select10_r;
    reg [31:0] read_group10_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr10_r <= apb_paddr_i[4:0];
            read_select10_r <= apb_paddr_i[11:5] == 7'd32;
        end
    end
    always @(*) begin
        read_group10_w = 32'd0;
        case (read_addr10_r)
            5'h00: read_group10_w = rd_txn_snapshot_r[0];
            5'h14: read_group10_w = wr_txn_snapshot_r[0];
            5'h04: read_group10_w = rd_beat_snapshot_r[0];
            5'h18: read_group10_w = wr_beat_snapshot_r[0];
            5'h08: read_group10_w = {16'b0, max_snapshot_r[0]};
            5'h0c: read_group10_w = sum_snapshot_r[0];
            5'h10: read_group10_w = urg_snapshot_r[0];
            default: begin end
        endcase
    end
    reg [4:0] read_addr11_r /* synthesis syn_preserve=1 */;
    reg read_select11_r;
    reg [31:0] read_group11_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr11_r <= apb_paddr_i[4:0];
            read_select11_r <= apb_paddr_i[11:5] == 7'd33;
        end
    end
    always @(*) begin
        read_group11_w = 32'd0;
        case (read_addr11_r)
            5'h00: read_group11_w = rd_txn_snapshot_r[1];
            5'h14: read_group11_w = wr_txn_snapshot_r[1];
            5'h04: read_group11_w = rd_beat_snapshot_r[1];
            5'h18: read_group11_w = wr_beat_snapshot_r[1];
            5'h08: read_group11_w = {16'b0, max_snapshot_r[1]};
            5'h0c: read_group11_w = sum_snapshot_r[1];
            5'h10: read_group11_w = urg_snapshot_r[1];
            default: begin end
        endcase
    end
    reg [4:0] read_addr12_r /* synthesis syn_preserve=1 */;
    reg read_select12_r;
    reg [31:0] read_group12_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr12_r <= apb_paddr_i[4:0];
            read_select12_r <= apb_paddr_i[11:5] == 7'd34;
        end
    end
    always @(*) begin
        read_group12_w = 32'd0;
        case (read_addr12_r)
            5'h00: read_group12_w = rd_txn_snapshot_r[2];
            5'h14: read_group12_w = wr_txn_snapshot_r[2];
            5'h04: read_group12_w = rd_beat_snapshot_r[2];
            5'h18: read_group12_w = wr_beat_snapshot_r[2];
            5'h08: read_group12_w = {16'b0, max_snapshot_r[2]};
            5'h0c: read_group12_w = sum_snapshot_r[2];
            5'h10: read_group12_w = urg_snapshot_r[2];
            default: begin end
        endcase
    end
    reg [4:0] read_addr13_r /* synthesis syn_preserve=1 */;
    reg read_select13_r;
    reg [31:0] read_group13_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr13_r <= apb_paddr_i[4:0];
            read_select13_r <= apb_paddr_i[11:5] == 7'd35;
        end
    end
    always @(*) begin
        read_group13_w = 32'd0;
        case (read_addr13_r)
            5'h00: read_group13_w = rd_txn_snapshot_r[3];
            5'h14: read_group13_w = wr_txn_snapshot_r[3];
            5'h04: read_group13_w = rd_beat_snapshot_r[3];
            5'h18: read_group13_w = wr_beat_snapshot_r[3];
            5'h08: read_group13_w = {16'b0, max_snapshot_r[3]};
            5'h0c: read_group13_w = sum_snapshot_r[3];
            5'h10: read_group13_w = urg_snapshot_r[3];
            default: begin end
        endcase
    end
    reg [4:0] read_addr14_r /* synthesis syn_preserve=1 */;
    reg read_select14_r;
    reg [31:0] read_group14_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr14_r <= apb_paddr_i[4:0];
            read_select14_r <= apb_paddr_i[11:5] == 7'd36;
        end
    end
    always @(*) begin
        read_group14_w = 32'd0;
        case (read_addr14_r)
            5'h00: read_group14_w = rd_txn_snapshot_r[4];
            5'h14: read_group14_w = wr_txn_snapshot_r[4];
            5'h04: read_group14_w = rd_beat_snapshot_r[4];
            5'h18: read_group14_w = wr_beat_snapshot_r[4];
            5'h08: read_group14_w = {16'b0, max_snapshot_r[4]};
            5'h0c: read_group14_w = sum_snapshot_r[4];
            5'h10: read_group14_w = urg_snapshot_r[4];
            default: begin end
        endcase
    end
    reg [4:0] read_addr15_r /* synthesis syn_preserve=1 */;
    reg read_select15_r;
    reg [31:0] read_group15_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr15_r <= apb_paddr_i[4:0];
            read_select15_r <= apb_paddr_i[11:5] == 7'd37;
        end
    end
    always @(*) begin
        read_group15_w = 32'd0;
        case (read_addr15_r)
            5'h00: read_group15_w = rd_txn_snapshot_r[5];
            5'h14: read_group15_w = wr_txn_snapshot_r[5];
            5'h04: read_group15_w = rd_beat_snapshot_r[5];
            5'h18: read_group15_w = wr_beat_snapshot_r[5];
            5'h08: read_group15_w = {16'b0, max_snapshot_r[5]};
            5'h0c: read_group15_w = sum_snapshot_r[5];
            5'h10: read_group15_w = urg_snapshot_r[5];
            default: begin end
        endcase
    end
    reg [4:0] read_addr16_r /* synthesis syn_preserve=1 */;
    reg read_select16_r;
    reg [31:0] read_group16_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr16_r <= apb_paddr_i[4:0];
            read_select16_r <= apb_paddr_i[11:5] == 7'd38;
        end
    end
    always @(*) begin
        read_group16_w = 32'd0;
        case (read_addr16_r)
            5'h00: read_group16_w = rd_txn_snapshot_r[6];
            5'h14: read_group16_w = wr_txn_snapshot_r[6];
            5'h04: read_group16_w = rd_beat_snapshot_r[6];
            5'h18: read_group16_w = wr_beat_snapshot_r[6];
            5'h08: read_group16_w = {16'b0, max_snapshot_r[6]};
            5'h0c: read_group16_w = sum_snapshot_r[6];
            5'h10: read_group16_w = urg_snapshot_r[6];
            default: begin end
        endcase
    end
    reg [4:0] read_addr17_r /* synthesis syn_preserve=1 */;
    reg read_select17_r;
    reg [31:0] read_group17_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr17_r <= apb_paddr_i[4:0];
            read_select17_r <= apb_paddr_i[11:5] == 7'd40;
        end
    end
    always @(*) begin
        read_group17_w = 32'd0;
        case (read_addr17_r)
            5'h00: read_group17_w = dir_snapshot_r;
            5'h04: read_group17_w = busy_snapshot_r;
            5'h08: read_group17_w = window_snapshot_r;
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
        apb_prdata_o = apb_prdata_o | (read_group5_w & {32{read_select5_r}});
        apb_prdata_o = apb_prdata_o | (read_group6_w & {32{read_select6_r}});
        apb_prdata_o = apb_prdata_o | (read_group7_w & {32{read_select7_r}});
        apb_prdata_o = apb_prdata_o | (read_group8_w & {32{read_select8_r}});
        apb_prdata_o = apb_prdata_o | (read_group9_w & {32{read_select9_r}});
        apb_prdata_o = apb_prdata_o | (read_group10_w & {32{read_select10_r}});
        apb_prdata_o = apb_prdata_o | (read_group11_w & {32{read_select11_r}});
        apb_prdata_o = apb_prdata_o | (read_group12_w & {32{read_select12_r}});
        apb_prdata_o = apb_prdata_o | (read_group13_w & {32{read_select13_r}});
        apb_prdata_o = apb_prdata_o | (read_group14_w & {32{read_select14_r}});
        apb_prdata_o = apb_prdata_o | (read_group15_w & {32{read_select15_r}});
        apb_prdata_o = apb_prdata_o | (read_group16_w & {32{read_select16_r}});
        apb_prdata_o = apb_prdata_o | (read_group17_w & {32{read_select17_r}});
    end

    always @(posedge clk_i or negedge rst_n_i[0]) begin
        if (!rst_n_i[0]) begin
            outst_total_o <= 4'd8;
            urg_max_o <= 8'd8;
            starve_cyc_o <= 16'd256;
            dir_batch_o <= 8'd4;
            irq_en_r <= 1'b0;
            irq_stat_r <= 1'b0;
            err_port_r <= 3'b0;
            err_addr_r <= 32'b0;
            err_type_r <= 3'b0;
            for (idx = 0; idx < 7; idx = idx + 1) begin
                outst_rd_r[idx] <= idx == 2 ? 4'd1 :
                                    idx == 0 || idx == 3 ? 4'd4 : 4'd2;
                outst_wr_r[idx] <= idx == 0 ? 4'd0 :
                                    idx == 2 ? 4'd1 : idx == 1 ? 4'd4 : 4'd2;
                weight_r[idx] <= idx < 2 ? 4'd4 : idx == 2 ? 4'd0 :
                                    idx == 3 ? 4'd3 : idx == 6 ? 4'd1 : 4'd2;
                rate_r[idx] <= idx == 2 ? 9'd26 : idx == 6 ? 9'd13 : 9'd0;
            end
        end else begin
            if (write_w) begin
                for (idx = 0; idx < 7; idx = idx + 1) begin
                    if ({20'b0, apb_paddr_r} == 32'h200 + 32*idx) begin
                        outst_rd_r[idx] <= apb_pwdata_r[3:0];
                    end
                    if ({20'b0, apb_paddr_r} == 32'h204 + 32*idx) begin
                        outst_wr_r[idx] <= apb_pwdata_r[3:0];
                    end
                    if ({20'b0, apb_paddr_r} == 32'h208 + 32*idx) begin
                        weight_r[idx] <= apb_pwdata_r[3:0];
                    end
                    if ({20'b0, apb_paddr_r} == 32'h20c + 32*idx) begin
                        rate_r[idx] <= apb_pwdata_r[8:0];
                    end
                end
                case (apb_paddr_r)
                    12'h00c: irq_en_r <= apb_pwdata_r[1];
                    12'h100: outst_total_o <= apb_pwdata_r[3:0];
                    12'h104: urg_max_o <= apb_pwdata_r[7:0];
                    12'h108: starve_cyc_o <= apb_pwdata_r[15:0];
                    12'h10c: dir_batch_o <= apb_pwdata_r[7:0];
                    default: begin end
                endcase
            end
            if (irq_clear_w) begin
                irq_stat_r <= 1'b0;
                err_port_r <= 3'b0;
                err_addr_r <= 32'b0;
                err_type_r <= 3'b0;
            end
            // A new violation wins over a simultaneous software clear.
            if (err_valid_i) begin
                irq_stat_r <= 1'b1;
                err_port_r <= err_port_i;
                err_addr_r <= err_addr_i;
                err_type_r <= err_type_i;
            end
        end
    end

    // Independent control copies preserve the original D, enable and effective edge.
    always @(posedge clk_i or negedge rst_n_i[1]) begin
        if (!rst_n_i[1]) begin
            dir_switch_r <= 32'b0;
            dir_snapshot_r <= 32'b0;
        end else begin
            if (snapshot_cmd_w[7]) begin
                dir_snapshot_r <= dir_switch_r;
            end
            if (clear_group_w[21 + 0]) begin
                dir_switch_r <= 32'b0;
            end else begin
                if (dir_switch_event_r) begin
                    dir_switch_r <= count_inc(dir_switch_r, dir_switch_carry_r);
                end
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i[1]) begin
        if (!rst_n_i[1]) begin
            ds_busy_r <= 32'b0;
            busy_snapshot_r <= 32'b0;
        end else begin
            if (snapshot_cmd_w[7]) begin
                busy_snapshot_r <= ds_busy_r;
            end
            if (clear_group_w[21 + 1]) begin
                ds_busy_r <= 32'b0;
            end else begin
                if (ds_busy_event_r) begin
                    ds_busy_r <= count_inc(ds_busy_r, ds_busy_carry_r);
                end
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i[1]) begin
        if (!rst_n_i[1]) begin
            window_cyc_r <= 32'b0;
            window_snapshot_r <= 32'b0;
        end else begin
            if (snapshot_cmd_w[7]) begin
                window_snapshot_r <= window_cyc_r;
            end
            if (clear_group_w[21 + 2]) begin
                window_cyc_r <= 32'b0;
            end else begin
                if (window_event_r) begin
                    window_cyc_r <= count_inc(window_cyc_r, window_cyc_carry_r);
                end
            end
        end
    end
    genvar stat_idx;
    generate
        for (stat_idx = 0; stat_idx < 7; stat_idx = stat_idx + 1) begin : g_stat_idx
            reg [31:0] bank_rd_txn_r;
            reg [31:0] bank_wr_txn_r;
            reg [31:0] bank_rd_beat_r;
            reg [31:0] bank_wr_beat_r;
            reg [15:0] bank_wait_max_r;
            reg [31:0] bank_wait_sum_r;
            reg [31:0] bank_urg_cnt_r;
            reg [31:0] bank_rd_txn_snapshot_r;
            reg [31:0] bank_wr_txn_snapshot_r;
            reg [31:0] bank_rd_beat_snapshot_r;
            reg [31:0] bank_wr_beat_snapshot_r;
            reg [15:0] bank_max_snapshot_r;
            reg [31:0] bank_sum_snapshot_r;
            reg [31:0] bank_urg_snapshot_r;
            assign rd_txn_r[stat_idx] = bank_rd_txn_r;
            assign wr_txn_r[stat_idx] = bank_wr_txn_r;
            assign urg_cnt_r[stat_idx] = bank_urg_cnt_r;
            assign rd_txn_snapshot_r[stat_idx] = bank_rd_txn_snapshot_r;
            assign wr_txn_snapshot_r[stat_idx] = bank_wr_txn_snapshot_r;
            assign rd_beat_snapshot_r[stat_idx] = bank_rd_beat_snapshot_r;
            assign wr_beat_snapshot_r[stat_idx] = bank_wr_beat_snapshot_r;
            assign max_snapshot_r[stat_idx] = bank_max_snapshot_r;
            assign sum_snapshot_r[stat_idx] = bank_sum_snapshot_r;
            assign urg_snapshot_r[stat_idx] = bank_urg_snapshot_r;
            // Independent control copies preserve the original D, enable and effective edge.
    always @(posedge clk_i or negedge rst_mem_stat_n_i[stat_idx*3+0]) begin
        if (!rst_mem_stat_n_i[stat_idx*3+0]) begin
            bank_rd_txn_r <= 32'b0;
            bank_rd_beat_r <= 32'b0;
            bank_rd_txn_snapshot_r <= 32'b0;
            bank_rd_beat_snapshot_r <= 32'b0;
        end else begin
            if (snapshot_cmd_w[stat_idx]) begin
                bank_rd_txn_snapshot_r <= bank_rd_txn_r;
                bank_rd_beat_snapshot_r <= bank_rd_beat_r;
            end
            if (clear_group_w[stat_idx*3 + 0]) begin
                bank_rd_txn_r <= 32'b0;
                bank_rd_beat_r <= 32'b0;
            end else begin
                if (grant_event_r && grant_port_event_r == stat_idx[2:0]) begin
                    if (grant_write_event_r) begin
                    end else begin
                        bank_rd_txn_r <=
                            count_inc(bank_rd_txn_r, rd_txn_carry_r[stat_idx]);
                        bank_rd_beat_r <=
                            sat_add(bank_rd_beat_r, {27'b0, grant_beats_event_r});
                    end
                end
            end
        end
    end
    always @(posedge clk_i or negedge rst_mem_stat_n_i[stat_idx*3+1]) begin
        if (!rst_mem_stat_n_i[stat_idx*3+1]) begin
            bank_wr_txn_r <= 32'b0;
            bank_wr_beat_r <= 32'b0;
            bank_wr_txn_snapshot_r <= 32'b0;
            bank_wr_beat_snapshot_r <= 32'b0;
        end else begin
            if (snapshot_cmd_w[stat_idx]) begin
                bank_wr_txn_snapshot_r <= bank_wr_txn_r;
                bank_wr_beat_snapshot_r <= bank_wr_beat_r;
            end
            if (clear_group_w[stat_idx*3 + 1]) begin
                bank_wr_txn_r <= 32'b0;
                bank_wr_beat_r <= 32'b0;
            end else begin
                if (grant_event_r && grant_port_event_r == stat_idx[2:0]) begin
                    if (grant_write_event_r) begin
                        bank_wr_txn_r <=
                            count_inc(bank_wr_txn_r, wr_txn_carry_r[stat_idx]);
                        bank_wr_beat_r <=
                            sat_add(bank_wr_beat_r, {27'b0, grant_beats_event_r});
                    end
                end
            end
        end
    end
    always @(posedge clk_i or negedge rst_mem_stat_n_i[stat_idx*3+2]) begin
        if (!rst_mem_stat_n_i[stat_idx*3+2]) begin
            bank_wait_max_r <= 16'b0;
            bank_wait_sum_r <= 32'b0;
            bank_urg_cnt_r <= 32'b0;
            bank_max_snapshot_r <= 16'b0;
            bank_sum_snapshot_r <= 32'b0;
            bank_urg_snapshot_r <= 32'b0;
        end else begin
            if (snapshot_cmd_w[stat_idx]) begin
                bank_max_snapshot_r <= bank_wait_max_r;
                bank_sum_snapshot_r <= bank_wait_sum_r;
                bank_urg_snapshot_r <= bank_urg_cnt_r;
            end
            if (clear_group_w[stat_idx*3 + 2]) begin
                bank_wait_max_r <= 16'b0;
                bank_wait_sum_r <= 32'b0;
                bank_urg_cnt_r <= 32'b0;
            end else begin
                if (grant_event_r && grant_port_event_r == stat_idx[2:0]) begin
                    bank_wait_sum_r <=
                        sat_add(bank_wait_sum_r, {16'b0, grant_wait_event_r});
                    if (grant_wait_event_r > bank_wait_max_r) begin
                        bank_wait_max_r <= grant_wait_event_r;
                    end
                    if (grant_urgent_event_r) begin
                        bank_urg_cnt_r <=
                            count_inc(bank_urg_cnt_r, urg_cnt_carry_r[stat_idx]);
                    end
                end
            end
        end
    end
        end
    endgenerate
    always @(posedge clk_i or negedge rst_n_i[1]) begin
        if (!rst_n_i[1]) begin
            grant_event_r <= 1'b0;
            dir_switch_event_r <= 1'b0;
            ds_busy_event_r <= 1'b0;
            window_event_r <= 1'b0;
        end else begin
            grant_event_r <= grant_i;
            dir_switch_event_r <= dir_switch_i;
            ds_busy_event_r <= ds_busy_i;
            window_event_r <= 1'b1;
        end
    end
    always @(posedge clk_i) begin
        grant_write_event_r <= grant_write_i;
        grant_port_event_r <= grant_port_i;
        grant_beats_event_r <= grant_beats_i;
        grant_wait_event_r <= grant_wait_i;
        grant_urgent_event_r <= grant_urgent_i;
    end
    // Keep one command register per counter bank through synthesis merging.
    genvar bank;
    generate
        for (bank = 0; bank < 8; bank = bank + 1) begin : g_stat_command
            reg snapshot_r /* synthesis syn_preserve=1 */;
            reg clear_r /* synthesis syn_preserve=1 */;
            reg clear1_r /* synthesis syn_preserve=1 */;
            reg clear2_r /* synthesis syn_preserve=1 */;
            assign clear_group_w[bank*3+1] = clear1_r;
            assign clear_group_w[bank*3+2] = clear2_r;
            assign snapshot_cmd_w[bank] = snapshot_r;
            if (bank < 7) begin : g_port_clear
                assign clear_cmd_w[bank] = clear_group_w[bank*3];
            end
            assign clear_group_w[bank*3] = clear_r;
            always @(posedge clk_i or negedge rst_n_i[2]) begin
                if (!rst_n_i[2]) begin
                    snapshot_r <= 1'b0;
                    clear_r <= 1'b0;
                    clear1_r <= 1'b0;
                    clear2_r <= 1'b0;
                end else begin
                    snapshot_r <= snapshot_w;
                    clear_r <= clear_w;
                    clear1_r <= clear_w;
                    clear2_r <= clear_w;
                end
            end
        end
    endgenerate



endmodule
