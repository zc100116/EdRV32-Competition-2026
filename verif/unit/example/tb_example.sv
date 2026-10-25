// File: tb_example.sv
// Spec: CLAUDE.md 9.1; infra-plan I-03
// Description: Exercise the regression verdict and exit-code contract.
// Clock domain: none.
module tb_example;
    initial begin
        if ((2 + 2) != 4) begin
            $display("FAIL: expected 4, got %0d at %0t", 2 + 2, $time);
            $fatal(1);
        end
        $display("PASS");
        $finish;
    end
endmodule
