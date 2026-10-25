// edrv32_cache_core_checker.sv
// cache-spec 5.1–5.3: expected hit response and precommit device bus exclusion.
// Clock domain: clk_sys.
module edrv32_cache_core_checker (
    // Clock and reset
    input logic clk_i,
    input logic rst_n_i,

    // Core interface observations
    input logic ic_accept_i,
    input logic dc_accept_i,
    input logic ic_hit_i,
    input logic dc_hit_i,
    input logic ic_resp_i,
    input logic dc_resp_i,
    input logic ic_kill_i,
    input logic dc_kill_i,
    input logic dc_device_i,
    input logic dc_commit_i,
    input logic dc_arvalid_i,
    input logic dc_awvalid_i,
    input logic [31:0] dc_addr_i,
    input logic dc_store_i,
    input logic [1:0] dc_size_i,
    input logic [31:0] dc_store_data_i,

    // AXI memory interface observations
    edrv32_axi64_if bus
);
    bit [31:0] request_addr;
    bit [1:0] request_size;
    bit request_store;
    bit request_device;
    bit [31:0] store_data;
    bit [63:0] store_mask;
    bit [63:0] shifted_store;
    bit bus_write_done;
    bit ic_due;
    bit dc_due;
    bit device_committed;
    bit ic_cancelled;
    bit dc_cancelled;
    always @(*) begin
        store_mask = ((64'b1 << (8 * (1 << request_size))) - 1) <<
                     (8 * request_addr[2:0]);
        shifted_store = 64'(store_data) << (8 * request_addr[2:0]);
    end
    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            request_device <= 0;
            bus_write_done <= 0;
            ic_due <= 0;
            dc_due <= 0;
            device_committed <= 0;
            ic_cancelled <= 0;
            dc_cancelled <= 0;
        end else begin
            if (ic_due && !ic_kill_i && !ic_resp_i)
                $fatal(1, "FAIL I hit response expected=1 actual=0 time=%0t", $time);
            if (dc_due && !dc_kill_i && !dc_resp_i)
                $fatal(1, "FAIL D hit response expected=1 actual=0 time=%0t", $time);
            if (ic_cancelled && ic_resp_i)
                $fatal(1, "FAIL killed I response expected=0 actual=1 time=%0t", $time);
            if (dc_cancelled && dc_resp_i)
                $fatal(1, "FAIL killed D response expected=0 actual=1 time=%0t", $time);
            if (dc_device_i && !device_committed && !dc_commit_i &&
                (dc_arvalid_i || dc_awvalid_i))
                $fatal(1, "FAIL device AXI before commit expected=0 actual=1 time=%0t",
                       $time);
            if (dc_device_i && (dc_arvalid_i || dc_awvalid_i)) begin
                if ((request_store ? bus.awaddr : bus.araddr) != request_addr)
                    $fatal(1, "FAIL device addr expected=%h actual=%h time=%0t",
                           request_addr, request_store ? bus.awaddr : bus.araddr, $time);
                if ((request_store ? bus.awsize : bus.arsize) != {1'b0, request_size})
                    $fatal(1, "FAIL device size expected=%h actual=%h time=%0t",
                           request_size, request_store ? bus.awsize : bus.arsize, $time);
            end
            if (dc_device_i && bus.wvalid) begin
                if ((bus.wdata & store_mask) != (shifted_store & store_mask))
                    $fatal(1, "FAIL device write data expected=%h actual=%h time=%0t",
                           shifted_store & store_mask, bus.wdata & store_mask, $time);
            end
            if (request_device && dc_resp_i && request_store && !bus.bvalid && !bus_write_done)
                $fatal(1, "FAIL device store before B expected=B actual=no_B time=%0t",
                       $time);
            if (ic_accept_i) ic_cancelled <= 0;
            if (dc_accept_i) begin
                dc_cancelled <= 0;
                request_device <= 0;
                bus_write_done <= 0;
                device_committed <= 0;
                request_addr <= dc_addr_i;
                request_size <= dc_size_i;
                request_store <= dc_store_i;
            end
            if (dc_device_i) request_device <= 1;
            if (ic_kill_i) ic_cancelled <= 1;
            if (dc_kill_i) dc_cancelled <= 1;
            if (bus.bvalid && bus.bready) bus_write_done <= 1;
            if (dc_commit_i) begin
                device_committed <= 1;
                store_data <= dc_store_data_i;
            end
            ic_due <= ic_accept_i && ic_hit_i && !ic_kill_i;
            dc_due <= dc_accept_i && dc_hit_i && !dc_kill_i;
        end
    end
endmodule
