// File: i2s_rx_model.sv
// Spec: aud-spec 2.5; aud-testplan 2, AT-01.
// Description: Standard I2S slave decoder and clock/slot phase checks.
//              Samples on rising BCLK; one dummy bit precedes each 16-bit word.
// Clock domain: clk_aud and derived BCLK.
`timescale 1ns/1ps
module i2s_rx_model (
    input logic clk_aud_i,
    input logic rst_n_i,
    input logic bclk_i,
    input logic lrck_i,
    input logic sdata_i,
    output logic [31:0] sample_o,
    output logic sample_valid_o
);
    int aud_cycles;
    int last_bclk;
    int last_lrck;
    bit old_bclk;
    bit old_lrck;
    bit old_sdata;
    bit seen_bclk;
    bit seen_lrck;
    int slot;
    bit channel;
    bit synchronized;
    bit observed;
    logic [31:0] shift;

    task automatic capture_bit();
        if (!observed) begin
            observed = 1;
            channel = lrck_i;
            slot = 0;
        end else if (channel != lrck_i) begin
            channel = lrck_i;
            slot = 0;
            if (!lrck_i) synchronized = 1;
        end else slot++;
        if (synchronized) begin
            if (slot >= 1 && slot <= 16) begin
                if (lrck_i) shift[32-slot] = sdata_i;
                else shift[16-slot] = sdata_i;
            end else if (sdata_i != 0)
                $fatal(1, "FAIL I2S padding slot=%0d actual=%b time=%0t",
                    slot, sdata_i, $time);
            if (lrck_i && slot == 31) begin
                sample_o = shift;
                sample_valid_o = 1;
            end
        end
    endtask

    // Observe after the DUT's registered outputs settle. Both BCLK edges are two aud clocks apart.
    always @(posedge clk_aud_i) begin
        #0.001;
        if (!rst_n_i) begin
            aud_cycles = 0;
            last_bclk = 0;
            last_lrck = 0;
            old_bclk = bclk_i;
            old_lrck = lrck_i;
            old_sdata = sdata_i;
            seen_bclk = 0;
            seen_lrck = 0;
            slot = 0;
            channel = 0;
            observed = 0;
            synchronized = 0;
            shift = 0;
            sample_o = 0;
            sample_valid_o = 0;
        end else begin
            sample_valid_o = 0;
            if (bclk_i && !old_bclk) capture_bit();
            aud_cycles++;
            if (bclk_i != old_bclk) begin
                if (seen_bclk && aud_cycles-last_bclk != 2)
                    $fatal(1, "FAIL BCLK half period expected=2 actual=%0d time=%0t",
                        aud_cycles-last_bclk, $time);
                seen_bclk = 1;
                last_bclk = aud_cycles;
            end
            if (lrck_i != old_lrck) begin
                if (bclk_i || !old_bclk)
                    $fatal(1, "FAIL LRCK must change at falling BCLK time=%0t", $time);
                if (seen_lrck && aud_cycles-last_lrck != 128)
                    $fatal(1, "FAIL LRCK half period expected=128 actual=%0d time=%0t",
                        aud_cycles-last_lrck, $time);
                seen_lrck = 1;
                last_lrck = aud_cycles;
            end
            if (sdata_i != old_sdata && (bclk_i || !old_bclk))
                $fatal(1, "FAIL SDATA must change at falling BCLK time=%0t", $time);
            old_sdata = sdata_i;
            old_bclk = bclk_i;
            old_lrck = lrck_i;
        end
    end

endmodule
