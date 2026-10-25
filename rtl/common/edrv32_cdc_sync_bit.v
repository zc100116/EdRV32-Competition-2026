// File: edrv32_cdc_sync_bit.v
// Spec: edrv32-soc-spec 5.2, 5.3; infra-plan I-06
// Description: Two-stage synchronizer for a stable level control signal.
//              Interface and use constraints are in rtl/common/README.md.
// Clock domain: ports identify the source and destination clocks.
module edrv32_cdc_sync_bit (
    // Destination clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Asynchronous input level.
    input wire bit_i,

    // Destination-domain level.
    output wire bit_o
);
    reg meta_r;
    reg sync_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            meta_r <= 1'b0;
            sync_r <= 1'b0;
        end else begin
            meta_r <= bit_i;
            sync_r <= meta_r;
        end
    end

    assign bit_o = sync_r;
endmodule
