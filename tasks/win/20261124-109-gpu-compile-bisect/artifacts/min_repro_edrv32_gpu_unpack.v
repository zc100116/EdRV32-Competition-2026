module unpack_probe (
    input wire clk_i,
    input wire [2:0] push_i, tail_i, head_i,
    input wire [2:0] data_i,
    output wire [2:0] data_o
);
    reg buf_r [0:5];
    genvar c;
    generate
        for (c = 0; c < 3; c = c + 1) begin : g_chan
            always @(posedge clk_i) begin
                if (push_i[c])
                    buf_r[c*2 + tail_i[c]] <= data_i[c];
            end
            assign data_o[c] = buf_r[c*2 + head_i[c]];
        end
    endgenerate
endmodule
