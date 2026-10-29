// File: media_stimulus.svh
// Spec: soc-testplan SC-03/04/05/08/09/10/11; section 4 reference models.
// Description: Supply full camera frames and compare HDMI/DDR against independent images.
//              A DDR mailbox controls external events without observing DUT internals.
// Clock domain: clk_sys mailbox, independent camera pclk and clk_pix.
    localparam bit [31:0] MAILBOX = 32'h0a3ff000;
    logic [15:0] camera_storage[0:1280*720-1];
    logic [15:0] camera_image[];
    int camera_remaining = 0;
    int checked_frames = 0;
    int checked_regions = 0;
    bit rx_requested = 0;
    bit rx_complete = 0;
    bit rx_stop = 0;

    function automatic bit [31:0] peek_word(input bit [31:0] address);
        bit [31:0] value;
        for (int i = 0; i < 4; i++) value[i*8+:8] = u_ddr.peek(address + 32'(i));
        return value;
    endfunction

    task automatic poke_word(input bit [31:0] address, input bit [31:0] value);
        for (int i = 0; i < 4; i++) u_ddr.poke(address + 32'(i), value[i*8+:8]);
    endtask

    initial begin : camera_source
        realtime start_ns;
        #1;
        if (case_number inside {3, 4, 8, 9, 10, 11}) begin
            $readmemh({data_dir, "/camera.hex"}, camera_storage);
            camera_image = new[1280*720];
            foreach (camera_image[i]) camera_image[i] = camera_storage[i];
            u_cam0.half_period_ns = 6.734007;
            u_cam1.half_period_ns = 6.734007;
            u_cam0.line_blank = 64;
            forever begin
                wait (camera_remaining != 0);
                start_ns = $realtime;
                u_cam0.send_frame(1280, 720, camera_image);
                camera_remaining--;
                // The 30 fps source includes active transfer plus the frame blank interval.
                #(33333333.333 - ($realtime - start_ns));
            end
        end
    end

    task automatic compare_region(input bit [31:0] address, input string name);
        int fd;
        int expected;
        int position;
        byte unsigned actual;
        fd = $fopen({data_dir, "/", name, ".bin"}, "rb");
        if (fd == 0) $fatal(1, "expected image open failed name=%s", name);
        position = 0;
        expected = $fgetc(fd);
        while (expected != -1) begin
            actual = u_ddr.peek(address + 32'(position));
            if (actual != 8'(expected))
                $fatal(1, "FAIL %s address=%h byte=%0d expected=%02h actual=%02h time=%0t",
                    name, address, position, 8'(expected), actual, $time);
            position++;
            expected = $fgetc(fd);
        end
        $fclose(fd);
        checked_regions++;
        $display("CHECK DDR %s bytes=%0d address=%h time=%0t", name, position, address, $time);
    endtask

    task automatic compare_display(input string name);
        int target;
        int fd;
        int unused_low_byte;
        int unused_high_byte;
        bit [15:0] pixel;
        bit [23:0] expected;
        bit [23:0] actual;
        // Discard the frame in progress when the check is armed, then inspect one full frame.
        hdmi_capture_enable = 1;
        target = unused_hdmi_frames + 2;
        wait (unused_hdmi_frames >= target);
        @(negedge clk_pix_i);
        if (unused_hdmi_pixels != 1280*720)
            $fatal(1, "FAIL HDMI length expected=921600 actual=%0d time=%0t",
                unused_hdmi_pixels, $time);
        fd = $fopen({data_dir, "/", name, ".bin"}, "rb");
        if (fd == 0) $fatal(1, "expected display open failed name=%s", name);
        for (int i = 0; i < 1280*720; i++) begin
            unused_low_byte = $fgetc(fd);
            unused_high_byte = $fgetc(fd);
            pixel = {8'(unused_high_byte), 8'(unused_low_byte)};
            expected = {pixel[15:11], pixel[15:13], pixel[10:5], pixel[10:9],
                        pixel[4:0], pixel[4:2]};
            actual = u_hdmi.frame_pixels[i];
            if (actual != expected)
                $fatal(1, "FAIL HDMI %s x=%0d y=%0d expected=%06h actual=%06h time=%0t",
                    name, i%1280, i/1280, expected, actual, $time);
        end
        $fclose(fd);
        hdmi_capture_enable = 0;
        checked_frames++;
        $display("CHECK HDMI %s pixels=921600 time=%0t", name, $time);
    endtask

    initial begin : model_commands
        bit [31:0] operation;
        bit [31:0] argument;
        #1;
        if (case_number != 1) begin
            forever begin
                repeat (10) @(negedge clk_sys_i);
                operation = peek_word(MAILBOX);
                argument = peek_word(MAILBOX + 4);
                if (operation != 0) begin
                    $display("MODEL operation=%0d argument=%h time=%0t",
                        operation, argument, $time);
                    $fflush();
                    case (operation)
                        1: camera_remaining += int'(argument);
                        2: begin
                            case (argument)
                                0: compare_display("bypass");
                                1: compare_display("mean");
                                2: compare_display("geo");
                                default: $fatal(1, "unknown display image=%0d", argument);
                            endcase
                        end
                        3: compare_region(argument, "ch2");
                        4: rx_requested = 1;
                        5: compare_region(argument, "npu");
                        6: compare_region(argument, "bypass");
                        7: compare_region(argument, "mean");
                        8: begin
                            wait (!u_cam0.transmitting);
                            camera_remaining = 0;
                        end
                        9: begin
                            rx_stop = 1;
                            wait (rx_complete);
                        end
                        99: begin
                            case (case_number)
                                3: checks_complete = checked_frames == 2;
                                4: checks_complete = checked_frames == 1;
                                5: checks_complete = checked_regions == 2;
                                6: checks_complete = rx_complete && arp_checked;
                                7: checks_complete = video_checked && monitor_checked;
                                8, 9: checks_complete = video_frames >= 1;
                                10: checks_complete = checked_frames == 1;
                                11: checks_complete = rx_complete;
                                default: $fatal(1, "unknown case=%0d", case_number);
                            endcase
                        end
                        default: $fatal(1, "unknown model operation=%0d", operation);
                    endcase
                    poke_word(MAILBOX, 0);
                    poke_word(MAILBOX + 8, 1);
                end
            end
        end
    end
