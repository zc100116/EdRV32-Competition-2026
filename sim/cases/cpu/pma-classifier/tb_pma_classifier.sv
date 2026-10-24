`timescale 1ns/1ps
`include "edrv32_pma.vh"

module tb_pma_classifier;
    reg [31:0] address;
    reg instruction;
    reg load;
    reg store;

    wire mapped_off;
    wire permitted_off;
    wire fault_off;
    wire cacheable_off;
    wire tcm_off;
    wire device_off;
    wire [`PMA_ATTR_WIDTH-1:0] attributes_off;
    wire mapped_on;
    wire permitted_on;
    wire fault_on;
    wire cacheable_on;
    wire tcm_on;
    wire device_on;
    wire [`PMA_ATTR_WIDTH-1:0] attributes_on;
    wire permitted_itcm_only;
    wire fault_itcm_only;
    integer checks;

    edrv32_pma_classifier #(.TCM_ENABLE(0)) dut_tcm_off (
        .address_i(address), .instruction_i(instruction),
        .load_i(load), .store_i(store), .mapped_o(mapped_off),
        .permitted_o(permitted_off), .access_fault_o(fault_off),
        .cacheable_o(cacheable_off), .tcm_o(tcm_off),
        .device_o(device_off), .attributes_o(attributes_off)
    );

    edrv32_pma_classifier #(.TCM_ENABLE(1)) dut_tcm_on (
        .address_i(address), .instruction_i(instruction),
        .load_i(load), .store_i(store), .mapped_o(mapped_on),
        .permitted_o(permitted_on), .access_fault_o(fault_on),
        .cacheable_o(cacheable_on), .tcm_o(tcm_on),
        .device_o(device_on), .attributes_o(attributes_on)
    );

    edrv32_pma_classifier #(
        .TCM_ENABLE (0),
        .ITCM_ENABLE(1),
        .DTCM_ENABLE(0)
    ) dut_itcm_only (
        .address_i(address), .instruction_i(instruction),
        .load_i(load), .store_i(store), .mapped_o(),
        .permitted_o(permitted_itcm_only),
        .access_fault_o(fault_itcm_only), .cacheable_o(), .tcm_o(),
        .device_o(), .attributes_o()
    );

    task automatic set_access;
        input [31:0] address_i;
        input instruction_i;
        input load_i;
        input store_i;
        begin
            address = address_i;
            instruction = instruction_i;
            load = load_i;
            store = store_i;
            #1;
        end
    endtask

    task automatic check_off;
        input expected_mapped;
        input expected_permitted;
        input expected_fault;
        input expected_cacheable;
        input expected_tcm;
        input expected_device;
        input [`PMA_ATTR_WIDTH-1:0] expected_attributes;
        input [8*96-1:0] message;
        begin
            checks = checks + 1;
            if ({mapped_off, permitted_off, fault_off, cacheable_off,
                 tcm_off, device_off, attributes_off} !==
                {expected_mapped, expected_permitted, expected_fault,
                 expected_cacheable, expected_tcm, expected_device,
                 expected_attributes}) begin
                $display("FAIL TCM-off: %0s got=%b%b%b%b%b%b/%02x", message,
                    mapped_off, permitted_off, fault_off, cacheable_off,
                    tcm_off, device_off, attributes_off);
                $fatal(1);
            end
        end
    endtask

    task automatic check_on;
        input expected_mapped;
        input expected_permitted;
        input expected_fault;
        input expected_cacheable;
        input expected_tcm;
        input expected_device;
        input [`PMA_ATTR_WIDTH-1:0] expected_attributes;
        input [8*96-1:0] message;
        begin
            checks = checks + 1;
            if ({mapped_on, permitted_on, fault_on, cacheable_on,
                 tcm_on, device_on, attributes_on} !==
                {expected_mapped, expected_permitted, expected_fault,
                 expected_cacheable, expected_tcm, expected_device,
                 expected_attributes}) begin
                $display("FAIL TCM-on: %0s got=%b%b%b%b%b%b/%02x", message,
                    mapped_on, permitted_on, fault_on, cacheable_on,
                    tcm_on, device_on, attributes_on);
                $fatal(1);
            end
        end
    endtask

    initial begin
        checks = 0;

        set_access(32'h0000_0000, 1'b0, 1'b0, 1'b0);
        check_off(1, 0, 0, 0, 0, 0, `PMA_ATTR_ROM,
                  "No access request never faults");

        set_access(32'h0000_0000, 1, 0, 0);
        check_off(1, 1, 0, 0, 0, 0, `PMA_ATTR_ROM, "ROM instruction base");
        set_access(32'h0000_3fff, 0, 1, 0);
        check_off(1, 1, 0, 0, 0, 0, `PMA_ATTR_ROM, "ROM load last byte");
        set_access(32'h0000_0100, 0, 0, 1);
        check_off(1, 0, 1, 0, 0, 0, `PMA_ATTR_ROM, "ROM store denied");
        set_access(32'h0000_4000, 1, 0, 0);
        check_off(0, 0, 1, 0, 0, 0, 8'd0, "Post-ROM hole denied");

        set_access(32'h0100_0000, 1, 0, 0);
        check_off(1, 0, 1, 0, 0, 0, `PMA_ATTR_ITCM,
                  "Disabled ITCM instruction denied");
        check_on(1, 1, 0, 0, 1, 0, `PMA_ATTR_ITCM,
                 "Enabled ITCM instruction allowed");
        if (!permitted_itcm_only || fault_itcm_only)
            $fatal(1, "ITCM-only profile denied an ITCM fetch");
        checks = checks + 1;
        set_access(32'h0100_ffff, 0, 1, 0);
        check_on(1, 0, 1, 0, 0, 0, `PMA_ATTR_ITCM,
                 "ITCM data load denied");

        set_access(32'h0200_0000, 0, 1, 0);
        check_off(1, 0, 1, 0, 0, 0, `PMA_ATTR_DTCM,
                  "Disabled DTCM load denied");
        check_on(1, 1, 0, 0, 1, 0, `PMA_ATTR_DTCM,
                 "Enabled DTCM load allowed");
        if (permitted_itcm_only || !fault_itcm_only)
            $fatal(1, "ITCM-only profile allowed a DTCM load");
        checks = checks + 1;
        set_access(32'h0200_ffff, 0, 0, 1);
        check_on(1, 1, 0, 0, 1, 0, `PMA_ATTR_DTCM,
                 "Enabled DTCM store last byte");
        set_access(32'h0200_0000, 1, 0, 0);
        check_on(1, 0, 1, 0, 0, 0, `PMA_ATTR_DTCM,
                 "DTCM instruction denied");

        set_access(32'h1000_0000, 1, 0, 0);
        check_off(1, 1, 0, 1, 0, 0, `PMA_ATTR_SRAM, "SRAM instruction base");
        set_access(32'h1003_ffff, 0, 0, 1);
        check_off(1, 1, 0, 1, 0, 0, `PMA_ATTR_SRAM, "SRAM store last byte");
        set_access(32'h1004_0000, 0, 1, 0);
        check_off(0, 0, 1, 0, 0, 0, 8'd0, "Post-SRAM hole denied");

        set_access(32'h2000_0000, 0, 1, 0);
        check_off(1, 1, 0, 0, 0, 1, `PMA_ATTR_CLINT, "CLINT load base");
        set_access(32'h2000_ffff, 0, 0, 1);
        check_off(1, 1, 0, 0, 0, 1, `PMA_ATTR_CLINT, "CLINT store last byte");
        set_access(32'h2000_0000, 1, 0, 0);
        check_off(1, 0, 1, 0, 0, 0, `PMA_ATTR_CLINT, "CLINT execute denied");

        set_access(32'h3000_0000, 0, 1, 0);
        check_off(1, 1, 0, 0, 0, 1, `PMA_ATTR_PLIC, "PLIC load base");
        set_access(32'h303f_ffff, 0, 0, 1);
        check_off(1, 1, 0, 0, 0, 1, `PMA_ATTR_PLIC, "PLIC store last byte");
        set_access(32'h3040_0000, 0, 1, 0);
        check_off(0, 0, 1, 0, 0, 0, 8'd0, "Post-PLIC hole denied");

        set_access(32'h4000_0000, 0, 1, 0);
        check_off(1, 1, 0, 0, 0, 1, `PMA_ATTR_PERIPH, "PERIPH load base");
        set_access(32'h4003_ffff, 0, 0, 1);
        check_off(1, 1, 0, 0, 0, 1, `PMA_ATTR_PERIPH, "PERIPH store last byte");
        set_access(32'h4004_0000, 1, 0, 0);
        check_off(0, 0, 1, 0, 0, 0, 8'd0, "Post-PERIPH hole denied");

        set_access(32'h8000_0000, 1, 0, 0);
        check_off(1, 1, 0, 1, 0, 0, `PMA_ATTR_DDR, "DDR instruction base");
        set_access(32'hbfff_ffff, 0, 0, 1);
        check_off(1, 1, 0, 1, 0, 0, `PMA_ATTR_DDR, "DDR store last byte");
        set_access(32'hc000_0000, 1, 0, 0);
        check_off(1, 0, 1, 0, 0, 0, `PMA_ATTR_DDR_UNCACHED,
                  "DDR alias execute denied");
        set_access(32'hffff_ffff, 0, 1, 0);
        check_off(1, 1, 0, 0, 0, 0, `PMA_ATTR_DDR_UNCACHED,
                  "DDR alias load last byte");

        set_access(32'h5000_0000, 0, 0, 1);
        check_off(0, 0, 1, 0, 0, 0, 8'd0, "Unmapped store denied");

        $display("PASS: PMA classifier boundaries and permissions (%0d checks)", checks);
        $finish;
    end
endmodule
