// ============================================================================
// File        : edrv32_render_compose_format.v
// Description : RGB565 base conversion around the shared ARGB blend pipeline.
// ============================================================================

module edrv32_render_compose_format (
    input  wire [31:0] base565_i,
    output wire [63:0] base_argb_o,
    input  wire [63:0] blended_argb_i,
    output wire [31:0] display565_o
);

    function [31:0] unpack565;
        input [15:0] color;
        begin
            unpack565 = {8'hff,
                         color[15:11], color[15:13],
                         color[10:5], color[10:9],
                         color[4:0], color[4:2]};
        end
    endfunction

    function [15:0] pack565;
        input [31:0] color;
        begin
            pack565 = {color[23:19], color[15:10], color[7:3]};
        end
    endfunction

    assign base_argb_o = {unpack565(base565_i[31:16]),
                          unpack565(base565_i[15:0])};
    assign display565_o = {pack565(blended_argb_i[63:32]),
                            pack565(blended_argb_i[31:0])};

endmodule
