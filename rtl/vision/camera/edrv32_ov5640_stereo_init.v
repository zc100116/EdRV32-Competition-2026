// ============================================================================
// File        : edrv32_ov5640_stereo_init.v
// Description : Power/reset, ROM setup and runtime writes for two OV5640s.
// Notes       : One ROM and SCCB engine configure camera 0 then camera 1. Once
//               initialization completes, a bundled-data toggle handshake
//               accepts runtime register writes from the SoC clock domain.
// ============================================================================

module edrv32_ov5640_stereo_init #(
    parameter integer CLK_HZ = 27000000,
    parameter integer SCCB_HZ = 250000,
    parameter integer RESET_CYCLES = 65536,
    parameter integer SETTLE_CYCLES = 1048576,
    parameter integer REG_COUNT = 248,
    parameter ROM_INIT_FILE = "rtl/vision/camera/ov5640_720p.hex"
) (
    input  wire clk_i,
    input  wire rst_n_i,
    input  wire cfg_req_toggle_i,
    input  wire cfg_camera_i,
    input  wire cfg_read_i,
    input  wire [15:0] cfg_reg_addr_i,
    input  wire [7:0] cfg_write_data_i,
    output wire cfg_ack_toggle_o,
    output wire cfg_error_o,
    output wire [7:0] cfg_read_data_o,
    output wire cam0_scl_o,
    input  wire cam0_sda_i,
    output wire cam0_sda_drive_low_o,
    output wire cam0_rst_n_o,
    output wire cam0_init_done_o,
    output wire cam1_scl_o,
    input  wire cam1_sda_i,
    output wire cam1_sda_drive_low_o,
    output wire cam1_rst_n_o,
    output wire cam1_init_done_o,
    output wire error_o
);

    localparam [2:0] STATE_RESET = 3'd0;
    localparam [2:0] STATE_SETTLE = 3'd1;
    localparam [2:0] STATE_ROM = 3'd2;
    localparam [2:0] STATE_START = 3'd3;
    localparam [2:0] STATE_WAIT = 3'd4;
    localparam [2:0] STATE_DONE = 3'd5;
    localparam [2:0] STATE_RUNTIME_WAIT = 3'd6;
    localparam [2:0] STATE_ERROR = 3'd7;

    localparam integer WAIT_W = (SETTLE_CYCLES <= RESET_CYCLES) ?
        ((RESET_CYCLES <= 1) ? 1 : $clog2(RESET_CYCLES + 1)) :
        ((SETTLE_CYCLES <= 1) ? 1 : $clog2(SETTLE_CYCLES + 1));

    reg [2:0] state_r;
    reg [WAIT_W-1:0] wait_count_r;
    reg camera_select_r;
    reg [7:0] rom_addr_r;
    reg rom_wait_r;
    reg sccb_start_r;
    reg cam0_done_r;
    reg cam1_done_r;
    reg error_r;
    reg cfg_req_meta_r;
    reg cfg_req_sync_r;
    reg cfg_ack_toggle_r;
    reg [23:0] runtime_data_r;
    reg runtime_read_r;
    reg cfg_error_r;
    reg [7:0] cfg_read_data_r;

    wire [23:0] rom_data_w;
    wire sccb_busy_w;
    wire sccb_done_w;
    wire sccb_bus_error_w;
    wire [7:0] sccb_read_data_w;
    wire sccb_scl_w;
    wire sccb_sda_drive_low_w;
    wire sccb_sda_i_w = camera_select_r ? cam1_sda_i : cam0_sda_i;
    wire [23:0] sccb_data_w =
        (state_r == STATE_RUNTIME_WAIT) ? runtime_data_r : rom_data_w;
    wire sccb_read_w =
        (state_r == STATE_RUNTIME_WAIT) ? runtime_read_r : 1'b0;

    edrv32_ov5640_reg_rom #(
        .INIT_FILE (ROM_INIT_FILE)
    ) u_reg_rom (
        .clk_i   (clk_i),
        .rst_n_i (rst_n_i),
        .addr_i  (rom_addr_r),
        .data_o  (rom_data_w)
    );

    edrv32_ov5640_sccb #(
        .CLK_HZ  (CLK_HZ),
        .SCCB_HZ (SCCB_HZ)
    ) u_sccb (
        .clk_i   (clk_i),
        .rst_n_i (rst_n_i),
        .start_i (sccb_start_r),
        .read_i  (sccb_read_w),
        .reg_addr_i(sccb_data_w[23:8]),
        .write_data_i(sccb_data_w[7:0]),
        .sda_i   (sccb_sda_i_w),
        .busy_o  (sccb_busy_w),
        .done_o  (sccb_done_w),
        .bus_error_o(sccb_bus_error_w),
        .read_data_o(sccb_read_data_w),
        .scl_o   (sccb_scl_w),
        .sda_drive_low_o(sccb_sda_drive_low_w)
    );

    assign cam0_rst_n_o = state_r != STATE_RESET;
    assign cam1_rst_n_o = state_r != STATE_RESET;
    assign cam0_scl_o = camera_select_r ? 1'b1 : sccb_scl_w;
    assign cam0_sda_drive_low_o = camera_select_r ?
        1'b0 : sccb_sda_drive_low_w;
    assign cam1_scl_o = camera_select_r ? sccb_scl_w : 1'b1;
    assign cam1_sda_drive_low_o = camera_select_r ?
        sccb_sda_drive_low_w : 1'b0;
    assign cam0_init_done_o = cam0_done_r;
    assign cam1_init_done_o = cam1_done_r;
    assign cfg_ack_toggle_o = cfg_ack_toggle_r;
    assign cfg_error_o = cfg_error_r;
    assign cfg_read_data_o = cfg_read_data_r;
    assign error_o = error_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= STATE_RESET;
            wait_count_r <= {WAIT_W{1'b0}};
            camera_select_r <= 1'b0;
            rom_addr_r <= 8'b0;
            rom_wait_r <= 1'b0;
            sccb_start_r <= 1'b0;
            cam0_done_r <= 1'b0;
            cam1_done_r <= 1'b0;
            error_r <= 1'b0;
            cfg_req_meta_r <= 1'b0;
            cfg_req_sync_r <= 1'b0;
            cfg_ack_toggle_r <= 1'b0;
            runtime_data_r <= 24'b0;
            runtime_read_r <= 1'b0;
            cfg_error_r <= 1'b0;
            cfg_read_data_r <= 8'b0;
        end else begin
            cfg_req_meta_r <= cfg_req_toggle_i;
            cfg_req_sync_r <= cfg_req_meta_r;
            sccb_start_r <= 1'b0;
            case (state_r)
                STATE_RESET: begin
                    if (wait_count_r == RESET_CYCLES - 1) begin
                        wait_count_r <= {WAIT_W{1'b0}};
                        state_r <= STATE_SETTLE;
                    end else begin
                        wait_count_r <= wait_count_r + 1'b1;
                    end
                end
                STATE_SETTLE: begin
                    if (wait_count_r == SETTLE_CYCLES - 1) begin
                        wait_count_r <= {WAIT_W{1'b0}};
                        rom_addr_r <= 8'b0;
                        rom_wait_r <= 1'b0;
                        state_r <= STATE_ROM;
                    end else begin
                        wait_count_r <= wait_count_r + 1'b1;
                    end
                end
                STATE_ROM: begin
                    if (!rom_wait_r) begin
                        rom_wait_r <= 1'b1;
                    end else begin
                        rom_wait_r <= 1'b0;
                        state_r <= STATE_START;
                    end
                end
                STATE_START: begin
                    if (!sccb_busy_w) begin
                        sccb_start_r <= 1'b1;
                        state_r <= STATE_WAIT;
                    end
                end
                STATE_WAIT: begin
                    if (sccb_done_w) begin
                        if (sccb_bus_error_w) begin
                            error_r <= 1'b1;
                            state_r <= STATE_ERROR;
                        end else if (rom_addr_r == REG_COUNT - 1) begin
                            if (!camera_select_r) begin
                                cam0_done_r <= 1'b1;
                                camera_select_r <= 1'b1;
                                rom_addr_r <= 8'b0;
                                state_r <= STATE_ROM;
                            end else begin
                                cam1_done_r <= 1'b1;
                                state_r <= STATE_DONE;
                            end
                        end else begin
                            rom_addr_r <= rom_addr_r + 1'b1;
                            state_r <= STATE_ROM;
                        end
                    end
                end
                STATE_DONE: begin
                    if (cfg_req_sync_r != cfg_ack_toggle_r && !sccb_busy_w) begin
                        camera_select_r <= cfg_camera_i;
                        runtime_data_r <= {
                            cfg_reg_addr_i, cfg_write_data_i
                        };
                        runtime_read_r <= cfg_read_i;
                        sccb_start_r <= 1'b1;
                        state_r <= STATE_RUNTIME_WAIT;
                    end
                end
                STATE_RUNTIME_WAIT: begin
                    if (sccb_done_w) begin
                        cfg_error_r <= sccb_bus_error_w;
                        cfg_read_data_r <= sccb_read_data_w;
                        cfg_ack_toggle_r <= cfg_req_sync_r;
                        state_r <= STATE_DONE;
                    end
                end
                STATE_ERROR: begin
                    state_r <= STATE_ERROR;
                end
                default: begin
                    state_r <= STATE_RESET;
                    error_r <= 1'b1;
                end
            endcase
        end
    end

    generate
        if (RESET_CYCLES < 1 || SETTLE_CYCLES < 1 ||
            REG_COUNT < 1 || REG_COUNT > 256) begin : gen_bad_parameters
            edrv32_ov5640_init_parameters_are_invalid
                u_static_assert ();
        end
    endgenerate

endmodule
