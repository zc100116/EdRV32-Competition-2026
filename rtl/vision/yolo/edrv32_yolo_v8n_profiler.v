// ============================================================================
// File        : edrv32_yolo_v8n_profiler.v
// Description : Per-command YOLO cycle, MAC and AXI traffic measurements.
// Notes       : Measurements are in the 150-MHz AXI source domain. Read-busy
//               cycles include CDC, interconnect and DDR response latency;
//               they may overlap MAC cycles and are not additive. One packed
//               synchronous record is stored per command.
// ============================================================================
`include "edrv32_build_mode.vh"

module edrv32_yolo_v8n_profiler (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         run_start_i,
    input  wire         run_done_i,
    input  wire [6:0]   step_i,
    input  wire         mac_beat_i,
    input  wire         arvalid_i,
    input  wire         arready_i,
    input  wire [7:0]   arlen_i,
    input  wire         rvalid_i,
    input  wire         rready_i,
    input  wire         awvalid_i,
    input  wire         awready_i,
    input  wire [7:0]   awlen_i,
    input  wire         wvalid_i,
    input  wire         wready_i,
    input  wire         bvalid_i,
    input  wire         bready_i,
    input  wire [6:0]   read_step_i,
    output wire [31:0]  read_cycles_o,
    output wire [31:0]  read_mac_o,
    output wire [31:0]  read_rbeats_o,
    output wire [31:0]  read_wbeats_o,
    output wire [31:0]  read_arstall_o,
    output wire [31:0]  read_rwait_o,
    output wire [31:0]  read_awstall_o,
    output wire [31:0]  read_wstall_o,
    output wire [31:0]  read_bwait_o
);

    reg active_r;
    reg [6:0] current_step_r;
    reg [31:0] cycles_r, mac_r, rbeats_r, wbeats_r;
    reg [31:0] arstall_r, rwait_r, awstall_r, wstall_r, bwait_r;
    reg [11:0] read_pending_r;
    reg [7:0] write_pending_r;
    reg [7:0] response_pending_r;

    wire ar_fire_w = arvalid_i && arready_i;
    wire r_fire_w = rvalid_i && rready_i;
    wire aw_fire_w = awvalid_i && awready_i;
    wire w_fire_w = wvalid_i && wready_i;
    wire b_fire_w = bvalid_i && bready_i;
    wire ar_stall_w = arvalid_i && !arready_i;
    wire r_wait_w = read_pending_r != 12'd0 && !r_fire_w;
    wire aw_stall_w = awvalid_i && !awready_i;
    wire w_stall_w = wvalid_i && !wready_i;
    wire b_wait_w = response_pending_r != 8'd0 &&
                    write_pending_r == 8'd0 && !b_fire_w;
    wire step_end_w = run_done_i || step_i != current_step_r;

    wire profile_wr_w = active_r && !run_start_i && step_end_w &&
                        current_step_r < 7'd74;
    wire [287:0] profile_write_w = {
        bwait_r + {31'd0, b_wait_w},
        wstall_r + {31'd0, w_stall_w},
        awstall_r + {31'd0, aw_stall_w},
        rwait_r + {31'd0, r_wait_w},
        arstall_r + {31'd0, ar_stall_w},
        wbeats_r + {31'd0, w_fire_w},
        rbeats_r + {31'd0, r_fire_w},
        mac_r + {31'd0, mac_beat_i},
        cycles_r + 32'd1
    };
    wire [287:0] profile_read_w;
`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`elsif EDRV32_FPGA_MEMORY_MODE
    wire [255:0] profile_hi_read_w;
    yolo_weight_ram u_profile_lo_ram (
        .wr_data(profile_write_w[255:0]),
        .wr_addr({2'd0, current_step_r}), .wr_en(profile_wr_w),
        .wr_clk(clk_i), .wr_rst(~rst_n_i),
        .wr_byte_en(32'hffff_ffff),
        .rd_data(profile_read_w[255:0]),
        .rd_addr({2'd0, read_step_i}),
        .rd_clk(clk_i), .rd_rst(~rst_n_i), .rd_clk_en(1'b1)
    );
    yolo_weight_ram u_profile_hi_ram (
        .wr_data({224'd0, profile_write_w[287:256]}),
        .wr_addr({2'd0, current_step_r}), .wr_en(profile_wr_w),
        .wr_clk(clk_i), .wr_rst(~rst_n_i),
        .wr_byte_en(32'hffff_ffff),
        .rd_data(profile_hi_read_w),
        .rd_addr({2'd0, read_step_i}),
        .rd_clk(clk_i), .rd_rst(~rst_n_i), .rd_clk_en(1'b1)
    );
    assign profile_read_w[287:256] = profile_hi_read_w[31:0];
`else
    reg [287:0] profile_mem_r [0:73];
    reg [287:0] profile_read_r;
    always @(posedge clk_i) begin
        if (profile_wr_w)
            profile_mem_r[current_step_r] <= profile_write_w;
        profile_read_r <= profile_mem_r[read_step_i];
    end
    assign profile_read_w = profile_read_r;
`endif

    assign read_cycles_o  = profile_read_w[31:0];
    assign read_mac_o     = profile_read_w[63:32];
    assign read_rbeats_o  = profile_read_w[95:64];
    assign read_wbeats_o  = profile_read_w[127:96];
    assign read_arstall_o = profile_read_w[159:128];
    assign read_rwait_o   = profile_read_w[191:160];
    assign read_awstall_o = profile_read_w[223:192];
    assign read_wstall_o  = profile_read_w[255:224];
    assign read_bwait_o   = profile_read_w[287:256];

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            active_r <= 1'b0;
            current_step_r <= 7'd0;
            cycles_r <= 32'd0;
            mac_r <= 32'd0;
            rbeats_r <= 32'd0;
            wbeats_r <= 32'd0;
            arstall_r <= 32'd0;
            rwait_r <= 32'd0;
            awstall_r <= 32'd0;
            wstall_r <= 32'd0;
            bwait_r <= 32'd0;
            read_pending_r <= 12'd0;
            write_pending_r <= 8'd0;
            response_pending_r <= 8'd0;
        end else begin
            if (run_start_i) begin
                active_r <= 1'b1;
                current_step_r <= 7'd0;
                cycles_r <= 32'd0;
                mac_r <= 32'd0;
                rbeats_r <= 32'd0;
                wbeats_r <= 32'd0;
                arstall_r <= 32'd0;
                rwait_r <= 32'd0;
                awstall_r <= 32'd0;
                wstall_r <= 32'd0;
                bwait_r <= 32'd0;
                read_pending_r <= 12'd0;
                write_pending_r <= 8'd0;
                response_pending_r <= 8'd0;
            end else if (active_r) begin
                case ({ar_fire_w, r_fire_w})
                    2'b10: read_pending_r <= read_pending_r +
                            {4'd0, arlen_i} + 12'd1;
                    2'b01: read_pending_r <= read_pending_r - 12'd1;
                    2'b11: read_pending_r <= read_pending_r +
                            {4'd0, arlen_i};
                    default: read_pending_r <= read_pending_r;
                endcase
                case ({aw_fire_w, w_fire_w})
                    2'b10: write_pending_r <= write_pending_r +
                            awlen_i + 8'd1;
                    2'b01: write_pending_r <= write_pending_r - 8'd1;
                    2'b11: write_pending_r <= write_pending_r + awlen_i;
                    default: write_pending_r <= write_pending_r;
                endcase
                case ({aw_fire_w, b_fire_w})
                    2'b10: response_pending_r <= response_pending_r + 8'd1;
                    2'b01: response_pending_r <= response_pending_r - 8'd1;
                    default: response_pending_r <= response_pending_r;
                endcase

                if (step_end_w) begin
                    current_step_r <= step_i;
                    cycles_r <= 32'd0;
                    mac_r <= 32'd0;
                    rbeats_r <= 32'd0;
                    wbeats_r <= 32'd0;
                    arstall_r <= 32'd0;
                    rwait_r <= 32'd0;
                    awstall_r <= 32'd0;
                    wstall_r <= 32'd0;
                    bwait_r <= 32'd0;
                    if (run_done_i)
                        active_r <= 1'b0;
                end else begin
                    cycles_r <= cycles_r + 32'd1;
                    mac_r <= mac_r + {31'd0, mac_beat_i};
                    rbeats_r <= rbeats_r + {31'd0, r_fire_w};
                    wbeats_r <= wbeats_r + {31'd0, w_fire_w};
                    arstall_r <= arstall_r + {31'd0, ar_stall_w};
                    rwait_r <= rwait_r + {31'd0, r_wait_w};
                    awstall_r <= awstall_r + {31'd0, aw_stall_w};
                    wstall_r <= wstall_r + {31'd0, w_stall_w};
                    bwait_r <= bwait_r + {31'd0, b_wait_w};
                end
            end
        end
    end
endmodule
