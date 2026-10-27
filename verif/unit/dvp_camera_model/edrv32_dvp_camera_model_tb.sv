// File: edrv32_dvp_camera_model_tb.sv
// Spec: vin 2.1; vin-testplan 2.
// Description: Independently decode sensor bytes, line/frame timing and fault injection.
// Clock domain: generated camera pclk.
`timescale 1ns/1ps
module edrv32_dvp_camera_model_tb;
    wire pclk;
    wire vsync;
    wire href;
    wire [7:0] data;
    logic [15:0] image[];
    logic [15:0] decoded[$];
    bit previous_href = 0;
    bit previous_vsync = 1;
    bit byte_phase = 0;
    logic [7:0] first_byte;
    int rows = 0;
    int starts = 0;
    int ends = 0;
    int active_bytes = 0;
    int row_bytes[$];
    int blank_ticks = 0;
    int frame_rows = 0;
    int high_ticks = 0;

    dvp_camera_model u_camera (
        .pclk_o(pclk),
        .vsync_o(vsync),
        .href_o(href),
        .data_o(data)
    );

    task automatic equal(input string name_i,
        input int expected_i,
        input int actual_i);
        if (actual_i != expected_i)
            $fatal(1, "FAIL %s expected=%0d actual=%0d time=%0t",
                name_i, expected_i, actual_i, $time);
    endtask

    always @(posedge pclk) begin
        if (vsync) high_ticks++;
        if (previous_vsync && !vsync) begin
            starts++;
            if (high_ticks < u_camera.vsync_width)
                $fatal(1, "FAIL VSYNC width expected>=%0d actual=%0d time=%0t",
                    u_camera.vsync_width, high_ticks, $time);
            high_ticks = 0;
            frame_rows = 0;
            blank_ticks = 0;
        end
        if (!vsync && !href) blank_ticks++;
        if (!previous_href && href) begin
            equal("line or leading frame blank", frame_rows == 0
                ? u_camera.frame_blank : u_camera.line_blank, blank_ticks);
            blank_ticks = 0;
        end
        if (!previous_vsync && vsync) ends++;
        if (href) begin
            active_bytes++;
            if (!byte_phase) first_byte = data;
            else decoded.push_back({first_byte, data});
            byte_phase = !byte_phase;
        end
        if (previous_href && !href) begin
            rows++;
            frame_rows++;
            row_bytes.push_back(active_bytes);
            active_bytes = 0;
            byte_phase = 0;
        end
        previous_href = href;
        previous_vsync = vsync;
    end

    task automatic run_frame(input int columns_i,
        input int rows_i,
        input int dx_i,
        input int dy_i,
        input bit odd_i,
        input int stop_i);
        int actual_rows;
        int actual_columns;
        decoded.delete();
        row_bytes.delete();
        rows = 0;
        actual_columns = columns_i + dx_i;
        actual_rows = stop_i < 0 ? rows_i + dy_i : stop_i;
        image = new[actual_columns * (rows_i+dy_i)];
        foreach (image[i]) image[i] = 16'h9182 ^ 16'(i*37);
        u_camera.send_frame(columns_i, rows_i, image, dx_i, dy_i, odd_i, stop_i);
        repeat (2) @(negedge pclk);
        equal("model task idle", 0, int'(u_camera.transmitting));
        equal("rows", actual_rows, rows);
        equal("pixel count", actual_rows*actual_columns, decoded.size());
        foreach (decoded[i]) equal("RGB565 high-byte first", int'(image[i]),
            int'(decoded[i]));
        foreach (row_bytes[i]) equal("HREF bytes", 2*actual_columns+int'(odd_i),
            row_bytes[i]);
    endtask

    initial begin
        u_camera.half_period_ns = 20.833;
        u_camera.phase_ns = 2.7;
        u_camera.line_blank = 7;
        u_camera.frame_blank = 9;
        u_camera.vsync_width = 3;
        run_frame(8, 4, 0, 0, 0, -1);
        run_frame(8, 4, 2, 1, 1, -1);
        u_camera.half_period_ns = 5.952;
        run_frame(8, 4, -2, -1, 1, -1);
        run_frame(8, 4, 0, 0, 0, 2);
        equal("stopped frame VSYNC", 0, int'(vsync));
        run_frame(8, 4, 0, 0, 0, -1);
        equal("SOF count", 5, starts);
        equal("EOF count including next-call closure", 5, ends);
        $display("PASS dvp_camera_model byte order, blanking, faults and clocks");
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "FAIL timeout expected=finished actual=running time=%0t", $time);
    end
endmodule
