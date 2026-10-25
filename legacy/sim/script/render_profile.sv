`timescale 1ns/1ps

// Compile alongside an existing renderer testbench, defining PROFILE_TB to
// that testbench's top module. No renderer RTL or AXI timing is modified.
module tb_render_profile;
    integer active_cycles [0:9];
    integer compute_only_cycles [0:9];
    integer ddr_only_cycles [0:9];
    integer overlap_cycles [0:9];
    integer control_cycles [0:9];
    integer work_items [0:9];
    integer ar_count [0:9];
    integer r_count [0:9];
    integer aw_count [0:9];
    integer w_count [0:9];
    integer b_count [0:9];
    integer ddr_wait_cycles [0:9];
    integer round_geometry_cycles;
    integer bitmap_scale_cycles;
    integer bitmap_scale_sample_cycles;
    integer blur_horizontal_cycles;
    integer blur_vertical_cycles;
    integer blur_horizontal_pixels;
    integer blur_vertical_pixels;
    integer blur_horizontal_reads;
    integer blur_vertical_reads;
    integer blur_horizontal_writes;
    integer blur_vertical_writes;
    integer index;
    integer op;
    reg compute_now;
    reg ddr_now;
    reg transfer_now;
    reg issue_now;

    initial begin
        round_geometry_cycles = 0;
        bitmap_scale_cycles = 0;
        bitmap_scale_sample_cycles = 0;
        blur_horizontal_cycles = 0;
        blur_vertical_cycles = 0;
        blur_horizontal_pixels = 0;
        blur_vertical_pixels = 0;
        blur_horizontal_reads = 0;
        blur_vertical_reads = 0;
        blur_horizontal_writes = 0;
        blur_vertical_writes = 0;
        for (index=0; index<10; index=index+1) begin
            active_cycles[index] = 0;
            compute_only_cycles[index] = 0;
            ddr_only_cycles[index] = 0;
            overlap_cycles[index] = 0;
            control_cycles[index] = 0;
            work_items[index] = 0;
            ar_count[index] = 0;
            r_count[index] = 0;
            aw_count[index] = 0;
            w_count[index] = 0;
            b_count[index] = 0;
            ddr_wait_cycles[index] = 0;
        end
    end

    always @(posedge `PROFILE_TB.clk) begin
        if (`PROFILE_TB.rst_n) begin
            op = `PROFILE_TB.u_dut.state_r;
            if (op > 0 && op < 10) begin
                ddr_now = `PROFILE_TB.arvalid || `PROFILE_TB.rready ||
                          `PROFILE_TB.awvalid || `PROFILE_TB.wvalid ||
                          `PROFILE_TB.bready;
                transfer_now = (`PROFILE_TB.arvalid &&
                                `PROFILE_TB.u_dut.m_arready_i) ||
                               (`PROFILE_TB.u_dut.m_rvalid_i &&
                                `PROFILE_TB.rready) ||
                               (`PROFILE_TB.awvalid &&
                                `PROFILE_TB.u_dut.m_awready_i) ||
                               (`PROFILE_TB.wvalid &&
                                `PROFILE_TB.u_dut.m_wready_i) ||
                               (`PROFILE_TB.u_dut.m_bvalid_i &&
                                `PROFILE_TB.bready);
                compute_now = 1'b0;
                issue_now = 1'b0;
                case (op)
                    2: begin
                        compute_now = `PROFILE_TB.u_dut.u_fill.state_r == 3'd5;
                        issue_now = compute_now;
                    end
                    3: begin
                        compute_now = `PROFILE_TB.u_dut.u_compose.pair_valid_w ||
                                      `PROFILE_TB.u_dut.u_shared_alpha.valid1_r ||
                                      `PROFILE_TB.u_dut.u_shared_alpha.valid2_r ||
                                      `PROFILE_TB.u_dut.u_shared_alpha.valid3_r;
                        issue_now = `PROFILE_TB.u_dut.u_compose.pair_fire_w;
                    end
                    4: begin
                        compute_now = (`PROFILE_TB.u_dut.u_round.state_r == 4'd1) ||
                                      (`PROFILE_TB.u_dut.u_round.state_r == 4'd2) ||
                                      (`PROFILE_TB.u_dut.u_round.state_r == 4'd5) ||
                                      `PROFILE_TB.u_dut.u_round.valid0_r ||
                                      `PROFILE_TB.u_dut.u_round.valid1_r ||
                                      `PROFILE_TB.u_dut.u_round.valid2_r ||
                                      `PROFILE_TB.u_dut.u_round.valid3_r ||
                                      `PROFILE_TB.u_dut.u_shared_alpha.valid1_r ||
                                      `PROFILE_TB.u_dut.u_shared_alpha.valid2_r ||
                                      `PROFILE_TB.u_dut.u_shared_alpha.valid3_r;
                        issue_now = `PROFILE_TB.u_dut.u_round.pair_issue_w;
                    end
                    5: begin
                        compute_now = (`PROFILE_TB.u_dut.u_a8.state_r == 4'd5) ||
                                      `PROFILE_TB.u_dut.u_a8.valid0_r ||
                                      `PROFILE_TB.u_dut.u_a8.valid1_r ||
                                      `PROFILE_TB.u_dut.u_a8.valid2_r ||
                                      `PROFILE_TB.u_dut.u_shared_alpha.valid1_r ||
                                      `PROFILE_TB.u_dut.u_shared_alpha.valid2_r ||
                                      `PROFILE_TB.u_dut.u_shared_alpha.valid3_r;
                        issue_now = `PROFILE_TB.u_dut.u_a8.pair_issue_w;
                    end
                    6: begin
                        compute_now = (`PROFILE_TB.u_dut.u_bitmap.state_r == 4'd7) ||
                                      (`PROFILE_TB.u_dut.u_bitmap.state_r == 4'd13) ||
                                      (`PROFILE_TB.u_dut.u_bitmap.state_r == 4'd14) ||
                                      `PROFILE_TB.u_dut.u_bitmap.valid0_r ||
                                      `PROFILE_TB.u_dut.u_bitmap.valid1_r ||
                                      `PROFILE_TB.u_dut.u_shared_alpha.valid1_r ||
                                      `PROFILE_TB.u_dut.u_shared_alpha.valid2_r ||
                                      `PROFILE_TB.u_dut.u_shared_alpha.valid3_r;
                        issue_now = `PROFILE_TB.u_dut.u_bitmap.pair_issue_w;
                    end
                    7: begin
                        compute_now = `PROFILE_TB.u_dut.u_copy.state_r == 4'd6;
                        issue_now = compute_now;
                    end
                    8: begin
                        compute_now = (`PROFILE_TB.u_dut.u_blur.state_r == 4'd4) ||
                                      (`PROFILE_TB.u_dut.u_blur.state_r == 4'd8);
                        issue_now = compute_now;
                    end
                    9: begin
                        compute_now = `PROFILE_TB.u_dut.u_mask.state_r == 3'd1;
                        issue_now = compute_now;
                    end
                    default: begin end
                endcase

                active_cycles[op] = active_cycles[op] + 1;
                if (compute_now && ddr_now)
                    overlap_cycles[op] = overlap_cycles[op] + 1;
                else if (compute_now)
                    compute_only_cycles[op] = compute_only_cycles[op] + 1;
                else if (ddr_now)
                    ddr_only_cycles[op] = ddr_only_cycles[op] + 1;
                else
                    control_cycles[op] = control_cycles[op] + 1;
                if (issue_now) work_items[op] = work_items[op] + 1;
                if (ddr_now && !transfer_now)
                    ddr_wait_cycles[op] = ddr_wait_cycles[op] + 1;
                if (`PROFILE_TB.arvalid && `PROFILE_TB.u_dut.m_arready_i)
                    ar_count[op] = ar_count[op] + 1;
                if (`PROFILE_TB.u_dut.m_rvalid_i && `PROFILE_TB.rready)
                    r_count[op] = r_count[op] + 1;
                if (`PROFILE_TB.awvalid && `PROFILE_TB.u_dut.m_awready_i)
                    aw_count[op] = aw_count[op] + 1;
                if (`PROFILE_TB.wvalid && `PROFILE_TB.u_dut.m_wready_i)
                    w_count[op] = w_count[op] + 1;
                if (`PROFILE_TB.u_dut.m_bvalid_i && `PROFILE_TB.bready)
                    b_count[op] = b_count[op] + 1;
                if (op == 4 &&
                    (`PROFILE_TB.u_dut.u_round.state_r == 4'd1 ||
                     `PROFILE_TB.u_dut.u_round.state_r == 4'd2))
                    round_geometry_cycles = round_geometry_cycles + 1;
                if (op == 6 && `PROFILE_TB.u_dut.u_bitmap.scale_enable_r) begin
                    bitmap_scale_cycles = bitmap_scale_cycles + 1;
                    if (`PROFILE_TB.u_dut.u_bitmap.state_r == 4'd13 ||
                        `PROFILE_TB.u_dut.u_bitmap.state_r == 4'd14)
                        bitmap_scale_sample_cycles =
                            bitmap_scale_sample_cycles + 1;
                end
                if (op == 8) begin
                    if (`PROFILE_TB.u_dut.u_blur.vertical_r) begin
                        blur_vertical_cycles = blur_vertical_cycles + 1;
                        if (`PROFILE_TB.u_dut.u_blur.state_r == 4'd8)
                            blur_vertical_pixels = blur_vertical_pixels + 1;
                        if (`PROFILE_TB.u_dut.m_rvalid_i && `PROFILE_TB.rready)
                            blur_vertical_reads = blur_vertical_reads + 1;
                        if (`PROFILE_TB.wvalid && `PROFILE_TB.u_dut.m_wready_i)
                            blur_vertical_writes = blur_vertical_writes + 1;
                    end else begin
                        blur_horizontal_cycles = blur_horizontal_cycles + 1;
                        if (`PROFILE_TB.u_dut.u_blur.state_r == 4'd4)
                            blur_horizontal_pixels =
                                blur_horizontal_pixels + 1;
                        if (`PROFILE_TB.u_dut.m_rvalid_i && `PROFILE_TB.rready)
                            blur_horizontal_reads = blur_horizontal_reads + 1;
                        if (`PROFILE_TB.wvalid && `PROFILE_TB.u_dut.m_wready_i)
                            blur_horizontal_writes = blur_horizontal_writes + 1;
                    end
                end
            end
        end
    end

    final begin
        $display("PROFILE_HEADER op,total,compute_only,ddr_only,overlap,control,work_items,ddr_wait,ar,r,aw,w,b");
        for (index=1; index<10; index=index+1)
            if (active_cycles[index] != 0)
                $display("PROFILE %0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                         index,active_cycles[index],
                         compute_only_cycles[index],
                         ddr_only_cycles[index],overlap_cycles[index],
                         control_cycles[index],work_items[index],
                         ddr_wait_cycles[index],ar_count[index],
                         r_count[index],aw_count[index],
                         w_count[index],b_count[index]);
        $display("PROFILE_DETAIL round_geometry=%0d bitmap_scale_total=%0d bitmap_scale_sample=%0d blur_h_total=%0d blur_h_pixels=%0d blur_h_reads=%0d blur_h_writes=%0d blur_v_total=%0d blur_v_pixels=%0d blur_v_reads=%0d blur_v_writes=%0d",
                 round_geometry_cycles,bitmap_scale_cycles,
                 bitmap_scale_sample_cycles,blur_horizontal_cycles,
                 blur_horizontal_pixels,blur_horizontal_reads,
                 blur_horizontal_writes,blur_vertical_cycles,
                 blur_vertical_pixels,blur_vertical_reads,
                 blur_vertical_writes);
    end
endmodule
