// File: media_stimulus.svh
// Spec: soc-testplan SC-05/06; section 4 reference models.
// Description: Compare CH2/NPU DDR results against independent reference images.
//              A DDR mailbox controls external events without observing DUT internals.
// Clock domain: clk_sys mailbox and clk_mem DDR model.
    localparam bit [31:0] MAILBOX = 32'h0a3ff000;
    int checked_regions = 0;
    bit rx_requested = 0;
    bit rx_complete = 0;

    function automatic bit [31:0] peek_word(input bit [31:0] address);
        bit [31:0] value;
        for (int i = 0; i < 4; i++) value[i*8+:8] = u_ddr.peek(address + 32'(i));
        return value;
    endfunction

    task automatic poke_word(input bit [31:0] address, input bit [31:0] value);
        for (int i = 0; i < 4; i++) u_ddr.poke(address + 32'(i), value[i*8+:8]);
    endtask

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
                        3: compare_region(argument, "ch2");
                        4: rx_requested = 1;
                        5: compare_region(argument, "npu");
                        99: begin
                            case (case_number)
                                5: checks_complete = checked_regions == 2;
                                6: checks_complete = rx_complete && arp_checked;
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
