// File: edrv32_fpga_imgtest_cam_init.v
// Spec: Task B3-9; design b2-software 3.2; legacy edrv32_ov5640_stereo_init.
// Description: Release both camera resets, then send the B2 sensor table to each.
//              Board PWDN is unbonded as on board_b2; no runtime SCCB interface.
// Clock domain: clk_mem (125 MHz).
module edrv32_fpga_imgtest_cam_init (
    // Clock and domain reset.
    input wire clk_i,
    input wire rst_n_i,

    // Released pins are implemented as open drain by the board top.
    output wire [1:0] scl_o,
    output wire [1:0] sda_o,
    output wire cam_rst_n_o,
    output reg [1:0] done_o
);
    localparam [2:0] S_RESET = 3'd0;
    localparam [2:0] S_SETTLE = 3'd1;
    localparam [2:0] S_START = 3'd2;
    localparam [2:0] S_WAIT = 3'd3;
    localparam [2:0] S_DONE = 3'd4;
    reg [2:0] state_r;
    reg [21:0] wait_cnt_r;
    reg [7:0] addr_r;
    reg camera_r;
    wire [23:0] data_w;
    wire done_w;
    wire scl_w;
    wire sda_w;

    edrv32_fpga_imgtest_cam_rom u_rom (
        .addr_i(addr_r),
        .data_o(data_w)
    );
    edrv32_fpga_imgtest_sccb u_sccb (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .start_i(state_r == S_START),
        .data_i(data_w),
        .done_o(done_w),
        .scl_o(scl_w),
        .sda_o(sda_w)
    );
    assign cam_rst_n_o = rst_n_i && state_r != S_RESET;
    assign scl_o = camera_r ? {scl_w, 1'b1} : {1'b1, scl_w};
    assign sda_o = camera_r ? {sda_w, 1'b1} : {1'b1, sda_w};

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_RESET;
            wait_cnt_r <= 22'd0;
            addr_r <= 8'd0;
            camera_r <= 1'b0;
            done_o <= 2'b0;
        end else begin
            case (state_r)
                S_RESET: begin
                    // B2 holds RESET low for 5 ms + 1.3 ms, then settles for 21 ms.
                    if (wait_cnt_r == 22'd787499) begin
                        wait_cnt_r <= 22'd0;
                        state_r <= S_SETTLE;
                    end else begin
                        wait_cnt_r <= wait_cnt_r + 1'b1;
                    end
                end
                S_SETTLE: begin
                    if (wait_cnt_r == 22'd2624999) begin
                        state_r <= S_START;
                    end else begin
                        wait_cnt_r <= wait_cnt_r + 1'b1;
                    end
                end
                S_START: state_r <= S_WAIT;
                S_WAIT: begin
                    if (done_w) begin
                        if (addr_r == 8'd243) begin
                            done_o[camera_r] <= 1'b1;
                            if (camera_r) begin
                                state_r <= S_DONE;
                            end else begin
                                camera_r <= 1'b1;
                                addr_r <= 8'd0;
                                state_r <= S_START;
                            end
                        end else begin
                            addr_r <= addr_r + 1'b1;
                            state_r <= S_START;
                        end
                    end
                end
                S_DONE: state_r <= S_DONE;
                default: state_r <= S_RESET;
            endcase
        end
    end
endmodule
