// File: tb_blend_ref.sv
// Spec: DISP v0.3 2.7; testplan 4, DS-15 reference cross-comparison.
// Description: Compare six Python expected frames with the SV pixel reference,
//              independently of which DUT version is present.
// Clock domain: none (untimed reference calculations).
module tb_blend_ref;
    localparam logic [31:0] BASE_A = 32'h80000000;
    localparam logic [31:0] BASE_1 = 32'h81000000;
    localparam int OPACITY[6] = '{0, 1, 128, 255, 73, 219};
    int test_case = 15;
    int seed = 1;
    `include "blend_ref.svh"
    initial begin
        int source;
        int count;
        string path;
        logic [23:0] actual;
        logic [23:0] expected;
        void'($value$plusargs("BLEND_REF=%s", path));
        source = $fopen(path, "r");
        if (source == 0) $fatal(1, "FAIL DS-15 Python frame open expected=file actual=%s", path);
        for (int f = 0; f < 6; f++) begin
            for (int row = 0; row < 720; row++) begin
                for (int column = 0; column < 1280; column++) begin
                    if ($fscanf(source, "%h", expected) != 1)
                        $fatal(1, "FAIL DS15 expected=pixel actual=EOF row=%0d col=%0d",
                            row, column);
                    actual = mix(expand(pixel565(BASE_A, column, row)),
                                    pixel_argb(BASE_1, column, row), OPACITY[f]);
                    if (expected != actual)
                        $fatal(1,
                            "FAIL DS15 expected=%h actual=%h L=blend row=%0d col=%0d OPA=%0d",
                            expected, actual, row, column, OPACITY[f]);
                    count++;
                end
            end
        end
        $fclose(source);
        $display("PASS DS-15 Python/SV reference pixels=%0d", count);
        $finish;
    end
endmodule
