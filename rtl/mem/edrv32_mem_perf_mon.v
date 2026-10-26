// File: edrv32_mem_perf_mon.v
// Spec: mem-subsys-spec 2.3, 4.2, 5.4, 6; edrv32-soc-spec 7.1
// Description: Command traffic generator, pattern checker and latency measurement.
//              M-R3 confirmed: ratio accumulator; LFSR x^32+x^22+x^2+x+1, zero holds.
//              START ignores ENABLE; idle SOFT_RST; ABORT drains without DONE.
//              Unused common registers read zero; software keeps config stable when BUSY.
//              M-R3 confirmed: random block = (LFSR[31:16] * (SIZE/512)) >> 16.
// Clock: clk_i (clk_mem).
module edrv32_mem_perf_mon (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // APB4 control registers.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output reg [31:0] apb_prdata_o,
    output wire apb_pslverr_o,

    // Downstream AXI256 master, local ID zero.
    output wire axi_awid_o,
    output wire [31:0] axi_awaddr_o,
    output wire [3:0] axi_awlen_o,
    output wire axi_awvalid_o,
    input wire axi_awready_i,
    output wire [255:0] axi_wdata_o,
    output wire [31:0] axi_wstrb_o,
    output wire axi_wlast_o,
    output wire axi_wvalid_o,
    input wire axi_wready_i,
    input wire axi_bid_i,
    input wire [1:0] axi_bresp_i,
    input wire axi_bvalid_i,
    output wire axi_bready_o,
    output wire axi_arid_o,
    output wire [31:0] axi_araddr_o,
    output wire [3:0] axi_arlen_o,
    output wire axi_arvalid_o,
    input wire axi_arready_i,
    input wire axi_rid_i,
    input wire [255:0] axi_rdata_i,
    input wire [1:0] axi_rresp_i,
    input wire axi_rlast_i,
    input wire axi_rvalid_i,
    output wire axi_rready_o
);
    reg [31:0] mode_r;
    reg [31:0] base_r;
    reg [31:0] size_r;
    reg [31:0] burst_len_r;
    reg [31:0] addr_mode_r;
    reg [31:0] rw_ratio_r;
    reg [31:0] txn_count_r;
    reg [31:0] outstanding_r;
    reg [31:0] seed_r;
    reg [31:0] check_en_r;
    reg [31:0] hist_width_r;
    reg enable_r;
    reg [31:0] irq_en_r;
    reg [1:0] irq_stat_r;
    reg [31:0] err_code_r;
    reg [31:0] done_count_r;
    reg busy_r;
    reg abort_r;
    reg cmd_valid_r;
    reg cmd_read_r;
    reg [31:0] cmd_addr_r;
    reg [3:0] cmd_len_r;
    reg [31:0] launched_r;
    reg [31:0] seq_offset_r;
    reg [31:0] lfsr_r;
    reg [4:0] ratio_r;
    reg [2:0] rd_count_r;
    reg [2:0] wr_count_r;
    reg [2:0] w_count_r;
    reg [1:0] rd_head_r;
    reg [1:0] rd_tail_r;
    reg [1:0] wr_head_r;
    reg [1:0] wr_tail_r;
    reg [3:0] rd_beat_r;
    reg [3:0] wr_beat_r;
    reg [31:0] rd_addr_r [0:3];
    reg [31:0] rd_age_r [0:3];
    reg [3:0] rd_timing_r;
    reg [31:0] wr_addr_r [0:3];
    reg [3:0] wr_len_r [0:3];
    reg [31:0] txn_done_r;
    reg [31:0] beats_r;
    reg [31:0] cycles_r;
    reg [31:0] lat_min_r;
    reg [31:0] lat_max_r;
    reg [31:0] lat_sum_r;
    reg [31:0] read_cnt_r;
    reg [31:0] err_beats_r;
    reg [31:0] first_err_addr_r;
    reg [31:0] hist_r [0:15];
    wire apb_write_w;
    wire [31:0] write_mask_w;
    wire start_w;
    wire abort_w;
    wire soft_reset_w;
    wire invalid_w;
    wire ar_fire_w;
    wire aw_fire_w;
    wire r_fire_w;
    wire b_fire_w;
    wire w_fire_w;
    wire r_last_w;
    wire w_last_w;
    wire cmd_fire_w;
    wire launch_w;
    wire next_read_w;
    wire [32:0] ratio_sum_w;
    wire [31:0] next_addr_w;
    wire [31:0] offset_w;
    wire [31:0] region_beats_w;
    wire [7:0] page_beats_w;
    reg [31:0] burst_beats_w;
    wire [31:0] wr_byte_addr_w;
    wire [31:0] rd_byte_addr_w;
    wire [31:0] latency_w;
    wire [38:0] random_scaled_w;
    wire [31:0] lfsr_next_w;
    wire finished_w;
    wire check_error_w;
    wire unused_w;
    reg [255:0] expected_w;
    reg [3:0] hist_idx_w;
    reg [35:0] hist_limit_w;
    integer word_idx_w;
    integer hist_loop_w;
    integer reset_idx_r;

    function [31:0] sat_add;
        input [31:0] value_i;
        input [31:0] increment_i;
        begin
            if (32'hffff_ffff - value_i < increment_i)
                sat_add = 32'hffff_ffff;
            else
                sat_add = value_i + increment_i;
        end
    endfunction

    assign unused_w = ^{axi_bid_i, axi_bresp_i, axi_rid_i, axi_rresp_i, random_scaled_w[15:0]};
    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    assign apb_write_w = apb_psel_i && apb_penable_i && apb_pwrite_i;
    assign write_mask_w = {{8{apb_pstrb_i[3]}}, {8{apb_pstrb_i[2]}},
        {8{apb_pstrb_i[1]}}, {8{apb_pstrb_i[0]}}};
    assign start_w = apb_write_w && apb_paddr_i == 12'h004 &&
        apb_pstrb_i[0] && apb_pwdata_i[1] && !busy_r;
    assign abort_w = apb_write_w && apb_paddr_i == 12'h004 &&
        apb_pstrb_i[0] && apb_pwdata_i[2];
    assign soft_reset_w = apb_write_w && apb_paddr_i == 12'h004 &&
        apb_pstrb_i[0] && apb_pwdata_i[3] && !busy_r;
    // spec 4.2: exactly the six enumerated illegal configuration conditions.
    assign invalid_w = burst_len_r == 0 || burst_len_r > 16 ||
        outstanding_r == 0 || outstanding_r > 4 || size_r == 0 ||
        txn_count_r == 0 || hist_width_r == 0;
    assign ar_fire_w = axi_arvalid_o && axi_arready_i;
    assign aw_fire_w = axi_awvalid_o && axi_awready_i;
    assign r_fire_w = axi_rvalid_i && axi_rready_o;
    assign b_fire_w = axi_bvalid_i && axi_bready_o;
    assign w_fire_w = axi_wvalid_o && axi_wready_i;
    assign r_last_w = r_fire_w && axi_rlast_i;
    assign w_last_w = w_fire_w && axi_wlast_o;
    assign cmd_fire_w = ar_fire_w || aw_fire_w;
    assign ratio_sum_w = {28'b0, ratio_r} + {1'b0, rw_ratio_r};
    assign next_read_w = mode_r == 0 || (mode_r == 2 && ratio_sum_w >= 16);
    // A pending address counts toward the next launch's reservation.
    assign launch_w = busy_r && !abort_r && !abort_w && launched_r < txn_count_r &&
        (!cmd_valid_r || cmd_fire_w) &&
        (next_read_w ? ({29'b0, rd_count_r} + {31'b0, ar_fire_w} < outstanding_r) :
        ({29'b0, wr_count_r} + {31'b0, aw_fire_w} < outstanding_r));
    assign random_scaled_w = lfsr_r[31:16] * size_r[31:9];
    assign offset_w = addr_mode_r == 0 ? seq_offset_r : {random_scaled_w[38:16], 9'b0};
    assign next_addr_w = base_r + offset_w;
    assign region_beats_w = (size_r - offset_w) >> 5;
    assign page_beats_w = 8'd128 - {1'b0, next_addr_w[11:5]};
    always @(*) begin
        burst_beats_w = burst_len_r;
        if (burst_beats_w > {24'b0, page_beats_w})
            burst_beats_w = {24'b0, page_beats_w};
        if (burst_beats_w > region_beats_w)
            burst_beats_w = region_beats_w;
    end
    assign lfsr_next_w = {lfsr_r[30:0],
        lfsr_r[31] ^ lfsr_r[21] ^ lfsr_r[1] ^ lfsr_r[0]};
    assign wr_byte_addr_w = wr_addr_r[wr_head_r] + {23'b0, wr_beat_r, 5'b0};
    assign rd_byte_addr_w = rd_addr_r[rd_head_r] + {23'b0, rd_beat_r, 5'b0};
    assign latency_w = sat_add(rd_age_r[rd_head_r], 32'd1);
    assign finished_w = busy_r && !cmd_valid_r && rd_count_r == 0 && wr_count_r == 0 &&
        (abort_r || launched_r == txn_count_r);
    assign check_error_w = r_fire_w && (check_en_r != 0) && axi_rdata_i != expected_w;

    assign axi_awid_o = 1'b0;
    assign axi_awaddr_o = cmd_addr_r;
    assign axi_awlen_o = cmd_len_r;
    assign axi_awvalid_o = rst_n_i && cmd_valid_r && !cmd_read_r;
    assign axi_arid_o = 1'b0;
    assign axi_araddr_o = cmd_addr_r;
    assign axi_arlen_o = cmd_len_r;
    assign axi_arvalid_o = rst_n_i && cmd_valid_r && cmd_read_r;
    assign axi_wstrb_o = 32'hffff_ffff;
    assign axi_wvalid_o = rst_n_i && w_count_r != 0;
    assign axi_wlast_o = wr_beat_r == wr_len_r[wr_head_r];
    assign axi_bready_o = rst_n_i;
    assign axi_rready_o = rst_n_i;
    // Read ages remain accurate after the public CYCLES counter saturates.
    genvar age_slot;
    generate
        for (age_slot = 0; age_slot < 4; age_slot = age_slot + 1) begin : g_read_age
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    rd_timing_r[age_slot] <= 1'b0;
                else if (ar_fire_w && rd_tail_r == age_slot)
                    rd_timing_r[age_slot] <= 1'b1;
                else if (r_fire_w && rd_beat_r == 0 && rd_head_r == age_slot)
                    rd_timing_r[age_slot] <= 1'b0;
            end
            always @(posedge clk_i) begin
                if (ar_fire_w && rd_tail_r == age_slot)
                    rd_age_r[age_slot] <= 32'b0;
                else if (rd_timing_r[age_slot])
                    rd_age_r[age_slot] <= sat_add(rd_age_r[age_slot], 32'd1);
            end
        end
    endgenerate
    genvar lane;
    generate
        for (lane = 0; lane < 8; lane = lane + 1) begin : g_pattern
            assign axi_wdata_o[lane*32 +: 32] =
                (wr_byte_addr_w + lane*4) ^ seed_r;
        end
    endgenerate
    always @(*) begin
        expected_w = 256'b0;
        for (word_idx_w = 0; word_idx_w < 8; word_idx_w = word_idx_w + 1)
            expected_w[word_idx_w*32 +: 32] = (rd_byte_addr_w + word_idx_w*4) ^ seed_r;
        hist_idx_w = 4'b0;
        hist_limit_w = {4'b0, hist_width_r};
        for (hist_loop_w = 1; hist_loop_w < 16; hist_loop_w = hist_loop_w + 1) begin
            if ({4'b0, latency_w} >= hist_limit_w)
                hist_idx_w = hist_loop_w[3:0];
            hist_limit_w = hist_limit_w + {4'b0, hist_width_r};
        end
    end

    // Configuration is byte writable; software leaves it stable while BUSY.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            mode_r <= 32'd0;
            base_r <= 32'd0;
            size_r <= 32'd4096;
            burst_len_r <= 32'd16;
            addr_mode_r <= 32'd0;
            rw_ratio_r <= 32'd8;
            txn_count_r <= 32'd0;
            outstanding_r <= 32'd4;
            seed_r <= 32'd0;
            check_en_r <= 32'd0;
            hist_width_r <= 32'd16;
            enable_r <= 1'b0;
            irq_en_r <= 32'b0;
        end else if (soft_reset_w) begin
            mode_r <= 32'd0;
            base_r <= 32'd0;
            size_r <= 32'd4096;
            burst_len_r <= 32'd16;
            addr_mode_r <= 32'd0;
            rw_ratio_r <= 32'd8;
            txn_count_r <= 32'd0;
            outstanding_r <= 32'd4;
            seed_r <= 32'd0;
            check_en_r <= 32'd0;
            hist_width_r <= 32'd16;
            enable_r <= 1'b0;
            irq_en_r <= 32'b0;
        end else if (apb_write_w) begin
            case (apb_paddr_i)
                12'h004: if (apb_pstrb_i[0]) enable_r <= apb_pwdata_i[0];
                12'h00c: irq_en_r <= (irq_en_r & ~write_mask_w) |
                    (apb_pwdata_i & write_mask_w);
                12'h100: mode_r <= ((mode_r & ~write_mask_w) |
                    (apb_pwdata_i & write_mask_w));
                12'h104: base_r <= ((base_r & ~write_mask_w) |
                    (apb_pwdata_i & write_mask_w)) & 32'hffff_f000;
                12'h108: size_r <= ((size_r & ~write_mask_w) |
                    (apb_pwdata_i & write_mask_w)) & 32'hffff_fe00;
                12'h10c: burst_len_r <= ((burst_len_r & ~write_mask_w) |
                    (apb_pwdata_i & write_mask_w));
                12'h110: addr_mode_r <= ((addr_mode_r & ~write_mask_w) |
                    (apb_pwdata_i & write_mask_w));
                12'h114: rw_ratio_r <= ((rw_ratio_r & ~write_mask_w) |
                    (apb_pwdata_i & write_mask_w));
                12'h118: txn_count_r <= ((txn_count_r & ~write_mask_w) |
                    (apb_pwdata_i & write_mask_w));
                12'h11c: outstanding_r <= ((outstanding_r & ~write_mask_w) |
                    (apb_pwdata_i & write_mask_w));
                12'h120: seed_r <= ((seed_r & ~write_mask_w) |
                    (apb_pwdata_i & write_mask_w));
                12'h124: check_en_r <= ((check_en_r & ~write_mask_w) |
                    (apb_pwdata_i & write_mask_w));
                12'h128: hist_width_r <= ((hist_width_r & ~write_mask_w) |
                    (apb_pwdata_i & write_mask_w));
                default: begin end
            endcase
        end
    end

    always @(posedge clk_i) begin
        if (launch_w) begin
            cmd_read_r <= next_read_w;
            cmd_addr_r <= next_addr_w;
            cmd_len_r <= burst_beats_w[3:0] - 1'b1;
        end
        if (ar_fire_w) begin
            rd_addr_r[rd_tail_r] <= cmd_addr_r;
        end
        if (aw_fire_w) begin
            wr_addr_r[wr_tail_r] <= cmd_addr_r;
            wr_len_r[wr_tail_r] <= cmd_len_r;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            cmd_valid_r <= 1'b0;
        end else if (start_w || soft_reset_w) begin
            cmd_valid_r <= 1'b0;
        end else if (launch_w) begin
            cmd_valid_r <= 1'b1;
        end else if (cmd_fire_w) begin
            cmd_valid_r <= 1'b0;
        end
    end

    // Four-entry metadata queues; no AXI data storage is required.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            busy_r <= 1'b0;
            abort_r <= 1'b0;
            launched_r <= 32'b0;
            seq_offset_r <= 32'b0;
            lfsr_r <= 32'b0;
            ratio_r <= 5'b0;
            rd_count_r <= 3'b0;
            wr_count_r <= 3'b0;
            w_count_r <= 3'b0;
            rd_head_r <= 2'b0;
            rd_tail_r <= 2'b0;
            wr_head_r <= 2'b0;
            wr_tail_r <= 2'b0;
            rd_beat_r <= 4'b0;
            wr_beat_r <= 4'b0;
        end else begin
            if (start_w) begin
                busy_r <= !invalid_w;
                abort_r <= 1'b0;
                launched_r <= 32'b0;
                seq_offset_r <= 32'b0;
                lfsr_r <= seed_r;
                ratio_r <= 5'b0;
            end else if (busy_r) begin
                if (abort_w)
                    abort_r <= 1'b1;
                if (finished_w)
                    busy_r <= 1'b0;
                if (launch_w) begin
                    launched_r <= launched_r + 1'b1;
                    ratio_r <= ratio_sum_w[4:0] - (next_read_w ? 5'd16 : 5'd0);
                    if (offset_w + (burst_beats_w << 5) >= size_r)
                        seq_offset_r <= 32'b0;
                    else
                        seq_offset_r <= offset_w + (burst_beats_w << 5);
                    lfsr_r <= lfsr_next_w;
                end
            end
            rd_count_r <= rd_count_r + {2'b0, ar_fire_w} - {2'b0, r_last_w};
            wr_count_r <= wr_count_r + {2'b0, aw_fire_w} - {2'b0, b_fire_w};
            w_count_r <= w_count_r + {2'b0, aw_fire_w} - {2'b0, w_last_w};
            if (ar_fire_w)
                rd_tail_r <= rd_tail_r + 1'b1;
            if (aw_fire_w)
                wr_tail_r <= wr_tail_r + 1'b1;
            if (r_fire_w) begin
                rd_beat_r <= rd_beat_r + 1'b1;
                if (axi_rlast_i) begin
                    rd_beat_r <= 4'b0;
                    rd_head_r <= rd_head_r + 1'b1;
                end
            end
            if (w_fire_w) begin
                wr_beat_r <= wr_beat_r + 1'b1;
                if (axi_wlast_o) begin
                    wr_beat_r <= 4'b0;
                    wr_head_r <= wr_head_r + 1'b1;
                end
            end
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            irq_stat_r <= 2'b0;
            err_code_r <= 32'b0;
            done_count_r <= 32'b0;
        end else if (soft_reset_w) begin
            irq_stat_r <= 2'b0;
            err_code_r <= 32'b0;
            done_count_r <= 32'b0;
        end else begin
            if (apb_write_w && apb_paddr_i == 12'h010 && apb_pstrb_i[0]) begin
                irq_stat_r <= irq_stat_r & ~apb_pwdata_i[1:0];
                if (apb_pwdata_i[1])
                    err_code_r <= 32'b0;
            end
            if (start_w && invalid_w) begin
                irq_stat_r[1] <= 1'b1;
                err_code_r <= 32'd1;
            end
            if (finished_w && !abort_r) begin
                irq_stat_r[0] <= 1'b1;
                done_count_r <= done_count_r + 1'b1;
            end
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            txn_done_r <= 32'b0;
            beats_r <= 32'b0;
            cycles_r <= 32'b0;
            lat_min_r <= 32'hffff_ffff;
            lat_max_r <= 32'b0;
            lat_sum_r <= 32'b0;
            read_cnt_r <= 32'b0;
            err_beats_r <= 32'b0;
            first_err_addr_r <= 32'b0;
            for (reset_idx_r = 0; reset_idx_r < 16; reset_idx_r = reset_idx_r + 1)
                hist_r[reset_idx_r] <= 32'b0;
        end else if (start_w || soft_reset_w) begin
            txn_done_r <= 32'b0;
            beats_r <= 32'b0;
            cycles_r <= 32'b0;
            lat_min_r <= 32'hffff_ffff;
            lat_max_r <= 32'b0;
            lat_sum_r <= 32'b0;
            read_cnt_r <= 32'b0;
            err_beats_r <= 32'b0;
            first_err_addr_r <= 32'b0;
            for (reset_idx_r = 0; reset_idx_r < 16; reset_idx_r = reset_idx_r + 1)
                hist_r[reset_idx_r] <= 32'b0;
        end else begin
            if (busy_r)
                cycles_r <= sat_add(cycles_r, 32'd1);
            txn_done_r <= sat_add(txn_done_r, {31'b0, b_fire_w} + {31'b0, r_last_w});
            beats_r <= sat_add(beats_r, {31'b0, w_fire_w} + {31'b0, r_fire_w});
            if (r_last_w)
                read_cnt_r <= sat_add(read_cnt_r, 32'd1);
            if (r_fire_w && rd_beat_r == 0) begin
                if (latency_w < lat_min_r)
                    lat_min_r <= latency_w;
                if (latency_w > lat_max_r)
                    lat_max_r <= latency_w;
                lat_sum_r <= sat_add(lat_sum_r, latency_w);
                hist_r[hist_idx_w] <= sat_add(hist_r[hist_idx_w], 32'd1);
            end
            if (check_error_w) begin
                err_beats_r <= sat_add(err_beats_r, 32'd1);
                if (err_beats_r == 0)
                    first_err_addr_r <= rd_byte_addr_w;
            end
        end
    end

    always @(*) begin
        apb_prdata_o = 32'b0;
        case (apb_paddr_i)
            12'h000: apb_prdata_o = 32'h0009_0001;
            12'h004: apb_prdata_o = {31'b0, enable_r};
            12'h008: apb_prdata_o = {29'b0, irq_stat_r[1], !busy_r, busy_r};
            12'h00c: apb_prdata_o = irq_en_r;
            12'h010: apb_prdata_o = {30'b0, irq_stat_r};
            12'h014: apb_prdata_o = err_code_r;
            12'h02c: apb_prdata_o = done_count_r;
            12'h100: apb_prdata_o = mode_r;
            12'h104: apb_prdata_o = base_r;
            12'h108: apb_prdata_o = size_r;
            12'h10c: apb_prdata_o = burst_len_r;
            12'h110: apb_prdata_o = addr_mode_r;
            12'h114: apb_prdata_o = rw_ratio_r;
            12'h118: apb_prdata_o = txn_count_r;
            12'h11c: apb_prdata_o = outstanding_r;
            12'h120: apb_prdata_o = seed_r;
            12'h124: apb_prdata_o = check_en_r;
            12'h128: apb_prdata_o = hist_width_r;
            12'h200: apb_prdata_o = txn_done_r;
            12'h204: apb_prdata_o = beats_r;
            12'h208: apb_prdata_o = cycles_r;
            12'h20c: apb_prdata_o = lat_min_r;
            12'h210: apb_prdata_o = lat_max_r;
            12'h214: apb_prdata_o = lat_sum_r;
            12'h218: apb_prdata_o = read_cnt_r;
            12'h21c: apb_prdata_o = err_beats_r;
            12'h220: apb_prdata_o = first_err_addr_r;
            12'h300: apb_prdata_o = hist_r[0];
            12'h304: apb_prdata_o = hist_r[1];
            12'h308: apb_prdata_o = hist_r[2];
            12'h30c: apb_prdata_o = hist_r[3];
            12'h310: apb_prdata_o = hist_r[4];
            12'h314: apb_prdata_o = hist_r[5];
            12'h318: apb_prdata_o = hist_r[6];
            12'h31c: apb_prdata_o = hist_r[7];
            12'h320: apb_prdata_o = hist_r[8];
            12'h324: apb_prdata_o = hist_r[9];
            12'h328: apb_prdata_o = hist_r[10];
            12'h32c: apb_prdata_o = hist_r[11];
            12'h330: apb_prdata_o = hist_r[12];
            12'h334: apb_prdata_o = hist_r[13];
            12'h338: apb_prdata_o = hist_r[14];
            12'h33c: apb_prdata_o = hist_r[15];
            default: begin end
        endcase
    end
endmodule
