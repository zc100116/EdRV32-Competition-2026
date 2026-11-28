// File: tb.sv
// Spec: fpu-testplan FT01; fpu-spec 3.1.
// Description: Exercise the common reader with a hand-computed fused vector.
// Clock: host testbench, no DUT clock.
module tb;
    import edrv32_fpu_vectors_pkg::*;
    integer descriptor;
    fpu_vector_t vector;
    bit available;
    string path;
    initial begin
        if (!$value$plusargs("VECTORS=%s", path)) $fatal(1, "FAIL missing +VECTORS");
        open_vectors(path, descriptor);
        read_vector(descriptor, vector, available);
        if (!available) $fatal(1, "FAIL missing fused vector");
        if (vector.instr !== 32'h18208043 || vector.rm !== 3'd0 ||
            vector.src1 !== 64'h000000003f800001 ||
            vector.src2 !== 64'h000000003f7ffffe ||
            vector.src3 !== 64'h00000000bf800000 || vector.int_src !== 32'd0)
            $fatal(1, "FAIL vector input round trip");
        compare_response(vector, 64'h00000000a8800000, 5'd0, 1'b0);
        read_vector(descriptor, vector, available);
        if (available) $fatal(1, "FAIL unexpected trailing vector");
        $fclose(descriptor);
        $display("PASS FPU common vector reader");
        $finish;
    end
endmodule
