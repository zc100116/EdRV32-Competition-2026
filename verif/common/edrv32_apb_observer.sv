// File: edrv32_apb_observer.sv
// Spec: sys-subsys-testplan 2.1; sys-subsys 3.2.
// Description: Passive adapter for a decoder's full sixteen-slot APB boundary.
// Clock domain: the observed APB domain.
module edrv32_apb_observer #(parameter bit COUNT_USED = 0) (
    input logic clk_i,
    input logic rst_n_i,
    input logic [11:0] paddr_i,
    input logic [15:0] psel_i,
    input logic penable_i,
    input logic pwrite_i,
    input logic [31:0] pwdata_i,
    input logic [3:0] pstrb_i,
    input logic [511:0] prdata_i,
    input logic [15:0] pready_i,
    input logic [15:0] pslverr_i
);
    edrv32_apb_if bus();
    assign bus.paddr = paddr_i;
    assign bus.psel = psel_i;
    assign bus.penable = penable_i;
    assign bus.pwrite = pwrite_i;
    assign bus.pwdata = pwdata_i;
    assign bus.pstrb = pstrb_i;
    assign bus.prdata = prdata_i;
    assign bus.pready = pready_i;
    assign bus.pslverr = pslverr_i;
    always @(posedge clk_i)
        if (rst_n_i && psel_i != 0 && !penable_i)
            edrv32_apb_observation_pkg::setup_seen(COUNT_USED);
    // Timing checks do not constrain the value of an APB read/error payload.
    wire unused_read_payload = &{bus.prdata, bus.pslverr};
    edrv32_apb_checker u_check (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .bus(bus)
    );
endmodule
