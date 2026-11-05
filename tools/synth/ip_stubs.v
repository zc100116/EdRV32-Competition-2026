// File: ip_stubs.v
// Spec: C-Y1; fpga/ip/*.md expected ports.
// Description: Port-only synchronous IP blackboxes for structural synthesis.
// Clock domain: clk_sys (connections supplied by rtl/tech wrappers).

(* blackbox *) module ip_ram_icache_tag (
    input wire wr_clk,
    input wire wr_en,
    input wire [8:0] wr_addr,
    input wire [17:0] wr_data,
    input wire rd_clk,
    input wire rd_clk_en,
    input wire wr_rst,
    input wire rd_rst,
    input wire [8:0] rd_addr,
    output wire [17:0] rd_data
);
endmodule

(* blackbox *) module ip_ram_icache_data (
    input wire wr_clk,
    input wire wr_en,
    input wire [10:0] wr_addr,
    input wire [63:0] wr_data,
    input wire rd_clk,
    input wire rd_clk_en,
    input wire wr_rst,
    input wire rd_rst,
    input wire [10:0] rd_addr,
    output wire [63:0] rd_data
);
endmodule

(* blackbox *) module ip_ram_dcache_tag (
    input wire wr_clk,
    input wire wr_en,
    input wire [8:0] wr_addr,
    input wire [19:0] wr_data,
    input wire rd_clk,
    input wire rd_clk_en,
    input wire wr_rst,
    input wire rd_rst,
    input wire [8:0] rd_addr,
    output wire [19:0] rd_data
);
endmodule

(* blackbox *) module ip_ram_dcache_data (
    input wire wr_clk,
    input wire wr_en,
    input wire [10:0] wr_addr,
    input wire [63:0] wr_data,
    input wire [7:0] wr_byte_en,
    input wire rd_clk,
    input wire rd_clk_en,
    input wire wr_rst,
    input wire rd_rst,
    input wire [10:0] rd_addr,
    output wire [63:0] rd_data
);
endmodule

(* blackbox *) module ip_ram_sram (
    input wire clk,
    input wire clk_en,
    input wire wr_en,
    input wire [7:0] wr_byte_en,
    input wire rst,
    input wire [12:0] addr,
    input wire [63:0] wr_data,
    output wire [63:0] rd_data
);
endmodule

(* blackbox *) module ip_rom_boot (
    input wire clk,
    input wire clk_en,
    input wire rst,
    input wire [10:0] addr,
    output wire [63:0] rd_data
);
endmodule

(* blackbox *) module ip_mul_s33x33 (
    input wire clk,
    input wire ce,
    input wire rst,
    input wire [32:0] a,
    input wire [32:0] b,
    output wire [65:0] p
);
endmodule

(* blackbox *) module ip_lutram_cpu_btb (
    input wire wr_clk,
    input wire rd_clk,
    input wire rst,
    input wire wr_en,
    input wire [6:0] wr_addr,
    input wire [57:0] wr_data,
    input wire [6:0] rd_addr,
    output wire [57:0] rd_data
);
endmodule

(* blackbox *) module ip_lutram_cpu_direction (
    input wire wr_clk,
    input wire rd_clk,
    input wire rst,
    input wire wr_en,
    input wire [9:0] wr_addr,
    input wire [3:0] wr_data,
    input wire [9:0] rd_addr,
    output wire [3:0] rd_data
);
endmodule
