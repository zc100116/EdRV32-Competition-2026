// ============================================================================
// File        : apb_mux.v
// Author      : Edward ZC
// Description : 64-slot APB address decoder and response multiplexer.
//               paddr[17:12] selects one of 64 4KiB slots.  Unselected
//               slots see psel=0.  Returns pready/prdata/pslverr from the
//               selected slot.
// Notes       : One-hot PSEL is enforced by construction — only the decoded
//               slot index drives psel=1; all others are 0.  Addresses outside
//               NUM_SLOTS produce no downstream selection.
// ============================================================================
`include "edrv32_apb.vh"

module apb_mux #(
    parameter NUM_SLOTS = 64
)(
    // --- Clock and reset ---
    input  wire         pclk_i,
    input  wire         presetn_i,

    // --- Upstream APB (from bridge) ---
    input  wire [31:0]  up_paddr_i,
    input  wire         up_psel_i,
    input  wire         up_penable_i,
    input  wire         up_pwrite_i,
    input  wire [31:0]  up_pwdata_i,
    input  wire [3:0]   up_pstrb_i,

    output wire         up_pready_o,
    output wire [31:0]  up_prdata_o,
    output wire         up_pslverr_o,

    // --- Downstream APB slaves (NUM_SLOTS slots) ---
    output wire [NUM_SLOTS-1:0]   psel_o,
    output wire                   penable_o,
    output wire                   pwrite_o,
    output wire [31:0]            paddr_o,
    output wire [31:0]            pwdata_o,
    output wire [3:0]             pstrb_o,

    input  wire [NUM_SLOTS-1:0]   pready_i,
    input  wire [NUM_SLOTS*32-1:0] prdata_i,
    input  wire [NUM_SLOTS-1:0]   pslverr_i
);

    // ======================================================================
    // Slot decode
    // ======================================================================
    wire [5:0] slot_index_w;
    assign slot_index_w = up_paddr_i[17:12];

    // One-hot decode: only the selected slot gets psel
    wire [NUM_SLOTS-1:0] slot_sel_w;
    genvar gi;
    generate
        for (gi = 0; gi < NUM_SLOTS; gi = gi + 1) begin : gen_slot_decode
            assign slot_sel_w[gi] = up_psel_i && (slot_index_w == gi);
        end
    endgenerate

    assign psel_o = slot_sel_w;

    // Fan-out: all slots see the same address/control/data
    // Strip slot bits (paddr[17:12]) so each slave sees offset within its 4KiB window
    assign penable_o = up_penable_i;
    assign pwrite_o  = up_pwrite_i;
    assign paddr_o   = {20'd0, up_paddr_i[11:0]};
    assign pwdata_o  = up_pwdata_i;
    assign pstrb_o   = up_pstrb_i;

    // ======================================================================
    // Response mux: select from the active slot
    // ======================================================================
    reg        selected_pready_r;
    reg [31:0] selected_prdata_r;
    reg        selected_pslverr_r;
    integer    resp_slot_i;

    // Select by the bounded one-hot vector rather than indexing NUM_SLOTS
    // arrays with the raw six-bit address field.  Addresses in unimplemented
    // slots therefore return the neutral values below and are converted to an
    // error by the integration-level empty-slot responder.
    always @* begin
        selected_pready_r  = 1'b0;
        selected_prdata_r  = 32'h0;
        selected_pslverr_r = 1'b0;
        for (resp_slot_i = 0; resp_slot_i < NUM_SLOTS;
             resp_slot_i = resp_slot_i + 1) begin
            if (slot_sel_w[resp_slot_i]) begin
                selected_pready_r  = pready_i[resp_slot_i];
                selected_prdata_r  = prdata_i[resp_slot_i*32 +: 32];
                selected_pslverr_r = pslverr_i[resp_slot_i];
            end
        end
    end

    assign up_pready_o  = selected_pready_r;
    assign up_prdata_o  = selected_prdata_r;
    assign up_pslverr_o = selected_pslverr_r;

    wire unused_interface_w =
        ^{pclk_i, presetn_i, up_paddr_i[31:18]};

endmodule
