// File: edrv32_eth_mdio.v
// Spec: eth 2.7, 4.2.
// Description: Clause 22 management transactions with 32-bit preamble and clk/64 MDC.
//              Output changes on falling edges; read data is sampled on rising edges.
// Clock domain: clk_mem.
module edrv32_eth_mdio (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,
    input wire clear_i,

    // Command and result.
    input wire start_i,
    input wire [31:0] command_i,
    output reg busy_o,
    output reg [15:0] data_o,

    // PHY serial interface.
    output wire mdc_o,
    output wire mdio_o,
    output wire mdio_oe,
    input wire mdio_i
);
    wire unused_w;
    assign unused_w = &{1'b0, command_i[15:11]};
    reg [5:0] divider_r;
    reg [5:0] idx_r;
    reg [63:0] frame_r;
    reg write_r;
    reg [15:0] read_r;
    assign mdc_o = divider_r[5];
    assign mdio_o = frame_r[63];
    assign mdio_oe = busy_o && (write_r || idx_r < 6'd46);
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            divider_r <= 6'd0;
            idx_r <= 6'd0;
            busy_o <= 1'b0;
            data_o <= 16'd0;
        end else if (clear_i) begin
            divider_r <= 6'd0;
            idx_r <= 6'd0;
            busy_o <= 1'b0;
            data_o <= 16'd0;
        end else begin
            divider_r <= divider_r + 6'd1;
            if (start_i && !busy_o) begin
                busy_o <= 1'b1;
                divider_r <= 6'd0;
                idx_r <= 6'd0;
            end else if (busy_o && divider_r == 6'd63) begin
                if (idx_r == 6'd63) begin
                    busy_o <= 1'b0;
                    if (!write_r)
                        data_o <= read_r;
                end else begin
                    idx_r <= idx_r + 6'd1;
                end
            end
        end
    end
    always @(posedge clk_i) begin
        if (start_i && !busy_o) begin
            frame_r <= {32'hffffffff, 2'b01, command_i[10] ? 2'b01 : 2'b10,
                command_i[9:5], command_i[4:0], 2'b10, command_i[31:16]};
            write_r <= command_i[10];
        end else if (busy_o && divider_r == 6'd63) begin
            frame_r <= {frame_r[62:0], 1'b1};
        end
        if (busy_o && divider_r == 6'd31 && idx_r >= 6'd48)
            read_r <= {read_r[14:0], mdio_i};
    end
endmodule
