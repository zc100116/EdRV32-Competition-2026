// ============================================================================
// File        : edrv32_yolo_v8n_reporter.v
// Description : UART status and per-command performance report serializer.
// Notes       : The 74 command rows are emitted after core/postprocessing
//               finish, so UART transfer time is outside measured run cycles.
// ============================================================================
`include "edrv32_build_mode.vh"

module edrv32_yolo_v8n_reporter (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         start_i,
    input  wire         fail_i,
    input  wire [6:0]   last_step_i,
    input  wire [31:0]  total_cycles_i,
    input  wire [31:0]  core_cycles_i,
    input  wire [31:0]  post_cycles_i,
    input  wire [9:0]   candidate_count_i,
    input  wire [6:0]   detection_count_i,
    input  wire [31:0]  post_load_cycles_i,
    input  wire [31:0]  post_class_cycles_i,
    input  wire [31:0]  post_dfl_cycles_i,
    input  wire [31:0]  post_nms_cycles_i,
    input  wire [31:0]  post_meta_cycles_i,
    input  wire [31:0]  post_rbeats_i,
    input  wire [31:0]  post_wbeats_i,
    input  wire [31:0]  post_arstall_i,
    input  wire [31:0]  post_rwait_i,
    input  wire [31:0]  post_awstall_i,
    input  wire [31:0]  post_wstall_i,
    input  wire [31:0]  post_bwait_i,
    input  wire         profile_valid_i,
    input  wire         detection_valid_i,
    input  wire [6:0]   detection_index_i,
    input  wire [255:0] detection_record_i,
    output wire [6:0]   profile_step_o,
    input  wire [31:0]  profile_cycles_i,
    input  wire [31:0]  profile_mac_i,
    input  wire [31:0]  profile_rbeats_i,
    input  wire [31:0]  profile_wbeats_i,
    input  wire [31:0]  profile_arstall_i,
    input  wire [31:0]  profile_rwait_i,
    input  wire [31:0]  profile_awstall_i,
    input  wire [31:0]  profile_wstall_i,
    input  wire [31:0]  profile_bwait_i,
    output wire         tx_valid_o,
    input  wire         tx_ready_i,
    output wire [7:0]   tx_data_o,
    output wire         busy_o,
    output wire         done_o
);

    localparam [3:0] S_IDLE = 4'd0;
    localparam [3:0] S_STATUS = 4'd1;
    localparam [3:0] S_CORE = 4'd2;
    localparam [3:0] S_POST = 4'd3;
    localparam [3:0] S_PHASE = 4'd4;
    localparam [3:0] S_IO = 4'd5;
    localparam [3:0] S_STEP = 4'd6;
    localparam [3:0] S_DET = 4'd7;
    localparam [3:0] S_DONE = 4'd8;
    localparam [3:0] S_DET_PREP = 4'd9;
    localparam [247:0] STATUS_TEMPLATE =
        "YV8 PASS STEP=00 CYC=00000000\r\n";
    localparam [159:0] CORE_TEMPLATE =
        "YCORE CYC=00000000\r\n";
    localparam [295:0] POST_TEMPLATE =
        "YPOST CYC=00000000 CAND=0000 DET=00\r\n";
    localparam [519:0] PHASE_TEMPLATE =
        "YPH LD=00000000 CL=00000000 DF=00000000 NM=00000000 WR=00000000\r\n";
    localparam [719:0] IO_TEMPLATE =
        "YPIO RB=00000000 WB=00000000 AR=00000000 RW=00000000 AW=00000000 WW=00000000 BW=00000000\r\n";
    localparam [919:0] STEP_TEMPLATE =
        "YS 00 CY=00000000 MC=00000000 RB=00000000 WB=00000000 AR=00000000 RW=00000000 AW=00000000 WW=00000000 BW=00000000\r\n";
    localparam [567:0] DET_TEMPLATE =
        "YDET 00 CL=00 SC=0000 X1=00000000 Y1=00000000 X2=00000000 Y2=00000000\r\n";

    reg [3:0] state_r;
    reg started_r;
    reg [6:0] index_r;
    reg [6:0] profile_step_r;
    reg [6:0] detection_index_r;
    reg fail_r;
    reg [6:0] last_step_r;
    reg [31:0] total_cycles_r, core_cycles_r, post_cycles_r;
    reg [31:0] post_load_cycles_r, post_class_cycles_r;
    reg [31:0] post_dfl_cycles_r, post_nms_cycles_r;
    reg [31:0] post_meta_cycles_r, post_rbeats_r, post_wbeats_r;
    reg [31:0] post_arstall_r, post_rwait_r;
    reg [31:0] post_awstall_r, post_wstall_r, post_bwait_r;
    reg [9:0] candidate_count_r;
    reg [6:0] detection_count_r;
    reg done_r;
    reg [7:0] tx_data_r;
    reg [7:0] tx_byte_r;
    reg tx_valid_r;
    reg [255:0] detection_record_r;
    wire format_active_w = state_r == S_STATUS || state_r == S_CORE ||
        state_r == S_POST || state_r == S_PHASE || state_r == S_IO ||
        state_r == S_STEP || state_r == S_DET;
    wire load_byte_w = format_active_w &&
        (!tx_valid_r || tx_ready_i);
    wire [255:0] selected_detection_w;
    wire detection_write_w = detection_valid_i &&
                             detection_index_i < 7'd100;
`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`elsif EDRV32_FPGA_MEMORY_MODE
    yolo_weight_ram u_detection_ram (
        .wr_data(detection_record_i),
        .wr_addr({2'd0, detection_index_i}),
        .wr_en(detection_write_w),
        .wr_clk(clk_i), .wr_rst(~rst_n_i),
        .wr_byte_en(32'hffff_ffff),
        .rd_data(selected_detection_w),
        .rd_addr({2'd0, detection_index_r}),
        .rd_clk(clk_i), .rd_rst(~rst_n_i), .rd_clk_en(1'b1)
    );
`else
    reg [255:0] detection_mem_r [0:99];
    reg [255:0] detection_read_r;
    always @(posedge clk_i) begin
        if (detection_write_w)
            detection_mem_r[detection_index_i] <= detection_record_i;
        detection_read_r <= detection_mem_r[detection_index_r];
    end
    assign selected_detection_w = detection_read_r;
`endif

    function [7:0] hex_digit;
        input [3:0] value_i;
        begin
            hex_digit = value_i < 4'd10 ? 8'h30 + {4'd0, value_i} :
                        8'h41 + {4'd0, value_i} - 8'd10;
        end
    endfunction

    function [7:0] hex32;
        input [31:0] value_i;
        input [2:0] digit_i;
        reg [4:0] shift;
        begin
            shift = ({2'd0, 3'd7 - digit_i} << 2);
            hex32 = hex_digit((value_i >> shift) & 4'hf);
        end
    endfunction

    always @(*) begin
        tx_data_r = 8'd0;
        case (state_r)
            S_STATUS: begin
                tx_data_r = STATUS_TEMPLATE[(30-index_r)*8 +: 8];
                if (index_r == 7'd4)
                    tx_data_r = fail_r ? "F" : "P";
                else if (index_r == 7'd6)
                    tx_data_r = fail_r ? "I" : "S";
                else if (index_r == 7'd7)
                    tx_data_r = fail_r ? "L" : "S";
                else if (index_r == 7'd14)
                    tx_data_r = hex_digit({1'd0, last_step_r[6:4]});
                else if (index_r == 7'd15)
                    tx_data_r = hex_digit(last_step_r[3:0]);
                else if (index_r >= 7'd21 && index_r <= 7'd28)
                    tx_data_r = hex32(total_cycles_r, index_r[2:0]-3'd5);
                else if (index_r == 7'd29)
                    tx_data_r = 8'h0d;
            end
            S_CORE: begin
                tx_data_r = CORE_TEMPLATE[(19-index_r)*8 +: 8];
                if (index_r >= 7'd10 && index_r <= 7'd17)
                    tx_data_r = hex32(core_cycles_r, index_r[2:0]-3'd2);
                else if (index_r == 7'd18)
                    tx_data_r = 8'h0d;
            end
            S_POST: begin
                tx_data_r = POST_TEMPLATE[(36-index_r)*8 +: 8];
                if (index_r >= 7'd10 && index_r <= 7'd17)
                    tx_data_r = hex32(post_cycles_r, index_r[2:0]-3'd2);
                else if (index_r >= 7'd24 && index_r <= 7'd27)
                    tx_data_r = hex32({22'd0, candidate_count_r},
                                        index_r[1:0]+3'd4);
                else if (index_r >= 7'd33 && index_r <= 7'd34)
                    tx_data_r = hex32({25'd0, detection_count_r},
                                        index_r[0] ? 3'd6 : 3'd7);
                else if (index_r == 7'd35)
                    tx_data_r = 8'h0d;
            end
            S_PHASE: begin
                tx_data_r = PHASE_TEMPLATE[(64-index_r)*8 +: 8];
                if (index_r >= 7'd7 && index_r <= 7'd14)
                    tx_data_r = hex32(post_load_cycles_r,
                                      index_r[2:0] - 3'd7);
                else if (index_r >= 7'd19 && index_r <= 7'd26)
                    tx_data_r = hex32(post_class_cycles_r,
                                      index_r[2:0] - 3'd3);
                else if (index_r >= 7'd31 && index_r <= 7'd38)
                    tx_data_r = hex32(post_dfl_cycles_r,
                                      index_r[2:0] - 3'd7);
                else if (index_r >= 7'd43 && index_r <= 7'd50)
                    tx_data_r = hex32(post_nms_cycles_r,
                                      index_r[2:0] - 3'd3);
                else if (index_r >= 7'd55 && index_r <= 7'd62)
                    tx_data_r = hex32(post_meta_cycles_r,
                                      index_r[2:0] - 3'd7);
                else if (index_r == 7'd63)
                    tx_data_r = 8'h0d;
            end
            S_IO: begin
                tx_data_r = IO_TEMPLATE[(89-index_r)*8 +: 8];
                if (index_r >= 7'd8 && index_r <= 7'd15)
                    tx_data_r = hex32(post_rbeats_r, index_r[2:0]);
                else if (index_r >= 7'd20 && index_r <= 7'd27)
                    tx_data_r = hex32(post_wbeats_r,
                                      index_r[2:0] - 3'd4);
                else if (index_r >= 7'd32 && index_r <= 7'd39)
                    tx_data_r = hex32(post_arstall_r, index_r[2:0]);
                else if (index_r >= 7'd44 && index_r <= 7'd51)
                    tx_data_r = hex32(post_rwait_r,
                                      index_r[2:0] - 3'd4);
                else if (index_r >= 7'd56 && index_r <= 7'd63)
                    tx_data_r = hex32(post_awstall_r, index_r[2:0]);
                else if (index_r >= 7'd68 && index_r <= 7'd75)
                    tx_data_r = hex32(post_wstall_r,
                                      index_r[2:0] - 3'd4);
                else if (index_r >= 7'd80 && index_r <= 7'd87)
                    tx_data_r = hex32(post_bwait_r, index_r[2:0]);
                else if (index_r == 7'd88)
                    tx_data_r = 8'h0d;
            end
            S_STEP: begin
                tx_data_r = STEP_TEMPLATE[(114-index_r)*8 +: 8];
                if (index_r == 7'd3)
                    tx_data_r = hex_digit({1'd0, profile_step_r[6:4]});
                else if (index_r == 7'd4)
                    tx_data_r = hex_digit(profile_step_r[3:0]);
                else if (index_r >= 7'd9 && index_r <= 7'd16)
                    tx_data_r = hex32(profile_cycles_i, index_r[2:0]-3'd1);
                else if (index_r >= 7'd21 && index_r <= 7'd28)
                    tx_data_r = hex32(profile_mac_i, index_r[2:0]-3'd5);
                else if (index_r >= 7'd33 && index_r <= 7'd40)
                    tx_data_r = hex32(profile_rbeats_i, index_r[2:0]-3'd1);
                else if (index_r >= 7'd45 && index_r <= 7'd52)
                    tx_data_r = hex32(profile_wbeats_i, index_r[2:0]-3'd5);
                else if (index_r >= 7'd57 && index_r <= 7'd64)
                    tx_data_r = hex32(profile_arstall_i, index_r[2:0]-3'd1);
                else if (index_r >= 7'd69 && index_r <= 7'd76)
                    tx_data_r = hex32(profile_rwait_i, index_r[2:0]-3'd5);
                else if (index_r >= 7'd81 && index_r <= 7'd88)
                    tx_data_r = hex32(profile_awstall_i, index_r[2:0]-3'd1);
                else if (index_r >= 7'd93 && index_r <= 7'd100)
                    tx_data_r = hex32(profile_wstall_i, index_r[2:0]-3'd5);
                else if (index_r >= 7'd105 && index_r <= 7'd112)
                    tx_data_r = hex32(profile_bwait_i, index_r[2:0]-3'd1);
                else if (index_r == 7'd113)
                    tx_data_r = 8'h0d;
            end
            S_DET: begin
                tx_data_r = DET_TEMPLATE[(70-index_r)*8 +: 8];
                if (index_r == 7'd5)
                    tx_data_r = hex_digit({1'd0, detection_index_r[6:4]});
                else if (index_r == 7'd6)
                    tx_data_r = hex_digit(detection_index_r[3:0]);
                else if (index_r == 7'd11)
                    tx_data_r = hex_digit(detection_record_r[135:132]);
                else if (index_r == 7'd12)
                    tx_data_r = hex_digit(detection_record_r[131:128]);
                else if (index_r >= 7'd17 && index_r <= 7'd20)
                    tx_data_r = hex32({16'd0, detection_record_r[151:136]},
                                         index_r[2:0] - 3'd5);
                else if (index_r >= 7'd25 && index_r <= 7'd32)
                    tx_data_r = hex32(detection_record_r[31:0],
                                         index_r[2:0] - 3'd1);
                else if (index_r >= 7'd37 && index_r <= 7'd44)
                    tx_data_r = hex32(detection_record_r[63:32],
                                         index_r[2:0] - 3'd5);
                else if (index_r >= 7'd49 && index_r <= 7'd56)
                    tx_data_r = hex32(detection_record_r[95:64],
                                         index_r[2:0] - 3'd1);
                else if (index_r >= 7'd61 && index_r <= 7'd68)
                    tx_data_r = hex32(detection_record_r[127:96],
                                         index_r[2:0] - 3'd5);
                else if (index_r == 7'd69)
                    tx_data_r = 8'h0d;
            end
            default: tx_data_r = 8'd0;
        endcase
    end

    assign profile_step_o = profile_step_r;
    assign tx_valid_o = tx_valid_r;
    assign tx_data_o = tx_byte_r;
    assign busy_o = state_r != S_IDLE || tx_valid_r;
    assign done_o = done_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            started_r <= 1'b0;
            index_r <= 7'd0;
            profile_step_r <= 7'd0;
            detection_index_r <= 7'd0;
            fail_r <= 1'b0;
            last_step_r <= 7'd0;
            total_cycles_r <= 32'd0;
            core_cycles_r <= 32'd0;
            post_cycles_r <= 32'd0;
            post_load_cycles_r <= 32'd0;
            post_class_cycles_r <= 32'd0;
            post_dfl_cycles_r <= 32'd0;
            post_nms_cycles_r <= 32'd0;
            post_meta_cycles_r <= 32'd0;
            post_rbeats_r <= 32'd0;
            post_wbeats_r <= 32'd0;
            post_arstall_r <= 32'd0;
            post_rwait_r <= 32'd0;
            post_awstall_r <= 32'd0;
            post_wstall_r <= 32'd0;
            post_bwait_r <= 32'd0;
            candidate_count_r <= 10'd0;
            detection_count_r <= 7'd0;
            done_r <= 1'b0;
            tx_byte_r <= 8'd0;
            tx_valid_r <= 1'b0;
        end else begin
            done_r <= 1'b0;
            if (state_r == S_DET && index_r == 7'd0)
                detection_record_r <= selected_detection_w;
            if (load_byte_w) begin
                tx_byte_r <= tx_data_r;
                tx_valid_r <= 1'b1;
            end else if (tx_valid_r && tx_ready_i)
                tx_valid_r <= 1'b0;
            case (state_r)
                S_IDLE: if (start_i && !started_r) begin
                    started_r <= 1'b1;
                    fail_r <= fail_i;
                    last_step_r <= last_step_i;
                    total_cycles_r <= total_cycles_i;
                    core_cycles_r <= core_cycles_i;
                    post_cycles_r <= post_cycles_i;
                    post_load_cycles_r <= post_load_cycles_i;
                    post_class_cycles_r <= post_class_cycles_i;
                    post_dfl_cycles_r <= post_dfl_cycles_i;
                    post_nms_cycles_r <= post_nms_cycles_i;
                    post_meta_cycles_r <= post_meta_cycles_i;
                    post_rbeats_r <= post_rbeats_i;
                    post_wbeats_r <= post_wbeats_i;
                    post_arstall_r <= post_arstall_i;
                    post_rwait_r <= post_rwait_i;
                    post_awstall_r <= post_awstall_i;
                    post_wstall_r <= post_wstall_i;
                    post_bwait_r <= post_bwait_i;
                    candidate_count_r <= candidate_count_i;
                    detection_count_r <= detection_count_i;
                    profile_step_r <= 7'd0;
                    detection_index_r <= 7'd0;
                    index_r <= 7'd0;
                    state_r <= S_STATUS;
                end
                S_STATUS: if (load_byte_w) begin
                    if (index_r == 7'd30) begin
                        index_r <= 7'd0;
                        state_r <= S_CORE;
                    end else
                        index_r <= index_r + 7'd1;
                end
                S_CORE: if (load_byte_w) begin
                    if (index_r == 7'd19) begin
                        index_r <= 7'd0;
                        state_r <= S_POST;
                    end else
                        index_r <= index_r + 7'd1;
                end
                S_POST: if (load_byte_w) begin
                    if (index_r == 7'd36) begin
                        index_r <= 7'd0;
                        state_r <= S_PHASE;
                    end else
                        index_r <= index_r + 7'd1;
                end
                S_PHASE: if (load_byte_w) begin
                    if (index_r == 7'd64) begin
                        index_r <= 7'd0;
                        state_r <= S_IO;
                    end else
                        index_r <= index_r + 7'd1;
                end
                S_IO: if (load_byte_w) begin
                    if (index_r == 7'd89) begin
                        index_r <= 7'd0;
                        state_r <= profile_valid_i ? S_STEP : S_DONE;
                    end else
                        index_r <= index_r + 7'd1;
                end
                S_STEP: if (load_byte_w) begin
                    if (index_r == 7'd114) begin
                        index_r <= 7'd0;
                        if (profile_step_r == last_step_r)
                            state_r <= detection_count_r == 7'd0 ?
                                       S_DONE : S_DET_PREP;
                        else
                            profile_step_r <= profile_step_r + 7'd1;
                    end else
                        index_r <= index_r + 7'd1;
                end
                S_DET_PREP: state_r <= S_DET;
                S_DET: if (load_byte_w) begin
                    if (index_r == 7'd70) begin
                        index_r <= 7'd0;
                        if (detection_index_r + 7'd1 == detection_count_r)
                            state_r <= S_DONE;
                        else begin
                            detection_index_r <= detection_index_r + 7'd1;
                            state_r <= S_DET_PREP;
                        end
                    end else
                        index_r <= index_r + 7'd1;
                end
                S_DONE: if (!tx_valid_r || tx_ready_i) begin
                    done_r <= 1'b1;
                    state_r <= S_IDLE;
                end
                default: state_r <= S_IDLE;
            endcase
        end
    end
endmodule
