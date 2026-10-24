// Simulation-only functional model of the generated Pango 128x21 DRM.
module pango_cache_tag_128x21 (
    input  wire [20:0] wr_data,
    input  wire [6:0]  wr_addr,
    input  wire        wr_en,
    input  wire        wr_clk,
    input  wire        wr_rst,
    output reg  [20:0] rd_data,
    input  wire [6:0]  rd_addr,
    input  wire        rd_clk,
    input  wire        rd_rst
);
    reg [20:0] memory [0:127];

    // Separate generated-IP clocks are part of the vendor interface.  The
    // cache wrapper connects them to one clock; nonblocking updates preserve
    // read-first behavior for a same-address collision.
    always @(posedge wr_clk) begin
        if (!wr_rst && wr_en)
            memory[wr_addr] <= wr_data;
    end

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst)
            rd_data <= 21'd0;
        else
            rd_data <= memory[rd_addr];
    end
endmodule
