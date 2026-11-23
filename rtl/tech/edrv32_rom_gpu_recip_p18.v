// File: edrv32_rom_gpu_recip_p18.v
// Spec: gpu-spec 2.13.10; microarch 4.8.
// Description: Fixed 1024 x 18 P18 midpoint seed ROM, enabled synchronous read.
//              One cycle read latency; each perspective lane owns one instance.
// Clock domain: clk_gpu.
`include "edrv32_build_mode.vh"
module edrv32_rom_gpu_recip_p18 (
    // Memory clock.
    input wire clk_i,

    // Read port.
    input wire en_i,
    input wire [9:0] addr_i,
    output wire [17:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_rom_gpu_recip_p18 u_ip (
        .clk(clk_i),
        .clk_en(en_i),
        .rst(1'b0),
        .addr(addr_i),
        .rd_data(rd_data_o)
    );
`else
    reg [17:0] memory_r [0:1023];
    reg [17:0] rd_data_r;
    reg [4095:0] image_path_r;

    assign rd_data_o = rd_data_r;

    initial begin
        if (!$value$plusargs("GPU_RECIP_P18_HEX=%s", image_path_r)) begin
            $fatal(1, "GPU_RECIP_P18_HEX is required");
        end
        $readmemh(image_path_r, memory_r);
    end

    always @(posedge clk_i) begin
        if (en_i) begin
            rd_data_r <= memory_r[addr_i];
        end
    end
`endif
endmodule
