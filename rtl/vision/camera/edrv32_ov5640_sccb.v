// ============================================================================
// File        : edrv32_ov5640_sccb.v
// Description : OV5640 SCCB register read/write transaction engine.
// Notes       : SDA is open-drain. The caller owns the top-level tri-state and
//               feeds the resolved pin value back through sda_i.
// ============================================================================

module edrv32_ov5640_sccb #(
    parameter integer CLK_HZ = 27000000,
    parameter integer SCCB_HZ = 250000,
    parameter integer DIVIDER = CLK_HZ / SCCB_HZ
) (
    input  wire        clk_i,
    input  wire        rst_n_i,
    input  wire        start_i,
    input  wire        read_i,
    input  wire [15:0] reg_addr_i,
    input  wire [7:0]  write_data_i,
    input  wire        sda_i,
    output wire        busy_o,
    output wire        done_o,
    output wire        bus_error_o,
    output wire [7:0]  read_data_o,
    output wire        scl_o,
    output wire        sda_drive_low_o
);

    localparam [3:0] STATE_IDLE        = 4'd0;
    localparam [3:0] STATE_START       = 4'd1;
    localparam [3:0] STATE_SEND        = 4'd2;
    localparam [3:0] STATE_DONT_CARE   = 4'd3;
    localparam [3:0] STATE_RESTART     = 4'd4;
    localparam [3:0] STATE_READ        = 4'd5;
    localparam [3:0] STATE_MASTER_NA   = 4'd6;
    localparam [3:0] STATE_STOP        = 4'd7;

    localparam [2:0] PHASE_DEVICE_WRITE = 3'd0;
    localparam [2:0] PHASE_ADDR_HIGH    = 3'd1;
    localparam [2:0] PHASE_ADDR_LOW     = 3'd2;
    localparam [2:0] PHASE_WRITE_DATA   = 3'd3;
    localparam [2:0] PHASE_DEVICE_READ  = 3'd4;

    localparam integer DIV_W = (DIVIDER <= 2) ? 1 : $clog2(DIVIDER);

    reg [3:0] state_r;
    reg [DIV_W-1:0] div_count_r;
    reg [2:0] bit_index_r;
    reg [2:0] phase_r;
    reg [7:0] tx_byte_r;
    reg [15:0] reg_addr_r;
    reg [7:0] write_data_r;
    reg [7:0] read_data_r;
    reg read_r;
    reg done_r;
    reg bus_error_r;

    wire half_w = div_count_r == (DIVIDER / 2);
    wire tick_w = div_count_r == DIVIDER - 1;

    reg scl_w;
    reg sda_drive_low_w;

    always @(*) begin
        scl_w = 1'b1;
        sda_drive_low_w = 1'b0;
        case (state_r)
            STATE_START: begin
                scl_w = 1'b1;
                sda_drive_low_w = div_count_r >= (DIVIDER / 2);
            end
            STATE_SEND: begin
                scl_w = (div_count_r >= (DIVIDER / 4)) &&
                    (div_count_r < ((DIVIDER * 3) / 4));
                sda_drive_low_w = !tx_byte_r[bit_index_r];
            end
            STATE_DONT_CARE: begin
                scl_w = (div_count_r >= (DIVIDER / 4)) &&
                    (div_count_r < ((DIVIDER * 3) / 4));
                sda_drive_low_w = 1'b0;
            end
            STATE_RESTART: begin
                scl_w = 1'b1;
                sda_drive_low_w = div_count_r >= (DIVIDER / 2);
            end
            STATE_READ: begin
                scl_w = (div_count_r >= (DIVIDER / 4)) &&
                    (div_count_r < ((DIVIDER * 3) / 4));
                sda_drive_low_w = 1'b0;
            end
            STATE_MASTER_NA: begin
                scl_w = (div_count_r >= (DIVIDER / 4)) &&
                    (div_count_r < ((DIVIDER * 3) / 4));
                sda_drive_low_w = 1'b0;
            end
            STATE_STOP: begin
                scl_w = div_count_r >= (DIVIDER / 4);
                sda_drive_low_w = div_count_r < ((DIVIDER * 3) / 4);
            end
            default: begin
                scl_w = 1'b1;
                sda_drive_low_w = 1'b0;
            end
        endcase
    end

    assign busy_o = state_r != STATE_IDLE;
    assign done_o = done_r;
    assign bus_error_o = bus_error_r;
    assign read_data_o = read_data_r;
    assign scl_o = scl_w;
    assign sda_drive_low_o = sda_drive_low_w;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= STATE_IDLE;
            div_count_r <= {DIV_W{1'b0}};
            bit_index_r <= 3'd7;
            phase_r <= PHASE_DEVICE_WRITE;
            tx_byte_r <= 8'b0;
            reg_addr_r <= 16'b0;
            write_data_r <= 8'b0;
            read_data_r <= 8'b0;
            read_r <= 1'b0;
            done_r <= 1'b0;
            bus_error_r <= 1'b0;
        end else begin
            done_r <= 1'b0;
            case (state_r)
                STATE_IDLE: begin
                    div_count_r <= {DIV_W{1'b0}};
                    if (start_i) begin
                        bit_index_r <= 3'd7;
                        phase_r <= PHASE_DEVICE_WRITE;
                        tx_byte_r <= 8'h78;
                        reg_addr_r <= reg_addr_i;
                        write_data_r <= write_data_i;
                        read_data_r <= 8'b0;
                        read_r <= read_i;
                        bus_error_r <= !sda_i;
                        state_r <= sda_i ? STATE_START : STATE_STOP;
                    end
                end
                STATE_START: begin
                    if (tick_w) begin
                        div_count_r <= {DIV_W{1'b0}};
                        bit_index_r <= 3'd7;
                        state_r <= STATE_SEND;
                    end else begin
                        div_count_r <= div_count_r + 1'b1;
                    end
                end
                STATE_SEND: begin
                    if (tick_w) begin
                        div_count_r <= {DIV_W{1'b0}};
                        if (bit_index_r == 3'd0) begin
                            bit_index_r <= 3'd7;
                            state_r <= STATE_DONT_CARE;
                        end else begin
                            bit_index_r <= bit_index_r - 1'b1;
                        end
                    end else begin
                        div_count_r <= div_count_r + 1'b1;
                    end
                end
                STATE_DONT_CARE: begin
                    if (tick_w) begin
                        div_count_r <= {DIV_W{1'b0}};
                        bit_index_r <= 3'd7;
                        case (phase_r)
                            PHASE_DEVICE_WRITE: begin
                                phase_r <= PHASE_ADDR_HIGH;
                                tx_byte_r <= reg_addr_r[15:8];
                                state_r <= STATE_SEND;
                            end
                            PHASE_ADDR_HIGH: begin
                                phase_r <= PHASE_ADDR_LOW;
                                tx_byte_r <= reg_addr_r[7:0];
                                state_r <= STATE_SEND;
                            end
                            PHASE_ADDR_LOW: begin
                                if (read_r) begin
                                    phase_r <= PHASE_DEVICE_READ;
                                    tx_byte_r <= 8'h79;
                                    state_r <= STATE_RESTART;
                                end else begin
                                    phase_r <= PHASE_WRITE_DATA;
                                    tx_byte_r <= write_data_r;
                                    state_r <= STATE_SEND;
                                end
                            end
                            PHASE_WRITE_DATA: begin
                                state_r <= STATE_STOP;
                            end
                            PHASE_DEVICE_READ: begin
                                read_data_r <= 8'b0;
                                state_r <= STATE_READ;
                            end
                            default: state_r <= STATE_STOP;
                        endcase
                    end else begin
                        div_count_r <= div_count_r + 1'b1;
                    end
                end
                STATE_RESTART: begin
                    if (tick_w) begin
                        div_count_r <= {DIV_W{1'b0}};
                        bit_index_r <= 3'd7;
                        state_r <= STATE_SEND;
                    end else begin
                        div_count_r <= div_count_r + 1'b1;
                    end
                end
                STATE_READ: begin
                    if (half_w)
                        read_data_r[bit_index_r] <= sda_i;
                    if (tick_w) begin
                        div_count_r <= {DIV_W{1'b0}};
                        if (bit_index_r == 3'd0) begin
                            bit_index_r <= 3'd7;
                            state_r <= STATE_MASTER_NA;
                        end else begin
                            bit_index_r <= bit_index_r - 1'b1;
                        end
                    end else begin
                        div_count_r <= div_count_r + 1'b1;
                    end
                end
                STATE_MASTER_NA: begin
                    if (tick_w) begin
                        div_count_r <= {DIV_W{1'b0}};
                        state_r <= STATE_STOP;
                    end else begin
                        div_count_r <= div_count_r + 1'b1;
                    end
                end
                STATE_STOP: begin
                    if ((div_count_r == ((DIVIDER * 7) / 8)) && !sda_i)
                        bus_error_r <= 1'b1;
                    if (tick_w) begin
                        div_count_r <= {DIV_W{1'b0}};
                        done_r <= 1'b1;
                        state_r <= STATE_IDLE;
                    end else begin
                        div_count_r <= div_count_r + 1'b1;
                    end
                end
                default: state_r <= STATE_IDLE;
            endcase
        end
    end

    generate
        if (DIVIDER < 4) begin : gen_bad_divider
            edrv32_ov5640_sccb_divider_must_be_at_least_four
                u_static_assert ();
        end
    endgenerate

endmodule
