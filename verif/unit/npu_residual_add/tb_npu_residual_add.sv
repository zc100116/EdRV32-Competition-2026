// File: tb_npu_residual_add.sv
// Spec: npu-spec 2.3, 5.4, 5.5; datapath 4.2.4; OP-06/07, ER-05 local behavior.
// Description: Independent byte arithmetic model with scheduled low/high RAM returns.
// Check WB1 to WB2 boundary, plane packing, mode changes, bypass and cancellation.
// Clock: clk_npu test clock.
module tb_npu_residual_add;
    reg clk = 0;
    initial forever #5 clk = !clk;
    reg rst_n = 0;
    reg cancel = 0;
    reg quant_valid = 0;
    reg [48:0] quant_tag = 0;
    reg [511:0] quant_data = 0;
    reg residual_valid = 0;
    reg [255:0] residual_data = 0;
    wire writeback_valid;
    wire [48:0] writeback_tag;
    wire [511:0] writeback_data;
    wire idle;
    localparam CYCLES = 5000;
    bit quant_schedule [0:CYCLES-1];
    bit residual_schedule [0:CYCLES-1];
    bit cancel_schedule [0:CYCLES-1];
    reg [48:0] tags [0:CYCLES-1];
    reg [511:0] quant_vectors [0:CYCLES-1];
    reg [255:0] residual_vectors [0:CYCLES-1];
    reg [511:0] expected_vectors [0:CYCLES-1];
    reg [31:0] random_state = 32'h7415bd21;
    reg [511:0] y;
    reg [511:0] r;
    integer next_cycle = 0;
    integer checked = 0;

    edrv32_npu_residual_add dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .cancel_i(cancel),
        .quant_valid_i(quant_valid),
        .quant_tag_i(quant_tag),
        .quant_data_i(quant_data),
        .residual_rd_valid_i(residual_valid),
        .residual_rd_data_i(residual_data),
        .writeback_valid_o(writeback_valid),
        .writeback_tag_o(writeback_tag),
        .writeback_data_o(writeback_data),
        .idle_o(idle)
    );

    function automatic [31:0] random_word;
        random_state = random_state ^ (random_state << 13);
        random_state = random_state ^ (random_state >> 17);
        random_state = random_state ^ (random_state << 5);
        return random_state;
    endfunction

    task automatic schedule_pair(input bit half, input bit residual_enable,
        input integer zero_point, input integer sequence_id);
        reg [48:0] tag_value;
        integer result_value;
        integer unused_qcycle;
        begin
            unused_qcycle = next_cycle + 1;
            tag_value = 49'(sequence_id);
            tag_value[26] = half;
            tag_value[28] = residual_enable;
            tag_value[36:29] = 8'(zero_point);
            quant_schedule[unused_qcycle] = 1;
            tags[unused_qcycle] = tag_value;
            quant_vectors[unused_qcycle] = y;
            if (residual_enable) begin
                residual_schedule[next_cycle] = 1;
                residual_vectors[next_cycle] = r[255:0];
                if (!half) begin
                    residual_schedule[unused_qcycle] = 1;
                    residual_vectors[unused_qcycle] = r[511:256];
                end
            end
            for (integer lane = 0; lane < 64; lane++) begin
                result_value = int'($signed(y[8*lane +: 8]));
                if (residual_enable)
                    result_value += int'($signed(r[8*lane +: 8])) - zero_point;
                if (half && lane >= 32) result_value = 0;
                if (result_value > 127) result_value = 127;
                if (result_value < -128) result_value = -128;
                expected_vectors[unused_qcycle][8*lane +: 8] = 8'(result_value);
            end
            next_cycle += half ? 2 : 4;
        end
    endtask

    task automatic tick;
        @(posedge clk);
        #1;
    endtask

    initial begin
        for (integer c = 0; c < CYCLES; c++) begin
            quant_schedule[c] = 0;
            residual_schedule[c] = 0;
            cancel_schedule[c] = 0;
            tags[c] = 0;
            quant_vectors[c] = 0;
            residual_vectors[c] = 0;
            expected_vectors[c] = 0;
        end
        // Reach the full 10-bit range and both saturation boundaries, for each plane.
        for (integer mode = 0; mode < 4; mode++) begin
            for (integer zp_index = 0; zp_index < 3; zp_index++) begin
                for (integer v = 0; v < 8; v++) begin
                    for (integer lane = 0; lane < 64; lane++) begin
                        case ((lane + v) % 8)
                            0: begin y[8*lane +: 8] = 127; r[8*lane +: 8] = 127; end
                            1: begin y[8*lane +: 8] = 128; r[8*lane +: 8] = 128; end
                            2: begin y[8*lane +: 8] = 127; r[8*lane +: 8] = 0; end
                            3: begin y[8*lane +: 8] = 128; r[8*lane +: 8] = 0; end
                            4: begin y[8*lane +: 8] = 126; r[8*lane +: 8] = 1; end
                            5: begin y[8*lane +: 8] = 129; r[8*lane +: 8] = 255; end
                            6: begin y[8*lane +: 8] = 255; r[8*lane +: 8] = 1; end
                            default: begin y[8*lane +: 8] = 1; r[8*lane +: 8] = 255; end
                        endcase
                    end
                    schedule_pair(1'(mode), 1'(mode >> 1),
                        (zp_index == 0) ? -128 : ((zp_index == 1) ? 0 : 127), next_cycle);
                end
            end
        end
        // Consecutive minimum-spacing half/full pairs exercise changing tag modes.
        for (integer p = 0; p < 1000; p++) begin
            for (integer lane = 0; lane < 64; lane++) begin
                y[8*lane +: 8] = 8'(random_word());
                r[8*lane +: 8] = 8'(random_word());
            end
            schedule_pair((p % 3) != 0, (p % 5) != 0,
                int'($signed(8'(random_word()))), p);
        end
        // Cancel an incoming pair, then cancel WB1 immediately before the WB2 edge.
        y = {64{8'h7f}};
        r = {64{8'h80}};
        schedule_pair(0, 1, 0, 2001);
        cancel_schedule[next_cycle-3] = 1;
        schedule_pair(1, 1, 0, 2002);
        cancel_schedule[next_cycle] = 1;
        next_cycle += 2;
        schedule_pair(0, 1, -5, 2003);
        schedule_pair(1, 0, 127, 2004);

        tick();
        tick();
        rst_n = 1;
        for (integer c = 0; c < next_cycle+3; c++) begin
            cancel = cancel_schedule[c];
            quant_valid = quant_schedule[c];
            quant_tag = tags[c];
            quant_data = quant_vectors[c];
            residual_valid = residual_schedule[c];
            residual_data = residual_vectors[c];
            #1;
            // This is the WB2 edge for the previous cycle's WB1 sum.
            if (c > 0 && quant_schedule[c-1] && !cancel_schedule[c-1] && !cancel) begin
                if (!writeback_valid || writeback_tag !== tags[c-1]
                    || writeback_data !== expected_vectors[c-1])
                    $fatal(1, "FAIL WB2 cycle=%0d tag=%h expected=%h actual=%h t=%0t",
                        c, writeback_tag, expected_vectors[c-1], writeback_data, $time);
                checked++;
            end else if (writeback_valid) begin
                $fatal(1, "FAIL extra WB2 valid cycle=%0d t=%0t", c, $time);
            end
            tick();
            if (writeback_valid !== (quant_valid && !cancel))
                $fatal(1, "FAIL WB1 valid cycle=%0d t=%0t", c, $time);
        end
        if (!idle || checked != 1098)
            $fatal(1, "FAIL checked=%0d idle=%b", checked, idle);
        $display("PASS residual_add: %0d pairs, WB1/WB2 timing, signed clamp, bypass, cancel", checked);
        $finish;
    end
endmodule
