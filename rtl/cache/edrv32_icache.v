// File: edrv32_icache.v
// Spec: cache-spec 2, 3.1, 5.1, 6.
// Description: Pipelined instruction lookup and blocking AXI64 refill.
// Organization: 32 KiB, 512 sets, two ways, 32-byte lines, synchronous tag/data RAM.
// Hit lookup is pipelined; an outstanding refill survives a core kill.
// Clock domain: clk_sys.
module edrv32_icache (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,
    input wire [1:0] rst_sys_ivalid0_n_i,
    input wire [1:0] rst_sys_ivalid1_n_i,
    input wire [1:0] rst_sys_ilru_n_i,


    // Core instruction interface.
    input wire ic_req_valid_i,
    input wire [31:0] ic_req_addr_i,
    output wire ic_req_ready_o,
    output wire ic_resp_valid_o,
    output wire [7:0] ic_resp_valid_copy_o,
    output wire [63:0] ic_resp_data_o,
    output wire [43:0] ic_resp_predecode_o,
    output wire ic_resp_err_o,
    input wire ic_kill_i,
    input wire ic_inv_i,
    output wire ic_inv_done_o,

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
    output wire axi_rready_o
);
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_AR = 3'd1;
    localparam [2:0] S_FILL = 3'd2;
    localparam [2:0] S_RETURN = 3'd3;
    localparam [2:0] S_DRAIN = 3'd4;
    reg [2:0] state_r;
    wire [511:0] valid0_r;
    wire [511:0] valid1_r;
    wire [511:0] lru_r;
    reg [31:0] invalidate_bank_r;
    genvar bank;
    genvar metadata_part;
    genvar compare_part;
    reg lookup_valid_r;
    wire [31:0] addr_r;
    reg [31:0] lookup_addr_r;
    reg [31:0] miss_addr_r;
    assign addr_r = state_r == S_IDLE ? lookup_addr_r : miss_addr_r;
    // A miss discovers ownership one cycle after the synchronous lookup launch.
    // Snapshot its address before accepting the speculative successor internally.
    always @(posedge clk_i) begin
        lookup_addr_r <= ic_req_addr_i;
        if (state_r == S_IDLE)
            miss_addr_r <= lookup_addr_r;
    end
    reg cacheable_r;
    reg response_lookup_r;
    reg response_pma_err_r;
    wire lookup_valid0_w;
    wire lookup_valid1_w;
    wire lookup_compare_valid0_w;
    wire lookup_compare_valid1_w;
    wire lookup_lru_w;

    reg [31:0] lookup_bank_r;
    reg [15:0] lookup_slot_r;
    wire [15:0] request_slot_w;
    assign request_slot_w = 16'b1 << ic_req_addr_i[8:5];
    reg [31:0] lookup_valid0_bank_r;
    reg [31:0] lookup_valid1_bank_r;
    reg [31:0] lookup_lru_bank_r;
    (* keep = "true", syn_preserve = 1 *) reg [31:0] lookup_compare_valid0_bank_r;
    (* keep = "true", syn_preserve = 1 *) reg [31:0] lookup_compare_valid1_bank_r;
    // Tag comparison retires into local metadata controls before bank writes.
    reg [31:0] metadata_bank_r;
    reg [15:0] metadata_slot_r;
    reg metadata_victim_r;
    wire replacement_w;
    assign replacement_w = lookup_lru_w;
    always @(posedge clk_i) begin
        metadata_bank_r <= lookup_bank_r;
        metadata_slot_r <= lookup_slot_r;
        metadata_victim_r <= replacement_w;
    end
    reg pma_err_r;
    reg victim_r;
    wire [7:0] victim_copy_w;
    wire [7:0] hit0_copy_w;
    wire [7:0] tag_write_copy_w;
    wire [7:0] lookup_accept_copy_w;
    genvar victim_group;
    generate
        for (victim_group = 0; victim_group < 8;
            victim_group = victim_group + 1) begin : g_victim
            (* keep = "true", syn_preserve = 1 *) reg victim_copy1_r;
            (* keep = "true", syn_preserve = 1 *) reg lookup_valid_copy1_r;
            (* keep = "true", syn_preserve = 1 *) reg [17:0] addr_tag_copy1_r;
            (* keep = "true", syn_preserve = 1 *) reg fill_err_copy1_r;
            (* keep = "true", syn_preserve = 1 *) reg fill_invalidated_copy1_r;
            wire hit1_w_copy;
            (* keep = "true" *) wire [5:0] tag0_half_copy_w;
            (* keep = "true" *) wire [5:0] tag1_half_copy_w;
            (* keep = "true", syn_preserve = 1 *) reg response_lookup_copy1_r;
            (* keep = "true", syn_preserve = 1 *) reg response_pma_err_copy1_r;
            wire lookup_ready_w_copy;
            assign lookup_ready_w_copy = state_r == S_IDLE &&
                (!lookup_valid_copy1_r || pma_err_r ||
                (cacheable_r && (hit0_copy_w[victim_group] || hit1_w_copy)));
            assign lookup_accept_copy_w[victim_group] = ic_req_valid_i && lookup_ready_w_copy;
            for (compare_part = 0; compare_part < 6;
                compare_part = compare_part + 1) begin : g_compare
                assign tag0_half_copy_w[compare_part] =
                    tag0_w[compare_part*3 +: 3] == addr_tag_copy1_r[compare_part*3 +: 3];
                assign tag1_half_copy_w[compare_part] =
                    tag1_w[compare_part*3 +: 3] == addr_tag_copy1_r[compare_part*3 +: 3];
            end
            assign hit0_copy_w[victim_group] = lookup_compare_valid0_w && (&tag0_half_copy_w);
            assign hit1_w_copy = lookup_compare_valid1_w && (&tag1_half_copy_w);
            (* keep = "true" *) wire [7:0] valid_data0_w;
            (* keep = "true" *) wire [7:0] valid_data1_w;
            assign valid_data0_w = data0_w[victim_group*8 +: 8] & {8{lookup_valid0_w}};
            assign valid_data1_w = data1_w[victim_group*8 +: 8] & {8{lookup_valid1_w}};
            assign ic_resp_data_o[victim_group*8 +: 8] = state_r == S_RETURN ?
                result_r[victim_group*8 +: 8] :
                (valid_data0_w & {8{&tag0_half_copy_w}}) |
                (valid_data1_w & {8{&tag1_half_copy_w}});
            if (victim_group < 4) begin : g_predecode_response
                wire [10:0] valid_predecode0_w;
                wire [10:0] valid_predecode1_w;
                assign valid_predecode0_w = data0_w[64+victim_group*11 +: 11] &
                    {11{lookup_valid0_w}};
                assign valid_predecode1_w = data1_w[64+victim_group*11 +: 11] &
                    {11{lookup_valid1_w}};
                assign ic_resp_predecode_o[victim_group*11 +: 11] = state_r == S_RETURN ?
                    result_predecode_r[victim_group*11 +: 11] :
                    (valid_predecode0_w & {11{&tag0_half_copy_w}}) |
                    (valid_predecode1_w & {11{&tag1_half_copy_w}});
            end
            assign ic_resp_valid_copy_o[victim_group] = response_pma_err_copy1_r ||
                (response_lookup_copy1_r && (hit0_copy_w[victim_group] || hit1_w_copy)) ||
                (state_r == S_RETURN && !killed_r);
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    response_lookup_copy1_r <= 0;
                    response_pma_err_copy1_r <= 0;
                end else begin
                    response_lookup_copy1_r <= lookup_accept_copy_w[victim_group] &&
                        cacheable_w && !pma_err_w;
                    response_pma_err_copy1_r <= lookup_accept_copy_w[victim_group] && pma_err_w;
                end
            end
            assign tag_write_copy_w[victim_group] = fill_write_w && fill_last_r &&
                !fill_err_copy1_r && !fill_invalidated_copy1_r && !ic_inv_i;
            always @(posedge clk_i) begin
                // Only a valid lookup owns these snapshots; inactive values are not consumed.
                addr_tag_copy1_r <= ic_req_addr_i[31:14];
            end
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    fill_err_copy1_r <= 0;
                    fill_invalidated_copy1_r <= 0;
                end else begin
                    if (ic_inv_i && state_r != S_IDLE)
                        fill_invalidated_copy1_r <= 1;
                    if (state_r == S_IDLE && lookup_valid_r && !pma_err_r &&
                        (!cacheable_r || !hit_w)) begin
                        fill_err_copy1_r <= 0;
                        fill_invalidated_copy1_r <= ic_inv_i;
                    end
                    if (state_r == S_FILL && axi_rvalid_i)
                        fill_err_copy1_r <= fill_err_r || axi_rresp_i != 0;
                end
            end
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    lookup_valid_copy1_r <= 0;
                else if (state_r == S_IDLE)
                    lookup_valid_copy1_r <= lookup_accept_copy_w[victim_group];
            end
            assign victim_copy_w[victim_group] = victim_copy1_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    victim_copy1_r <= 0;
                else if (state_r == S_IDLE && lookup_valid_r && !pma_err_r &&
                    (!cacheable_r || !hit_w))
                    victim_copy1_r <= replacement_w;
            end
        end
    endgenerate
    reg killed_r;
    reg fill_err_r;
    reg [1:0] beat_r;
    reg [63:0] result_r;
    reg [43:0] result_predecode_r;
    reg fill_pending_r;
    reg [63:0] fill_data_r;
    reg [1:0] fill_beat_r;
    reg fill_last_r;
    wire [43:0] fill_predecode_w;
    genvar instruction;
    generate
        for (instruction = 0; instruction < 2;
            instruction = instruction + 1) begin : g_fill_predecode
            edrv32_cpu_predecode u_predecode (
                .instr_i(fill_data_r[instruction*32 +: 32]),
                .predecode_o(fill_predecode_w[instruction*22 +: 22])
            );
        end
    endgenerate
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            fill_pending_r <= 0;
        else
            fill_pending_r <= state_r == S_FILL && axi_rvalid_i;
    end
    always @(posedge clk_i) begin
        if (state_r == S_FILL && axi_rvalid_i) begin
            fill_data_r <= axi_rdata_i;
            fill_beat_r <= beat_r;
            fill_last_r <= axi_rlast_i;
        end
    end
    reg inv_done_r;
    reg fill_invalidated_r;
    wire cacheable_w;
    wire device_unused_w;
    wire pma_err_w;
    (* keep = 1 *) wire [5:0] tag0_half_hit_w /* synthesis syn_keep=1 */;
    (* keep = 1 *) wire [5:0] tag1_half_hit_w /* synthesis syn_keep=1 */;
    wire hit0_w;
    wire hit1_w;
    wire hit_w;
    wire accept_w;
    wire lookup_ready_w;
    wire lookup_metadata_w;
    wire [511:0] evict0_w;
    wire [511:0] evict1_w;
    wire [511:0] fill0_w;
    wire [511:0] fill1_w;
    wire fill_write_w;
    wire tag_write_w;
    wire [17:0] tag0_w;
    wire [17:0] tag1_w;
    wire [107:0] data0_w;
    wire [107:0] data1_w;
    wire unused_axi_w;

    assign unused_axi_w = &{1'b0, axi_rid_i, device_unused_w};
    edrv32_cache_pma u_pma (
        .addr_i(ic_req_addr_i),
        .execute_i(1'b1),
        .store_i(1'b0),
        .cacheable_o(cacheable_w),
        .device_o(device_unused_w),
        .err_o(pma_err_w)
    );
    assign lookup_valid0_w = |(lookup_valid0_bank_r & lookup_bank_r);
    assign lookup_valid1_w = |(lookup_valid1_bank_r & lookup_bank_r);
    assign lookup_compare_valid0_w = |(lookup_compare_valid0_bank_r & lookup_bank_r);
    assign lookup_compare_valid1_w = |(lookup_compare_valid1_bank_r & lookup_bank_r);
    assign lookup_lru_w = |(lookup_lru_bank_r & lookup_bank_r);
    // cpu-spec 4.9: retain independent three-bit tag comparisons. Valid data
    // candidates are masked before the late tag match selects each response byte.
    generate
        for (compare_part = 0; compare_part < 6;
            compare_part = compare_part + 1) begin : g_primary_compare
            assign tag0_half_hit_w[compare_part] =
                tag0_w[compare_part*3 +: 3] == addr_r[14+compare_part*3 +: 3];
            assign tag1_half_hit_w[compare_part] =
                tag1_w[compare_part*3 +: 3] == addr_r[14+compare_part*3 +: 3];
        end
    endgenerate
    assign hit0_w = lookup_compare_valid0_w && (&tag0_half_hit_w);
    assign hit1_w = lookup_compare_valid1_w && (&tag1_half_hit_w);
    assign hit_w = hit0_w || hit1_w;
    // cache-spec v0.11 5.1: externally accept through the miss-discovery cycle.
    // The speculative successor is discarded internally; the miss keeps its address/set.
    assign ic_req_ready_o = state_r == S_IDLE;
    assign lookup_ready_w = state_r == S_IDLE &&
        (!lookup_valid_r || pma_err_r || (cacheable_r && hit_w));
    assign accept_w = ic_req_valid_i && lookup_ready_w;
    assign lookup_metadata_w = state_r == S_IDLE && lookup_valid_r &&
        !pma_err_r && cacheable_r;
    assign ic_resp_valid_o =
        response_pma_err_r || (response_lookup_r && hit_w) ||
        (state_r == S_RETURN && !killed_r);
    assign ic_resp_err_o = state_r == S_RETURN ? fill_err_r : pma_err_r;
    assign ic_inv_done_o = inv_done_r;
    assign axi_arid_o = 4'b0;
    assign axi_araddr_o = cacheable_r ? {addr_r[31:5], 5'b0} : addr_r;
    assign axi_arlen_o = cacheable_r ? 8'd3 : 8'd0;
    assign axi_arsize_o = 3'd3;
    assign axi_arburst_o = 2'b01;
    assign axi_arvalid_o = state_r == S_AR;
    assign axi_rready_o = state_r == S_FILL;
    assign fill_write_w = fill_pending_r && cacheable_r;
    assign tag_write_w = fill_write_w && fill_last_r && !fill_err_r &&
                            !fill_invalidated_r && !ic_inv_i;
    edrv32_ram_icache_tag u_tag0 (
        .clk_i(clk_i),
        .wr_en_i(tag_write_w && victim_r == 1'b0),
        .wr_addr_i(addr_r[13:5]),
        .wr_data_i(addr_r[31:14]),
        .rd_en_i(accept_w),
        .rd_addr_i(ic_req_addr_i[13:5]),
        .rd_data_o(tag0_w)
    );
    edrv32_ram_icache_data u_data0 (
        .clk_i(clk_i),
        .wr_en_i(fill_write_w && victim_r == 1'b0),
        .wr_addr_i({addr_r[13:5], fill_beat_r}),
        .wr_data_i({fill_predecode_w, fill_data_r}),
        .rd_en_i(accept_w),
        .rd_addr_i(ic_req_addr_i[13:3]),
        .rd_data_o(data0_w)
    );
    edrv32_ram_icache_tag u_tag1 (
        .clk_i(clk_i),
        .wr_en_i(tag_write_w && victim_r == 1'b1),
        .wr_addr_i(addr_r[13:5]),
        .wr_data_i(addr_r[31:14]),
        .rd_en_i(accept_w),
        .rd_addr_i(ic_req_addr_i[13:5]),
        .rd_data_o(tag1_w)
    );
    edrv32_ram_icache_data u_data1 (
        .clk_i(clk_i),
        .wr_en_i(fill_write_w && victim_r == 1'b1),
        .wr_addr_i({addr_r[13:5], fill_beat_r}),
        .wr_data_i({fill_predecode_w, fill_data_r}),
        .rd_en_i(accept_w),
        .rd_addr_i(ic_req_addr_i[13:3]),
        .rd_data_o(data1_w)
    );
    // cache-spec 5.1 / cpu-spec 4.9: qualify the synchronous tag result at its
    // launching edge. An accepted lookup always occupies S_IDLE next cycle;
    // misses clear these pulses while retaining their refill ownership.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            response_lookup_r <= 0;
            response_pma_err_r <= 0;
        end else begin
            response_lookup_r <= accept_w && cacheable_w && !pma_err_w;
            response_pma_err_r <= accept_w && pma_err_w;
        end
    end
    always @(posedge clk_i) begin
        if (lookup_accept_copy_w[4]) begin
            cacheable_r <= cacheable_w;
            pma_err_r <= pma_err_w;
        end
        // cache-spec 5.1: snapshot the next set whenever the lookup slot is free.
        // Only accept_w gives it an owner; misses retain the set through refill.
        // Removing request-valid from this enable cuts E JALR resolution -> I$ set decode.
        if (lookup_ready_w) begin
            lookup_bank_r <= 32'b1 << ic_req_addr_i[13:9];
            lookup_slot_r <= request_slot_w;
        end
        if (fill_pending_r && (!cacheable_r || fill_beat_r == addr_r[4:3])) begin
            result_r <= fill_data_r;
            result_predecode_r <= fill_predecode_w;
        end
    end

    // cache-spec 5.1: invalidate is visible immediately at the lookup boundary.
    // Bank-local clear pulses retire the physical valid bits one edge later;
    // banked lookup snapshots mask those pulses until the clear has retired.
    // Each pulse depends on its own bank, preventing synthesis from merging
    // replicas and returning a 1024-load invalidate net.
    generate
        for (bank = 0; bank < 32; bank = bank + 1) begin : g_valid_bank
            reg [15:0] valid0_bank_r;
            reg [15:0] valid1_bank_r;
            reg [15:0] lru_bank_r;
            wire rst_ivalid0_n_w;
            wire rst_ivalid1_n_w;
            wire rst_ilru_n_w;
            (* keep = "true", syn_preserve = 1 *) reg [5:0] metadata_miss0_r;
            (* keep = "true", syn_preserve = 1 *) reg [5:0] metadata_miss1_r;
            (* keep = "true", syn_preserve = 1 *) reg metadata_lookup_r;
            wire metadata_valid0_w;
            wire metadata_valid1_w;
            assign metadata_valid0_w = bank < 16 ? lookup_valid0_w : lookup_compare_valid0_w;
            assign metadata_valid1_w = bank < 16 ? lookup_valid1_w : lookup_compare_valid1_w;
            wire metadata_hit_w;
            wire metadata_miss_w;
            wire metadata_way_w;
            assign metadata_way_w = !(|metadata_miss0_r);
            assign metadata_miss_w = (|metadata_miss0_r) && (|metadata_miss1_r);
            assign metadata_hit_w = metadata_lookup_r && !metadata_miss_w;
            // Each mismatch flag includes ownership and way validity before
            // capture. OR reductions then form a miss without a late context mux.
            for (metadata_part = 0; metadata_part < 6;
                metadata_part = metadata_part + 1) begin : g_compare
                always @(posedge clk_i or negedge rst_ivalid0_n_w) begin
                    if (!rst_ivalid0_n_w)
                        metadata_miss0_r[metadata_part] <= 0;
                    else
                        metadata_miss0_r[metadata_part] <= lookup_metadata_w &&
                            (!metadata_valid0_w || tag0_w[metadata_part*3 +: 3] !=
                            addr_r[14+metadata_part*3 +: 3]);
                end
                always @(posedge clk_i or negedge rst_ivalid1_n_w) begin
                    if (!rst_ivalid1_n_w)
                        metadata_miss1_r[metadata_part] <= 0;
                    else
                        metadata_miss1_r[metadata_part] <= lookup_metadata_w &&
                            (!metadata_valid1_w || tag1_w[metadata_part*3 +: 3] !=
                            addr_r[14+metadata_part*3 +: 3]);
                end
            end
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    metadata_lookup_r <= 0;
                else
                    metadata_lookup_r <= lookup_metadata_w;
            end
            integer lru_slot;
            (* keep = "true" *) wire lru_data_w;
            assign lru_data_w = tag_write_copy_w[bank/4] ?
                !victim_copy_w[bank/4] : metadata_way_w;
            assign valid0_r[bank*16 +: 16] = valid0_bank_r;
            assign valid1_r[bank*16 +: 16] = valid1_bank_r;
            assign lru_r[bank*16 +: 16] = lru_bank_r;
            assign rst_ivalid0_n_w = rst_sys_ivalid0_n_i[bank/16];
            assign rst_ivalid1_n_w = rst_sys_ivalid1_n_i[bank/16];
            assign rst_ilru_n_w = rst_sys_ilru_n_i[bank/16];
            assign evict0_w[bank*16 +: 16] = metadata_slot_r &
                {16{metadata_bank_r[bank] && metadata_miss_w && !metadata_victim_r}};
            assign evict1_w[bank*16 +: 16] = metadata_slot_r &
                {16{metadata_bank_r[bank] && metadata_miss_w && metadata_victim_r}};
            assign fill0_w[bank*16 +: 16] = lookup_slot_r &
                {16{lookup_bank_r[bank] && tag_write_copy_w[bank/4] && !victim_copy_w[bank/4]}};
            assign fill1_w[bank*16 +: 16] = lookup_slot_r &
                {16{lookup_bank_r[bank] && tag_write_copy_w[bank/4] && victim_copy_w[bank/4]}};
            always @(posedge clk_i) begin
                lookup_valid0_bank_r[bank] <= !ic_inv_i && !invalidate_bank_r[bank] &&
                    (|(valid0_r[bank*16 +: 16] & request_slot_w));
                lookup_valid1_bank_r[bank] <= !ic_inv_i && !invalidate_bank_r[bank] &&
                    (|(valid1_r[bank*16 +: 16] & request_slot_w));
                lookup_lru_bank_r[bank] <= |(lru_r[bank*16 +: 16] & request_slot_w);
            end
            // Comparison/metadata consumers and data consumers own separate
            // valid snapshots; each qualified mismatch drives at most 16 banks.
            always @(posedge clk_i) begin
                lookup_compare_valid0_bank_r[bank] <= !ic_inv_i && !invalidate_bank_r[bank] &&
                    (|(valid0_r[bank*16 +: 16] & request_slot_w));
                lookup_compare_valid1_bank_r[bank] <= !ic_inv_i && !invalidate_bank_r[bank] &&
                    (|(valid1_r[bank*16 +: 16] & request_slot_w));
            end
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    invalidate_bank_r[bank] <= 1'b0;
                else
                    invalidate_bank_r[bank] <= ic_inv_i &&
                        (|valid0_r[bank*16 +: 16] || |valid1_r[bank*16 +: 16]);
            end
            always @(posedge clk_i or negedge rst_ivalid0_n_w) begin
                if (!rst_ivalid0_n_w)
                    valid0_bank_r <= 16'b0;
                else
                    valid0_bank_r <= invalidate_bank_r[bank] ? 16'b0 :
                        (valid0_r[bank*16 +: 16] & ~evict0_w[bank*16 +: 16]) |
                        fill0_w[bank*16 +: 16];
            end
            always @(posedge clk_i or negedge rst_ivalid1_n_w) begin
                if (!rst_ivalid1_n_w)
                    valid1_bank_r <= 16'b0;
                else
                    valid1_bank_r <= invalidate_bank_r[bank] ? 16'b0 :
                        (valid1_r[bank*16 +: 16] & ~evict1_w[bank*16 +: 16]) |
                        fill1_w[bank*16 +: 16];
            end
            // Keep late hit qualification on per-slot enables. Data is the
            // common way value; it never passes through the old-bit feedback mux.
            // Refill and delayed lookup events cannot overlap in the blocking FSM.
            always @(posedge clk_i or negedge rst_ilru_n_w) begin
                if (!rst_ilru_n_w) begin
                    lru_bank_r <= 16'b0;
                end else begin
                    for (lru_slot = 0; lru_slot < 16; lru_slot = lru_slot + 1) begin
                        if ((lookup_bank_r[bank] && tag_write_copy_w[bank/4] &&
                            lookup_slot_r[lru_slot]) ||
                            (metadata_bank_r[bank] && metadata_hit_w &&
                            metadata_slot_r[lru_slot]))
                            lru_bank_r[lru_slot] <= lru_data_w;
                    end
                end
            end
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            lookup_valid_r <= 1'b0;
            victim_r <= 1'b0;
            killed_r <= 1'b0;
            fill_err_r <= 1'b0;
            beat_r <= 2'b0;
            inv_done_r <= 1'b0;
            fill_invalidated_r <= 1'b0;
        end else begin
            inv_done_r <= ic_inv_i;
            if (ic_kill_i && state_r != S_IDLE) killed_r <= 1'b1;
            if (ic_inv_i && state_r != S_IDLE) fill_invalidated_r <= 1'b1;
            case (state_r)
                S_IDLE: begin
                    lookup_valid_r <= accept_w;
                    if (lookup_valid_r && !pma_err_r) begin
                        if (!cacheable_r || !hit_w) begin
                            state_r <= S_AR;
                            victim_r <= replacement_w;
                            killed_r <= ic_kill_i;
                            fill_invalidated_r <= ic_inv_i;
                            fill_err_r <= 1'b0;
                            beat_r <= 2'b0;
                        end
                    end
                end
                S_AR: if (axi_arready_i) state_r <= S_FILL;
                S_FILL: if (axi_rvalid_i) begin
                    fill_err_r <= fill_err_r || axi_rresp_i != 0;
                    beat_r <= beat_r + 1'b1;
                    if (axi_rlast_i) begin
                        state_r <= S_DRAIN;
                    end
                end
                S_DRAIN: state_r <= S_RETURN;
                S_RETURN: state_r <= S_IDLE;
                default: begin end
            endcase

        end
    end
endmodule
