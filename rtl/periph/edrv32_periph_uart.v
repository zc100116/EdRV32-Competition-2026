// File: edrv32_periph_uart.v
// Spec: sys-subsys-spec 2.6, 3.2, 4.3, 6, 7; edrv32-soc-spec 4.3
// Description: Full duplex 8N1 UART with sixteen-byte transmit and receive FIFOs.
//              Fractional bit timers retain sixteenths of a system clock cycle.
// Clock domain: clk_sys (clk_i); RX enters through the common synchronizer.
module edrv32_periph_uart (
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

    // UART pads.
    input wire uart0_rx_i,
    output wire uart0_tx_o,

    // Interrupt.
    output wire irq_o
);
    // S-R3 integration: replace with generated EDRV32_CLK_SYS_HZ after S-R2 merges.
    localparam [31:0] CLK_SYS_HZ = 150000000;
    localparam [31:0] BAUD_RESET = (CLK_SYS_HZ * 16 + 57600) / 115200;
    reg [1:0] enable_r;
    reg [3:0] irq_en_r;
    reg [1:0] error_r;
    reg [23:0] baud_div_r;
    reg [4:0] rx_thresh_r;
    reg [7:0] tx_fifo_r [0:15];
    reg [7:0] rx_fifo_r [0:15];
    reg [3:0] tx_write_ptr_r;
    reg [3:0] tx_read_ptr_r;
    reg [3:0] rx_write_ptr_r;
    reg [3:0] rx_read_ptr_r;
    reg [4:0] tx_level_r;
    reg [4:0] rx_level_r;
    reg tx_busy_r;
    reg [9:0] tx_shift_r;
    reg [3:0] tx_bit_r;
    reg [24:0] tx_timer_r;
    reg rx_busy_r;
    reg [7:0] rx_shift_r;
    reg [3:0] rx_bit_r;
    reg [24:0] rx_timer_r;
    reg rx_previous_r;
    wire rx_active_w;
    wire rx_w;
    wire write_w;
    wire read_w;
    wire tx_clear_w;
    wire rx_clear_w;
    wire tx_push_w;
    wire tx_pop_w;
    wire rx_push_w;
    wire rx_pop_w;
    wire rx_finish_w;
    wire tx_tick_w;
    wire rx_tick_w;
    wire [3:0] irq_stat_w;
    wire [1:0] error_clear_w;
    wire [1:0] error_set_w;
    wire unused_w;

    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_i;
    assign read_w = apb_psel_i && apb_penable_i && !apb_pwrite_i;
    assign tx_clear_w = write_w && apb_paddr_i == 12'h004 && apb_pwdata_i[2];
    assign rx_clear_w = write_w && apb_paddr_i == 12'h004 && apb_pwdata_i[3];
    assign tx_push_w = write_w && apb_paddr_i == 12'h020 && tx_level_r != 16;
    assign tx_pop_w = !tx_busy_r && enable_r[0] && tx_level_r != 0 && !tx_clear_w;
    assign rx_pop_w = read_w && apb_paddr_i == 12'h024 && rx_level_r != 0;
    assign tx_tick_w = tx_timer_r < 25'd16;
    assign rx_tick_w = rx_timer_r < 25'd16;
    assign rx_finish_w = rx_busy_r && rx_tick_w && rx_bit_r == 9;
    assign rx_push_w = rx_finish_w && rx_w && rx_level_r != 16;
    assign error_set_w = {rx_finish_w && !rx_w,
                            rx_finish_w && rx_w && rx_level_r == 16};
    assign error_clear_w = (write_w && apb_paddr_i == 12'h010)
                            ? apb_pwdata_i[3:2] : 2'b0;
    assign irq_stat_w = {error_r, tx_level_r == 0 && !tx_busy_r,
                        rx_thresh_r != 0 && rx_level_r >= rx_thresh_r};
    assign uart0_tx_o = tx_busy_r ? tx_shift_r[0] : 1'b1;
    assign irq_o = |(irq_stat_w & irq_en_r);
    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    assign unused_w = |{apb_pwdata_i[31:24], apb_pstrb_i};

    // Synchronize the active-low sense so the primitive's reset value means idle.
    edrv32_cdc_sync_bit u_rx_sync (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .bit_i(!uart0_rx_i),
        .bit_o(rx_active_w)
    );
    assign rx_w = !rx_active_w;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            enable_r <= 2'b11;
            irq_en_r <= 4'b0;
            error_r <= 2'b0;
            baud_div_r <= BAUD_RESET[23:0];
            rx_thresh_r <= 5'd1;
        end else begin
            error_r <= (error_r & ~error_clear_w) | error_set_w;
            if (write_w) begin
                case (apb_paddr_i)
                    12'h004: enable_r <= apb_pwdata_i[1:0];
                    12'h00c: irq_en_r <= apb_pwdata_i[3:0];
                    12'h014: baud_div_r <= apb_pwdata_i[23:0];
                    12'h018: rx_thresh_r <= apb_pwdata_i[4:0];
                    default: begin end
                endcase
            end
        end
    end

    // spec 2.6/4.3: clearing a FIFO changes ownership, never resets its storage.
    always @(posedge clk_i) begin
        if (tx_push_w && !tx_clear_w) tx_fifo_r[tx_write_ptr_r] <= apb_pwdata_i[7:0];
        if (rx_push_w && !rx_clear_w) rx_fifo_r[rx_write_ptr_r] <= rx_shift_r;
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            tx_write_ptr_r <= 4'b0;
            tx_read_ptr_r <= 4'b0;
            tx_level_r <= 5'b0;
        end else if (tx_clear_w) begin
            tx_write_ptr_r <= 4'b0;
            tx_read_ptr_r <= 4'b0;
            tx_level_r <= 5'b0;
        end else begin
            if (tx_push_w) tx_write_ptr_r <= tx_write_ptr_r + 1'b1;
            if (tx_pop_w) tx_read_ptr_r <= tx_read_ptr_r + 1'b1;
            case ({tx_push_w, tx_pop_w})
                2'b10: tx_level_r <= tx_level_r + 1'b1;
                2'b01: tx_level_r <= tx_level_r - 1'b1;
                default: begin end
            endcase
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rx_write_ptr_r <= 4'b0;
            rx_read_ptr_r <= 4'b0;
            rx_level_r <= 5'b0;
        end else if (rx_clear_w) begin
            rx_write_ptr_r <= 4'b0;
            rx_read_ptr_r <= 4'b0;
            rx_level_r <= 5'b0;
        end else begin
            if (rx_push_w) rx_write_ptr_r <= rx_write_ptr_r + 1'b1;
            if (rx_pop_w) rx_read_ptr_r <= rx_read_ptr_r + 1'b1;
            case ({rx_push_w, rx_pop_w})
                2'b10: rx_level_r <= rx_level_r + 1'b1;
                2'b01: rx_level_r <= rx_level_r - 1'b1;
                default: begin end
            endcase
        end
    end

    always @(posedge clk_i) begin
        if (tx_pop_w) tx_shift_r <= {1'b1, tx_fifo_r[tx_read_ptr_r], 1'b0};
        else if (tx_busy_r && tx_tick_w) tx_shift_r <= {1'b1, tx_shift_r[9:1]};
        if (rx_busy_r && rx_tick_w && rx_bit_r >= 1 && rx_bit_r <= 8)
            rx_shift_r <= {rx_w, rx_shift_r[7:1]};
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            tx_busy_r <= 1'b0;
            tx_bit_r <= 4'b0;
            tx_timer_r <= 25'b0;
        end else if (tx_pop_w) begin
            tx_busy_r <= 1'b1;
            tx_bit_r <= 4'b0;
            tx_timer_r <= {1'b0, baud_div_r} - 25'd16;
        end else if (tx_busy_r) begin
            if (tx_tick_w) begin
                tx_timer_r <= tx_timer_r + {1'b0, baud_div_r} - 25'd16;
                tx_bit_r <= tx_bit_r + 1'b1;
                if (tx_bit_r == 9) tx_busy_r <= 1'b0;
            end else begin
                tx_timer_r <= tx_timer_r - 25'd16;
            end
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rx_busy_r <= 1'b0;
            rx_bit_r <= 4'b0;
            rx_timer_r <= 25'b0;
            rx_previous_r <= 1'b1;
        end else begin
            rx_previous_r <= rx_w;
            if (!rx_busy_r) begin
                if (enable_r[1] && rx_previous_r && !rx_w) begin
                    rx_busy_r <= 1'b1;
                    rx_bit_r <= 4'b0;
                    rx_timer_r <= {2'b0, baud_div_r[23:1]} - 25'd16;
                end
            end else if (rx_tick_w) begin
                rx_timer_r <= rx_timer_r + {1'b0, baud_div_r} - 25'd16;
                rx_bit_r <= rx_bit_r + 1'b1;
                if (rx_bit_r == 9) rx_busy_r <= 1'b0;
            end else begin
                rx_timer_r <= rx_timer_r - 25'd16;
            end
        end
    end

    always @(*) begin
        apb_prdata_o = 32'b0;
        case (apb_paddr_i)
            12'h000: apb_prdata_o = 32'h00000001;
            12'h004: apb_prdata_o = {30'b0, enable_r};
            12'h008: begin
                apb_prdata_o[0] = tx_level_r == 0;
                apb_prdata_o[1] = tx_level_r == 16;
                apb_prdata_o[2] = rx_level_r == 0;
                apb_prdata_o[3] = rx_level_r == 16;
                apb_prdata_o[4] = tx_busy_r;
                apb_prdata_o[12:8] = tx_level_r;
                apb_prdata_o[20:16] = rx_level_r;
            end
            12'h00c: apb_prdata_o = {28'b0, irq_en_r};
            12'h010: apb_prdata_o = {28'b0, irq_stat_w};
            12'h014: apb_prdata_o = {8'b0, baud_div_r};
            12'h018: apb_prdata_o = {27'b0, rx_thresh_r};
            12'h024: begin
                if (rx_level_r != 0)
                    apb_prdata_o = {23'b0, 1'b1, rx_fifo_r[rx_read_ptr_r]};
            end
            default: begin end
        endcase
    end
endmodule
