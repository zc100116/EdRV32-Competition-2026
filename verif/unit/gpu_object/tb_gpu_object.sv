// File: tb_gpu_object.sv
// Spec: gpu-spec.md 2.9, 4, 5; microarchitecture 4.2 and 4.5.
// Description: Model scoreboard for ordered outputs, stalls, publication and II=1.
// Clock: generated GPU test clock.
module tb_gpu_object;
    logic clk_i;
    logic rst_n_i;
    logic object_cfg_valid_i;
    logic object_cfg_ready_o;
    logic [63:0] object_cfg_live_i;
    logic [511:0] object_cfg_targets_i;
    logic [31:0] object_cfg_hit_base_i;
    logic [23:0] object_cfg_hit_max_i;
    logic [31:0] object_cfg_free_base_i;
    logic [23:0] object_cfg_free_max_i;
    logic draw_valid_i;
    logic draw_ready_o;
    logic [255:0] draw_command_i;
    logic object_record_valid_i;
    logic object_record_ready_o;
    logic [255:0] object_record_data_i;
    logic [23:0] object_record_idx_i;
    logic object_update_valid_o;
    logic object_update_ready_i;
    logic [23:0] object_update_idx_o;
    logic [255:0] object_update_data_o;
    logic object_event_valid_o;
    logic object_event_ready_i;
    logic [23:0] object_event_idx_o;
    logic [7:0] object_event_hit_o;
    logic object_event_free_o;
    logic object_quad_valid_o;
    logic object_quad_ready_i;
    logic [127:0] object_quad_data_o;
    logic [16:0] object_quad_x_o;
    logic [16:0] object_quad_y_o;
    logic finish_i;
    logic stop_i;
    logic unit_done_o;
    logic object_publish_i;
    logic object_result_valid_o;
    logic object_result_ready_i;
    logic [23:0] object_result_hit_count_o;
    logic [23:0] object_result_free_count_o;
    logic [23:0] object_result_alive_count_o;
    logic [1:0] object_result_overflow_o;
    logic perf_object_busy_o;

    edrv32_gpu_object u_object (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .object_cfg_valid_i(object_cfg_valid_i),
        .object_cfg_ready_o(object_cfg_ready_o),
        .object_cfg_live_i(object_cfg_live_i),
        .object_cfg_targets_i(object_cfg_targets_i),
        .object_cfg_hit_base_i(object_cfg_hit_base_i),
        .object_cfg_hit_max_i(object_cfg_hit_max_i),
        .object_cfg_free_base_i(object_cfg_free_base_i),
        .object_cfg_free_max_i(object_cfg_free_max_i),
        .draw_valid_i(draw_valid_i),
        .draw_ready_o(draw_ready_o),
        .draw_command_i(draw_command_i),
        .object_record_valid_i(object_record_valid_i),
        .object_record_ready_o(object_record_ready_o),
        .object_record_data_i(object_record_data_i),
        .object_record_idx_i(object_record_idx_i),
        .object_update_valid_o(object_update_valid_o),
        .object_update_ready_i(object_update_ready_i),
        .object_update_idx_o(object_update_idx_o),
        .object_update_data_o(object_update_data_o),
        .object_event_valid_o(object_event_valid_o),
        .object_event_ready_i(object_event_ready_i),
        .object_event_idx_o(object_event_idx_o),
        .object_event_hit_o(object_event_hit_o),
        .object_event_free_o(object_event_free_o),
        .object_quad_valid_o(object_quad_valid_o),
        .object_quad_ready_i(object_quad_ready_i),
        .object_quad_data_o(object_quad_data_o),
        .object_quad_x_o(object_quad_x_o),
        .object_quad_y_o(object_quad_y_o),
        .finish_i(finish_i),
        .stop_i(stop_i),
        .unit_done_o(unit_done_o),
        .object_publish_i(object_publish_i),
        .object_result_valid_o(object_result_valid_o),
        .object_result_ready_i(object_result_ready_i),
        .object_result_hit_count_o(object_result_hit_count_o),
        .object_result_free_count_o(object_result_free_count_o),
        .object_result_alive_count_o(object_result_alive_count_o),
        .object_result_overflow_o(object_result_overflow_o),
        .perf_object_busy_o(perf_object_busy_o)
    );

    `include "sizes.svh"
    logic [255:0] records [0:RECORDS-1];
    logic [255:0] updates [0:RECORDS-1];
    logic [11:0] events [0:RECORDS-1];
    logic [127:0] quads [0:RECORDS-1];
    logic [33:0] positions [0:RECORDS-1];
    logic [767:0] configs [0:CASES-1];
    logic [767:0] cfg;
    integer case_number = 0;
    integer base_index = 0;
    integer object_count = 0;
    integer update_index = 0;
    integer event_index = 0;
    integer quad_index = 0;
    integer cycle = 0;
    integer last_input = -1;
    integer last_update = -1;
    integer last_event = -1;
    integer last_quad = -1;
    integer input_total = 0;
    integer update_total = 0;
    integer event_total = 0;
    integer quad_total = 0;
    integer throughput_checks = 0;
    logic checking = 0;
    logic stalls = 0;
    logic throughput = 0;
    logic step_mode = 0;
    logic hold_update = 0;
    logic hold_event = 0;
    logic hold_quad = 0;
    logic [279:0] held_update;
    logic [32:0] held_event;
    logic [161:0] held_quad;

    initial clk_i = 0;
    always #5 clk_i = ~clk_i;
    initial begin
        #1000000;
        $fatal(1, "FAIL timeout");
    end

    always @(negedge clk_i) begin
        object_update_ready_i = !stalls || cycle % 31 >= 14;
        object_event_ready_i = !stalls || cycle % 23 >= 11;
        object_quad_ready_i = !stalls || cycle % 29 >= 16;
    end

    task automatic check_spacing(input integer previous, input integer stream);
        if (throughput && previous >= 0) begin
            if (cycle != previous + 1)
                $fatal(1, "FAIL II=1 stream=%0d cycle=%0d previous=%0d", stream, cycle, previous);
            throughput_checks++;
        end
    endtask

    always @(posedge clk_i) begin
        cycle = cycle + 1;
        if (rst_n_i && checking) begin
            if (hold_update && (!object_update_valid_o ||
                {object_update_idx_o, object_update_data_o} !== held_update))
                $fatal(1, "FAIL held update case=%0d cycle=%0d", case_number, cycle);
            if (hold_event && (!object_event_valid_o ||
                {object_event_idx_o, object_event_hit_o, object_event_free_o} !== held_event))
                $fatal(1, "FAIL held event case=%0d cycle=%0d", case_number, cycle);
            if (hold_quad && (!object_quad_valid_o ||
                {object_quad_data_o, object_quad_y_o, object_quad_x_o} !== held_quad))
                $fatal(1, "FAIL held quad case=%0d cycle=%0d", case_number, cycle);
            hold_update = object_update_valid_o && !object_update_ready_i;
            hold_event = object_event_valid_o && !object_event_ready_i;
            hold_quad = object_quad_valid_o && !object_quad_ready_i;
            held_update = {object_update_idx_o, object_update_data_o};
            held_event = {object_event_idx_o, object_event_hit_o, object_event_free_o};
            held_quad = {object_quad_data_o, object_quad_y_o, object_quad_x_o};
            if (object_record_valid_i && object_record_ready_o) begin
                check_spacing(last_input, 0);
                last_input = cycle;
                input_total++;
            end
            if (!step_mode && (object_event_valid_o || object_update_valid_o))
                $fatal(1, "FAIL STEP=0 emitted update/event");
            if (object_update_valid_o && object_update_ready_i) begin
                while (update_index < object_count && !events[base_index+update_index][9])
                    update_index++;
                if (update_index >= object_count || object_update_idx_o !== 24'(update_index))
                    $fatal(1, "FAIL update index case=%0d got=%0d expected=%0d",
                           case_number, object_update_idx_o, update_index);
                if (object_update_data_o !== updates[base_index+update_index])
                    $fatal(1, "FAIL update case=%0d idx=%0d got=%064h expected=%064h",
                           case_number, update_index, object_update_data_o,
                           updates[base_index+update_index]);
                check_spacing(last_update, 1);
                last_update = cycle;
                update_index++;
                update_total++;
            end
            if (object_event_valid_o && object_event_ready_i) begin
                if (event_index >= object_count || object_event_idx_o !== 24'(event_index) ||
                    {object_event_free_o, object_event_hit_o} !==
                    events[base_index+event_index][8:0])
                    $fatal(1, "FAIL event case=%0d idx=%0d got=%03h expected=%03h",
                           case_number, event_index, {object_event_free_o, object_event_hit_o},
                           events[base_index+event_index][8:0]);
                check_spacing(last_event, 2);
                last_event = cycle;
                event_index++;
                event_total++;
            end
            if (object_quad_valid_o && object_quad_ready_i) begin
                while (quad_index < object_count && !events[base_index+quad_index][10])
                    quad_index++;
                if (quad_index >= object_count ||
                    object_quad_data_o !== quads[base_index+quad_index] ||
                    {object_quad_y_o, object_quad_x_o} !== positions[base_index+quad_index])
                    $fatal(1, "FAIL quad case=%0d idx=%0d data=%032h expected=%032h xy=%09h/%09h",
                           case_number, quad_index, object_quad_data_o,
                           quads[base_index+quad_index], {object_quad_y_o, object_quad_x_o},
                           positions[base_index+quad_index]);
                check_spacing(last_quad, 3);
                last_quad = cycle;
                quad_index++;
                quad_total++;
            end
            if (unit_done_o && (object_update_valid_o || object_event_valid_o ||
                                object_quad_valid_o))
                $fatal(1, "FAIL done before output drain");
            if (object_result_valid_o && !object_publish_i)
                $fatal(1, "FAIL result before publication barrier");
        end
    end

    task automatic launch(input logic [625:0] configuration);
        @(negedge clk_i);
        finish_i = 0;
        object_publish_i = 0;
        object_result_ready_i = 0;
        object_cfg_live_i = configuration[63:0];
        object_cfg_targets_i = configuration[575:64];
        object_cfg_hit_max_i = configuration[599:576];
        object_cfg_free_max_i = configuration[623:600];
        object_cfg_valid_i = 1;
        do @(posedge clk_i); while (!object_cfg_ready_o);
        @(negedge clk_i);
        object_cfg_valid_i = 0;
        object_cfg_live_i = 0;
        object_cfg_targets_i = 0;
        object_cfg_hit_max_i = 0;
        object_cfg_free_max_i = 0;
        draw_command_i = 0;
        draw_command_i[33:32] = configuration[625:624];
        draw_valid_i = 1;
        do @(posedge clk_i); while (!draw_ready_o);
        @(negedge clk_i);
        draw_valid_i = 0;
        draw_command_i = '1;
    endtask

    task automatic send_object(input integer index);
        object_record_data_i = records[base_index+index];
        object_record_idx_i = 24'(index);
        object_record_valid_i = 1;
        do @(posedge clk_i); while (!object_record_ready_o);
        @(negedge clk_i);
        object_record_valid_i = 0;
    endtask

    initial begin
        rst_n_i = 0;
        object_cfg_valid_i = 0;
        object_cfg_live_i = 0;
        object_cfg_targets_i = 0;
        object_cfg_hit_base_i = 32'h80010000;
        object_cfg_hit_max_i = 0;
        object_cfg_free_base_i = 32'h80030000;
        object_cfg_free_max_i = 0;
        draw_valid_i = 0;
        draw_command_i = 0;
        object_record_valid_i = 0;
        object_record_data_i = 0;
        object_record_idx_i = 0;
        object_update_ready_i = 1;
        object_event_ready_i = 1;
        object_quad_ready_i = 1;
        finish_i = 0;
        stop_i = 0;
        object_publish_i = 0;
        object_result_ready_i = 0;
        $readmemh("build/gpu_object/records.hex", records);
        $readmemh("build/gpu_object/updates.hex", updates);
        $readmemh("build/gpu_object/events.hex", events);
        $readmemh("build/gpu_object/quads.hex", quads);
        $readmemh("build/gpu_object/positions.hex", positions);
        $readmemh("build/gpu_object/configs.hex", configs);
        repeat (3) @(negedge clk_i);
        rst_n_i = 1;
        finish_i = 1;
        repeat (2) @(negedge clk_i);
        finish_i = 0;
        repeat (8) begin
            @(negedge clk_i);
            if (unit_done_o) $fatal(1, "FAIL no-cfg waiting done must be low");
        end
        finish_i = 1;
        @(negedge clk_i);
        if (!unit_done_o) $fatal(1, "FAIL no-cfg empty completion");
        finish_i = 0;
        @(negedge clk_i);
        if (unit_done_o) $fatal(1, "FAIL falling finish did not clear done");
        for (case_number = 0; case_number < CASES; case_number++) begin
            cfg = configs[case_number];
            base_index = int'(cfg[673:650]);
            object_count = int'(cfg[649:626]);
            stalls = cfg[748];
            throughput = cfg[749];
            step_mode = cfg[624];
            update_index = 0;
            event_index = 0;
            quad_index = 0;
            last_input = -1;
            last_update = -1;
            last_event = -1;
            last_quad = -1;
            checking = 1;
            launch(cfg[625:0]);
            for (integer index = 0; index < object_count; index++)
                send_object(index);
            finish_i = 1;
            while (!unit_done_o) @(negedge clk_i);
            while (update_index < object_count && !events[base_index+update_index][9])
                update_index++;
            while (quad_index < object_count && !events[base_index+quad_index][10])
                quad_index++;
            if (update_index != object_count || quad_index != object_count ||
                event_index != (step_mode ? object_count : 0))
                $fatal(1, "FAIL missing output case=%0d updates=%0d events=%0d quads=%0d",
                       case_number, update_index, event_index, quad_index);
            repeat (4) begin
                @(negedge clk_i);
                if (object_result_valid_o || !unit_done_o || perf_object_busy_o)
                    $fatal(1, "FAIL deferred publication/done/busy case=%0d", case_number);
            end
            object_publish_i = 1;
            repeat (4) begin
                @(negedge clk_i);
                if (!object_result_valid_o || object_result_hit_count_o !== cfg[697:674] ||
                    object_result_free_count_o !== cfg[721:698] ||
                    object_result_alive_count_o !== cfg[745:722] ||
                    object_result_overflow_o !== cfg[747:746])
                    $fatal(1, "FAIL result case=%0d got=%0d/%0d/%0d/%b expected=%0d/%0d/%0d/%b",
                           case_number, object_result_hit_count_o, object_result_free_count_o,
                           object_result_alive_count_o, object_result_overflow_o,
                           cfg[697:674], cfg[721:698], cfg[745:722], cfg[747:746]);
            end
            object_result_ready_i = 1;
            @(negedge clk_i);
            object_result_ready_i = 0;
            object_publish_i = 0;
            checking = 0;
            $display("case %0d PASS objects=%0d", case_number, object_count);
        end
        // Stop discards queued business outputs and keeps the DMA-return consumer ready.
        stalls = 1;
        base_index = int'(configs[10][673:650]);
        launch(configs[10][625:0]);
        for (integer index = 0; index < 8; index++) send_object(index);
        stop_i = 1;
        #1;
        if (object_update_valid_o || object_event_valid_o || object_quad_valid_o ||
            !object_record_ready_o)
            $fatal(1, "FAIL stop stream behavior");
        @(negedge clk_i);
        if (!unit_done_o || perf_object_busy_o || object_result_valid_o)
            $fatal(1, "FAIL stop completion");
        stop_i = 0;
        $display("PASS gpu_object cases=%0d inputs=%0d updates=%0d events=%0d quads=%0d II1=%0d",
                 CASES, input_total, update_total, event_total, quad_total, throughput_checks);
        $finish;
    end
endmodule
