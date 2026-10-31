// File: edrv32_drm_level_probe.sv
// Spec: npu-spec 5.2; vin-spec 2.6; disp-spec 2.6; Task T-DRM1.
// Description: Passive lifetime and reset-separated occupancy/live row peak measurement.
// Only samples valid observation cycles; does not change any test verdict.
// Clock domain: the measured owner's domain.
module edrv32_drm_level_probe (
    input wire clk_i,
    input wire valid_i,
    input wire [31:0] level_i
);
    reg [31:0] peak_r = 0;
    reg [31:0] segment_peak_r = 0;
    always @(posedge clk_i or negedge valid_i) begin
        if (!valid_i) segment_peak_r <= 0;
        else begin
            if (level_i > peak_r) peak_r <= level_i;
            if (level_i > segment_peak_r) segment_peak_r <= level_i;
        end
    end
    always @(negedge valid_i) begin
        $display("DRM_SEGMENT %m peak=%0d time=%0t", segment_peak_r, $time);
    end
    final $display("DRM_LEVEL %m peak=%0d segment_peak=%0d", peak_r, segment_peak_r);
endmodule
