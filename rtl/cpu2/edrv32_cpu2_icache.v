// File: edrv32_cpu2_icache.v
// Spec: cpu-v2-spec 3.8, 5.5, 6.4; interface freeze C02/C03.
// Description: Two ordered group contexts retain requests behind a blocking line refill.
// RAM metadata scans invalidate both ways; canceled AXI bursts drain. Clock: clk_sys.
module edrv32_cpu2_icache #(
    parameter ISSUE_WIDTH = 2
) (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Frontend group request and ordered response.
    input wire ic_req_valid_i,
    output wire ic_req_ready_o,
    input wire [31:0] ic_req_addr_i,
    output wire ic_resp_valid_o,
    input wire ic_resp_ready_i,
    output wire [31:0] ic_resp_bank0_way0_instr_o,
    output wire [31:0] ic_resp_bank0_way1_instr_o,
    output wire [31:0] ic_resp_bank1_way0_instr_o,
    output wire [31:0] ic_resp_bank1_way1_instr_o,
    output wire [1:0] ic_resp_bank0_way_hit_o,
    output wire ic_resp_bank0_error_o,
    output wire [1:0] ic_resp_bank1_way_hit_o,
    output wire ic_resp_bank1_error_o,

    // AXI64 read master.
    output wire [3:0] axi_arid_o,
    output wire [31:0] axi_araddr_o,
    output wire [7:0] axi_arlen_o,
    output wire [2:0] axi_arsize_o,
    output wire [1:0] axi_arburst_o,
    output wire axi_arvalid_o,
    input wire axi_arready_i,
    input wire [3:0] axi_rid_i,
    input wire [63:0] axi_rdata_i,
    input wire [1:0] axi_rresp_i,
    input wire axi_rlast_i,
    input wire axi_rvalid_i,
    output wire axi_rready_o,

    // Cancellation and metadata invalidation.
    input wire ic_cancel_i,
    input wire ic_inv_valid_i,
    output wire ic_inv_ready_o,
    output wire ic_inv_done_o,
    output wire ic_miss_event_o
);
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    /* verilator lint_on UNUSEDPARAM */
    localparam ROM_BITS = $clog2(EDRV32_ROM_SIZE);
    localparam SRAM_BITS = $clog2(EDRV32_SRAM_SIZE);
    localparam DDR_BITS = $clog2(EDRV32_DDR_SIZE);
    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_AR = 2'd1;
    localparam [1:0] S_FILL = 2'd2;
    reg [1:0] state_r;
    reg scan_r;
    reg scan_inv_r;
    reg [8:0] scan_idx_r;
    reg inv_done_r;
    reg [1:0] valid_r;
    reg head_r;
    reg tail_r;
    reg [1:0] count_r;
    reg [31:0] addr_r [0:1];
    reg [1:0] done0_r;
    reg [1:0] done1_r;
    reg [1:0] error0_r;
    reg [1:0] error1_r;
    reg [1:0] hit0_r [0:1];
    reg [1:0] hit1_r [0:1];
    reg [31:0] word00_r [0:1];
    reg [31:0] word01_r [0:1];
    reg [31:0] word10_r [0:1];
    reg [31:0] word11_r [0:1];
    reg pipe_valid_r;
    reg pipe_slot_r;
    reg pipe_odd_r;
    reg [31:0] pipe_bank0_addr_r;
    reg [31:0] pipe_bank1_addr_r;
    reg miss_slot_r;
    reg [31:0] miss_addr_r;
    reg miss_cacheable_r;
    reg victim_r;
    reg [1:0] fill_beat_r;
    reg fill_error_r;
    reg fill_invalidated_r;
    reg lru_valid0_r;
    reg lru_valid1_r;
    reg [8:0] lru_set0_r;
    reg [8:0] lru_set1_r;
    reg lru_data0_r;
    reg lru_data1_r;
    wire accept_w;
    wire pop_w;
    wire replay_w;
    wire read_w;
    wire [31:0] read_addr0_w;
    wire [31:0] read_addr1_w;
    wire [31:0] slot_addr1_w;
    wire [31:0] slot_bank0_addr_w;
    wire [31:0] slot_bank1_addr_w;
    wire [31:0] read_bank0_addr_w;
    wire [31:0] read_bank1_addr_w;
    wire miss_bank_w;
    wire pipe_use_w;
    wire pipe_complete_w;
    wire response_pipe_w;
    wire inv_start_w;
    wire fill_last_w;
    wire tag_install_w;
    wire [10:0] fill_addr_w;
    wire [18:0] tag0_w [0:1];
    wire [18:0] tag1_w [0:1];
    wire [31:0] data_w [0:3];
    wire [1:0] hit0_w;
    wire [1:0] hit1_w;
    wire cacheable0_w;
    wire cacheable1_w;
    wire pma_error0_w;
    wire pma_error1_w;
    wire complete0_w;
    wire complete1_w;
    wire replacement0_w;
    wire replacement1_w;
    wire lru0_w;
    wire lru1_w;
    wire unused_w;

    assign ic_req_ready_o = !scan_r && state_r == S_IDLE && count_r < 2 &&
        (!valid_r[head_r] || pipe_valid_r || (done0_r[head_r] && done1_r[head_r]));
    assign accept_w = ic_req_valid_i && ic_req_ready_o;
    assign replay_w = !scan_r && state_r == S_IDLE && !pipe_valid_r &&
        valid_r[head_r] && !(done0_r[head_r] && done1_r[head_r]);
    assign read_w = accept_w || replay_w;
    assign read_addr0_w = replay_w ? addr_r[head_r] : ic_req_addr_i;
    assign read_addr1_w = read_addr0_w + 32'd4;
    assign slot_addr1_w = addr_r[miss_slot_r] + 32'd4;
    assign slot_bank0_addr_w = ISSUE_WIDTH == 2 && addr_r[miss_slot_r][2] ?
        slot_addr1_w : addr_r[miss_slot_r];
    assign slot_bank1_addr_w = ISSUE_WIDTH == 2 && addr_r[miss_slot_r][2] ?
        addr_r[miss_slot_r] : slot_addr1_w;
    assign read_bank0_addr_w = ISSUE_WIDTH == 2 && read_addr0_w[2] ?
        read_addr1_w : read_addr0_w;
    assign read_bank1_addr_w = ISSUE_WIDTH == 2 && read_addr0_w[2] ?
        read_addr0_w : read_addr1_w;
    assign miss_bank_w = ISSUE_WIDTH == 2 && pipe_odd_r ? !complete1_w : complete0_w;
    assign pipe_use_w = pipe_valid_r && state_r == S_IDLE && !scan_r;
    assign cacheable0_w = pipe_bank0_addr_r[31:SRAM_BITS] ==
        EDRV32_SRAM_BASE[31:SRAM_BITS] ||
        pipe_bank0_addr_r[31:DDR_BITS] == EDRV32_DDR_BASE[31:DDR_BITS];
    assign cacheable1_w = pipe_bank1_addr_r[31:SRAM_BITS] ==
        EDRV32_SRAM_BASE[31:SRAM_BITS] ||
        pipe_bank1_addr_r[31:DDR_BITS] == EDRV32_DDR_BASE[31:DDR_BITS];
    assign pma_error0_w = !(cacheable0_w ||
        pipe_bank0_addr_r[31:ROM_BITS] == EDRV32_ROM_BASE[31:ROM_BITS]);
    assign pma_error1_w = !(cacheable1_w ||
        pipe_bank1_addr_r[31:ROM_BITS] == EDRV32_ROM_BASE[31:ROM_BITS]);
    assign hit0_w = {tag0_w[1][18] && tag0_w[1][17:0] == pipe_bank0_addr_r[31:14],
                    tag0_w[0][18] && tag0_w[0][17:0] == pipe_bank0_addr_r[31:14]};
    assign hit1_w = {tag1_w[1][18] && tag1_w[1][17:0] == pipe_bank1_addr_r[31:14],
                    tag1_w[0][18] && tag1_w[0][17:0] == pipe_bank1_addr_r[31:14]};
    assign complete0_w = done0_r[pipe_slot_r] || pma_error0_w ||
        (cacheable0_w && |hit0_w);
    assign complete1_w = done1_r[pipe_slot_r] || pma_error1_w ||
        (cacheable1_w && |hit1_w);
    assign pipe_complete_w = complete0_w && complete1_w;
    assign response_pipe_w = pipe_use_w && pipe_slot_r == head_r;
    assign ic_resp_valid_o = valid_r[head_r] &&
        ((done0_r[head_r] && done1_r[head_r]) || (response_pipe_w && pipe_complete_w));
    assign pop_w = ic_resp_valid_o && ic_resp_ready_i;
    assign ic_resp_bank0_way0_instr_o = response_pipe_w && !done0_r[head_r] ?
        data_w[0] : word00_r[head_r];
    assign ic_resp_bank0_way1_instr_o = response_pipe_w && !done0_r[head_r] ?
        data_w[1] : word01_r[head_r];
    assign ic_resp_bank1_way0_instr_o = response_pipe_w && !done1_r[head_r] ?
        data_w[2] : word10_r[head_r];
    assign ic_resp_bank1_way1_instr_o = response_pipe_w && !done1_r[head_r] ?
        data_w[3] : word11_r[head_r];
    assign ic_resp_bank0_way_hit_o = response_pipe_w && !done0_r[head_r] ?
        hit0_w : hit0_r[head_r];
    assign ic_resp_bank1_way_hit_o = response_pipe_w && !done1_r[head_r] ?
        hit1_w : hit1_r[head_r];
    assign ic_resp_bank0_error_o = response_pipe_w && !done0_r[head_r] ?
        pma_error0_w : error0_r[head_r];
    assign ic_resp_bank1_error_o = response_pipe_w && !done1_r[head_r] ?
        pma_error1_w : error1_r[head_r];
    assign replacement0_w = !tag0_w[0][18] ? 1'b0 : !tag0_w[1][18] ? 1'b1 : lru0_w;
    assign replacement1_w = !tag1_w[0][18] ? 1'b0 : !tag1_w[1][18] ? 1'b1 : lru1_w;
    assign ic_inv_ready_o = !scan_r;
    assign inv_start_w = ic_inv_valid_i && ic_inv_ready_o;
    assign ic_inv_done_o = inv_done_r;
    assign ic_miss_event_o = pipe_use_w && !pipe_complete_w &&
        (miss_bank_w ? cacheable1_w : cacheable0_w);
    assign axi_arid_o = 4'd0;
    assign axi_araddr_o = miss_cacheable_r ? {miss_addr_r[31:5], 5'd0} :
        {miss_addr_r[31:3], 3'd0};
    assign axi_arlen_o = miss_cacheable_r ? 8'd3 : 8'd0;
    assign axi_arsize_o = 3'd3;
    assign axi_arburst_o = 2'b01;
    assign axi_arvalid_o = state_r == S_AR;
    assign axi_rready_o = state_r == S_FILL;
    assign fill_last_w = axi_rvalid_i && axi_rready_o && axi_rlast_i;
    assign tag_install_w = fill_last_w && miss_cacheable_r && !scan_r && !inv_start_w &&
        !fill_invalidated_r && !fill_error_r && axi_rresp_i == 2'b00;
    assign fill_addr_w = {miss_addr_r[13:5], fill_beat_r};
    assign unused_w = ^{axi_rid_i, pipe_odd_r,
        miss_addr_r[2:0], slot_addr1_w[1:0], slot_bank0_addr_w[2:0],
        slot_bank1_addr_w[2:0], pipe_bank0_addr_r[13:0], pipe_bank1_addr_r[13:0],
        read_bank0_addr_w[2:0],
        read_bank1_addr_w[2:0]};
    genvar way;
    genvar bank;
    generate
        for (way = 0; way < 2; way = way + 1) begin : g_way
            localparam WAY = way != 0;
            wire tag_write_w;
            wire [8:0] tag_addr_w;
            wire [18:0] tag_data_w;
            assign tag_write_w = scan_r || (victim_r == WAY &&
                (tag_install_w || (state_r == S_AR && axi_arready_i && miss_cacheable_r)));
            assign tag_addr_w = scan_r ? scan_idx_r : miss_addr_r[13:5];
            assign tag_data_w = {tag_install_w && !scan_r, miss_addr_r[31:14]};
            edrv32_ram_cpu2_cache_tag u_tag0 (
                .clk_i(clk_i),
                .wr_en_i(tag_write_w),
                .wr_addr_i(tag_addr_w),
                .wr_data_i(tag_data_w),
                .rd_en_i(read_w),
                .rd_addr_i(read_bank0_addr_w[13:5]),
                .rd_data_o(tag0_w[way])
            );
            if (ISSUE_WIDTH == 1) begin : g_single
                wire [63:0] data64_w;
                assign tag1_w[way] = tag0_w[way];
                assign data_w[way] = data64_w[31:0];
                assign data_w[2+way] = data64_w[63:32];
                edrv32_ram_cpu2_cache_data64 u_data (
                    .clk_i(clk_i),
                    .wr_en_i(axi_rvalid_i && axi_rready_o && miss_cacheable_r &&
                        victim_r == WAY),
                    .wr_addr_i(fill_addr_w),
                    .wr_data_i(axi_rdata_i),
                    .wr_mask_i(8'hff),
                    .rd_en_i(read_w),
                    .rd_addr_i(read_addr0_w[13:3]),
                    .rd_data_o(data64_w)
                );
            end else begin : g_dual
                wire [31:0] even_w;
                wire [31:0] odd_w;
                wire [10:0] even_addr_w;
                wire [10:0] odd_addr_w;
                assign even_addr_w = read_addr0_w[2] ? read_addr1_w[13:3] : read_addr0_w[13:3];
                assign odd_addr_w = read_addr0_w[2] ? read_addr0_w[13:3] : read_addr1_w[13:3];
                assign data_w[way] = even_w;
                assign data_w[2+way] = odd_w;
                edrv32_ram_cpu2_cache_tag u_tag1 (
                    .clk_i(clk_i),
                    .wr_en_i(tag_write_w),
                    .wr_addr_i(tag_addr_w),
                    .wr_data_i(tag_data_w),
                    .rd_en_i(read_w),
                    .rd_addr_i(read_bank1_addr_w[13:5]),
                    .rd_data_o(tag1_w[way])
                );
                edrv32_ram_cpu2_cache_data u_even (
                    .clk_i(clk_i),
                    .wr_en_i(axi_rvalid_i && axi_rready_o && miss_cacheable_r &&
                        victim_r == WAY),
                    .wr_addr_i(fill_addr_w),
                    .wr_data_i(axi_rdata_i[31:0]),
                    .rd_en_i(read_w),
                    .rd_addr_i(even_addr_w),
                    .rd_data_o(even_w)
                );
                edrv32_ram_cpu2_cache_data u_odd (
                    .clk_i(clk_i),
                    .wr_en_i(axi_rvalid_i && axi_rready_o && miss_cacheable_r &&
                        victim_r == WAY),
                    .wr_addr_i(fill_addr_w),
                    .wr_data_i(axi_rdata_i[63:32]),
                    .rd_en_i(read_w),
                    .rd_addr_i(odd_addr_w),
                    .rd_data_o(odd_w)
                );
            end
        end
        if (ISSUE_WIDTH == 1) begin : g_single_lru
            wire unused_lru1_w;
            assign unused_lru1_w = ^{lru_valid1_r, lru_set1_r, lru_data1_r};
            edrv32_ram_cpu2_cache_lru u_lru (
                .clk_i(clk_i),
                .wr_en_i(scan_r || lru_valid0_r),
                .wr_addr_i(scan_r ? scan_idx_r : lru_set0_r),
                .wr_data_i(scan_r ? 1'b0 : lru_data0_r),
                .rd_en_i(read_w),
                .rd_addr_i(read_bank0_addr_w[13:5]),
                .rd_data_o(lru0_w)
            );
            assign lru1_w = lru0_w;
        end else begin : g_dual_lru
            wire [1:0] bank_data_w;
            assign lru0_w = pipe_bank0_addr_r[5] ? bank_data_w[1] : bank_data_w[0];
            assign lru1_w = pipe_bank1_addr_r[5] ? bank_data_w[1] : bank_data_w[0];
            for (bank = 0; bank < 2; bank = bank + 1) begin : g_bank
                localparam BANK = bank != 0;
                wire update0_w;
                wire update1_w;
                wire [7:0] write_set_w;
                wire [7:0] query_addr_w;
                assign update0_w = lru_valid0_r && lru_set0_r[0] == BANK;
                assign update1_w = lru_valid1_r && lru_set1_r[0] == BANK;
                assign write_set_w = scan_r ? scan_idx_r[8:1] :
                    update0_w ? lru_set0_r[8:1] : lru_set1_r[8:1];
                assign query_addr_w = read_addr0_w[5] == BANK ?
                    read_addr0_w[13:6] : read_addr1_w[13:6];
                edrv32_ram_cpu2_cache_lru u_lru (
                    .clk_i(clk_i),
                    .wr_en_i((scan_r && scan_idx_r[0] == BANK) || update0_w || update1_w),
                    .wr_addr_i({1'b0, write_set_w}),
                    .wr_data_i(scan_r ? 1'b0 : update0_w ? lru_data0_r : lru_data1_r),
                    .rd_en_i(read_w),
                    .rd_addr_i({1'b0, query_addr_w}),
                    .rd_data_o(bank_data_w[bank])
                );
            end
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            scan_r <= 1'b1;
            scan_inv_r <= 1'b0;
            scan_idx_r <= 9'd0;
            inv_done_r <= 1'b0;
            state_r <= S_IDLE;
            valid_r <= 2'd0;
            done0_r <= 2'd0;
            done1_r <= 2'd0;
            error0_r <= 2'd0;
            error1_r <= 2'd0;
            head_r <= 1'b0;
            tail_r <= 1'b0;
            count_r <= 2'd0;
            pipe_valid_r <= 1'b0;
            fill_beat_r <= 2'd0;
            fill_error_r <= 1'b0;
            fill_invalidated_r <= 1'b0;
            lru_valid0_r <= 1'b0;
            lru_valid1_r <= 1'b0;
        end else begin
            inv_done_r <= 1'b0;
            if (scan_r) begin
                scan_idx_r <= scan_idx_r + 9'd1;
                if (scan_idx_r == 9'd511) begin
                    scan_r <= 1'b0;
                    inv_done_r <= scan_inv_r;
                end
            end
            if (inv_start_w) begin
                scan_r <= 1'b1;
                scan_inv_r <= 1'b1;
                scan_idx_r <= 9'd0;
            end
            pipe_valid_r <= read_w;
            lru_valid0_r <= 1'b0;
            lru_valid1_r <= 1'b0;
            if (pipe_use_w) begin
                if (!done0_r[pipe_slot_r]) begin
                    done0_r[pipe_slot_r] <= pma_error0_w || (cacheable0_w && |hit0_w);
                    error0_r[pipe_slot_r] <= pma_error0_w;
                end
                if (!done1_r[pipe_slot_r]) begin
                    done1_r[pipe_slot_r] <= pma_error1_w || (cacheable1_w && |hit1_w);
                    error1_r[pipe_slot_r] <= pma_error1_w;
                end
                lru_valid0_r <= cacheable0_w && |hit0_w;
                lru_valid1_r <= ISSUE_WIDTH == 2 && cacheable1_w && |hit1_w &&
                    pipe_bank0_addr_r[13:5] != pipe_bank1_addr_r[13:5];
                if (!pipe_complete_w) begin
                    state_r <= S_AR;
                    fill_beat_r <= 2'd0;
                    fill_error_r <= 1'b0;
                    fill_invalidated_r <= inv_start_w;
                end
            end
            if (inv_start_w && state_r != S_IDLE)
                fill_invalidated_r <= 1'b1;
            if (pop_w) begin
                valid_r[head_r] <= 1'b0;
                head_r <= !head_r;
            end

            if (accept_w) begin
                valid_r[tail_r] <= 1'b1;
                done0_r[tail_r] <= 1'b0;
                done1_r[tail_r] <= 1'b0;
                error0_r[tail_r] <= 1'b0;
                error1_r[tail_r] <= 1'b0;
                tail_r <= !tail_r;
            end
            if (ic_cancel_i) begin
                valid_r <= 2'd0;
                done0_r <= 2'd0;
                done1_r <= 2'd0;
                pipe_valid_r <= 1'b0;
                head_r <= 1'b0;
                tail_r <= 1'b0;
                count_r <= 2'd0;
            end
            case (state_r)
                S_AR: if (axi_arready_i) state_r <= S_FILL;
                S_FILL: begin
                    if (axi_rvalid_i) begin
                        fill_beat_r <= fill_beat_r + 2'd1;
                        fill_error_r <= fill_error_r || |axi_rresp_i;
                        if (axi_rlast_i) begin
                            state_r <= S_IDLE;
                            // Any word in the failed line reports failure, even a beat seen earlier.
                            if ((miss_cacheable_r && slot_bank0_addr_w[31:5] ==
                                miss_addr_r[31:5]) || (!miss_cacheable_r &&
                                slot_bank0_addr_w[31:3] == miss_addr_r[31:3])) begin
                                done0_r[miss_slot_r] <= 1'b1;
                                error0_r[miss_slot_r] <= fill_error_r || |axi_rresp_i;
                            end
                            if ((miss_cacheable_r && slot_bank1_addr_w[31:5] ==
                                miss_addr_r[31:5]) || (!miss_cacheable_r &&
                                slot_bank1_addr_w[31:3] == miss_addr_r[31:3])) begin
                                done1_r[miss_slot_r] <= 1'b1;
                                error1_r[miss_slot_r] <= fill_error_r || |axi_rresp_i;
                            end
                            lru_valid0_r <= tag_install_w;
                        end
                    end
                end
                default: begin end
            endcase
            begin
            case ({accept_w && !ic_cancel_i, pop_w && !ic_cancel_i})
                2'b10: count_r <= count_r + 2'd1;
                2'b01: count_r <= count_r - 2'd1;
                default: begin end
            endcase
            end
        end
    end
    always @(posedge clk_i) begin
        if (accept_w)
            addr_r[tail_r] <= ic_req_addr_i;
        if (read_w) begin
            pipe_slot_r <= replay_w ? head_r : tail_r;
            pipe_odd_r <= read_addr0_w[2];
            pipe_bank0_addr_r <= read_bank0_addr_w;
            pipe_bank1_addr_r <= read_bank1_addr_w;
        end
        if (pipe_use_w) begin
            if (!done0_r[pipe_slot_r]) begin
                hit0_r[pipe_slot_r] <= hit0_w;
                word00_r[pipe_slot_r] <= data_w[0];
                word01_r[pipe_slot_r] <= data_w[1];
            end
            if (!done1_r[pipe_slot_r]) begin
                hit1_r[pipe_slot_r] <= hit1_w;
                word10_r[pipe_slot_r] <= data_w[2];
                word11_r[pipe_slot_r] <= data_w[3];
            end
            lru_set0_r <= pipe_bank0_addr_r[13:5];
            lru_set1_r <= pipe_bank1_addr_r[13:5];
            lru_data0_r <= !hit0_w[1];
            lru_data1_r <= !hit1_w[1];
            if (!pipe_complete_w) begin
                miss_slot_r <= pipe_slot_r;
                miss_addr_r <= miss_bank_w ? pipe_bank1_addr_r : pipe_bank0_addr_r;
                miss_cacheable_r <= miss_bank_w ? cacheable1_w : cacheable0_w;
                victim_r <= miss_bank_w ? replacement1_w : replacement0_w;
            end
        end
        if (axi_rvalid_i && axi_rready_o) begin
            if ((miss_cacheable_r && slot_bank0_addr_w[31:3] ==
                {miss_addr_r[31:5], fill_beat_r}) ||
                (!miss_cacheable_r && slot_bank0_addr_w[31:3] == miss_addr_r[31:3])) begin
                word00_r[miss_slot_r] <= axi_rdata_i[31:0];
                hit0_r[miss_slot_r] <= 2'b01;
            end
            if ((miss_cacheable_r && slot_bank1_addr_w[31:3] ==
                {miss_addr_r[31:5], fill_beat_r}) ||
                (!miss_cacheable_r && slot_bank1_addr_w[31:3] == miss_addr_r[31:3])) begin
                word10_r[miss_slot_r] <= axi_rdata_i[63:32];
                hit1_r[miss_slot_r] <= 2'b01;
            end
            if (fill_last_w) begin
                lru_set0_r <= miss_addr_r[13:5];
                lru_data0_r <= !victim_r;
            end
        end
    end
endmodule
