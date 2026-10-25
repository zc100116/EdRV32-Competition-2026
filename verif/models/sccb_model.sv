// File: sccb_model.sv
// Spec: sys-subsys 2.8; sys-subsys-testplan IC-01/02/03/05.
// Description: OV5640 SCCB peer at 0x3c, 16-bit register index, byte data.
//              NACK byte index counts address as zero; START preserves read pointer.
// Clock domain: external SCL/SDA, timing expressed in ns.
module sccb_model (
    input logic scl_i,
    input logic sda_i,
    output logic sda_oe_o
);
    timeunit 1ns;
    timeprecision 1ps;
    byte unsigned registers[65536];
    int nack_byte = -1;
    realtime quarter_ns = 0.0;
    int writes = 0;
    int reads = 0;
    int starts = 0;
    int stops = 0;
    int nacks = 0;
    byte unsigned bytes_seen[$];
    bit active = 0;
    bit selected = 0;
    bit reading = 0;
    bit ack_phase = 0;
    bit ack_driven = 0;
    bit master_ack = 0;
    int bit_count = 0;
    int byte_count = 0;
    int read_bit = 7;
    byte unsigned shift;
    bit [15:0] pointer;
    byte unsigned unused_last_write;
    bit [15:0] unused_last_register;
    realtime last_rise = 0;
    realtime last_fall = 0;
    realtime last_data = 0;
    realtime last_start = 0;
    realtime last_stop = 0;
    realtime last_slave_change = 0;
    /* verilator lint_off BLKSEQ */
    task automatic drive_sda(input bit enable);
        if (sda_oe_o != enable) last_slave_change = $realtime;
        sda_oe_o = enable;
    endtask
    /* verilator lint_on BLKSEQ */

    initial sda_oe_o = 0;

    // Bus events update one atomic protocol model, rather than synthesizable flops.
    /* verilator lint_off BLKSEQ */
    always @(negedge sda_i) begin
        if (scl_i) begin
            if (quarter_ns != 0 && last_stop != 0 &&
                $realtime - last_stop + 0.001 < quarter_ns)
                $fatal(1, "FAIL SCCB STOP hold time=%0t", $time);
            if (quarter_ns != 0 && last_rise != 0 &&
                $realtime - last_rise + 0.001 < quarter_ns)
                $fatal(1, "FAIL SCCB START setup time=%0t", $time);
            active = 1;
            selected = 0;
            reading = 0;
            ack_phase = 0;
            ack_driven = 0;
            master_ack = 0;
            bit_count = 0;
            byte_count = 0;
            starts++;
            last_start = $realtime;
        end
        last_data = $realtime;
    end

    always @(posedge sda_i) begin
        if (scl_i && active) begin
            if (quarter_ns != 0 && $realtime - last_rise + 0.001 < quarter_ns)
                $fatal(1, "FAIL SCCB STOP setup time=%0t", $time);
            active = 0;
            drive_sda(0);
            stops++;
            last_stop = $realtime;
        end
        last_data = $realtime;
    end

    always @(sda_i) begin
        if (!scl_i && quarter_ns != 0 && last_fall != 0 &&
            last_slave_change != $realtime && $realtime - last_fall + 0.001 < quarter_ns)
            $fatal(1, "FAIL SCCB data hold time=%0t", $time);
    end

    always @(posedge scl_i) begin
        if (active) begin
            if (quarter_ns != 0 && bit_count != 0 && !ack_phase &&
                (($realtime - last_rise < 4.0 * quarter_ns - 0.002) ||
                    ($realtime - last_rise > 4.0 * quarter_ns + 0.002)))
                $fatal(1, "FAIL SCCB SCL period expected=%0f actual=%0f time=%0t",
                        4.0 * quarter_ns, $realtime - last_rise, $time);
            if (quarter_ns != 0 && last_fall != 0 &&
                $realtime - last_fall + 0.001 < 2.0 * quarter_ns)
                $fatal(1, "FAIL SCCB SCL low time=%0t", $time);
            if (quarter_ns != 0 && $realtime - last_data + 0.001 < quarter_ns)
                $fatal(1, "FAIL SCCB data setup time=%0t", $time);
            if (ack_phase) begin
                // Ninth clock belongs to the slave ACK.
            end else if (reading && selected) begin
                if (master_ack) begin
                    if (!sda_i) pointer++;
                    else selected = 0;
                end else if (read_bit == 0) begin
                    reads++;
                    master_ack = 1;
                end else read_bit--;
            end else begin
                shift = {shift[6:0], sda_i};
                bit_count++;
                if (bit_count == 8) begin
                    bytes_seen.push_back(shift);
                    if (byte_count == 0) begin
                        selected = shift[7:1] == 7'h3c;
                        reading = shift[0];
                    end
                    if (selected && byte_count != nack_byte) begin
                        case (byte_count)
                            1: pointer[15:8] = shift;
                            2: pointer[7:0] = shift;
                            default: begin
                                if (byte_count >= 3) begin
                                    registers[pointer] = shift;
                                    unused_last_register = pointer;
                                    unused_last_write = shift;
                                    pointer++;
                                    writes++;
                                end
                            end
                        endcase
                    end else if (selected) nacks++;
                    ack_phase = 1;
                    ack_driven = 0;
                    bit_count = 0;
                end
            end
        end
        last_rise = $realtime;
    end

    always @(negedge scl_i) begin
        if (active) begin
            if (quarter_ns != 0 && $realtime - last_rise + 0.001 < 2.0 * quarter_ns &&
                last_start < last_rise)
                $fatal(1, "FAIL SCCB SCL high time=%0t", $time);
            if (quarter_ns != 0 && last_start > last_rise &&
                $realtime - last_start + 0.001 < quarter_ns)
                $fatal(1, "FAIL SCCB START hold time=%0t", $time);
            if (ack_phase) begin
                if (!ack_driven) begin
                    drive_sda(selected && byte_count != nack_byte);
                    ack_driven = 1;
                end else begin
                    drive_sda(0);
                    ack_phase = 0;
                    byte_count++;
                    if (reading && selected) begin
                        read_bit = 7;
                        drive_sda(!registers[pointer][7]);
                    end
                end
            end else if (reading && selected) begin
                if (master_ack) begin
                    drive_sda(0);
                    if (read_bit == 0) read_bit = -1;
                    else begin
                        master_ack = 0;
                        read_bit = 7;
                        drive_sda(!registers[pointer][7]);
                    end
                end else drive_sda(!registers[pointer][read_bit]);
            end
        end else drive_sda(0);
        last_fall = $realtime;
    end
    /* verilator lint_on BLKSEQ */
endmodule
