// File: edrv32_cdc_pulse.v
// Spec: edrv32-soc-spec 5.2, 5.3; infra-plan I-06
// Description: Transfer a spaced source pulse through a synchronized toggle.
//              Interface and use constraints are in rtl/common/README.md.
// Clock domain: ports identify the source and destination clocks.
module edrv32_cdc_pulse (
    // Clock domains and their resets.
    input wire clk_src_i,
    input wire rst_src_n_i,
    input wire clk_dst_i,
    input wire rst_dst_n_i,

    // Source event.
    input wire pulse_i,

    // One destination-cycle event.
    output wire pulse_o
);
    reg toggle_r;
    reg previous_r;
    wire toggle_w;

    always @(posedge clk_src_i or negedge rst_src_n_i) begin
        if (!rst_src_n_i) begin
            toggle_r <= 1'b0;
        end else if (pulse_i) begin
            toggle_r <= ~toggle_r;
        end
    end

    edrv32_cdc_sync_bit u_toggle (
        // Destination clock and reset.
        .clk_i(clk_dst_i),
        .rst_n_i(rst_dst_n_i),

        // Event toggle.
        .bit_i(toggle_r),
        .bit_o(toggle_w)
    );

    always @(posedge clk_dst_i or negedge rst_dst_n_i) begin
        if (!rst_dst_n_i) begin
            previous_r <= 1'b0;
        end else begin
            previous_r <= toggle_w;
        end
    end

    assign pulse_o = toggle_w ^ previous_r;
endmodule
