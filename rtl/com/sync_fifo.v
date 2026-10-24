// ============================================================================
// File        : sync_fifo.v
// Author      : Edward ZC
// Description : Generic synchronous (single-clock) FIFO. Parameterized data width
//               and depth (power of two). Standard push/pop with full/empty and a
//               live occupancy count. Used by peripherals (UART TX/RX, and future
//               SPI/other) as a shared reusable primitive.
// Notes       : Verilog-2001, single clock, async reset / sync release. Depth must
//               be a power of two; pointers are (AW+1) bits so full/empty are
//               distinguished by the wrap bit. Push when full and pop when empty
//               are ignored (caller should gate on full_o/empty_o). First-word-
//               fall-through read: rdata_o always shows the current head.
// ============================================================================

// ============================================================================
// sync_fifo - single-clock FIFO with full/empty and occupancy count
// ============================================================================
module sync_fifo #(
    parameter integer WIDTH = 8,
    parameter integer DEPTH = 8            // power of two
)(
    // --- Clock and reset ---
    input  wire                     clk,
    input  wire                     rst_n,

    // --- Control ---
    input  wire                     flush_i,    // synchronous clear
    input  wire                     push_i,     // write wdata when ~full
    input  wire  [WIDTH-1:0]        wdata_i,
    input  wire                     pop_i,      // advance read when ~empty

    // --- Data / status ---
    output wire  [WIDTH-1:0]        rdata_o,    // current head (valid when ~empty)
    output wire                     full_o,
    output wire                     empty_o,
    output wire  [$clog2(DEPTH):0]  count_o
);

    localparam integer AW = $clog2(DEPTH);

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [AW:0] wptr_r;
    reg [AW:0] rptr_r;

    wire [AW:0] cnt_w   = wptr_r - rptr_r;
    wire        full_w  = (cnt_w == DEPTH[AW:0]);
    wire        empty_w = (cnt_w == 0);

    wire do_push_w = push_i & ~full_w;
    wire do_pop_w  = pop_i  & ~empty_w;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr_r <= {(AW+1){1'b0}};
            rptr_r <= {(AW+1){1'b0}};
        end else if (flush_i) begin
            wptr_r <= {(AW+1){1'b0}};
            rptr_r <= {(AW+1){1'b0}};
        end else begin
            if (do_push_w) wptr_r <= wptr_r + 1'b1;
            if (do_pop_w)  rptr_r <= rptr_r + 1'b1;
        end
    end

    always @(posedge clk) begin
        if (do_push_w) mem[wptr_r[AW-1:0]] <= wdata_i;
    end

    assign rdata_o = mem[rptr_r[AW-1:0]];
    assign full_o  = full_w;
    assign empty_o = empty_w;
    assign count_o = cnt_w;

endmodule
