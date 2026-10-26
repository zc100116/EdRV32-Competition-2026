// File: pango_ddr3_ip_model.sv
// Spec: mem-subsys-spec Appendix A; mem-subsys-testplan AD-01.
// Description: Ordered DDR3 user-port model with byte strobes and bounded stalls.
//              A word address names four bytes; each data beat advances 8 words.
// Clock domain: core_clk (the testbench supplies the IP user clock).
// This models user ports only, not the PHY, reference-clock PLL or APB/debug ports.
// One command executes at a time, preserving write-before-later-read visibility.
// WUSER_DELAY=0 marks the last sampled beat; positive values delay that pulse
// until WREADY is low, exercising B synthesis without coupling it to WREADY.
// Memory is deliberately not reset/initialized: tests write before reading.
module pango_ddr3_ip_model #(
    parameter integer MEMORY_BYTES = 65536,
    parameter integer INIT_CYCLES = 8,
    parameter integer COMMAND_LATENCY = 3,
    parameter integer WUSER_DELAY = 0
) (
    // Clock/reset supplied by the board simulation.
    input wire core_clk_i,
    input wire resetn_i,

    // IP user-port template signals; direction suffixes follow CLAUDE.md.
    input wire [27:0] axi_awaddr_i,
    input wire axi_awuser_ap_i,
    input wire [3:0] axi_awuser_id_i,
    input wire [3:0] axi_awlen_i,
    input wire axi_awvalid_i,
    output wire axi_awready_o,
    input wire [255:0] axi_wdata_i,
    input wire [31:0] axi_wstrb_i,
    output wire axi_wready_o,
    output wire [3:0] axi_wusero_id_o,
    output wire axi_wusero_last_o,
    input wire [27:0] axi_araddr_i,
    input wire axi_aruser_ap_i,
    input wire [3:0] axi_aruser_id_i,
    input wire [3:0] axi_arlen_i,
    input wire axi_arvalid_i,
    output wire axi_arready_o,
    output wire [3:0] axi_rid_o,
    output wire [255:0] axi_rdata_o,
    output wire axi_rlast_o,
    output wire axi_rvalid_o,

    // IP initialization status.
    output wire ddr_init_done_o
);

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_WRITE = 2'd1;
    localparam [1:0] S_READ = 2'd2;
    localparam [1:0] S_COMPLETE = 2'd3;

    reg [1:0] state_r;
    integer init_count_r;
    integer delay_r;
    reg [31:0] lfsr_r;
    reg [27:0] addr_r;
    reg [4:0] left_r;
    reg [3:0] id_r;
    reg [7:0] memory_r [0:MEMORY_BYTES-1];
    integer lane;
    wire command_ready_w = ddr_init_done_o && (state_r == S_IDLE) && lfsr_r[0];
    wire last_write_w = axi_wready_o && (left_r == 5'd1);
    wire unused_ap_w = &{1'b0, axi_awuser_ap_i, axi_aruser_ap_i};

    assign ddr_init_done_o = init_count_r == INIT_CYCLES;
    assign axi_awready_o = command_ready_w;
    assign axi_arready_o = command_ready_w && !axi_awvalid_i;
    assign axi_wready_o = (state_r == S_WRITE) && (delay_r == 0) && lfsr_r[1];
    assign axi_wusero_id_o = id_r;
    assign axi_wusero_last_o = (WUSER_DELAY == 0) ? last_write_w :
        ((state_r == S_COMPLETE) && (delay_r == 0));
    assign axi_rvalid_o = (state_r == S_READ) && (delay_r == 0) && lfsr_r[2];
    assign axi_rid_o = id_r;
    assign axi_rlast_o = left_r == 5'd1;
    genvar g;
    generate
        for (g = 0; g < 32; g = g + 1) begin : g_read_byte
            assign axi_rdata_o[g*8 +: 8] = memory_r[{2'b00, addr_r, 2'b00} + g];
        end
    endgenerate

    always @(posedge core_clk_i or negedge resetn_i) begin
        if (!resetn_i) begin
            state_r <= S_IDLE;
            init_count_r <= 0;
            delay_r <= 0;
            lfsr_r <= 32'h1234_abcd;
            left_r <= 0;
        end else begin
            if (init_count_r < INIT_CYCLES)
                init_count_r <= init_count_r + 1;
            lfsr_r <= {lfsr_r[30:0], lfsr_r[31] ^ lfsr_r[21] ^ lfsr_r[1] ^ lfsr_r[0]};
            if (delay_r > 0)
                delay_r <= delay_r - 1;
            case (state_r)
                S_IDLE: begin
                    if (axi_awvalid_i && axi_awready_o) begin
                        state_r <= S_WRITE;
                        delay_r <= COMMAND_LATENCY;
                        left_r <= {1'b0, axi_awlen_i} + 5'd1;
                    end else if (axi_arvalid_i && axi_arready_o) begin
                        state_r <= S_READ;
                        delay_r <= COMMAND_LATENCY;
                        left_r <= {1'b0, axi_arlen_i} + 5'd1;
                    end
                end
                S_WRITE: begin
                    if (axi_wready_o) begin
                        left_r <= left_r - 5'd1;
                        if (last_write_w) begin
                            state_r <= (WUSER_DELAY == 0) ? S_IDLE : S_COMPLETE;
                            delay_r <= WUSER_DELAY;
                        end
                    end
                end
                S_READ: begin
                    if (axi_rvalid_o) begin
                        left_r <= left_r - 5'd1;
                        if (axi_rlast_o)
                            state_r <= S_IDLE;
                    end
                end
                S_COMPLETE: begin
                    if (delay_r == 0)
                        state_r <= S_IDLE;
                end
                default: state_r <= S_IDLE;
            endcase
        end
    end

    // Payload is not reset; each accepted command owns the following data beats.
    always @(posedge core_clk_i) begin
        if (axi_awvalid_i && axi_awready_o) begin
            addr_r <= axi_awaddr_i;
            id_r <= axi_awuser_id_i;
        end else if (axi_arvalid_i && axi_arready_o) begin
            addr_r <= axi_araddr_i;
            id_r <= axi_aruser_id_i;
        end else if (axi_wready_o || axi_rvalid_o) begin
            addr_r <= addr_r + 28'd8;
        end
        if (axi_wready_o) begin
            for (lane = 0; lane < 32; lane = lane + 1)
                if (axi_wstrb_i[lane])
                    memory_r[{2'b00, addr_r, 2'b00} + lane] <= axi_wdata_i[lane*8 +: 8];
        end
    end
endmodule
