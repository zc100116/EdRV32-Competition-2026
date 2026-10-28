// File: edrv32_boot_window.sv
// Spec: edrv32-soc-spec 7.5(3); B1-8 coordinator-approved simulation acceleration.
// Description: Observe three real KEY1 reads before advancing only the CLINT testbench time.
//              Optionally release KEY1 for one sample to check the sticky release decision.
// Clock domain: clk_sys.
module edrv32_boot_window (
    input wire clk_i,
    input wire rst_n_i,
    input wire enable_i,
    input wire release_once_i,
    input wire sample_i,
    input wire [63:0] time_i,
    input wire [31:0] clock_hz_i,
    output reg advance_o,
    output reg [63:0] time_o,
    output reg key_released_o
);
    reg [2:0] samples_r;
    reg [63:0] first_sample_time_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            samples_r <= 0;
            first_sample_time_r <= 0;
            advance_o <= 0;
            time_o <= 0;
            key_released_o <= 0;
        end else begin
            advance_o <= 0;
            if (sample_i && samples_r < 3) begin
                samples_r <= samples_r + 1'b1;
                if (samples_r == 0) begin
                    first_sample_time_r <= time_i;
                    key_released_o <= release_once_i;
                end
                if (samples_r == 1) key_released_o <= 0;
                if (samples_r == 2 && enable_i) begin
                    // Stay before the deadline, leaving thousands of cycles of real sampling.
                    time_o <= first_sample_time_r + 64'(clock_hz_i) / 10 - 4096;
                    advance_o <= 1;
                end
            end
        end
    end
endmodule
