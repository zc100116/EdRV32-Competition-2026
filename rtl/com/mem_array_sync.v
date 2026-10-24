// ============================================================================
// File        : mem_array_sync.v
// Author      : Edward ZC
// Description : Generic synchronous-read memory array contract used by cache
//               data arrays and intended for other large on-chip memories.
//               Read contract: when rd_en_i is asserted the read address is
//               sampled on the clock edge and the data is returned in the NEXT
//               cycle; when rd_en_i is low the output register holds its value
//               (response hold under backpressure).  Write contract: one write
//               port with a full-width byte strobe (all-ones selects a fast
//               full-word write, used by line refills; partial strobes
//               implement store byte merges).
// Notes       : Verilog-2001.  Storage is never reset (visibility is owned by
//               the surrounding valid/dirty metadata).  Simulation uses this
//               RTL model with exact one-cycle latency.  A Pango-specific
//               implementation must preserve this interface and is a separate
//               board-integration deliverable; it is not hidden in this file.
//               Callers must
//               not rely on same-edge read-during-write values (design §5.2
//               conservative store-port policy): the read returns the OLD data
//               if a write to the same address lands on the same edge.
// ============================================================================
// ============================================================================
// mem_array_sync - one gated synchronous read port + one byte-strobe write port
// ============================================================================
module mem_array_sync #(
    parameter integer DEPTH  = 256,   // number of storage words
    parameter integer DATA_W = 32,    // bits per storage word
    parameter integer ADDR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
    parameter integer BYTE_N = DATA_W / 8
)(
    // --- Clock ---
    input  wire                  clk,

    // --- Gated synchronous read port (data returned one cycle after rd_en) ---
    input  wire                  rd_en_i,
    input  wire [ADDR_W-1:0]           rd_addr_i,
    output wire [DATA_W-1:0]        rd_data_o,

    // --- Write port (byte strobe; all-ones = full word) ---
    input  wire                     wr_en_i,
    input  wire [ADDR_W-1:0]           wr_addr_i,
    input  wire [DATA_W-1:0]        wr_data_i,
    input  wire [BYTE_N-1:0]        wr_be_i
);

    reg [DATA_W-1:0] mem [0:DEPTH-1];
    reg [DATA_W-1:0] rd_data_r;

    always @(posedge clk) begin
        if (rd_en_i)
            rd_data_r <= mem[rd_addr_i[ADDR_W-1:0]];
    end

    assign rd_data_o = rd_data_r;

    wire [DATA_W-1:0] wr_mask_w;

    genvar byte_gv;
    generate
        for (byte_gv = 0; byte_gv < BYTE_N; byte_gv = byte_gv + 1) begin : gen_write_mask
            assign wr_mask_w[8*byte_gv +: 8] = {8{wr_be_i[byte_gv]}};
        end
    endgenerate

    always @(posedge clk) begin
        if (wr_en_i)
            // One procedural driver per memory word.  The explicit mask keeps
            // byte-write semantics while avoiding the multiple slice drivers
            // rejected by PDS 2022.2 during cache-array elaboration.
            mem[wr_addr_i[ADDR_W-1:0]] <=
                (mem[wr_addr_i[ADDR_W-1:0]] & ~wr_mask_w) |
                (wr_data_i & wr_mask_w);
    end

endmodule
