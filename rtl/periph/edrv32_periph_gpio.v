// File: edrv32_periph_gpio.v
// Spec: sys-subsys-spec 2.7, 3.2, 4.4, 6; edrv32-soc-spec 4.3
// Description: Sixteen synchronized GPIO inputs with programmable debounce.
//              Byte strobes apply to OUT/OE; enabled edges latch interrupt status.
// Clock domain: clk_sys (clk_i).
module edrv32_periph_gpio (
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

    // GPIO pads.
    input wire [15:0] gpio_i,
    output wire [15:0] gpio_o,
    output wire [15:0] gpio_oe_o,

    // Interrupt.
    output wire irq_o
);
    reg [15:0] out_r;
    reg [15:0] oe_r;
    reg [15:0] rise_en_r;
    reg [15:0] fall_en_r;
    reg [15:0] irq_stat_r;
    reg [23:0] debounce_r;
    reg [15:0] previous_r;
    wire [15:0] sync_w;
    wire [15:0] filtered_w;
    wire [15:0] in_w;
    wire [15:0] edge_w;
    wire write_w;
    wire [15:0] clear_w;
    wire unused_w;

    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_i;
    assign clear_w = (write_w && apb_paddr_i == 12'h018) ? apb_pwdata_i[15:0] : 16'b0;
    assign in_w = (debounce_r == 0) ? sync_w : filtered_w;
    assign edge_w = ((in_w & ~previous_r) & rise_en_r)
                    | ((~in_w & previous_r) & fall_en_r);
    assign gpio_o = out_r;
    assign gpio_oe_o = oe_r;
    assign irq_o = |irq_stat_r;
    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    assign unused_w = |{apb_pwdata_i[31:24], apb_pstrb_i[3:2]};

    genvar pin;
    generate
        for (pin = 0; pin < 16; pin = pin + 1) begin : g_pin
            reg [23:0] stable_cnt_r;
            reg filtered_r;

            edrv32_cdc_sync_bit u_input_sync (
                .clk_i(clk_i),
                .rst_n_i(rst_n_i),
                .bit_i(gpio_i[pin]),
                .bit_o(sync_w[pin])
            );

            assign filtered_w[pin] = filtered_r;

            // spec 2.7: count consecutive samples differing from the accepted level.
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    stable_cnt_r <= 24'b0;
                    filtered_r <= 1'b0;
                end else if (debounce_r == 0) begin
                    stable_cnt_r <= 24'b0;
                    filtered_r <= sync_w[pin];
                end else if (sync_w[pin] == filtered_r) begin
                    stable_cnt_r <= 24'b0;
                end else if (stable_cnt_r >= debounce_r - 1'b1) begin
                    filtered_r <= sync_w[pin];
                    stable_cnt_r <= 24'b0;
                end else begin
                    stable_cnt_r <= stable_cnt_r + 1'b1;
                end
            end
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            out_r <= 16'b0;
            oe_r <= 16'b0;
            rise_en_r <= 16'b0;
            fall_en_r <= 16'b0;
            irq_stat_r <= 16'b0;
            debounce_r <= 24'b0;
            previous_r <= 16'b0;
        end else begin
            previous_r <= in_w;
            irq_stat_r <= (irq_stat_r & ~clear_w) | edge_w;
            if (write_w) begin
                case (apb_paddr_i)
                    12'h004: begin
                        if (apb_pstrb_i[0]) out_r[7:0] <= apb_pwdata_i[7:0];
                        if (apb_pstrb_i[1]) out_r[15:8] <= apb_pwdata_i[15:8];
                    end
                    12'h008: begin
                        if (apb_pstrb_i[0]) oe_r[7:0] <= apb_pwdata_i[7:0];
                        if (apb_pstrb_i[1]) oe_r[15:8] <= apb_pwdata_i[15:8];
                    end
                    12'h010: rise_en_r <= apb_pwdata_i[15:0];
                    12'h014: fall_en_r <= apb_pwdata_i[15:0];
                    12'h01c: debounce_r <= apb_pwdata_i[23:0];
                    default: begin end
                endcase
            end
        end
    end

    always @(*) begin
        apb_prdata_o = 32'b0;
        case (apb_paddr_i)
            12'h000: apb_prdata_o = 32'h00010001;
            12'h004: apb_prdata_o = {16'b0, out_r};
            12'h008: apb_prdata_o = {16'b0, oe_r};
            12'h00c: apb_prdata_o = {16'b0, in_w};
            12'h010: apb_prdata_o = {16'b0, rise_en_r};
            12'h014: apb_prdata_o = {16'b0, fall_en_r};
            12'h018: apb_prdata_o = {16'b0, irq_stat_r};
            12'h01c: apb_prdata_o = {8'b0, debounce_r};
            default: begin end
        endcase
    end
endmodule
