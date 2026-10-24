// ============================================================================
// File        : pango_boot_rom_storage.v
// Author      : Edward ZC
// Description : PG2L200H 16-KiB Boot ROM backend using generated Pango DRM IP.
// Notes       : The generated IP module is named boot_rom. Its initialization
//               image is selected when the IP is generated in the PDS GUI.
// ============================================================================
module pango_boot_rom_storage (
    // --- Clock and reset ---
    input  wire         clk,
    input  wire         rst_n,

    // --- Synchronous 64-bit read port ---
    input  wire         rd_en_i,
    input  wire [10:0]  rd_addr_i,
    output wire [63:0]  rd_data_o
);
    reg [10:0] rd_addr_r;
    wire [10:0] ip_rd_addr_w = rd_en_i ? rd_addr_i : rd_addr_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rd_addr_r <= 11'h000;
        else if (rd_en_i)
            rd_addr_r <= rd_addr_i;
    end

    boot_rom u_boot_rom (
        .addr    (ip_rd_addr_w),
        .rd_data (rd_data_o),
        .clk     (clk),
        .rst     (~rst_n)
    );
endmodule
