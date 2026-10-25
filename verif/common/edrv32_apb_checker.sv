// File: edrv32_apb_checker.sv
// Spec: sys-subsys-testplan 2.1; SoC 4.3; sys-subsys 2.3, 5.
// Description: Check SETUP/ACCESS, one-hot selection and stalled payload.
// Clock domain: the observed APB PCLK.
module edrv32_apb_checker (
    input logic clk_i,
    input logic rst_n_i,
    edrv32_apb_if bus
);
    bit setup;
    bit waiting;
    int wait_cycles;
    logic [64:0] saved;
    wire [64:0] payload = {bus.psel, bus.paddr, bus.pwrite, bus.pwdata, bus.pstrb};
    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            setup <= 0;
            waiting <= 0;
            wait_cycles <= 0;
        end else begin
            if ((bus.psel & (bus.psel - 16'b1)) != 0)
                $fatal(1, "FAIL APB psel not one-hot actual=%h time=%0t", bus.psel, $time);
            if (bus.penable && bus.psel == 0)
                $fatal(1, "FAIL APB ACCESS without select time=%0t", $time);
            if (setup && (!bus.penable || payload != saved))
                $fatal(1, "FAIL APB SETUP/ACCESS expected=%h actual=%h time=%0t",
                        saved, payload, $time);
            if (bus.penable && bus.psel != 0 && !setup && !waiting)
                $fatal(1, "FAIL APB ACCESS without SETUP time=%0t", $time);
            // A timed-out transfer may end after its 256th ACCESS cycle (spec 2.3).
            if (waiting && wait_cycles < 256 &&
                (!bus.penable || payload != saved))
                $fatal(1, "FAIL APB wait hold expected=%h actual=%h time=%0t",
                        saved, payload, $time);
            setup <= bus.psel != 0 && !bus.penable;
            waiting <= bus.psel != 0 && bus.penable && !(|(bus.pready & bus.psel));
            if (bus.penable && bus.psel != 0) wait_cycles <= wait_cycles + 1;
            else wait_cycles <= 0;
            saved <= payload;
        end
    end
endmodule
