// File: edrv32_mem_xbar_regs.v
// Spec: mem-subsys-spec 4.1, 6; edrv32-soc-spec 7.1.
// Description: APB parameters, sticky violation interrupt and atomic statistics snapshots.
// Statistics use downstream AW/AR handshakes. Snapshot captures before the write edge.
// Event counters saturate; simultaneous SNAPSHOT/CLEAR captures before clearing.
// APB writes ignore PSTRB and update complete words (coordinator clarification).
// CTRL and unused common registers read zero; ERR_CODE aliases ERR_TYPE.
// Clock: clk_mem.
module edrv32_mem_xbar_regs (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // APB control interface.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    output wire apb_pready_o,
    output reg [31:0] apb_prdata_o,
    output wire apb_pslverr_o,

    // Scheduler configuration and events.
    output reg [31:0] outst_total_o,
    output reg [31:0] urg_max_o,
    output reg [31:0] starve_cyc_o,
    output reg [31:0] dir_batch_o,
    output wire [223:0] outst_rd_o,
    output wire [223:0] outst_wr_o,
    output wire [223:0] weight_o,
    output wire [223:0] rate_o,
    input wire grant_i,
    input wire [2:0] grant_port_i,
    input wire [4:0] grant_beats_i,
    input wire [31:0] grant_wait_i,
    input wire grant_urgent_i,
    input wire dir_switch_i,
    input wire ds_busy_i,
    input wire busy_i,
    input wire err_valid_i,
    input wire [2:0] err_port_i,
    input wire [31:0] err_addr_i,
    input wire [2:0] err_type_i,

    // Interrupt.
    output wire irq_o
);
    reg [31:0] outst_rd_r [0:6];
    reg [31:0] outst_wr_r [0:6];
    reg [31:0] weight_r [0:6];
    reg [31:0] rate_r [0:6];
    reg irq_en_r;
    reg irq_stat_r;
    reg [2:0] err_port_r;
    reg [31:0] err_addr_r;
    reg [2:0] err_type_r;
    reg [31:0] txn_cnt_r [0:6];
    reg [31:0] beat_cnt_r [0:6];
    reg [31:0] wait_max_r [0:6];
    reg [31:0] wait_sum_r [0:6];
    reg [31:0] urg_cnt_r [0:6];
    reg [31:0] txn_snapshot_r [0:6];
    reg [31:0] beat_snapshot_r [0:6];
    reg [31:0] max_snapshot_r [0:6];
    reg [31:0] sum_snapshot_r [0:6];
    reg [31:0] urg_snapshot_r [0:6];
    reg [31:0] dir_switch_r;
    reg [31:0] ds_busy_r;
    reg [31:0] window_cyc_r;
    reg [31:0] dir_snapshot_r;
    reg [31:0] busy_snapshot_r;
    reg [31:0] window_snapshot_r;
    wire write_w;
    wire snapshot_w;
    wire clear_w;
    wire irq_clear_w;
    integer idx;
    integer read_idx;
    integer stat_idx;
    genvar p;

    function [31:0] sat_add;
        input [31:0] value_i;
        input [31:0] increment_i;
        begin
            sat_add = ({1'b0, value_i} + {1'b0, increment_i}) > 33'h0_ffff_ffff ?
                32'hffff_ffff : value_i + increment_i;
        end
    endfunction

    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_i;
    assign snapshot_w = write_w && apb_paddr_i == 12'h110 &&
                        apb_pwdata_i[0];
    assign clear_w = write_w && apb_paddr_i == 12'h110 &&
                        apb_pwdata_i[1];
    assign irq_clear_w = write_w && apb_paddr_i == 12'h010 &&
                            apb_pwdata_i[1];
    assign irq_o = irq_en_r && irq_stat_r;

    generate
        for (p = 0; p < 7; p = p + 1) begin : g_config
            assign outst_rd_o[p*32 +: 32] = outst_rd_r[p];
            assign outst_wr_o[p*32 +: 32] = outst_wr_r[p];
            assign weight_o[p*32 +: 32] = weight_r[p];
            assign rate_o[p*32 +: 32] = rate_r[p];
        end
    endgenerate

    always @(*) begin
        apb_prdata_o = 32'b0;
        for (read_idx = 0; read_idx < 7; read_idx = read_idx + 1) begin
            if ({20'b0, apb_paddr_i} == 32'h200 + 32*read_idx) begin
                apb_prdata_o = outst_rd_r[read_idx];
            end
            if ({20'b0, apb_paddr_i} == 32'h204 + 32*read_idx) begin
                apb_prdata_o = outst_wr_r[read_idx];
            end
            if ({20'b0, apb_paddr_i} == 32'h208 + 32*read_idx) begin
                apb_prdata_o = weight_r[read_idx];
            end
            if ({20'b0, apb_paddr_i} == 32'h20c + 32*read_idx) begin
                apb_prdata_o = rate_r[read_idx];
            end
            if ({20'b0, apb_paddr_i} == 32'h400 + 32*read_idx) begin
                apb_prdata_o = txn_snapshot_r[read_idx];
            end
            if ({20'b0, apb_paddr_i} == 32'h404 + 32*read_idx) begin
                apb_prdata_o = beat_snapshot_r[read_idx];
            end
            if ({20'b0, apb_paddr_i} == 32'h408 + 32*read_idx) begin
                apb_prdata_o = max_snapshot_r[read_idx];
            end
            if ({20'b0, apb_paddr_i} == 32'h40c + 32*read_idx) begin
                apb_prdata_o = sum_snapshot_r[read_idx];
            end
            if ({20'b0, apb_paddr_i} == 32'h410 + 32*read_idx) begin
                apb_prdata_o = urg_snapshot_r[read_idx];
            end
        end
        case (apb_paddr_i)
            12'h000: apb_prdata_o = 32'h0008_0001;
            12'h008: apb_prdata_o = {29'b0, irq_stat_r, !busy_i, busy_i};
            12'h00c: apb_prdata_o = {30'b0, irq_en_r, 1'b0};
            12'h010: apb_prdata_o = {30'b0, irq_stat_r, 1'b0};
            12'h014: apb_prdata_o = {29'b0, err_type_r};
            12'h100: apb_prdata_o = outst_total_o;
            12'h104: apb_prdata_o = urg_max_o;
            12'h108: apb_prdata_o = starve_cyc_o;
            12'h10c: apb_prdata_o = dir_batch_o;
            12'h120: apb_prdata_o = {29'b0, err_port_r};
            12'h124: apb_prdata_o = err_addr_r;
            12'h128: apb_prdata_o = {29'b0, err_type_r};
            12'h500: apb_prdata_o = dir_snapshot_r;
            12'h504: apb_prdata_o = busy_snapshot_r;
            12'h508: apb_prdata_o = window_snapshot_r;
            default: begin end
        endcase
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            outst_total_o <= 32'd8;
            urg_max_o <= 32'd8;
            starve_cyc_o <= 32'd256;
            dir_batch_o <= 32'd4;
            irq_en_r <= 1'b0;
            irq_stat_r <= 1'b0;
            err_port_r <= 3'b0;
            err_addr_r <= 32'b0;
            err_type_r <= 3'b0;
            for (idx = 0; idx < 7; idx = idx + 1) begin
                outst_rd_r[idx] <= idx == 1 ? 32'd0 :
                                    idx == 2 ? 32'd1 :
                                    idx == 0 || idx == 3 ? 32'd4 : 32'd2;
                outst_wr_r[idx] <= idx == 0 ? 32'd0 :
                                    idx == 2 ? 32'd1 : idx == 1 ? 32'd4 : 32'd2;
                weight_r[idx] <= idx < 2 ? 32'd4 : idx == 2 ? 32'd0 :
                                    idx == 3 ? 32'd3 : idx == 6 ? 32'd1 : 32'd2;
                rate_r[idx] <= idx == 2 ? 32'd26 : idx == 6 ? 32'd13 : 32'd0;
            end
        end else begin
            if (write_w) begin
                for (idx = 0; idx < 7; idx = idx + 1) begin
                    if ({20'b0, apb_paddr_i} == 32'h200 + 32*idx) begin
                        outst_rd_r[idx] <= apb_pwdata_i;
                    end
                    if ({20'b0, apb_paddr_i} == 32'h204 + 32*idx) begin
                        outst_wr_r[idx] <= apb_pwdata_i;
                    end
                    if ({20'b0, apb_paddr_i} == 32'h208 + 32*idx) begin
                        weight_r[idx] <= apb_pwdata_i;
                    end
                    if ({20'b0, apb_paddr_i} == 32'h20c + 32*idx) begin
                        rate_r[idx] <= apb_pwdata_i;
                    end
                end
                case (apb_paddr_i)
                    12'h00c: irq_en_r <= apb_pwdata_i[1];
                    12'h100: outst_total_o <= apb_pwdata_i;
                    12'h104: urg_max_o <= apb_pwdata_i;
                    12'h108: starve_cyc_o <= apb_pwdata_i;
                    12'h10c: dir_batch_o <= apb_pwdata_i;
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
            for (stat_idx = 0; stat_idx < 7; stat_idx = stat_idx + 1) begin
                txn_cnt_r[stat_idx] <= 32'b0;
                beat_cnt_r[stat_idx] <= 32'b0;
                wait_max_r[stat_idx] <= 32'b0;
                wait_sum_r[stat_idx] <= 32'b0;
                urg_cnt_r[stat_idx] <= 32'b0;
                txn_snapshot_r[stat_idx] <= 32'b0;
                beat_snapshot_r[stat_idx] <= 32'b0;
                max_snapshot_r[stat_idx] <= 32'b0;
                sum_snapshot_r[stat_idx] <= 32'b0;
                urg_snapshot_r[stat_idx] <= 32'b0;
            end
        end else begin
            if (snapshot_w) begin
                dir_snapshot_r <= dir_switch_r;
                busy_snapshot_r <= ds_busy_r;
                window_snapshot_r <= window_cyc_r;
                for (stat_idx = 0; stat_idx < 7; stat_idx = stat_idx + 1) begin
                    txn_snapshot_r[stat_idx] <= txn_cnt_r[stat_idx];
                    beat_snapshot_r[stat_idx] <= beat_cnt_r[stat_idx];
                    max_snapshot_r[stat_idx] <= wait_max_r[stat_idx];
                    sum_snapshot_r[stat_idx] <= wait_sum_r[stat_idx];
                    urg_snapshot_r[stat_idx] <= urg_cnt_r[stat_idx];
                end
            end
            if (clear_w) begin
                dir_switch_r <= 32'b0;
                ds_busy_r <= 32'b0;
                window_cyc_r <= 32'b0;
                for (stat_idx = 0; stat_idx < 7; stat_idx = stat_idx + 1) begin
                    txn_cnt_r[stat_idx] <= 32'b0;
                    beat_cnt_r[stat_idx] <= 32'b0;
                    wait_max_r[stat_idx] <= 32'b0;
                    wait_sum_r[stat_idx] <= 32'b0;
                    urg_cnt_r[stat_idx] <= 32'b0;
                end
            end else begin
                window_cyc_r <= sat_add(window_cyc_r, 32'd1);
                if (ds_busy_i) begin
                    ds_busy_r <= sat_add(ds_busy_r, 32'd1);
                end
                if (dir_switch_i) begin
                    dir_switch_r <= sat_add(dir_switch_r, 32'd1);
                end
                if (grant_i) begin
                    txn_cnt_r[grant_port_i] <= sat_add(txn_cnt_r[grant_port_i], 32'd1);
                    beat_cnt_r[grant_port_i] <=
                        sat_add(beat_cnt_r[grant_port_i], {27'b0, grant_beats_i});
                    wait_sum_r[grant_port_i] <=
                        sat_add(wait_sum_r[grant_port_i], grant_wait_i);
                    if (grant_wait_i > wait_max_r[grant_port_i]) begin
                        wait_max_r[grant_port_i] <= grant_wait_i;
                    end
                    if (grant_urgent_i) begin
                        urg_cnt_r[grant_port_i] <= sat_add(urg_cnt_r[grant_port_i], 32'd1);
                    end
                end
            end
        end
    end
endmodule
