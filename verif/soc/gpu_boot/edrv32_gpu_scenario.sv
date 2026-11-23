// File: edrv32_gpu_scenario.sv
// Spec: gpu-soc-testplan ST-08; edrv32-soc-spec 7.5.
// Description: Observe real BIOS startup/menu and select Run over the UART pins.
//              The preloaded application checks CHIP_ID and writes SIM_EXIT.
// Clock domain: asynchronous UART; common SoC clocks.
`timescale 1ns/1ps
module edrv32_gpu_scenario (
    output bit checks_complete_o = 0,
    output wire [1:0] model_sda_oe_o
);
    assign model_sda_oe_o = 2'b00;
    string line_text = "";
    bit boot_seen = 0;
    bit chip_seen = 0;
    bit menu_seen = 0;
    bit run_prompt_seen = 0;
    int observed = 0;
    initial begin
        $root.edrv32_gpu_soc_tb.gpio_i[0] = 0;
        forever begin
            wait ($root.edrv32_gpu_soc_tb.uart_log.len() > observed);
            while ($root.edrv32_gpu_soc_tb.uart_log.len() > observed) begin
                case ($root.edrv32_gpu_soc_tb.uart_log[observed])
                    10: begin
                        if (line_text == "  EdRV32 Boot ROM - UART 115200 8N1") boot_seen = 1;
                        if (line_text == "CHIP_ID: 0xed320002") chip_seen = 1;
                        if (line_text == "BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud")
                            menu_seen = 1;
                        if (line_text == "Run address:") run_prompt_seen = 1;
                        if (line_text == "GPU CHIP_ID ed320002 PASS")
                            checks_complete_o = boot_seen && chip_seen && menu_seen;
                        line_text = "";
                    end
                    13: begin end
                    default: line_text = {line_text,
                        string'($root.edrv32_gpu_soc_tb.uart_log[observed])};
                endcase
                observed++;
            end
        end
    end
    initial begin
        wait (menu_seen);
        $root.edrv32_gpu_soc_tb.u_uart.send("3");
        $root.edrv32_gpu_soc_tb.u_uart.send(13);
        wait (run_prompt_seen);
        send_address();
    end
    task automatic send_address();
        string address_text = "0x10000000";
        foreach (address_text[index])
            $root.edrv32_gpu_soc_tb.u_uart.send(address_text[index]);
        $root.edrv32_gpu_soc_tb.u_uart.send(13);
    endtask
endmodule
