// ============================================================================
// File        : edrv32_mem_model.sv
// Author      : Edward ZC
// Description : Behavioral Harvard memory model for core testbenches. Separate
//               instruction (read-only) and data (read/write) valid/ready
//               channels, single outstanding, synchronous registered reads,
//               configurable extra response wait, TB-driven request backpressure
//               and out-of-range error reporting.
// Notes       : Simulation-only (behavioral). Loads image via +MEMFILE plusarg
//               with $readmemh. Word-addressed; sub-word extraction is the core's
//               responsibility (design 7). Not synthesizable.
// ============================================================================
`ifndef EDRV32_MEM_MODEL_SV
`define EDRV32_MEM_MODEL_SV

module edrv32_mem_model #(
    parameter integer MEM_DEPTH_WORDS = (1 << 19),   // 512K words = 2 MiB
    parameter [31:0]  BASE_ADDR       = 32'h8000_0000,
    parameter integer IMEM_LAT        = 0,           // waits after sync read cycle
    parameter integer DMEM_LAT        = 0,
    // Debug IO sink window (off by default). Emulates a minimal ns16550
    // UART at DEBUG_IO_BASE: TX writes (offset 0) are sunk, LSR reads
    // (offset 5) always report THRE/TSRE set (0x60), everything else reads
    // as zero. Legacy/custom tests poll this window for console output.
    parameter integer DEBUG_IO_EN     = 0,
    parameter [31:0]  DEBUG_IO_BASE   = 32'h1000_0000,
    parameter [31:0]  DEBUG_IO_SIZE   = 32'h0000_1000
)(
    input  wire        clk,
    input  wire        rst_n,

    // --- Instruction channel (read-only) ---
    input  wire        imem_req_valid_i,
    output reg         imem_req_ready_o,
    input  wire [31:0] imem_req_addr_i,
    output reg         imem_resp_valid_o,
    input  wire        imem_resp_ready_i,
    output reg  [31:0] imem_resp_rdata_o,
    output reg         imem_resp_error_o,

    // --- Data channel (read/write) ---
    input  wire        dmem_req_valid_i,
    output reg         dmem_req_ready_o,
    input  wire [31:0] dmem_req_addr_i,
    input  wire        dmem_req_we_i,
    input  wire [1:0]  dmem_req_size_i,
    input  wire [3:0]  dmem_req_wstrb_i,
    input  wire [31:0] dmem_req_wdata_i,
    output reg         dmem_resp_valid_o,
    input  wire        dmem_resp_ready_i,
    output reg  [31:0] dmem_resp_rdata_o,
    output reg         dmem_resp_error_o,

    // --- TB backpressure controls (drive 0 for no backpressure) ---
    input  wire        imem_req_stall_i,
    input  wire        dmem_req_stall_i
);

    localparam integer IDX_W = $clog2(MEM_DEPTH_WORDS);

    reg [31:0] mem [0:MEM_DEPTH_WORDS-1];

    // Optional image load. Keep enough room for deeply nested, reusable
    // regression artifact paths without truncating the leading directory.
    localparam integer MEMFILE_CHARS = 512;
    reg [(MEMFILE_CHARS*8)-1:0] memfile;
    integer                     i;
    initial begin
        for (i = 0; i < MEM_DEPTH_WORDS; i = i + 1) mem[i] = 32'h0;
        if ($value$plusargs("MEMFILE=%s", memfile)) begin
            $readmemh(memfile, mem);
        end
    end

    // ------------------------------------------------------------------
    // Instruction channel FSM. The request address is captured at acceptance;
    // mem[] is sampled only inside this clocked process. IMEM_LAT adds wait
    // cycles beyond the mandatory one-cycle synchronous read latency.
    // ------------------------------------------------------------------
    localparam [1:0] I_IDLE = 2'd0, I_WAIT = 2'd1, I_RESP = 2'd2;
    reg  [1:0]  i_state;
    integer     i_cnt;
    reg  [31:0] i_addr_q;

    wire        i_oob   = (imem_req_addr_i < BASE_ADDR) ||
                          (((imem_req_addr_i - BASE_ADDR) >> 2) >= MEM_DEPTH_WORDS);
    wire [31:0] i_index = (i_addr_q - BASE_ADDR) >> 2;
    reg         i_oob_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_state           <= I_IDLE;
            imem_req_ready_o   <= 1'b0;
            imem_resp_valid_o  <= 1'b0;
            imem_resp_rdata_o  <= 32'h0;
            imem_resp_error_o  <= 1'b0;
            i_cnt              <= 0;
            i_addr_q           <= 32'h0;
            i_oob_q            <= 1'b0;
        end else begin
            case (i_state)
                I_IDLE: begin
                    imem_resp_valid_o <= 1'b0;
                    // Transfer uses the registered ready the core actually sees,
                    // so a toggling stall never desyncs accept vs. observed ready.
                    if (imem_req_ready_o && imem_req_valid_i) begin
                        i_addr_q         <= imem_req_addr_i;
                        i_oob_q          <= i_oob;
                        imem_req_ready_o <= 1'b0;
                        i_cnt            <= IMEM_LAT;
                        i_state          <= I_WAIT;
                    end else begin
                        imem_req_ready_o <= ~imem_req_stall_i;
                    end
                end
                I_WAIT: begin
                    if (i_cnt == 0) begin
                        imem_resp_error_o <= i_oob_q;
                        imem_resp_rdata_o <= i_oob_q ? 32'h0 : mem[i_index[IDX_W-1:0]];
                        imem_resp_valid_o <= 1'b1;
                        i_state           <= I_RESP;
                    end else begin
                        i_cnt <= i_cnt - 1;
                    end
                end
                I_RESP: begin
                    if (imem_resp_ready_i) begin
                        imem_resp_valid_o <= 1'b0;
                        imem_req_ready_o  <= ~imem_req_stall_i;
                        i_state           <= I_IDLE;
                    end
                end
                default: i_state <= I_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Data channel FSM. Writes commit at request acceptance; reads sample mem[]
    // in this clocked process after the captured address and mandatory one-cycle
    // synchronous latency. DMEM_LAT adds only extra response wait cycles.
    // ------------------------------------------------------------------
    localparam [1:0] D_IDLE = 2'd0, D_WAIT = 2'd1, D_RESP = 2'd2;
    reg  [1:0]  d_state;
    integer     d_cnt;
    reg  [31:0] d_addr_q;
    reg         d_oob_q;
    reg         d_dbg_io_q;

    wire        d_dbg_io = (DEBUG_IO_EN != 0) &&
                           (dmem_req_addr_i >= DEBUG_IO_BASE) &&
                           (dmem_req_addr_i < (DEBUG_IO_BASE + DEBUG_IO_SIZE));
    wire        d_oob    = !d_dbg_io &&
                           ((dmem_req_addr_i < BASE_ADDR) ||
                           (((dmem_req_addr_i - BASE_ADDR) >> 2) >= MEM_DEPTH_WORDS));
    wire [31:0] d_ridx   = (dmem_req_addr_i - BASE_ADDR) >> 2;   // request-time index
    wire [31:0] d_index  = (d_addr_q - BASE_ADDR) >> 2;          // latched index

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d_state           <= D_IDLE;
            dmem_req_ready_o   <= 1'b0;
            dmem_resp_valid_o  <= 1'b0;
            dmem_resp_rdata_o  <= 32'h0;
            dmem_resp_error_o  <= 1'b0;
            d_cnt              <= 0;
            d_addr_q           <= 32'h0;
            d_oob_q            <= 1'b0;
        end else begin
            case (d_state)
                D_IDLE: begin
                    dmem_resp_valid_o <= 1'b0;
                    // Transfer uses the registered ready the core actually sees.
                    if (dmem_req_ready_o && dmem_req_valid_i) begin
                        d_addr_q         <= dmem_req_addr_i;
                        d_oob_q          <= d_oob;
                        d_dbg_io_q       <= d_dbg_io;
                        dmem_req_ready_o <= 1'b0;
                        d_cnt            <= DMEM_LAT;
                        d_state          <= D_WAIT;
                        // Write commit (byte-strobed) unless out of range or
                        // a debug-IO sink access
                        if (dmem_req_we_i && !d_oob && !d_dbg_io) begin
                            if (dmem_req_wstrb_i[0]) mem[d_ridx[IDX_W-1:0]][7:0]   <= dmem_req_wdata_i[7:0];
                            if (dmem_req_wstrb_i[1]) mem[d_ridx[IDX_W-1:0]][15:8]  <= dmem_req_wdata_i[15:8];
                            if (dmem_req_wstrb_i[2]) mem[d_ridx[IDX_W-1:0]][23:16] <= dmem_req_wdata_i[23:16];
                            if (dmem_req_wstrb_i[3]) mem[d_ridx[IDX_W-1:0]][31:24] <= dmem_req_wdata_i[31:24];
                        end
                    end else begin
                        dmem_req_ready_o <= ~dmem_req_stall_i;
                    end
                end
                D_WAIT: begin
                    if (d_cnt == 0) begin
                        dmem_resp_error_o <= d_oob_q;
                        // Debug-IO reads: LSR (offset 5) always ready (0x60)
                        // replicated to all byte lanes (byte accesses land on
                        // any lane); everything else reads as zero.
                        dmem_resp_rdata_o <= d_oob_q ? 32'h0 :
                                             d_dbg_io_q ?
                                             ((d_addr_q[11:0] == 12'h005) ?
                                              {4{8'h60}} : 32'h0) :
                                             mem[d_index[IDX_W-1:0]];
                        dmem_resp_valid_o <= 1'b1;
                        d_state           <= D_RESP;
                    end else begin
                        d_cnt <= d_cnt - 1;
                    end
                end
                D_RESP: begin
                    if (dmem_resp_ready_i) begin
                        dmem_resp_valid_o <= 1'b0;
                        dmem_req_ready_o  <= ~dmem_req_stall_i;
                        d_state           <= D_IDLE;
                    end
                end
                default: d_state <= D_IDLE;
            endcase
        end
    end

endmodule

`endif // EDRV32_MEM_MODEL_SV
