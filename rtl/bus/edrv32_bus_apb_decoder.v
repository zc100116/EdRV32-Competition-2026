// File: edrv32_bus_apb_decoder.v
// Spec: sys-subsys-spec 2.3, 3.2, 5, 6.
// Description: Decode sixteen APB slots and end an unacknowledged ACCESS after 256 cycles.
//              Reserved slot ready/error/data values are supplied by the caller.
// Clock domain: clk_sys.
module edrv32_bus_apb_decoder (
    // Local APB clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Undecoded upstream APB.
    input wire [15:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire [31:0] apb_prdata_o,
    output wire apb_pready_o,
    output wire apb_pslverr_o,

    // Slot APB interfaces; reserved slots are tied to ready/error at the caller.
    output wire [11:0] slot_paddr_o,
    output wire [15:0] slot_psel_o,
    output wire slot_penable_o,
    output wire slot_pwrite_o,
    output wire [31:0] slot_pwdata_o,
    output wire [3:0] slot_pstrb_o,
    input wire [511:0] slot_prdata_i,
    input wire [15:0] slot_pready_i,
    input wire [15:0] slot_pslverr_i
);
    reg [7:0] wait_cnt_r;
    wire timeout_w;
    wire [3:0] slot_w;

    assign slot_w = apb_paddr_i[15:12];
    assign slot_paddr_o = apb_paddr_i[11:0];
    assign slot_psel_o = apb_psel_i ? (16'b1 << slot_w) : 16'b0;
    assign slot_penable_o = apb_penable_i;
    assign slot_pwrite_o = apb_pwrite_i;
    assign slot_pwdata_o = apb_pwdata_i;
    assign slot_pstrb_o = apb_pstrb_i;
    // The first ACCESS edge is cycle 1; count 255 terminates at edge 256.
    assign timeout_w = (wait_cnt_r == 8'd255);
    assign apb_pready_o = slot_pready_i[slot_w] || timeout_w;
    assign apb_pslverr_o = slot_pslverr_i[slot_w] ||
        (timeout_w && !slot_pready_i[slot_w]);
    assign apb_prdata_o = (timeout_w && !slot_pready_i[slot_w]) ?
        32'b0 : slot_prdata_i[slot_w*32 +: 32];

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            wait_cnt_r <= 0;
        end else if (!apb_psel_i || !apb_penable_i || apb_pready_o) begin
            wait_cnt_r <= 0;
        end else begin
            wait_cnt_r <= wait_cnt_r + 1'b1;
        end
    end
endmodule
