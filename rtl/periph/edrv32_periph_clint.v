// File: edrv32_periph_clint.v
// Spec: sys-subsys-spec 2.4, 4.1, 5, 6.
// Description: Machine time, timer comparison and software interrupt registers.
//              AXI64 accepts single-beat SIZE=2 register accesses.
// Clock domain: clk_sys.
module edrv32_periph_clint (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // AXI64 slave write address.
    input wire [3:0] axi_awid_i,
    input wire [31:0] axi_awaddr_i,
    input wire [7:0] axi_awlen_i,
    input wire [2:0] axi_awsize_i,
    input wire [1:0] axi_awburst_i,
    input wire axi_awvalid_i,
    output wire axi_awready_o,

    // AXI64 slave write data and response.
    input wire [63:0] axi_wdata_i,
    input wire [7:0] axi_wstrb_i,
    input wire axi_wlast_i,
    input wire axi_wvalid_i,
    output wire axi_wready_o,
    output reg [3:0] axi_bid_o,
    output reg [1:0] axi_bresp_o,
    output reg axi_bvalid_o,
    input wire axi_bready_i,

    // AXI64 slave read address and response.
    input wire [3:0] axi_arid_i,
    input wire [31:0] axi_araddr_i,
    input wire [7:0] axi_arlen_i,
    input wire [2:0] axi_arsize_i,
    input wire [1:0] axi_arburst_i,
    input wire axi_arvalid_i,
    output wire axi_arready_o,
    output reg [3:0] axi_rid_o,
    output reg [63:0] axi_rdata_o,
    output reg [1:0] axi_rresp_o,
    output wire axi_rlast_o,
    output reg axi_rvalid_o,
    input wire axi_rready_i,

    // CPU timer and interrupt outputs.
    output wire [63:0] mtime_o,
    output reg irq_mtip_o,
    output wire irq_msip_o
);
    // Address-map constants unused by this device are shared with other users.
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    /* verilator lint_on UNUSEDPARAM */
    reg write_active_r;
    reg write_error_r;
    reg [31:0] write_offset_r;
    reg [3:0] write_id_r;
    reg [7:0] write_left_r;
    reg [7:0] read_left_r;
    reg [31:0] read_data_w;
    wire [31:0] read_offset_w;
    wire [31:0] write_data_w;
    wire read_error_w;
    wire read_accept_w;
    wire write_accept_w;
    wire register_write_w;
    wire unused_w;

    // SIZE=2 writes from D$ select the complete addressed 32-bit half.
    assign unused_w = &{1'b0, axi_awburst_i, axi_arburst_i, axi_wlast_i, axi_wstrb_i};
    assign axi_awready_o = !write_active_r && !axi_bvalid_o;
    assign axi_wready_o = write_active_r;
    assign axi_arready_o = !axi_rvalid_o;
    assign axi_rlast_o = read_left_r == 8'd0;
    assign read_accept_w = axi_arvalid_i && axi_arready_o;
    assign write_accept_w = axi_wvalid_i && axi_wready_o;
    assign register_write_w = write_accept_w && !write_error_r;
    assign read_offset_w = axi_araddr_i - EDRV32_CLINT_BASE;
    assign write_data_w = write_offset_r[2] ? axi_wdata_i[63:32] : axi_wdata_i[31:0];
    assign read_error_w = axi_arlen_i != 8'd0 || axi_arsize_i != 3'd2;

    // spec 6: reject the whole illegal transaction, draining every write beat.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            write_active_r <= 1'b0;
            axi_bvalid_o <= 1'b0;
            axi_rvalid_o <= 1'b0;
            write_left_r <= 8'd0;
            read_left_r <= 8'd0;
        end else begin
            if (axi_awvalid_i && axi_awready_o) begin
                write_active_r <= 1'b1;
                write_left_r <= axi_awlen_i;
            end
            if (write_accept_w) begin
                if (write_left_r == 8'd0) begin
                    write_active_r <= 1'b0;
                    axi_bvalid_o <= 1'b1;
                end else begin
                    write_left_r <= write_left_r - 1'b1;
                end
            end
            if (axi_bvalid_o && axi_bready_i) begin
                axi_bvalid_o <= 1'b0;
            end
            if (read_accept_w) begin
                axi_rvalid_o <= 1'b1;
                read_left_r <= axi_arlen_i;
            end else if (axi_rvalid_o && axi_rready_i) begin
                if (read_left_r == 8'd0) begin
                    axi_rvalid_o <= 1'b0;
                end else begin
                    read_left_r <= read_left_r - 1'b1;
                end
            end
        end
    end
    // Payload is written only when owned, and held throughout response stalls.
    always @(posedge clk_i) begin
        if (axi_awvalid_i && axi_awready_o) begin
            write_offset_r <= axi_awaddr_i - EDRV32_CLINT_BASE;
            write_id_r <= axi_awid_i;
            write_error_r <= axi_awlen_i != 8'd0 || axi_awsize_i != 3'd2;
        end
        if (write_accept_w && write_left_r == 8'd0) begin
            axi_bid_o <= write_id_r;
            axi_bresp_o <= write_error_r ? 2'b10 : 2'b00;
        end
        if (read_accept_w) begin
            axi_rid_o <= axi_arid_i;
            axi_rresp_o <= read_error_w ? 2'b10 : 2'b00;
            axi_rdata_o <= read_error_w ? 64'd0 :
                            (read_offset_w[2] ? {read_data_w, 32'd0} :
                                                {32'd0, read_data_w});
        end
    end
    reg [63:0] mtime_r;
    reg [63:0] mtimecmp_r;
    reg msip_r;
    wire [63:0] mtime_next_w;

    assign mtime_o = mtime_r;
    assign irq_msip_o = msip_r;
    assign mtime_next_w = mtime_r + 64'd1;

    always @(*) begin
        read_data_w = 32'd0;
        case (read_offset_w)
            32'h00000000: read_data_w = {31'd0, msip_r};
            32'h00004000: read_data_w = mtimecmp_r[31:0];
            32'h00004004: read_data_w = mtimecmp_r[63:32];
            32'h0000BFF8: read_data_w = mtime_r[31:0];
            32'h0000BFFC: read_data_w = mtime_r[63:32];
            default: read_data_w = 32'd0;
        endcase
    end
    // spec 4.1: the unwritten half retains its normally incremented value.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            mtime_r <= 64'd0;
            mtimecmp_r <= 64'hFFFFFFFFFFFFFFFF;
            msip_r <= 1'b0;
            irq_mtip_o <= 1'b0;
        end else begin
            mtime_r <= mtime_next_w;
            irq_mtip_o <= mtime_r >= mtimecmp_r;
            if (register_write_w) begin
                case (write_offset_r)
                    32'h00000000: msip_r <= write_data_w[0];
                    32'h00004000: mtimecmp_r[31:0] <= write_data_w;
                    32'h00004004: mtimecmp_r[63:32] <= write_data_w;
                    32'h0000BFF8: mtime_r <= {mtime_next_w[63:32], write_data_w};
                    32'h0000BFFC: mtime_r <= {write_data_w, mtime_next_w[31:0]};
                    default: begin end
                endcase
            end
        end
    end
endmodule
