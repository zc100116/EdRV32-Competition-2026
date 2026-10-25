// File: edrv32_reset_sync.v
// Spec: edrv32-soc-spec 5.2, 5.3; infra-plan I-06
// Description: Asynchronous reset assertion with two-clock synchronous release.
//              Interface and use constraints are in rtl/common/README.md.
// Clock domain: ports identify the source and destination clocks.
module edrv32_reset_sync (
    // Clock and asynchronous reset.
    input wire clk_i,
    input wire rst_n_i,

    // Reset released in this clock domain.
    output wire rst_n_o
);
    reg release_meta_r;
    reg release_sync_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            release_meta_r <= 1'b0;
            release_sync_r <= 1'b0;
        end else begin
            release_meta_r <= 1'b1;
            release_sync_r <= release_meta_r;
        end
    end

    assign rst_n_o = release_sync_r;
endmodule
