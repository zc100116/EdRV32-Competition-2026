// File: blend_ref.svh
// Spec: DISP v0.3 2.3, 2.7; testplan 4, DS-15.
// Description: SV blend and deterministic surface functions shared by the
//              pixel scoreboard and independent Python/SV reference comparison.
// Clock domain: combinational host/testbench calculations.
    function automatic int divide255(input int value_i);
        int temporary;
        temporary = value_i + 128;
        return (temporary + (temporary >> 8)) >> 8;
    endfunction

    function automatic logic [23:0] expand(input logic [15:0] v);
        return {v[15:11], v[15:13], v[10:5], v[10:9], v[4:0], v[4:2]};
    endfunction

    function automatic logic [15:0] pixel565(input logic [31:0] base_i,
                                            input int column_i, input int row_i);
        logic [31:0] word;
        int tag;
        tag = int'((base_i - BASE_A) >> 22);
        if (test_case == 7 || test_case == 12 || test_case == 13)
            return {5'(1 + (column_i + row_i + tag*7) % 31),
                    6'((row_i*3 + column_i/7 + tag*13) % 64), 5'b0};
        word = 32'(column_i+1)*32'h045d9f3b ^ 32'(row_i+1)*32'h119de1f3 ^
                32'(seed)*32'h10204081 ^ 32'(tag)*32'h17234567;
        return 16'(word ^ (word >> 16));
    endfunction

    function automatic logic [31:0] pixel_argb(input logic [31:0] base_i,
                                                input int column_i, input int row_i);
        logic [31:0] word;
        int alpha;
        int tag;
        tag = int'((base_i - BASE_1) >> 22);
        if (test_case == 7 || test_case == 12 || test_case == 13)
            return {8'hff, 8'b0, 8'b0, 8'(129 + (column_i*3 + row_i*7 + tag) % 127)};
        word = 32'(column_i+1)*32'h1b873593 ^ 32'(row_i+1)*32'h5bd1e995 ^
                32'(seed)*32'h01010101 ^ 32'(tag)*32'h01234567;
        case (column_i % 8)
            0: alpha = 0;
            1: alpha = 1;
            2: alpha = 127;
            3: alpha = 128;
            4: alpha = 254;
            5: alpha = 255;
            default: alpha = int'(word[31:24]);
        endcase
        return {8'(alpha), word[23:0]};
    endfunction

    function automatic logic [23:0] mix(input logic [23:0] back_i,
                                        input logic [31:0] front_i, input int opacity_i);
        int alpha;
        logic [23:0] result;
        alpha = divide255(int'(front_i[31:24])*opacity_i);
        for (int c = 0; c < 3; c++)
            result[c*8+:8] = 8'(divide255(alpha*int'(front_i[c*8+:8]) +
                                            (255-alpha)*int'(back_i[c*8+:8])));
        return result;
    endfunction

