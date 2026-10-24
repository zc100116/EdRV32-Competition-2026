// ============================================================================
// File        : clint.v
// Author      : Edward ZC
// Description : Core-Local Interruptor (CLINT), SiFive register layout. Provides a
//               free-running 64-bit mtime, a 64-bit mtimecmp and a software-
//               interrupt register (msip). Drives the machine timer interrupt
//               (irq_timer_o = mtime >= mtimecmp) and machine software interrupt
//               (irq_soft_o = msip[0]) as level signals held until software clears
//               the source. Single native req/resp slave port (word accesses with
//               byte strobes; 64-bit registers via two 32-bit lo/hi transfers).
// Notes       : Verilog-2001, single clock, async reset / sync release. mtime
//               increments every MTIME_DIV clocks. Single hart. Reads return the
//               addressed register; unknown offsets read 0 (no error). Two-phase
//               handshake: accept in IDLE, response held in RESP until resp_ready.
// ============================================================================
`include "edrv32_bus.vh"
`include "edrv32_soc_map.vh"

// ============================================================================
// clint - machine timer + software interrupt (SiFive layout)
// ============================================================================
module clint #(
    parameter integer MTIME_DIV = 1     // mtime ticks once per MTIME_DIV clocks
)(
    // --- Clock and reset ---
    input  wire                 clk,
    input  wire                 rst_n,

    // --- Native req/resp slave port (from dmem fabric CLINT region) ---
    input  wire                 req_valid_i,
    output wire                 req_ready_o,
    input  wire [`XLEN-1:0]     req_addr_i,
    input  wire                 req_we_i,
    input  wire [3:0]           req_wstrb_i,
    input  wire [31:0]          req_wdata_i,
    input  wire                 resp_ready_i,
    output wire                 resp_valid_o,
    output wire [31:0]          resp_rdata_o,
    output wire                 resp_error_o,

    // --- Interrupt outputs (level; to core mip via irq_timer_i/irq_soft_i) ---
    output wire                 irq_timer_o,
    output wire                 irq_soft_o,

    // --- Platform time value (to core time/timeh CSRs) ---
    output wire [63:0]          mtime_o
);

    // ------------------------------------------------------------------------
    // Architectural registers.
    // ------------------------------------------------------------------------
    reg [63:0] mtime_r;
    reg [63:0] mtimecmp_r;
    reg        msip_r;

    // ------------------------------------------------------------------------
    // Two-phase slave FSM. Address offset within the CLINT region.
    // ------------------------------------------------------------------------
    wire [15:0] off_w = req_addr_i[15:0];

    localparam S_IDLE = 1'b0, S_RESP = 1'b1;
    reg        state_r;
    reg [31:0] rdata_r;
    wire       accept_w = (state_r == S_IDLE) & req_valid_i;

    // ------------------------------------------------------------------------
    // mtime free-running counter (divided).  Software writes take priority
    // over the tick increment and restart the divider phase.
    // ------------------------------------------------------------------------
    reg [31:0] tick_cnt_r;
    wire       tick_w = (tick_cnt_r == (MTIME_DIV - 1));
    wire       mtime_wr_w = accept_w && req_we_i &&
                            ((off_w == `CLINT_MTIME_LO) ||
                             (off_w == `CLINT_MTIME_HI));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_cnt_r <= 32'h0;
            mtime_r    <= 64'h0;
        end else if (mtime_wr_w) begin
            tick_cnt_r <= 32'h0;
            if (off_w == `CLINT_MTIME_LO)
                mtime_r[31:0]  <= wr_merge(mtime_r[31:0],  req_wdata_i, req_wstrb_i);
            else
                mtime_r[63:32] <= wr_merge(mtime_r[63:32], req_wdata_i, req_wstrb_i);
        end else begin
            if (tick_w) begin
                tick_cnt_r <= 32'h0;
                mtime_r    <= mtime_r + 64'h1;
            end else begin
                tick_cnt_r <= tick_cnt_r + 32'h1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r <= S_IDLE;
        end else begin
            case (state_r)
                S_IDLE: if (req_valid_i)  state_r <= S_RESP;
                S_RESP: if (resp_ready_i) state_r <= S_IDLE;
                default:                  state_r <= S_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Read data mux (registered at accept).
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (accept_w) begin
            case (off_w)
                `CLINT_MSIP:        rdata_r <= {31'b0, msip_r};
                `CLINT_MTIMECMP_LO: rdata_r <= mtimecmp_r[31:0];
                `CLINT_MTIMECMP_HI: rdata_r <= mtimecmp_r[63:32];
                `CLINT_MTIME_LO:    rdata_r <= mtime_r[31:0];
                `CLINT_MTIME_HI:    rdata_r <= mtime_r[63:32];
                default:            rdata_r <= 32'h0;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Register writes (byte-strobed) on accept.
    // ------------------------------------------------------------------------
    function [31:0] wr_merge(input [31:0] old, input [31:0] wd, input [3:0] strb);
        begin
            wr_merge = old;
            if (strb[0]) wr_merge[7:0]   = wd[7:0];
            if (strb[1]) wr_merge[15:8]  = wd[15:8];
            if (strb[2]) wr_merge[23:16] = wd[23:16];
            if (strb[3]) wr_merge[31:24] = wd[31:24];
        end
    endfunction

    wire [31:0] msip_merge_w =
        wr_merge({31'b0, msip_r}, req_wdata_i, req_wstrb_i);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mtimecmp_r <= 64'hFFFF_FFFF_FFFF_FFFF;   // no spurious timer irq at reset
            msip_r     <= 1'b0;
        end else if (accept_w && req_we_i) begin
            case (off_w)
                `CLINT_MSIP: begin
                    msip_r <= msip_merge_w[0];
                end
                `CLINT_MTIMECMP_LO: begin
                    mtimecmp_r[31:0] <= wr_merge(
                        mtimecmp_r[31:0], req_wdata_i, req_wstrb_i
                    );
                end
                `CLINT_MTIMECMP_HI: begin
                    mtimecmp_r[63:32] <= wr_merge(
                        mtimecmp_r[63:32], req_wdata_i, req_wstrb_i
                    );
                end
                default: ;   // mtime writes handled in the counter block above
            endcase
        end
    end

    assign req_ready_o  = (state_r == S_IDLE);
    assign resp_valid_o = (state_r == S_RESP);
    assign resp_rdata_o = rdata_r;
    assign resp_error_o = `BUS_OK;

    // ------------------------------------------------------------------------
    // Interrupt outputs (level).
    // ------------------------------------------------------------------------
    assign irq_timer_o = (mtime_r >= mtimecmp_r);
    assign irq_soft_o  = msip_r;
    assign mtime_o     = mtime_r;

endmodule
