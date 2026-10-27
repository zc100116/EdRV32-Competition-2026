// File: tb.sv
// Spec: disp-spec 2.1, 2.4.
// Description: Check every raster cycle for two complete fixed-format frames.
// Clock domain: test pixel clock.
module tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    wire hs;
    wire vs;
    wire de;
    wire [10:0] x;
    wire [9:0] y;
    wire frame_start;
    wire vblank;
    int active_pixels = 0;
    int hs_pixels = 0;
    int vs_pixels = 0;
    int starts = 0;
    int blanks = 0;
    edrv32_disp_timing dut (
        .clk_i(clk), .rst_n_i(rst_n), .hs_o(hs), .vs_o(vs), .de_o(de),
        .x_o(x), .y_o(y), .frame_start_o(frame_start), .vblank_o(vblank)
    );
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        for (int frame = 0; frame < 2; frame++) begin
            for (int row = 0; row < 750; row++) begin
                for (int col = 0; col < 1650; col++) begin
                    bit active;
                    active = col >= 260 && col < 1540 && row >= 25 && row < 745;
                    if (hs !== (col < 40) || vs !== (row < 5) || de !== active ||
                        x !== 11'(col >= 260 && col < 1540 ? col-260 : 0) ||
                        y !== 10'(row >= 25 && row < 745 ? row-25 : 0) ||
                        frame_start !== (col == 260 && row == 25) ||
                        vblank !== (col == 0 && row == 745))
                        $fatal(1, "FAIL timing frame=%0d row=%0d col=%0d", frame, row, col);
                    active_pixels += int'(de);
                    hs_pixels += int'(hs);
                    vs_pixels += int'(vs);
                    starts += int'(frame_start);
                    blanks += int'(vblank);
                    @(negedge clk);
                end
            end
        end
        if (active_pixels != 2*1280*720 || hs_pixels != 2*40*750 ||
            vs_pixels != 2*5*1650 || starts != 2 || blanks != 2)
            $fatal(1, "FAIL raster totals");
        $display("PASS timing: totals, sync polarity/width, porches, coordinates, boundaries");
        $finish;
    end
endmodule
