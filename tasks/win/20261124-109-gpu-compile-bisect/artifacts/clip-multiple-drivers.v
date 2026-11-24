module clip_output_probe (
    input wire clk_i,
    input wire push_i,
    input wire mode_i,
    input wire write_i,
    input wire read_i,
    input wire [5:0] triangle_i,
    input wire [15:0] clipped_i,
    output wire [15:0] data_o
);
    reg [15:0] output_r [0:1];
    integer chunk;
    always @(posedge clk_i) begin
        if (push_i) begin
            if (mode_i)
                output_r[write_i] <= {10'd0, triangle_i};
            else begin
                for (chunk = 0; chunk < 8; chunk = chunk + 1)
                    output_r[write_i][chunk * 2 +: 2] <= clipped_i[chunk * 2 +: 2];
            end
        end
    end
    assign data_o = output_r[read_i];
endmodule
