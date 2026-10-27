// File: tb_npu_result_quant.sv
// Spec: npu-spec 2.3, 5.4, 5.5; TL-01, OP-05, OP-08; datapath design 5.2 D1-D.
// Description: Independent integer formula scoreboard, two-edge memory contracts,
// and exact Q0-Q12 calendar checks across continuous four/two group pairs.
// Clock: clk_npu, 10 simulation time units per period.
module tb_npu_result_quant;
    localparam integer CYCLES = 4096;
    reg clk = 0;
    initial forever #5 clk = ~clk;
    reg rst_n = 0;
    reg cancel = 0;
    reg prepare_valid = 0;
    reg [48:0] prepare_tag = 0;
    reg accum_valid = 0;
    reg [48:0] accum_tag = 0;
    reg [2047:0] accum_data = 0;
    wire param_en;
    wire [2:0] param_block;
    wire [1:0] param_phase;
    reg [511:0] param_stage;
    reg [511:0] param_data;
    wire lut_en;
    wire [2:0] lut_block;
    wire [127:0] lut_addr;
    reg [127:0] lut_stage;
    reg [127:0] lut_data;
    wire residual_en;
    wire [4:0] residual_addr;
    wire quant_valid;
    wire [48:0] quant_tag;
    wire [511:0] quant_data;
    wire idle;
    reg [63:0] parameters_mem [0:7][0:31];
    reg prepare_schedule [0:CYCLES-1];
    reg [48:0] prepare_tags [0:CYCLES-1];
    reg accum_schedule [0:CYCLES-1];
    reg [48:0] accum_tags [0:CYCLES-1];
    reg [2047:0] accum_vectors [0:CYCLES-1];
    reg cancel_schedule [0:CYCLES-1];
    reg param_expected [0:CYCLES-1];
    reg [4:0] param_addresses [0:CYCLES-1];
    reg lut_expected [0:CYCLES-1];
    reg [2:0] lut_blocks [0:CYCLES-1];
    reg [127:0] lut_addresses [0:CYCLES-1];
    reg residual_expected [0:CYCLES-1];
    reg [4:0] residual_addresses [0:CYCLES-1];
    reg output_expected [0:CYCLES-1];
    reg [48:0] output_tags [0:CYCLES-1];
    reg [511:0] output_vectors [0:CYCLES-1];
    reg [3:0] lut_boundaries_seen = 0;
    integer output_count = 0;
    integer lut_count = 0;
    integer residual_count = 0;
    integer finish_cycle;
    reg [31:0] random_state = 32'h1234abcd;

    edrv32_npu_result_quant u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .cancel_i(cancel),
        .quant_prepare_valid_i(prepare_valid),
        .quant_prepare_tag_i(prepare_tag),
        .accum_valid_i(accum_valid),
        .accum_tag_i(accum_tag),
        .accum_data_i(accum_data),
        .param_rd_en_o(param_en),
        .param_rd_block_o(param_block),
        .param_rd_phase_o(param_phase),
        .param_rd_data_i(param_data),
        .lut_rd_en_o(lut_en),
        .lut_rd_block_o(lut_block),
        .lut_rd_addr_o(lut_addr),
        .lut_rd_data_i(lut_data),
        .residual_rd_en_o(residual_en),
        .residual_rd_addr_o(residual_addr),
        .quant_valid_o(quant_valid),
        .quant_tag_o(quant_tag),
        .quant_data_o(quant_data),
        .idle_o(idle)
    );

    // Separate stages reproduce the frozen storage response, including held data.
    always @(posedge clk) begin
        if (param_en) begin
            for (integer j = 0; j < 8; j++) begin
                param_stage[64*j +: 64] <= parameters_mem[param_block][8*int'(param_phase)+j];
            end
        end
        param_data <= param_stage;
        if (lut_en) begin
            for (integer j = 0; j < 16; j++) begin
                lut_stage[8*j +: 8] <= activation(lut_block, lut_addr[8*j +: 8]);
            end
        end
        lut_data <= lut_stage;
    end

    function automatic [7:0] activation(input [2:0] block_id, input [7:0] addr);
        // Block-dependent permutation distinguishes all four unsigned boundaries.
        activation = (addr ^ 8'hb3) + {5'd0, block_id};
    endfunction

    function automatic [31:0] random_word();
        random_state = 32'd1664525 * random_state + 32'd1013904223;
        return random_state;
    endfunction

    function automatic [7:0] quantize(input [31:0] acc, input [53:0] param_word,
                                    input [7:0] zp);
        longint signed total;
        longint signed product_value;
        longint signed shifted;
        integer amount;
        // Spec 2.3 directly in 64 bits: no split multiply or staged shifts.
        total = longint'($signed(acc)) + longint'($signed(param_word[31:0]));
        product_value = total * longint'($signed(param_word[47:32]));
        amount = int'(param_word[53:48]);
        shifted = (product_value + ((amount == 0) ? 64'sd0 : (64'sd1 << (amount-1))))
            >>> amount;
        shifted = shifted + longint'($signed(zp));
        if (shifted > 127) return 8'h7f;
        if (shifted < -128) return 8'h80;
        return shifted[7:0];
    endfunction

    task automatic add_pair(input integer start, input integer number,
                            input bit half_plane, input bit use_lut, input bit use_res,
                            input integer cancel_edge = -1);
        reg [48:0] tag_value;
        reg [2047:0] vector_value;
        reg [511:0] result_value;
        reg [127:0] indices [0:3];
        reg [31:0] acc_value;
        reg [7:0] q;
        integer groups;
        integer b;
        integer edge_value;
        integer destination;
        groups = half_plane ? 2 : 4;
        b = number % 8;
        tag_value = 49'd0;
        tag_value[11:0] = 12'(number+3);
        tag_value[14:12] = 3'(b);
        tag_value[25:15] = 11'(number);
        tag_value[26] = half_plane;
        tag_value[27] = use_lut;
        tag_value[28] = use_res;
        tag_value[36:29] = (number < 8) ? 8'd0 : 8'(number*71);
        tag_value[37] = (number%3 == 0);
        tag_value[42:38] = 5'(number);
        tag_value[47:43] = 5'(number*2);
        tag_value[48] = half_plane && number[0];
        result_value = 0;
        foreach (indices[g]) indices[g] = 0;
        for (integer pixel = 0; pixel < 2; pixel++) begin
            for (integer c = 0; c < 32; c++) begin
                case ((number+c+pixel)%12)
                    0: acc_value = 32'h7fffffff;
                    1: acc_value = 32'h80000000;
                    2: acc_value = 32'h0001ffff;
                    3: acc_value = 32'hfffe0000;
                    4: acc_value = 32'h00010000;
                    5: acc_value = 32'hffff0000;
                    6: acc_value = 32'd1;
                    7: acc_value = -32'd1;
                    8: acc_value = 32'd0;
                    default: acc_value = random_word();
                endcase
                if (b == 0 && c < 4) begin
                    case (c)
                        0: acc_value = 0;
                        1: acc_value = 127;
                        2: acc_value = -128;
                        3: acc_value = -1;
                        default: acc_value = 0;
                    endcase
                end
                if (b == 0 && (c == 4 || c == 5))
                    acc_value = pixel == 0 ? 32'd1 : -32'd1;
                vector_value[32*(pixel*32+c) +: 32] = acc_value;
                q = quantize(acc_value, parameters_mem[b][c][53:0], tag_value[36:29]);
                indices[c/8][8*(pixel*8+c%8) +: 8] = q;
                destination = (c/16)*32 + pixel*16 + c%16;
                if (!half_plane || c < 16) begin
                    result_value[8*destination +: 8] = use_lut ? activation(3'(b), q) : q;
                end
            end
        end
        prepare_schedule[start] = 1;
        prepare_tags[start] = tag_value;
        if (cancel_edge < 0 || start+2 < cancel_edge) begin
            accum_schedule[start+2] = 1;
            accum_tags[start+2] = tag_value;
            accum_vectors[start+2] = vector_value;
        end
        for (integer g = 0; g < groups; g++) begin
            if (cancel_edge < 0 || start+g < cancel_edge) begin
                param_expected[start+g] = 1;
                param_addresses[start+g] = {3'(b), 2'(g)};
            end
            edge_value = start+12+g;
            if (use_lut && (cancel_edge < 0 || edge_value < cancel_edge)) begin
                lut_expected[edge_value] = 1;
                lut_blocks[edge_value] = 3'(b);
                lut_addresses[edge_value] = indices[g];
            end
        end
        edge_value = start+12+groups-1;
        if (use_res && (cancel_edge < 0 || edge_value < cancel_edge)) begin
            residual_expected[edge_value] = 1;
            residual_addresses[edge_value] = tag_value[47:43];
        end
        if (use_res && !half_plane
            && (cancel_edge < 0 || edge_value+1 < cancel_edge)) begin
            residual_expected[edge_value+1] = 1;
            residual_addresses[edge_value+1] = tag_value[47:43]+5'd1;
        end
        edge_value = start+14+groups-1;
        if (cancel_edge < 0 || edge_value < cancel_edge) begin
            output_expected[edge_value] = 1;
            output_tags[edge_value] = tag_value;
            output_vectors[edge_value] = result_value;
        end
        if (cancel_edge >= 0) cancel_schedule[cancel_edge] = 1;
    endtask

    initial begin : run_test
        integer start;
        integer pattern;
        reg [31:0] bias_value;
        reg [15:0] multiplier;
        reg [5:0] amount;
        for (integer t = 0; t < CYCLES; t++) begin
            prepare_schedule[t] = 0;
            accum_schedule[t] = 0;
            cancel_schedule[t] = 0;
            param_expected[t] = 0;
            lut_expected[t] = 0;
            residual_expected[t] = 0;
            output_expected[t] = 0;
        end
        for (integer b = 0; b < 8; b++) begin
            for (integer c = 0; c < 32; c++) begin
                pattern = (b*3+c)%12;
                case (pattern%4)
                    0: bias_value = 32'h7fffffff;
                    1: bias_value = 32'h80000000;
                    2: bias_value = 32'd0;
                    default: bias_value = random_word();
                endcase
                case (pattern%6)
                    0: multiplier = 16'h7fff;
                    1: multiplier = 16'h8000;
                    2: multiplier = 16'd0;
                    3: multiplier = 16'hffff;
                    4: multiplier = 16'd1;
                    default: multiplier = 16'(random_word());
                endcase
                case (pattern)
                    0, 1, 2, 3: amount = 0;
                    4, 5, 6, 7: amount = 47;
                    8: amount = 1;
                    9: amount = 7;
                    10: amount = 8;
                    default: amount = 31;
                endcase
                if (b == 0 && (c == 4 || c == 5)) begin
                    bias_value = 0;
                    multiplier = (c == 4) ? 16'd1 : 16'hffff;
                    amount = 1;
                end
                if (b == 0 && c < 4) begin
                    bias_value = 0;
                    multiplier = 1;
                    amount = 0;
                end
                parameters_mem[b][c] = {10'd0, amount, multiplier, bias_value};
            end
        end
        start = 4;
        // Continuous G4 -> G2 -> G4, alternating per-group block, zp and flags.
        for (integer n = 0; n < 256; n++) begin
            add_pair(start, n, n%3 == 1, n%4 < 2, n%5 != 0);
            start += (n%3 == 1) ? 2 : 4;
        end
        start += 24;
        // Cancellation at every pipeline boundary, followed by clean re-use.
        for (integer offset = 0; offset <= 17; offset++) begin
            add_pair(start, offset, 0, 1, 1, start+offset);
            start += 24;
            add_pair(start, offset+32, offset[0], offset[1], 1);
            start += 24;
        end
        finish_cycle = start+24;
        repeat (3) @(negedge clk);
        rst_n = 1;
        for (integer cycle = 0; cycle <= finish_cycle; cycle++) begin
            @(negedge clk);
            cancel = cancel_schedule[cycle];
            prepare_valid = prepare_schedule[cycle];
            prepare_tag = prepare_tags[cycle];
            accum_valid = accum_schedule[cycle];
            accum_tag = accum_tags[cycle];
            accum_data = accum_vectors[cycle];
            #1;
            if (param_en !== param_expected[cycle])
                $fatal(1, "FAIL parameter enable cycle=%0d expected=%b got=%b", cycle,
                    param_expected[cycle], param_en);
            if (param_en && {param_block,param_phase} !== param_addresses[cycle])
                $fatal(1, "FAIL parameter address cycle=%0d expected=%h got=%h", cycle,
                    param_addresses[cycle], {param_block,param_phase});
            if (lut_en !== lut_expected[cycle])
                $fatal(1, "FAIL LUT enable cycle=%0d expected=%b got=%b", cycle,
                    lut_expected[cycle], lut_en);
            if (lut_en) begin
                lut_count++;
                for (integer j = 0; j < 16; j++) begin
                    case (lut_addr[8*j +: 8])
                        8'd0: lut_boundaries_seen[0] = 1;
                        8'd127: lut_boundaries_seen[1] = 1;
                        8'd128: lut_boundaries_seen[2] = 1;
                        8'd255: lut_boundaries_seen[3] = 1;
                        default: begin end
                    endcase
                end
                if (lut_block !== lut_blocks[cycle] || lut_addr !== lut_addresses[cycle])
                    $fatal(1, "FAIL LUT indices cycle=%0d block=%0d expected=%h got=%h", cycle,
                        lut_block, lut_addresses[cycle], lut_addr);
            end
            if (residual_en !== residual_expected[cycle])
                $fatal(1, "FAIL residual enable cycle=%0d expected=%b got=%b", cycle,
                    residual_expected[cycle], residual_en);
            if (residual_en) begin
                residual_count++;
                if (residual_addr !== residual_addresses[cycle])
                    $fatal(1, "FAIL residual address cycle=%0d expected=%h got=%h", cycle,
                        residual_addresses[cycle], residual_addr);
            end
            @(posedge clk);
            #1;
            if (quant_valid !== output_expected[cycle])
                $fatal(1, "FAIL output valid cycle=%0d expected=%b got=%b", cycle,
                    output_expected[cycle], quant_valid);
            if (quant_valid) begin
                output_count++;
                if (quant_tag !== output_tags[cycle] || quant_data !== output_vectors[cycle])
                    $fatal(1, "FAIL output cycle=%0d tag expected=%h got=%h data expected=%h got=%h",
                        cycle, output_tags[cycle], quant_tag, output_vectors[cycle], quant_data);
            end
            if (cancel && !idle) $fatal(1, "FAIL cancel did not empty pipeline cycle=%0d", cycle);
        end
        if (lut_boundaries_seen != 4'b1111)
            $fatal(1, "FAIL missing LUT boundary coverage: %b", lut_boundaries_seen);
        if (!idle) $fatal(1, "FAIL pipeline did not drain");
        $display("PASS npu_result_quant pairs=%0d LUT_groups=%0d residual_beats=%0d",
            output_count, lut_count, residual_count);
        $display("PASS prepare->Q12 G4=17/G2=15 cycles; Q0->Q12=12 cycles; cadence=4/2");
        $finish;
    end
endmodule
