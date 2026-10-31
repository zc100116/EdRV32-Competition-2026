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
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,
    input wire [6:0] rst_mem_stat_n_i,

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
    wire [7:0] clear_cmd_w;
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

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            dir_switch_carry_r <= 4'b0;
            ds_busy_carry_r <= 4'b0;
            window_cyc_carry_r <= 4'b0;
        end else begin
            dir_switch_carry_r <= clear_cmd_w[7] ? 4'b0 :
                count_carry(dir_switch_r, dir_switch_event_r, dir_switch_carry_r[3]);
            ds_busy_carry_r <= clear_cmd_w[7] ? 4'b0 :
                count_carry(ds_busy_r, ds_busy_event_r, ds_busy_carry_r[3]);
            window_cyc_carry_r <= clear_cmd_w[7] ? 4'b0 :
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
            always @(posedge clk_i or negedge rst_mem_stat_n_i[carry_idx]) begin
                if (!rst_mem_stat_n_i[carry_idx]) begin
                    bank_rd_txn_carry_r <= 4'b0;
                    bank_wr_txn_carry_r <= 4'b0;
                    bank_urg_cnt_carry_r <= 4'b0;
                end else begin
                    bank_rd_txn_carry_r <= clear_cmd_w[carry_idx] ? 4'b0 :
                        count_carry(rd_txn_r[carry_idx],
                            grant_event_r && grant_port_event_r == carry_idx[2:0] &&
                            !grant_write_event_r,
                            bank_rd_txn_carry_r[3]);
                    bank_wr_txn_carry_r <= clear_cmd_w[carry_idx] ? 4'b0 :
                        count_carry(wr_txn_r[carry_idx],
                            grant_event_r && grant_port_event_r == carry_idx[2:0] &&
                            grant_write_event_r,
                            bank_wr_txn_carry_r[3]);
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
    always @(*) begin
        apb_prdata_o = 32'b0;
        case (apb_paddr_r)
            12'h000: apb_prdata_o = 32'h0008_0001;
            12'h008: apb_prdata_o = {29'b0, irq_stat_r, !busy_i, busy_i};
            12'h00c: apb_prdata_o = {30'b0, irq_en_r, 1'b0};
            12'h010: apb_prdata_o = {30'b0, irq_stat_r, 1'b0};
            12'h014: apb_prdata_o = {29'b0, err_type_r};
            12'h100: apb_prdata_o = {28'b0, outst_total_o};
            12'h104: apb_prdata_o = {24'b0, urg_max_o};
            12'h108: apb_prdata_o = {16'b0, starve_cyc_o};
            12'h10c: apb_prdata_o = {24'b0, dir_batch_o};
            12'h120: apb_prdata_o = {29'b0, err_port_r};
            12'h124: apb_prdata_o = err_addr_r;
            12'h128: apb_prdata_o = {29'b0, err_type_r};
            12'h200: apb_prdata_o = {28'b0, outst_rd_r[0]};
            12'h204: apb_prdata_o = {28'b0, outst_wr_r[0]};
            12'h208: apb_prdata_o = {28'b0, weight_r[0]};
            12'h20c: apb_prdata_o = {23'b0, rate_r[0]};
            12'h220: apb_prdata_o = {28'b0, outst_rd_r[1]};
            12'h224: apb_prdata_o = {28'b0, outst_wr_r[1]};
            12'h228: apb_prdata_o = {28'b0, weight_r[1]};
            12'h22c: apb_prdata_o = {23'b0, rate_r[1]};
            12'h240: apb_prdata_o = {28'b0, outst_rd_r[2]};
            12'h244: apb_prdata_o = {28'b0, outst_wr_r[2]};
            12'h248: apb_prdata_o = {28'b0, weight_r[2]};
            12'h24c: apb_prdata_o = {23'b0, rate_r[2]};
            12'h260: apb_prdata_o = {28'b0, outst_rd_r[3]};
            12'h264: apb_prdata_o = {28'b0, outst_wr_r[3]};
            12'h268: apb_prdata_o = {28'b0, weight_r[3]};
            12'h26c: apb_prdata_o = {23'b0, rate_r[3]};
            12'h280: apb_prdata_o = {28'b0, outst_rd_r[4]};
            12'h284: apb_prdata_o = {28'b0, outst_wr_r[4]};
            12'h288: apb_prdata_o = {28'b0, weight_r[4]};
            12'h28c: apb_prdata_o = {23'b0, rate_r[4]};
            12'h2a0: apb_prdata_o = {28'b0, outst_rd_r[5]};
            12'h2a4: apb_prdata_o = {28'b0, outst_wr_r[5]};
            12'h2a8: apb_prdata_o = {28'b0, weight_r[5]};
            12'h2ac: apb_prdata_o = {23'b0, rate_r[5]};
            12'h2c0: apb_prdata_o = {28'b0, outst_rd_r[6]};
            12'h2c4: apb_prdata_o = {28'b0, outst_wr_r[6]};
            12'h2c8: apb_prdata_o = {28'b0, weight_r[6]};
            12'h2cc: apb_prdata_o = {23'b0, rate_r[6]};
            12'h400: apb_prdata_o = rd_txn_snapshot_r[0];
            12'h414: apb_prdata_o = wr_txn_snapshot_r[0];
            12'h404: apb_prdata_o = rd_beat_snapshot_r[0];
            12'h418: apb_prdata_o = wr_beat_snapshot_r[0];
            12'h408: apb_prdata_o = {16'b0, max_snapshot_r[0]};
            12'h40c: apb_prdata_o = sum_snapshot_r[0];
            12'h410: apb_prdata_o = urg_snapshot_r[0];
            12'h420: apb_prdata_o = rd_txn_snapshot_r[1];
            12'h434: apb_prdata_o = wr_txn_snapshot_r[1];
            12'h424: apb_prdata_o = rd_beat_snapshot_r[1];
            12'h438: apb_prdata_o = wr_beat_snapshot_r[1];
            12'h428: apb_prdata_o = {16'b0, max_snapshot_r[1]};
            12'h42c: apb_prdata_o = sum_snapshot_r[1];
            12'h430: apb_prdata_o = urg_snapshot_r[1];
            12'h440: apb_prdata_o = rd_txn_snapshot_r[2];
            12'h454: apb_prdata_o = wr_txn_snapshot_r[2];
            12'h444: apb_prdata_o = rd_beat_snapshot_r[2];
            12'h458: apb_prdata_o = wr_beat_snapshot_r[2];
            12'h448: apb_prdata_o = {16'b0, max_snapshot_r[2]};
            12'h44c: apb_prdata_o = sum_snapshot_r[2];
            12'h450: apb_prdata_o = urg_snapshot_r[2];
            12'h460: apb_prdata_o = rd_txn_snapshot_r[3];
            12'h474: apb_prdata_o = wr_txn_snapshot_r[3];
            12'h464: apb_prdata_o = rd_beat_snapshot_r[3];
            12'h478: apb_prdata_o = wr_beat_snapshot_r[3];
            12'h468: apb_prdata_o = {16'b0, max_snapshot_r[3]};
            12'h46c: apb_prdata_o = sum_snapshot_r[3];
            12'h470: apb_prdata_o = urg_snapshot_r[3];
            12'h480: apb_prdata_o = rd_txn_snapshot_r[4];
            12'h494: apb_prdata_o = wr_txn_snapshot_r[4];
            12'h484: apb_prdata_o = rd_beat_snapshot_r[4];
            12'h498: apb_prdata_o = wr_beat_snapshot_r[4];
            12'h488: apb_prdata_o = {16'b0, max_snapshot_r[4]};
            12'h48c: apb_prdata_o = sum_snapshot_r[4];
            12'h490: apb_prdata_o = urg_snapshot_r[4];
            12'h4a0: apb_prdata_o = rd_txn_snapshot_r[5];
            12'h4b4: apb_prdata_o = wr_txn_snapshot_r[5];
            12'h4a4: apb_prdata_o = rd_beat_snapshot_r[5];
            12'h4b8: apb_prdata_o = wr_beat_snapshot_r[5];
            12'h4a8: apb_prdata_o = {16'b0, max_snapshot_r[5]};
            12'h4ac: apb_prdata_o = sum_snapshot_r[5];
            12'h4b0: apb_prdata_o = urg_snapshot_r[5];
            12'h4c0: apb_prdata_o = rd_txn_snapshot_r[6];
            12'h4d4: apb_prdata_o = wr_txn_snapshot_r[6];
            12'h4c4: apb_prdata_o = rd_beat_snapshot_r[6];
            12'h4d8: apb_prdata_o = wr_beat_snapshot_r[6];
            12'h4c8: apb_prdata_o = {16'b0, max_snapshot_r[6]};
            12'h4cc: apb_prdata_o = sum_snapshot_r[6];
            12'h4d0: apb_prdata_o = urg_snapshot_r[6];
            12'h500: apb_prdata_o = dir_snapshot_r;
            12'h504: apb_prdata_o = busy_snapshot_r;
            12'h508: apb_prdata_o = window_snapshot_r;
            default: begin end
        endcase
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
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

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            dir_switch_r <= 32'b0;
            ds_busy_r <= 32'b0;
            window_cyc_r <= 32'b0;
            dir_snapshot_r <= 32'b0;
            busy_snapshot_r <= 32'b0;
            window_snapshot_r <= 32'b0;
        end else begin
            if (snapshot_cmd_w[7]) begin
                dir_snapshot_r <= dir_switch_r;
                busy_snapshot_r <= ds_busy_r;
                window_snapshot_r <= window_cyc_r;
            end
            if (clear_cmd_w[7]) begin
                dir_switch_r <= 32'b0;
                ds_busy_r <= 32'b0;
                window_cyc_r <= 32'b0;
            end else begin
                if (window_event_r)
                    window_cyc_r <= count_inc(window_cyc_r, window_cyc_carry_r);
                if (ds_busy_event_r)
                    ds_busy_r <= count_inc(ds_busy_r, ds_busy_carry_r);
                if (dir_switch_event_r)
                    dir_switch_r <= count_inc(dir_switch_r, dir_switch_carry_r);
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
            always @(posedge clk_i or negedge rst_mem_stat_n_i[stat_idx]) begin
                if (!rst_mem_stat_n_i[stat_idx]) begin
                    bank_rd_txn_r <= 32'b0;
                    bank_wr_txn_r <= 32'b0;
                    bank_rd_beat_r <= 32'b0;
                    bank_wr_beat_r <= 32'b0;
                    bank_wait_max_r <= 16'b0;
                    bank_wait_sum_r <= 32'b0;
                    bank_urg_cnt_r <= 32'b0;
                    bank_rd_txn_snapshot_r <= 32'b0;
                    bank_wr_txn_snapshot_r <= 32'b0;
                    bank_rd_beat_snapshot_r <= 32'b0;
                    bank_wr_beat_snapshot_r <= 32'b0;
                    bank_max_snapshot_r <= 16'b0;
                    bank_sum_snapshot_r <= 32'b0;
                    bank_urg_snapshot_r <= 32'b0;
                end else begin
                    if (snapshot_cmd_w[stat_idx]) begin
                        bank_rd_txn_snapshot_r <= bank_rd_txn_r;
                        bank_wr_txn_snapshot_r <= bank_wr_txn_r;
                        bank_rd_beat_snapshot_r <= bank_rd_beat_r;
                        bank_wr_beat_snapshot_r <= bank_wr_beat_r;
                        bank_max_snapshot_r <= bank_wait_max_r;
                        bank_sum_snapshot_r <= bank_wait_sum_r;
                        bank_urg_snapshot_r <= bank_urg_cnt_r;
                    end
                    if (clear_cmd_w[stat_idx]) begin
                        bank_rd_txn_r <= 32'b0;
                        bank_wr_txn_r <= 32'b0;
                        bank_rd_beat_r <= 32'b0;
                        bank_wr_beat_r <= 32'b0;
                        bank_wait_max_r <= 16'b0;
                        bank_wait_sum_r <= 32'b0;
                        bank_urg_cnt_r <= 32'b0;
                    end else begin
                        if (grant_event_r && grant_port_event_r == stat_idx[2:0]) begin
                            if (grant_write_event_r) begin
                                bank_wr_txn_r <=
                                count_inc(bank_wr_txn_r, wr_txn_carry_r[stat_idx]);
                                bank_wr_beat_r <=
                                    sat_add(bank_wr_beat_r, {27'b0, grant_beats_event_r});
                            end else begin
                                bank_rd_txn_r <=
                                count_inc(bank_rd_txn_r, rd_txn_carry_r[stat_idx]);
                                bank_rd_beat_r <=
                                    sat_add(bank_rd_beat_r, {27'b0, grant_beats_event_r});
                            end
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
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
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
            assign snapshot_cmd_w[bank] = snapshot_r;
            assign clear_cmd_w[bank] = clear_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    snapshot_r <= 1'b0;
                    clear_r <= 1'b0;
                end else begin
                    snapshot_r <= snapshot_w;
                    clear_r <= clear_w;
                end
            end
        end
    endgenerate
endmodule
