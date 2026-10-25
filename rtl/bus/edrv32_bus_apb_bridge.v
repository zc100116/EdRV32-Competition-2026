// File: edrv32_bus_apb_bridge.v
// Spec: sys-subsys-spec 2.3, 3.2, 5, 6.
// Description: Convert one aligned AXI word to APB; reject invalid requests without APB activity.
//              The destination decoder owns slot selection and the timeout.
// Clock domain: clk_sys.
module edrv32_bus_apb_bridge (
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
    input wire axi_rready_i,

    // Undecoded APB master.
    output wire [15:0] apb_paddr_o,
    output wire apb_psel_o,
    output wire apb_penable_o,
    output wire apb_pwrite_o,
    output wire [31:0] apb_pwdata_o,
    output wire [3:0] apb_pstrb_o,
    input wire [31:0] apb_prdata_i,
    input wire apb_pready_i,
    input wire apb_pslverr_i
);
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_WRITE = 3'd1;
    localparam [2:0] S_SETUP = 3'd2;
    localparam [2:0] S_ACCESS = 3'd3;
    localparam [2:0] S_READ_RESP = 3'd4;
    localparam [2:0] S_WRITE_RESP = 3'd5;
    reg [2:0] state_r;
    reg [7:0] remain_r;
    reg [3:0] id_r;
    reg [15:0] addr_r;
    reg write_r;
    reg invalid_r;
    reg [31:0] wr_data_r;
    reg [3:0] wr_strb_r;
    reg [63:0] rd_data_r;
    reg [1:0] resp_r;
    wire aw_fire_w;
    wire ar_fire_w;
    wire invalid_aw_w;
    wire invalid_ar_w;
    wire unused_w;

    assign axi_awready_o = (state_r == S_IDLE);
    assign axi_arready_o = (state_r == S_IDLE) && !axi_awvalid_i;
    assign aw_fire_w = axi_awvalid_i && axi_awready_o;
    assign ar_fire_w = axi_arvalid_i && axi_arready_o;
    assign invalid_aw_w = (axi_awlen_i != 0) || (axi_awsize_i != 2) ||
        (axi_awaddr_i[1:0] != 0);
    assign invalid_ar_w = (axi_arlen_i != 0) || (axi_arsize_i != 2) ||
        (axi_araddr_i[1:0] != 0);
    assign axi_wready_o = (state_r == S_WRITE);
    assign axi_bid_o = id_r;
    assign axi_bresp_o = resp_r;
    assign axi_bvalid_o = (state_r == S_WRITE_RESP);
    assign axi_rid_o = id_r;
    assign axi_rdata_o = rd_data_r;
    assign axi_rresp_o = resp_r;
    assign axi_rlast_o = (remain_r == 0);
    assign axi_rvalid_o = (state_r == S_READ_RESP);
    assign apb_paddr_o = addr_r;
    assign apb_psel_o = (state_r == S_SETUP) || (state_r == S_ACCESS);
    assign apb_penable_o = (state_r == S_ACCESS);
    assign apb_pwrite_o = write_r;
    assign apb_pwdata_o = wr_data_r;
    assign apb_pstrb_o = write_r ? wr_strb_r : 4'b0000;
    assign unused_w = &{1'b0, axi_awburst_i, axi_arburst_i, axi_awaddr_i[31:16],
        axi_araddr_i[31:16], axi_wlast_i};

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
                        state_r <= invalid_ar_w ? S_READ_RESP : S_SETUP;
                        remain_r <= axi_arlen_i;
                    end
                end
                S_WRITE: begin
                    if (axi_wvalid_i) begin
                        if (remain_r != 0) begin
                            remain_r <= remain_r - 1'b1;
                        end else begin
                            state_r <= invalid_r ? S_WRITE_RESP : S_SETUP;
                        end
                    end
                end
                S_SETUP: begin
                    state_r <= S_ACCESS;
                end
                S_ACCESS: begin
                    if (apb_pready_i) begin
                        state_r <= write_r ? S_WRITE_RESP : S_READ_RESP;
                    end
                end
                S_READ_RESP: begin
                    if (axi_rready_i) begin
                        if (remain_r == 0) begin
                            state_r <= S_IDLE;
                        end else begin
                            remain_r <= remain_r - 1'b1;
                        end
                    end
                end
                S_WRITE_RESP: begin
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

    always @(posedge clk_i) begin
        if (aw_fire_w) begin
            id_r <= axi_awid_i;
            addr_r <= axi_awaddr_i[15:0];
            write_r <= 1'b1;
            invalid_r <= invalid_aw_w;
            resp_r <= invalid_aw_w ? 2'b10 : 2'b00;
        end else if (ar_fire_w) begin
            id_r <= axi_arid_i;
            addr_r <= axi_araddr_i[15:0];
            write_r <= 1'b0;
            invalid_r <= invalid_ar_w;
            resp_r <= invalid_ar_w ? 2'b10 : 2'b00;
            rd_data_r <= 0;
        end else if ((state_r == S_ACCESS) && apb_pready_i) begin
            resp_r <= apb_pslverr_i ? 2'b10 : 2'b00;
            rd_data_r <= addr_r[2] ? {apb_prdata_i, 32'b0} : {32'b0, apb_prdata_i};
        end
        if ((state_r == S_WRITE) && axi_wvalid_i) begin
            wr_data_r <= addr_r[2] ? axi_wdata_i[63:32] : axi_wdata_i[31:0];
            wr_strb_r <= addr_r[2] ? axi_wstrb_i[7:4] : axi_wstrb_i[3:0];
        end
    end
endmodule
