// ============================================================================
// File        : pango_ddr_ui_model.sv
// Description : Sparse-window behavioral model of the PG2L200H custom DDR UI.
// Notes       : There is intentionally no RREADY. AR/AW use bounded ready
//               stalls; read IDs can return in a different order. The model
//               stores 256-bit lines and applies 32-bit byte strobes. The
//               28-bit UI address indexes 32-bit memory words, not bytes.
// ============================================================================

module pango_ddr_ui_model #(
    parameter integer MEMORY_LINES = 8192,
    parameter integer RANDOM_STALL = 1,
    parameter integer INJECT_RERROR = 0,
    parameter integer ALLOW_AW_DURING_W = 0,
    parameter integer ALLOW_FIRST_W_WITH_AW = 0,
    parameter integer REVERSE_READ_DELAY = 0
)(
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         init_done_i,

    input  wire         awvalid_i,
    output wire         awready_o,
    input  wire [27:0]  awaddr_i,
    input  wire [3:0]   awlen_i,
    input  wire [3:0]   awid_i,
    input  wire [255:0] wdata_i,
    input  wire [31:0]  wstrb_i,
    output wire         wready_o,
    output wire [3:0]   wusero_id_o,
    output wire         wusero_last_o,
    input  wire         arvalid_i,
    output wire         arready_o,
    input  wire [27:0]  araddr_i,
    input  wire [3:0]   arlen_i,
    input  wire [3:0]   arid_i,
    output wire         rvalid_o,
    output wire [255:0] rdata_o,
    output wire [3:0]   rid_o,
    output wire         rlast_o,
    output wire         rerror_o,

    output wire [31:0]  write_count_o,
    output wire [31:0]  read_count_o
);

    reg [255:0] memory_r [0:MEMORY_LINES-1];
    reg [31:0] lfsr_r;
    reg wr_active_r;
    reg [27:0] wr_addr_r;
    reg [4:0] wr_left_r;
    reg [3:0] wr_id_r;
    reg wr_next_valid_r;
    reg [27:0] wr_next_addr_r;
    reg [4:0] wr_next_left_r;
    reg [3:0] wr_next_id_r;
    reg [15:0] read_delay_r [0:15];
    reg [27:0] read_addr_r [0:15];
    reg [4:0] read_left_r [0:15];
    reg [15:0] read_pending_r;
    reg read_active_r;
    reg [3:0] read_active_id_r;
    reg [31:0] write_count_r;
    reg [31:0] read_count_r;
    reg rerror_sent_r;
    integer model_i;
    integer byte_i;
    integer selected_id_i;

    wire random_ready_w = RANDOM_STALL ? (lfsr_r[2:0] != 3'b000) : 1'b1;
    assign awready_o = init_done_i && (!wr_active_r ||
                         (ALLOW_AW_DURING_W && !wr_next_valid_r)) && random_ready_w;
    wire first_write_with_aw_w = ALLOW_FIRST_W_WITH_AW &&
        awvalid_i && awready_o && !wr_active_r;
    assign wready_o  = init_done_i && random_ready_w &&
        (wr_active_r || first_write_with_aw_w);
    assign wusero_id_o = first_write_with_aw_w ? awid_i : wr_id_r;
    assign wusero_last_o = first_write_with_aw_w ?
        (awlen_i == 4'b0) : (wr_active_r && (wr_left_r == 5'd1));
    assign arready_o = init_done_i && random_ready_w;
    assign rvalid_o = read_active_r && (read_delay_r[read_active_id_r] == 0);
    assign rdata_o = memory_r[read_addr_r[read_active_id_r][27:3] % MEMORY_LINES];
    assign rid_o = read_active_id_r;
    assign rlast_o = read_active_r && (read_left_r[read_active_id_r] == 5'd1);
    // Optional one-shot error injection is a model-only test hook. It is not
    // presented as a real DDR_200H port by the FPGA adapter.
    assign rerror_o = INJECT_RERROR && rvalid_o && !rerror_sent_r;
    assign write_count_o = write_count_r;
    assign read_count_o = read_count_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            lfsr_r <= 32'h1ace_b00c;
            wr_active_r <= 1'b0;
            wr_addr_r <= 28'b0;
            wr_left_r <= 5'b0;
            wr_id_r <= 4'b0;
            wr_next_valid_r <= 1'b0;
            wr_next_addr_r <= 28'b0;
            wr_next_left_r <= 5'b0;
            wr_next_id_r <= 4'b0;
            read_pending_r <= 16'b0;
            read_active_r <= 1'b0;
            read_active_id_r <= 4'b0;
            write_count_r <= 32'b0;
            read_count_r <= 32'b0;
            rerror_sent_r <= 1'b0;
            for (model_i = 0; model_i < 16; model_i = model_i + 1) begin
                read_delay_r[model_i] <= 16'b0;
                read_addr_r[model_i] <= 28'b0;
                read_left_r[model_i] <= 5'b0;
            end
        end else begin
            lfsr_r <= {lfsr_r[30:0], lfsr_r[31] ^ lfsr_r[21] ^ lfsr_r[1] ^ lfsr_r[0]};

            if (INJECT_RERROR && rvalid_o)
                rerror_sent_r <= 1'b1;

            for (model_i = 0; model_i < 16; model_i = model_i + 1)
                if (read_pending_r[model_i] && (read_delay_r[model_i] != 0))
                    read_delay_r[model_i] <= read_delay_r[model_i] - 1'b1;

            if (awvalid_i && awready_o) begin
                if (awaddr_i[2:0] != 3'b0 ||
                    ({1'b0, awaddr_i[9:0]} +
                     (({7'b0, awlen_i} + 11'd1) << 3)) > 11'd1024)
                    $fatal(1, "Pango UI AW word-address alignment/4KiB violation");
                if (wr_active_r) begin
                    wr_next_valid_r <= 1'b1;
                    wr_next_addr_r <= awaddr_i;
                    wr_next_left_r <= awlen_i + 1'b1;
                    wr_next_id_r <= awid_i;
                end else begin
                    wr_active_r <= 1'b1;
                    wr_addr_r <= awaddr_i;
                    wr_left_r <= awlen_i + 1'b1;
                    wr_id_r <= awid_i;
                end
            end

            if (wready_o && first_write_with_aw_w) begin
                for (byte_i = 0; byte_i < 32; byte_i = byte_i + 1)
                    if (wstrb_i[byte_i])
                        memory_r[awaddr_i[27:3] % MEMORY_LINES][byte_i*8 +: 8] <=
                            wdata_i[byte_i*8 +: 8];
                write_count_r <= write_count_r + 1'b1;
                if (awlen_i == 4'b0) begin
                    wr_active_r <= 1'b0;
                    wr_left_r <= 5'b0;
                end else begin
                    wr_active_r <= 1'b1;
                    wr_addr_r <= awaddr_i + 28'd8;
                    wr_left_r <= {1'b0, awlen_i};
                    wr_id_r <= awid_i;
                end
            end else if (wready_o) begin
                for (byte_i = 0; byte_i < 32; byte_i = byte_i + 1)
                    if (wstrb_i[byte_i])
                        memory_r[wr_addr_r[27:3] % MEMORY_LINES][byte_i*8 +: 8] <=
                            wdata_i[byte_i*8 +: 8];
                write_count_r <= write_count_r + 1'b1;
                if (wr_left_r == 5'd1) begin
                    if (wr_next_valid_r) begin
                        wr_active_r <= 1'b1;
                        wr_addr_r <= wr_next_addr_r;
                        wr_left_r <= wr_next_left_r;
                        wr_id_r <= wr_next_id_r;
                        wr_next_valid_r <= 1'b0;
                    end else if (awvalid_i && awready_o && wr_active_r) begin
                        wr_active_r <= 1'b1;
                        wr_addr_r <= awaddr_i;
                        wr_left_r <= awlen_i + 1'b1;
                        wr_id_r <= awid_i;
                        // The AW block also sees wr_active_r high in this
                        // cycle and tentatively fills the next slot. This
                        // direct handoff consumes that same command now, so
                        // it must not remain queued for a second execution.
                        wr_next_valid_r <= 1'b0;
                    end else begin
                        wr_active_r <= 1'b0;
                        wr_left_r <= 5'b0;
                    end
                end else begin
                    wr_left_r <= wr_left_r - 1'b1;
                    wr_addr_r <= wr_addr_r + 28'd8;
                end
            end

            if (arvalid_i && arready_o) begin
                if (araddr_i[2:0] != 3'b0 ||
                    ({1'b0, araddr_i[9:0]} +
                     (({7'b0, arlen_i} + 11'd1) << 3)) > 11'd1024)
                    $fatal(1, "Pango UI AR word-address alignment/4KiB violation");
                read_pending_r[arid_i] <= 1'b1;
                read_addr_r[arid_i] <= araddr_i;
                read_left_r[arid_i] <= arlen_i + 1'b1;
                read_delay_r[arid_i] <= REVERSE_READ_DELAY ?
                    (arid_i[0] ? 16'd1 : 16'd30) :
                    16'd1 + {13'b0, arid_i[2:0]};
            end

            if (rvalid_o) begin
                read_count_r <= read_count_r + 1'b1;
                if (read_left_r[read_active_id_r] == 5'd1) begin
                    read_pending_r[read_active_id_r] <= 1'b0;
                    read_active_r <= 1'b0;
                    read_left_r[read_active_id_r] <= 5'b0;
                end else begin
                    read_left_r[read_active_id_r] <= read_left_r[read_active_id_r] - 1'b1;
                    read_addr_r[read_active_id_r] <= read_addr_r[read_active_id_r] + 28'd8;
                end
            end

            if (!read_active_r) begin
                selected_id_i = -1;
                for (model_i = 15; model_i >= 0; model_i = model_i - 1)
                    if ((selected_id_i < 0) && read_pending_r[model_i] &&
                        (read_delay_r[model_i] == 0))
                        selected_id_i = model_i;
                if (selected_id_i >= 0) begin
                    read_active_r <= 1'b1;
                    read_active_id_r <= selected_id_i[3:0];
                end
            end
        end
    end

endmodule
