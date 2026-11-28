// File: edrv32_fpu_vectors_pkg.sv
// Spec: fpu-testplan 4 FT01; fpu-spec 3.1.
// Description: Read uniform raw-bit vectors and compare public unit responses.
// Clock: called by the consuming clk_sys testbench.
package edrv32_fpu_vectors_pkg;
    typedef struct packed {
        logic [31:0] instr;
        logic [2:0] rm;
        logic [63:0] src1;
        logic [63:0] src2;
        logic [63:0] src3;
        logic [31:0] int_src;
        logic [63:0] result;
        logic [4:0] flags;
        logic int_dest;
    } fpu_vector_t;

    task automatic open_vectors(input string path, output integer descriptor);
        descriptor = $fopen(path, "r");
        if (descriptor == 0) $fatal(1, "FAIL cannot open FPU vectors: %s", path);
    endtask

    task automatic read_vector(
        input integer descriptor,
        output fpu_vector_t vector,
        output bit available
    );
        integer fields;
        logic [31:0] instr;
        logic [2:0] rm;
        logic [63:0] src1;
        logic [63:0] src2;
        logic [63:0] src3;
        logic [31:0] int_src;
        logic [63:0] result;
        logic [4:0] flags;
        logic int_dest;
        fields = $fscanf(descriptor, "%h %h %h %h %h %h %h %h %h\n",
                         instr, rm, src1, src2, src3, int_src, result, flags, int_dest);
        vector = {instr, rm, src1, src2, src3, int_src, result, flags, int_dest};
        available = fields == 9;
        if (!available && !$feof(descriptor))
            $fatal(1, "FAIL malformed FPU vector: read %0d fields", fields);
    endtask

    // Consumers zero-extend a 32-bit unit result. FPU top tests compare full boxing.
    task automatic compare_response(
        input fpu_vector_t vector,
        input logic [63:0] actual_data,
        input logic [4:0] actual_flags,
        input logic actual_int_dest
    );
        if ({actual_data, actual_flags, actual_int_dest} !==
            {vector.result, vector.flags, vector.int_dest}) begin
            $display("FAIL FPU time=%0t instr=%08h rm=%0h", $time, vector.instr, vector.rm);
            $display("src1=%016h src2=%016h src3=%016h int=%08h",
                     vector.src1, vector.src2, vector.src3, vector.int_src);
            $display("expected data=%016h flags=%02h int_dest=%0b",
                     vector.result, vector.flags, vector.int_dest);
            $fatal(1, "actual data=%016h flags=%02h int_dest=%0b",
                   actual_data, actual_flags, actual_int_dest);
        end
    endtask
endpackage
