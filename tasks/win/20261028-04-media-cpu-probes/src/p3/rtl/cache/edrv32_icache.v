// File: edrv32_icache.v
// Spec: cache-spec 2, 3.1, 5.1, 6.
// Description: Pipelined instruction lookup and blocking AXI64 refill.
// Two-way blocking instruction cache with synchronous per-way tag/data RAM.
// Hit lookup is pipelined; an outstanding refill survives a core kill.
// Clock domain: clk_sys.
module edrv32_icache (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Core instruction interface.
    input wire ic_req_valid_i,
    input wire [31:0] ic_req_addr_i,
    output wire ic_req_ready_o,
    output wire ic_resp_valid_o,
    output wire [63:0] ic_resp_data_o,
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
    reg [2:0] state_r;
    reg [127:0] valid0_r;
    reg [127:0] valid1_r;
    reg [127:0] lru_r;
    reg lookup_valid_r;
    reg [31:0] addr_r;
    reg cacheable_r;
    reg pma_err_r;
    reg victim_r;
    reg killed_r;
    reg fill_err_r;
    reg [1:0] beat_r;
    reg [63:0] result_r;
    reg inv_done_r;
    reg fill_invalidated_r;
    wire cacheable_w;
    wire device_unused_w;
    wire pma_err_w;
    wire hit0_w;
    wire hit1_w;
    wire hit_w;
    reg probe_hit_r;
    wire accept_w;
    wire fill_write_w;
    wire tag_write_w;
    wire [19:0] tag0_w;
    wire [19:0] tag1_w;
    wire [63:0] data0_w;
    wire [63:0] data1_w;
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
    assign hit0_w = valid0_r[addr_r[11:5]] && tag0_w == addr_r[31:12];
    assign hit1_w = valid1_r[addr_r[11:5]] && tag1_w == addr_r[31:12];
    assign hit_w = hit0_w || hit1_w;
    // P3 timing-only probe: tag comparisons end before control broadcast.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            probe_hit_r <= 0;
        else
            probe_hit_r <= hit_w;
    end
    assign ic_req_ready_o = state_r == S_IDLE &&
                            (!lookup_valid_r || pma_err_r || (cacheable_r && probe_hit_r));
    assign accept_w = ic_req_valid_i && ic_req_ready_o;
    assign ic_resp_valid_o =
        ((state_r == S_IDLE && lookup_valid_r && (pma_err_r || (cacheable_r && probe_hit_r))) ||
            (state_r == S_RETURN && !killed_r));
    assign ic_resp_data_o = state_r == S_RETURN ? result_r : (hit0_w ? data0_w : data1_w);
    assign ic_resp_err_o = state_r == S_RETURN ? fill_err_r : pma_err_r;
    assign ic_inv_done_o = inv_done_r;
    assign axi_arid_o = 4'b0;
    assign axi_araddr_o = cacheable_r ? {addr_r[31:5], 5'b0} : addr_r;
    assign axi_arlen_o = cacheable_r ? 8'd3 : 8'd0;
    assign axi_arsize_o = 3'd3;
    assign axi_arburst_o = 2'b01;
    assign axi_arvalid_o = state_r == S_AR;
    assign axi_rready_o = state_r == S_FILL;
    assign fill_write_w = state_r == S_FILL && axi_rvalid_i && cacheable_r;
    assign tag_write_w = fill_write_w && axi_rlast_i && !fill_err_r && axi_rresp_i == 0 &&
                            !fill_invalidated_r && !ic_inv_i;
    edrv32_ram_icache_tag u_tag0 (
        .clk_i(clk_i),
        .wr_en_i(tag_write_w && victim_r == 1'b0),
        .wr_addr_i(addr_r[11:5]),
        .wr_data_i(addr_r[31:12]),
        .rd_en_i(accept_w),
        .rd_addr_i(ic_req_addr_i[11:5]),
        .rd_data_o(tag0_w)
    );
    edrv32_ram_icache_data u_data0 (
        .clk_i(clk_i),
        .wr_en_i(fill_write_w && victim_r == 1'b0),
        .wr_addr_i({addr_r[11:5], beat_r}),
        .wr_data_i(axi_rdata_i),
        .rd_en_i(accept_w),
        .rd_addr_i(ic_req_addr_i[11:3]),
        .rd_data_o(data0_w)
    );
    edrv32_ram_icache_tag u_tag1 (
        .clk_i(clk_i),
        .wr_en_i(tag_write_w && victim_r == 1'b1),
        .wr_addr_i(addr_r[11:5]),
        .wr_data_i(addr_r[31:12]),
        .rd_en_i(accept_w),
        .rd_addr_i(ic_req_addr_i[11:5]),
        .rd_data_o(tag1_w)
    );
    edrv32_ram_icache_data u_data1 (
        .clk_i(clk_i),
        .wr_en_i(fill_write_w && victim_r == 1'b1),
        .wr_addr_i({addr_r[11:5], beat_r}),
        .wr_data_i(axi_rdata_i),
        .rd_en_i(accept_w),
        .rd_addr_i(ic_req_addr_i[11:3]),
        .rd_data_o(data1_w)
    );
    always @(posedge clk_i) begin
        if (accept_w) begin
            addr_r <= ic_req_addr_i;
            cacheable_r <= cacheable_w;
            pma_err_r <= pma_err_w;
        end
        if (state_r == S_FILL && axi_rvalid_i &&
            (!cacheable_r || beat_r == addr_r[4:3])) begin
            result_r <= axi_rdata_i;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            valid0_r <= 128'b0;
            valid1_r <= 128'b0;
            lru_r <= 128'b0;
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
            if (ic_inv_i) begin
                valid0_r <= 128'b0;
                valid1_r <= 128'b0;
            end
            case (state_r)
                S_IDLE: begin
                    lookup_valid_r <= accept_w;
                    if (lookup_valid_r && !pma_err_r) begin
                        if (cacheable_r && probe_hit_r) begin
                            lru_r[addr_r[11:5]] <= hit0_w;
                        end else begin
                            state_r <= S_AR;
                            victim_r <= lru_r[addr_r[11:5]];
                            killed_r <= ic_kill_i;
                            fill_invalidated_r <= ic_inv_i;
                            fill_err_r <= 1'b0;
                            beat_r <= 2'b0;
                            if (cacheable_r) begin
                                if (lru_r[addr_r[11:5]]) valid1_r[addr_r[11:5]] <= 1'b0;
                                else valid0_r[addr_r[11:5]] <= 1'b0;
                            end
                        end
                    end
                end
                S_AR: if (axi_arready_i) state_r <= S_FILL;
                S_FILL: if (axi_rvalid_i) begin
                    fill_err_r <= fill_err_r || axi_rresp_i != 0;
                    beat_r <= beat_r + 1'b1;
                    if (axi_rlast_i) begin
                        state_r <= S_RETURN;
                        if (tag_write_w) begin
                            if (victim_r) valid1_r[addr_r[11:5]] <= 1'b1;
                            else valid0_r[addr_r[11:5]] <= 1'b1;
                            lru_r[addr_r[11:5]] <= !victim_r;
                        end
                    end
                end
                S_RETURN: state_r <= S_IDLE;
                default: begin end
            endcase

        end
    end
endmodule
