// ============================================================================
// File        : edrv32_cache_maint.v
// Provenance  : Refactored from the validated cache_maint.v register block.
// Description : CPU-local native MMIO slave for the frozen cache-maintenance
//               window at 0x4000_3000.  It issues range-aware D$ maintenance
//               commands and whole-I$ invalidation pulses.
// ============================================================================
`include "edrv32_bus.vh"
`include "edrv32_soc_map.vh"

module edrv32_cache_maint #(
    parameter [31:0] BASE_ADDR = `SOC_CACHE_MAINT_BASE
) (
    input  wire                 clk_i,
    input  wire                 rst_n_i,

    input  wire                 request_valid_i,
    output wire                 request_ready_o,
    input  wire [31:0]          request_addr_i,
    input  wire                 request_write_i,
    input  wire [`BUS_SZ_W-1:0] request_size_i,
    input  wire [3:0]           request_wstrb_i,
    input  wire [31:0]          request_wdata_i,
    output wire                 response_valid_o,
    input  wire                 response_ready_i,
    output wire [31:0]          response_data_o,
    output wire                 response_error_o,

    output wire                 dcache_invalidate_o,
    output wire                 dcache_clean_o,
    output wire                 dcache_clean_invalidate_o,
    output wire [31:0]          dcache_addr_o,
    output wire [31:0]          dcache_size_o,
    input  wire                 dcache_busy_i,
    input  wire                 dcache_done_i,
    output wire                 icache_invalidate_o
);

    localparam [4:0] OFFSET_CONTROL   = 5'h00;
    localparam [4:0] OFFSET_ADDRESS   = 5'h04;
    localparam [4:0] OFFSET_SIZE      = 5'h08;
    localparam [4:0] OFFSET_STATUS    = 5'h0c;
    localparam [4:0] OFFSET_IC_INVALIDATE = 5'h10;

    reg response_valid_r;

    wire address_hit_w = (request_addr_i[31:5] == BASE_ADDR[31:5]);
    wire [4:0] request_offset_w = request_addr_i[4:0];
    wire response_slot_available_w = !response_valid_r;
    wire dcache_command_access_w = request_write_i &&
                                   (request_offset_w == OFFSET_CONTROL);
    wire command_blocked_w = address_hit_w && request_valid_i &&
                             dcache_command_access_w && dcache_busy_i;
    assign request_ready_o = response_slot_available_w && !command_blocked_w;
    wire request_fire_w = address_hit_w && request_valid_i && request_ready_o;
    wire register_write_fire_w = request_fire_w && request_write_i;

    reg [31:0] maintenance_addr_r;
    reg [31:0] maintenance_size_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            maintenance_addr_r <= 32'd0;
            maintenance_size_r <= 32'd0;
        end else if (register_write_fire_w) begin
            if (request_offset_w == OFFSET_ADDRESS)
                maintenance_addr_r <= request_wdata_i;
            if (request_offset_w == OFFSET_SIZE)
                maintenance_size_r <= request_wdata_i;
        end
    end

    reg dcache_invalidate_r;
    reg dcache_clean_r;
    reg dcache_clean_invalidate_r;
    reg icache_invalidate_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            dcache_invalidate_r <= 1'b0;
            dcache_clean_r <= 1'b0;
            dcache_clean_invalidate_r <= 1'b0;
            icache_invalidate_r <= 1'b0;
        end else begin
            dcache_invalidate_r <= 1'b0;
            dcache_clean_r <= 1'b0;
            dcache_clean_invalidate_r <= 1'b0;
            icache_invalidate_r <= 1'b0;

            if (register_write_fire_w &&
                (request_offset_w == OFFSET_CONTROL)) begin
                if (request_wdata_i[2])
                    dcache_clean_invalidate_r <= 1'b1;
                else if (request_wdata_i[1])
                    dcache_clean_r <= 1'b1;
                else if (request_wdata_i[0])
                    dcache_invalidate_r <= 1'b1;
            end
            if (register_write_fire_w &&
                (request_offset_w == OFFSET_IC_INVALIDATE) &&
                request_wdata_i[0])
                icache_invalidate_r <= 1'b1;
        end
    end

    reg [31:0] response_payload_w;
    always @* begin
        response_payload_w = 32'd0;
        case (request_offset_w)
            OFFSET_ADDRESS: response_payload_w = maintenance_addr_r;
            OFFSET_SIZE: response_payload_w = maintenance_size_r;
            OFFSET_STATUS: response_payload_w = {31'd0, dcache_busy_i};
            default: response_payload_w = 32'd0;
        endcase
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            response_valid_r <= 1'b0;
        else if (request_fire_w)
            response_valid_r <= 1'b1;
        else if (response_valid_r && response_ready_i)
            response_valid_r <= 1'b0;
    end

    reg [31:0] response_data_r;
    always @(posedge clk_i) begin
        if (request_fire_w)
            response_data_r <= response_payload_w;
    end

    assign response_valid_o = response_valid_r;
    assign response_data_o = response_data_r;
    assign response_error_o = 1'b0;
    assign dcache_invalidate_o = dcache_invalidate_r;
    assign dcache_clean_o = dcache_clean_r;
    assign dcache_clean_invalidate_o = dcache_clean_invalidate_r;
    assign dcache_addr_o = maintenance_addr_r;
    assign dcache_size_o = maintenance_size_r;
    assign icache_invalidate_o = icache_invalidate_r;

    // These fields are part of the preserved native-MMIO ABI.  The controller
    // accepts the same word-oriented accesses as the original implementation.
    wire unused_request_fields_w = ^{request_size_i, request_wstrb_i,
                                     dcache_done_i};

endmodule
