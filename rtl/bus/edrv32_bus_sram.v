// File: edrv32_bus_sram.v
// Spec: sys-subsys-spec 2.2, 3.2, 5, 6, 7.
// Description: Serialize AXI transactions onto the single synchronous memory port.
//              WSTRB selects bytes; complete transactions share one physical port.
// Clock domain: clk_sys.
module edrv32_bus_sram (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // axi AW channel.
    input wire [3:0] axi_awid_i,
    input wire [31:0] axi_awaddr_i,
    input wire [7:0] axi_awlen_i,
    input wire [2:0] axi_awsize_i,
    input wire [1:0] axi_awburst_i,
    input wire axi_awvalid_i,
    output wire axi_awready_o,

    // axi W channel.
    input wire [63:0] axi_wdata_i,
    input wire [7:0] axi_wstrb_i,
    input wire axi_wlast_i,
    input wire axi_wvalid_i,
    output wire axi_wready_o,

    // axi B channel.
    output wire [3:0] axi_bid_o,
    output wire [1:0] axi_bresp_o,
    output wire axi_bvalid_o,
    input wire axi_bready_i,

    // axi AR channel.
    input wire [3:0] axi_arid_i,
    input wire [31:0] axi_araddr_i,
    input wire [7:0] axi_arlen_i,
    input wire [2:0] axi_arsize_i,
    input wire [1:0] axi_arburst_i,
    input wire axi_arvalid_i,
    output wire axi_arready_o,

    // axi R channel.
    output wire [3:0] axi_rid_o,
    output wire [63:0] axi_rdata_o,
    output wire [1:0] axi_rresp_o,
    output wire axi_rlast_o,
    output wire axi_rvalid_o,
    input wire axi_rready_i
);
    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_READ = 2'd1;
    localparam [1:0] S_WRITE = 2'd2;
    localparam [1:0] S_RESP = 2'd3;
    reg [1:0] state_r;
    reg [7:0] remain_r;
    reg [31:0] addr_r;
    reg [31:0] step_r;
    reg [3:0] id_r;
    wire ar_fire_w;
    wire aw_fire_w;
    wire rd_next_w;
    wire wr_fire_w;
    wire [31:0] port_addr_w;
    wire [63:0] rd_data_w;
    wire unused_w;

    // The AW preference serializes overlapping requests at the single memory port.
    assign axi_awready_o = (state_r == S_IDLE);
    assign axi_arready_o = (state_r == S_IDLE) && !axi_awvalid_i;
    assign aw_fire_w = axi_awvalid_i && axi_awready_o;
    assign ar_fire_w = axi_arvalid_i && axi_arready_o;
    assign axi_wready_o = (state_r == S_WRITE);
    assign wr_fire_w = axi_wvalid_i && axi_wready_o;
    assign axi_rvalid_o = (state_r == S_READ);
    assign axi_rlast_o = (remain_r == 0);
    assign axi_rid_o = id_r;
    assign axi_rdata_o = rd_data_w;
    assign axi_rresp_o = 2'b00;
    assign axi_bid_o = id_r;
    assign axi_bvalid_o = (state_r == S_RESP);
    assign axi_bresp_o = 2'b00;
    assign rd_next_w = (state_r == S_READ) && axi_rready_i && (remain_r != 0);
    assign port_addr_w = ar_fire_w ? axi_araddr_i : addr_r;
    assign unused_w = &{1'b0, axi_awburst_i, axi_arburst_i, axi_wlast_i,
        port_addr_w[31:18], port_addr_w[2:0]};

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            remain_r <= 0;
        end else begin
            case (state_r)
                S_IDLE: begin
                    if (aw_fire_w) begin
                        state_r <= S_WRITE;
                        remain_r <= axi_awlen_i;
                    end else if (ar_fire_w) begin
                        state_r <= S_READ;
                        remain_r <= axi_arlen_i;
                    end
                end
                S_READ: begin
                    if (axi_rready_i) begin
                        if (remain_r == 0) begin
                            state_r <= S_IDLE;
                        end else begin
                            remain_r <= remain_r - 1'b1;
                        end
                    end
                end
                S_WRITE: begin
                    if (wr_fire_w) begin
                        if (remain_r == 0) begin
                            state_r <= S_RESP;
                        end else begin
                            remain_r <= remain_r - 1'b1;
                        end
                    end
                end
                S_RESP: begin
                    if (axi_bready_i) begin
                        state_r <= S_IDLE;
                    end
                end
                default: begin
                    state_r <= S_IDLE;
                end
            endcase
        end
    end

    // Only control resets; address, ID, stride and memory data remain unreset.
    always @(posedge clk_i) begin
        if (aw_fire_w) begin
            id_r <= axi_awid_i;
            addr_r <= axi_awaddr_i;
            step_r <= 32'd1 << axi_awsize_i;
        end else if (ar_fire_w) begin
            id_r <= axi_arid_i;
            addr_r <= axi_araddr_i + (32'd1 << axi_arsize_i);
            step_r <= 32'd1 << axi_arsize_i;
        end else if (rd_next_w || wr_fire_w) begin
            addr_r <= addr_r + step_r;
        end
    end

    edrv32_ram_sram u_memory (
        // Single physical memory port.
        .clk_i(clk_i),
        .en_i(ar_fire_w || rd_next_w || wr_fire_w),
        .wr_en_i({8{wr_fire_w}} & axi_wstrb_i),
        .wr_data_i(axi_wdata_i),
        .addr_i(port_addr_w[17:3]),
        .rd_data_o(rd_data_w)
    );
endmodule
