module unpack_probe (
    input wire clk_i,
    input wire [2:0] push_i, tail_i, head_i,
    input wire [2:0] data_i,
    output wire [2:0] data_o
);
    genvar c;
    generate
        for (c = 0; c < 3; c = c + 1) begin : g_chan
            reg buf_r [0:1];
            always @(posedge clk_i) begin
                if (push_i[c])
                    buf_r[tail_i[c]] <= data_i[c];
            end
            assign data_o[c] = buf_r[head_i[c]];
        end
    endgenerate
endmodule
