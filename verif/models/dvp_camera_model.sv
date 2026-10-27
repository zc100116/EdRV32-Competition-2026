// File: dvp_camera_model.sv
// Spec: vin 2.1; vin-testplan 2.
// Description: Task-driven DVP sensor with supplied RGB565 images and malformed frames.
// Clock domain: independently generated, configurable pclk.
`timescale 1ns/1ps
module dvp_camera_model (
    output logic pclk_o = 0,
    output logic vsync_o = 1,
    output logic href_o = 0,
    output logic [7:0] data_o = 0
);
    realtime half_period_ns = 10.416;
    realtime phase_ns = 0;
    int line_blank = 16;
    int frame_blank = 32;
    int vsync_width = 4;
    bit transmitting = 0;

    initial begin
        #0.001;
        #(phase_ns);
        forever begin
            #(half_period_ns);
            pclk_o = ~pclk_o;
        end
    end

    task automatic blank(input int cycles_i);
        repeat (cycles_i) @(negedge pclk_o);
    endtask

    // The image is row-major at raw_width, including any injected extra columns/rows.
    // A stopped frame leaves VSYNC low; the next call closes it before the next SOF.
    task automatic send_frame(
        input int width_i,
        input int height_i,
        input logic [15:0] image_i[],
        input int line_delta_i = 0,
        input int rows_delta_i = 0,
        input bit extra_byte_i = 0,
        input int stop_after_lines_i = -1
    );
        int raw_width;
        int raw_height;
        raw_width = width_i + line_delta_i;
        raw_height = height_i + rows_delta_i;
        transmitting = 1;
        @(negedge pclk_o);
        href_o = 0;
        vsync_o = 1;
        blank(vsync_width);
        vsync_o = 0;
        blank(frame_blank);
        for (int y = 0; y < raw_height; y++) begin
            if (stop_after_lines_i >= 0 && y == stop_after_lines_i) begin
                transmitting = 0;
                return;
            end
            for (int x = 0; x < raw_width; x++) begin
                href_o = 1;
                data_o = image_i[y*raw_width+x][15:8];
                @(negedge pclk_o);
                data_o = image_i[y*raw_width+x][7:0];
                @(negedge pclk_o);
            end
            if (extra_byte_i) begin
                href_o = 1;
                data_o = 8'he7;
                @(negedge pclk_o);
            end
            href_o = 0;
            data_o = 0;
            blank(line_blank);
        end
        blank(frame_blank);
        vsync_o = 1;
        transmitting = 0;
    endtask
endmodule
