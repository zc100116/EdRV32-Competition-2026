// Optional waveform recorder shared by all Icarus simulations.
module edrv32_wave_dump;
    reg [4095:0] wave_file;

    initial begin
        if ($value$plusargs("WAVE=%s", wave_file)) begin
            $dumpfile(wave_file);
            $dumpvars(0);
        end
    end
endmodule
