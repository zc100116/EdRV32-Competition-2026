// ============================================================================
// File        : dtcm.v
// Author      : Edward ZC
// Description : Data TCM storage with CPU-local and system load/read ports.
// Notes       : Storage is not cleared by internal reset. Both read ports have
//               one-cycle synchronous latency. The CPU-local write port has
//               priority on same-word, same-byte write conflicts.
// ============================================================================

// ============================================================================
// dtcm - CPU-local data tightly coupled memory storage
// ============================================================================
module dtcm #(
    parameter [31:0] SIZE_BYTES = 32'd65536
)(
    // --- Clock ---
    input  wire        clk,

    // --- System data port ---
    input  wire [31:0] sys_addr_i,
    input  wire        sys_we_i,
    input  wire [3:0]  sys_wstrb_i,
    input  wire [31:0] sys_wdata_i,
    output wire [31:0] sys_rdata_o,

    // --- CPU-local data port ---
    input  wire [31:0] local_addr_i,
    input  wire        local_we_i,
    input  wire [3:0]  local_wstrb_i,
    input  wire [31:0] local_wdata_i,
    output wire [31:0] local_rdata_o
);

    localparam integer WORDS = SIZE_BYTES >> 2;
    localparam integer IDX_W = $clog2(WORDS);

    reg [31:0] dtcm_mem [0:WORDS-1];
    reg [31:0] sys_rdata_r;
    reg [31:0] local_rdata_r;

    wire [IDX_W-1:0] sys_idx_w = sys_addr_i[IDX_W+1:2];
    wire [IDX_W-1:0] local_idx_w = local_addr_i[IDX_W+1:2];

    assign sys_rdata_o = sys_rdata_r;
    assign local_rdata_o = local_rdata_r;

    always @(posedge clk) begin
        // Read-first synchronous behavior, matching the Pango DRM18K RAM IP.
        sys_rdata_r   <= dtcm_mem[sys_idx_w];
        local_rdata_r <= dtcm_mem[local_idx_w];

        // System writes are applied first. A simultaneous CPU-local write to
        // the same byte is later in this block and therefore wins explicitly.
        if (sys_we_i) begin
            if (sys_wstrb_i[0])
                dtcm_mem[sys_idx_w][7:0] <= sys_wdata_i[7:0];
            if (sys_wstrb_i[1])
                dtcm_mem[sys_idx_w][15:8] <= sys_wdata_i[15:8];
            if (sys_wstrb_i[2])
                dtcm_mem[sys_idx_w][23:16] <= sys_wdata_i[23:16];
            if (sys_wstrb_i[3])
                dtcm_mem[sys_idx_w][31:24] <= sys_wdata_i[31:24];
        end
        if (local_we_i) begin
            if (local_wstrb_i[0])
                dtcm_mem[local_idx_w][7:0] <= local_wdata_i[7:0];
            if (local_wstrb_i[1])
                dtcm_mem[local_idx_w][15:8] <= local_wdata_i[15:8];
            if (local_wstrb_i[2])
                dtcm_mem[local_idx_w][23:16] <= local_wdata_i[23:16];
            if (local_wstrb_i[3])
                dtcm_mem[local_idx_w][31:24] <= local_wdata_i[31:24];
        end
    end

endmodule
