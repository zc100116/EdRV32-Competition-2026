// File: edrv32_fpga_imgtest_keys.v
// Spec: Task B3-9; edrv32-soc-spec 3.5.
// Description: Accept a key level after 10 ms stable and pulse once per press.
//              Inputs have already passed the board's common CDC primitives.
// Clock domain: clk_mem (125 MHz).
module edrv32_fpga_imgtest_keys (
    input wire clk_i,
    input wire rst_n_i,
    input wire [2:0] key_n_i,
    output wire [2:0] press_o
);
    genvar key;
    generate
        for (key = 0; key < 3; key = key + 1) begin : g_key
            reg [20:0] cnt_r;
            reg level_r;
            wire accept_w = cnt_r == 21'd1249999;
            assign press_o[key] = accept_w && level_r && !key_n_i[key];
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    cnt_r <= 21'd0;
                    level_r <= 1'b1;
                end else if (key_n_i[key] == level_r) begin
                    cnt_r <= 21'd0;
                end else if (accept_w) begin
                    cnt_r <= 21'd0;
                    level_r <= key_n_i[key];
                end else begin
                    cnt_r <= cnt_r + 1'b1;
                end
            end
        end
    endgenerate
endmodule
