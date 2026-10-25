// ============================================================================
// File        : reset_sync.v
// Author      : Edward ZC
// Description : Asynchronous-assert, synchronous-release reset synchronizer.
//               Drives an active-low reset that asserts immediately with the
//               asynchronous input but releases only after STAGES clean clock
//               edges, removing recovery/removal metastability on release.
// Notes       : Verilog-2001. Single clock domain. Reset value 0 (asserted).
// ============================================================================

// ============================================================================
// reset_sync - async-assert / sync-release reset synchronizer
// ============================================================================
module reset_sync #(
    parameter integer STAGES = 2       // number of synchronizing flops (>=2)
)(
    // --- Clock and async reset source ---
    input  wire clk,
    input  wire arst_n_i,              // async active-low reset (assert)

    // --- Synchronized reset ---
    output wire rst_n_o                // async assert, sync release
);

    reg [STAGES-1:0] sync_r;

    always @(posedge clk or negedge arst_n_i) begin
        if (!arst_n_i)
            sync_r <= {STAGES{1'b0}};
        else
            sync_r <= {sync_r[STAGES-2:0], 1'b1};
    end

    assign rst_n_o = sync_r[STAGES-1];

endmodule
