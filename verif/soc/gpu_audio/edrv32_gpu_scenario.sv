// File: edrv32_gpu_scenario.sv
// Spec: gpu-soc-testplan ST-12; aud-spec 2.5; ES8156 datasheet registers 02/08/11.
// Description: Independently compare I2C configuration writes and 256 stereo samples.
// Clock domain: clk_sys I2C observation; clk_aud I2S observation.
`timescale 1ns/1ps
/* verilator lint_off BLKSEQ */
module edrv32_gpu_scenario (
    output bit checks_complete_o,
    output wire [1:0] model_sda_oe_o
);
    wire codec_ack;
    wire codec_write;
    wire [7:0] codec_reg;
    wire [7:0] codec_value;
    wire [31:0] audio_sample;
    wire sample_valid;
    integer codec_count;
    integer samples_checked;
    integer writes_checked;
    bit started;
    bit armed;
    logic [31:0] expected [0:255];
    logic [15:0] expected_codec [0:26];
    assign model_sda_oe_o = {1'b0, codec_ack};

    i2c_rx_model u_codec (
        .clk_i($root.edrv32_gpu_soc_tb.clk_sys_i),
        .rst_n_i($root.edrv32_gpu_soc_tb.rst_n_i),
        .scl_i($root.edrv32_gpu_soc_tb.i2c0_scl_i[0]),
        .sda_i($root.edrv32_gpu_soc_tb.i2c0_sda_i[0]),
        .sda_oe_o(codec_ack),
        .write_valid_o(codec_write),
        .register_o(codec_reg),
        .value_o(codec_value),
        .write_count_o(codec_count)
    );
    i2s_rx_model u_audio (
        .clk_aud_i($root.edrv32_gpu_soc_tb.clk_aud_i),
        .rst_n_i($root.edrv32_gpu_soc_tb.rst_n_i),
        .bclk_i($root.edrv32_gpu_soc_tb.aud_bclk_o),
        .lrck_i($root.edrv32_gpu_soc_tb.aud_lrck_o),
        .sdata_i($root.edrv32_gpu_soc_tb.aud_sdata_o),
        .sample_o(audio_sample),
        .sample_valid_o(sample_valid)
    );
    initial begin
        checks_complete_o = 0;
        samples_checked = 0;
        writes_checked = 0;
        started = 0;
        armed = 0;
        #1;
        $readmemh({$root.edrv32_gpu_soc_tb.data_dir, "/audio.hex"}, expected);
        // Independent manufacturer sequence, modified for slave and 16-bit standard I2S.
        expected_codec = '{16'h1000, 16'h003c, 16'h0005, 16'h001c, 16'h0204,
            16'h0301, 16'h0400, 16'h0508, 16'h0600, 16'h082b, 16'h1300,
            16'h202a, 16'h213c, 16'h2202, 16'h2407, 16'h233a, 16'h0a01,
            16'h0b01, 16'h14bd, 16'h0121, 16'h0d14, 16'h1800, 16'h082f,
            16'h2520, 16'h0002, 16'h0003, 16'h1130};
        armed = 1;
        wait (samples_checked == 256);
        if (writes_checked != 27 || codec_count != 27)
            $fatal(1, "FAIL codec writes expected=27 actual=%0d time=%0t", codec_count, $time);
        wait ($root.edrv32_gpu_soc_tb.u_ddr.peek(32'h003ff000) == 12);
        $root.edrv32_gpu_soc_tb.u_ddr.poke(32'h003ff004, 8'd1);
        checks_complete_o = 1;
        $display("CHECK ST-12 I2C writes=27 I2S stereo frames=256");
    end
    always @(posedge $root.edrv32_gpu_soc_tb.clk_sys_i) begin
        #0.002;
        if (armed && codec_write) begin
            if (writes_checked >= 27 || {codec_reg, codec_value} != expected_codec[writes_checked])
                $fatal(1, "FAIL codec write=%0d reg/value=%h time=%0t",
                    writes_checked, {codec_reg, codec_value}, $time);
            writes_checked++;
        end
    end
    always @(posedge $root.edrv32_gpu_soc_tb.clk_aud_i) begin
        #0.002;
        if (armed && sample_valid && samples_checked < 256) begin
            if (audio_sample != 0) started = 1;
            if (started) begin
                if (audio_sample !== expected[samples_checked])
                    $fatal(1, "FAIL I2S frame=%0d expected=%h actual=%h time=%0t",
                        samples_checked, expected[samples_checked], audio_sample, $time);
                samples_checked++;
            end
        end
    end
endmodule
