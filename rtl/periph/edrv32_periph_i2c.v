// File: edrv32_periph_i2c.v
// Spec: sys-subsys-spec 2.8, 3.2, 4.5, 6; edrv32-soc-spec 4.3
// Description: Byte-command I2C master with two selectable open-drain pad pairs.
//              Four quarter phases generate START, repeated START, data, ACK and STOP.
// Clock domain: clk_sys (clk_i); pad inputs use common level synchronizers.
module edrv32_periph_i2c (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // APB slave.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output reg [31:0] apb_prdata_o,
    output wire apb_pready_o,
    output wire apb_pslverr_o,

    // I2C pads: output data is always zero; OE drives low, otherwise releases.
    input wire [1:0] i2c0_scl_i,
    output wire [1:0] i2c0_scl_o,
    output wire [1:0] i2c0_scl_oe_o,
    input wire [1:0] i2c0_sda_i,
    output wire [1:0] i2c0_sda_o,
    output wire [1:0] i2c0_sda_oe_o,

    // Interrupt.
    output wire irq_o
);
    // Share the generated system clock constant with SYSCTRL (spec 4.6).
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    /* verilator lint_on UNUSEDPARAM */
    localparam [31:0] DIV_RESET = (EDRV32_CLK_SYS_HZ + 800000) / 1600000 - 1;
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_START = 3'd1;
    localparam [2:0] S_DATA = 3'd2;
    localparam [2:0] S_ACK = 3'd3;
    localparam [2:0] S_STOP = 3'd4;
    reg enable_r;
    reg port_sel_r;
    reg irq_en_r;
    reg done_r;
    reg nack_r;
    reg bus_held_r;
    reg [15:0] clk_div_r;
    reg [15:0] quarter_cnt_r;
    reg [2:0] state_r;
    reg [1:0] phase_r;
    reg [2:0] bit_r;
    reg read_r;
    reg stop_r;
    reg read_nack_r;
    reg [7:0] tx_data_r;
    reg [7:0] rx_shift_r;
    reg [7:0] rx_data_r;
    reg scl_low_w;
    reg sda_low_w;
    wire [1:0] scl_sync_w;
    wire [1:0] sda_sync_w;
    wire write_w;
    wire busy_w;
    wire command_w;
    wire quarter_w;
    wire finish_w;
    wire done_clear_w;
    wire unused_w;

    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_i;
    assign busy_w = state_r != S_IDLE;
    assign command_w = write_w && apb_paddr_i == 12'h018 && enable_r && !busy_w;
    assign quarter_w = quarter_cnt_r == 0;
    assign finish_w = busy_w && quarter_w && phase_r == 3
                    && ((state_r == S_ACK && !stop_r) || state_r == S_STOP);
    assign done_clear_w = write_w && apb_paddr_i == 12'h010 && apb_pwdata_i[0];
    assign i2c0_scl_o = 2'b0;
    assign i2c0_sda_o = 2'b0;
    assign i2c0_scl_oe_o = port_sel_r ? {scl_low_w, 1'b0} : {1'b0, scl_low_w};
    assign i2c0_sda_oe_o = port_sel_r ? {sda_low_w, 1'b0} : {1'b0, sda_low_w};
    assign irq_o = done_r && irq_en_r;
    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    // SCL is synchronized as specified; stretching and arbitration are unsupported.
    assign unused_w = |{scl_sync_w, apb_pwdata_i[31:16], apb_pstrb_i};

    genvar port;
    generate
        for (port = 0; port < 2; port = port + 1) begin : g_port
            edrv32_cdc_sync_bit u_scl_sync (
                .clk_i(clk_i),
                .rst_n_i(rst_n_i),
                .bit_i(i2c0_scl_i[port]),
                .bit_o(scl_sync_w[port])
            );
            edrv32_cdc_sync_bit u_sda_sync (
                .clk_i(clk_i),
                .rst_n_i(rst_n_i),
                .bit_i(i2c0_sda_i[port]),
                .bit_o(sda_sync_w[port])
            );
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            enable_r <= 1'b0;
            port_sel_r <= 1'b0;
            irq_en_r <= 1'b0;
            done_r <= 1'b0;
            clk_div_r <= DIV_RESET[15:0];
        end else begin
            done_r <= (done_r && !done_clear_w) || finish_w;
            if (write_w) begin
                case (apb_paddr_i)
                    12'h004: begin
                        enable_r <= apb_pwdata_i[0];
                        if (!busy_w) port_sel_r <= apb_pwdata_i[1];
                    end
                    12'h00c: irq_en_r <= apb_pwdata_i[0];
                    12'h014: clk_div_r <= apb_pwdata_i[15:0];
                    default: begin end
                endcase
            end
        end
    end

    always @(*) begin
        scl_low_w = bus_held_r;
        sda_low_w = 1'b0;
        case (state_r)
            S_START: begin
                scl_low_w = (phase_r == 0 && bus_held_r) || phase_r == 3;
                sda_low_w = phase_r >= 2;
            end
            S_DATA: begin
                scl_low_w = phase_r == 0 || phase_r == 3;
                sda_low_w = !read_r && !tx_data_r[bit_r];
            end
            S_ACK: begin
                scl_low_w = phase_r == 0 || phase_r == 3;
                sda_low_w = read_r && !read_nack_r;
            end
            S_STOP: begin
                scl_low_w = phase_r == 0;
                sda_low_w = phase_r < 2;
            end
            default: begin end
        endcase
    end

    always @(posedge clk_i) begin
        if (command_w) begin
            tx_data_r <= apb_pwdata_i[7:0];
        end
        if (state_r == S_DATA && read_r && quarter_w && phase_r == 2)
            rx_shift_r <= {rx_shift_r[6:0], sda_sync_w[port_sel_r]};
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            phase_r <= 2'b0;
            bit_r <= 3'd7;
            quarter_cnt_r <= 16'b0;
            read_r <= 1'b0;
            stop_r <= 1'b0;
            read_nack_r <= 1'b0;
            bus_held_r <= 1'b0;
            nack_r <= 1'b0;
            rx_data_r <= 8'b0;
        end else if (command_w) begin
            state_r <= apb_pwdata_i[8] ? S_START : S_DATA;
            phase_r <= 2'b0;
            bit_r <= 3'd7;
            quarter_cnt_r <= clk_div_r;
            read_r <= apb_pwdata_i[10];
            stop_r <= apb_pwdata_i[9];
            read_nack_r <= apb_pwdata_i[11];
        end else if (busy_w) begin
            if (!quarter_w) begin
                quarter_cnt_r <= quarter_cnt_r - 1'b1;
            end else begin
                quarter_cnt_r <= clk_div_r;
                phase_r <= phase_r + 1'b1;
                case (state_r)
                    S_START: begin
                        if (phase_r == 1) bus_held_r <= 1'b1;
                        if (phase_r == 3) state_r <= S_DATA;
                    end
                    S_DATA: begin
                        if (phase_r == 3) begin
                            if (bit_r == 0) state_r <= S_ACK;
                            else bit_r <= bit_r - 1'b1;
                        end
                    end
                    S_ACK: begin
                        if (phase_r == 2 && !read_r)
                            nack_r <= sda_sync_w[port_sel_r];
                        if (phase_r == 3) begin
                            if (read_r) rx_data_r <= rx_shift_r;
                            state_r <= stop_r ? S_STOP : S_IDLE;
                        end
                    end
                    S_STOP: begin
                        if (phase_r == 3) begin
                            bus_held_r <= 1'b0;
                            state_r <= S_IDLE;
                        end
                    end
                    default: begin end
                endcase
            end
        end
    end

    always @(*) begin
        apb_prdata_o = 32'b0;
        case (apb_paddr_i)
            12'h000: apb_prdata_o = 32'h00040001;
            12'h004: apb_prdata_o = {30'b0, port_sel_r, enable_r};
            12'h008: apb_prdata_o = {29'b0, bus_held_r, nack_r, busy_w};
            12'h00c: apb_prdata_o = {31'b0, irq_en_r};
            12'h010: apb_prdata_o = {31'b0, done_r};
            12'h014: apb_prdata_o = {16'b0, clk_div_r};
            12'h01c: apb_prdata_o = {24'b0, rx_data_r};
            default: begin end
        endcase
    end
endmodule
