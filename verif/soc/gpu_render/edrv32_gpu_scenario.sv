// File: edrv32_gpu_scenario.sv
// Spec: gpu-soc-testplan ST-10; gpu-soc 8.2; GPU 2.1, 2.10.
// Description: Compare a full decoded HDMI frame against model-generated RGB565.
// Clock domain: clk_pix HDMI frame capture; DDR mailbox in clk_mem.
`timescale 1ns/1ps
module edrv32_gpu_scenario (
    output bit checks_complete_o,
    output wire [1:0] model_sda_oe_o
);
    logic [15:0] expected [0:230399];
    logic [15:0] pixel;
    logic [23:0] rgb;
    integer frame_start;
    assign model_sda_oe_o = 2'b00;
    initial begin
        checks_complete_o = 0;
        #1;
        $readmemh({$root.edrv32_gpu_soc_tb.data_dir, "/surface.hex"}, expected);
        wait ($root.edrv32_gpu_soc_tb.u_ddr.peek(32'h003ff000) == 10);
        frame_start = $root.edrv32_gpu_soc_tb.u_hdmi.frame_count_o;
        wait ($root.edrv32_gpu_soc_tb.u_hdmi.frame_count_o >= frame_start + 2);
        @(negedge $root.edrv32_gpu_soc_tb.clk_pix_i);
        if ($root.edrv32_gpu_soc_tb.u_hdmi.frame_pixel_count_o != 921600)
            $fatal(1, "FAIL HDMI frame pixel count time=%0t", $time);
        for (int y = 0; y < 720; y++) begin
            for (int x = 0; x < 1280; x++) begin
                pixel = expected[(y/2)*640 + x/2];
                rgb = {pixel[15:11], pixel[15:13], pixel[10:5], pixel[10:9],
                        pixel[4:0], pixel[4:2]};
                if ($root.edrv32_gpu_soc_tb.u_hdmi.frame_pixels[y*1280+x] !== rgb)
                    $fatal(1, "FAIL HDMI x=%0d y=%0d expected=%h actual=%h time=%0t",
                        x, y, rgb, $root.edrv32_gpu_soc_tb.u_hdmi.frame_pixels[y*1280+x], $time);
            end
        end
        checks_complete_o = 1;
        $root.edrv32_gpu_soc_tb.u_ddr.poke(32'h003ff004, 8'd1);
        $display("CHECK ST-10 HDMI pixels=921600 source=640x360 stripes=2");
    end
endmodule
