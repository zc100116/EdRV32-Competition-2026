// File: edrv32_reset_copy.v
// Spec: sys-subsys-spec 2.10; edrv32-soc-spec 5.3 item 5.
// Description: Replicate a domain reset with asynchronous assertion and
//              one additional destination clock before release.
// Clock domain: clk_i.
module edrv32_reset_copy (
    // Clock and active-low domain reset.
    input wire clk_i,
    input wire rst_n_i,

    // Regional reset released on the next domain clock.
    output reg rst_n_o
);
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rst_n_o <= 1'b0;
        end else begin
            rst_n_o <= 1'b1;
        end
    end
endmodule
