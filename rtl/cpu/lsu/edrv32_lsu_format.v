// ============================================================================
// File        : edrv32_lsu_format.v
// Description : Combinational aligned RV32 load extension and store byte-lane
//               formatter. Misaligned halfword/word accesses are rejected in EX.
// ============================================================================
`include "edrv32_bus.vh"

module edrv32_lsu_format (
    input  wire [1:0]            addr_lsb_i,
    input  wire [`BUS_SZ_W-1:0]  size_i,
    input  wire [31:0]           mem_rdata_i,
    input  wire                  load_unsigned_i,
    output reg  [31:0]           load_data_o,
    input  wire [31:0]           store_wdata_i,
    output reg  [31:0]           store_data_o,
    output reg  [3:0]            store_wstrb_o
);

    reg [7:0] selected_byte_w;
    reg [15:0] selected_half_w;

    always @* begin
        case (addr_lsb_i)
            2'd0: selected_byte_w = mem_rdata_i[7:0];
            2'd1: selected_byte_w = mem_rdata_i[15:8];
            2'd2: selected_byte_w = mem_rdata_i[23:16];
            default: selected_byte_w = mem_rdata_i[31:24];
        endcase
        selected_half_w = addr_lsb_i[1] ? mem_rdata_i[31:16]
                                              : mem_rdata_i[15:0];
    end

    always @* begin
        case (size_i)
            `BUS_SZ_BYTE: load_data_o = load_unsigned_i
                            ? {24'd0, selected_byte_w}
                            : {{24{selected_byte_w[7]}}, selected_byte_w};
            `BUS_SZ_HALF: load_data_o = load_unsigned_i
                            ? {16'd0, selected_half_w}
                            : {{16{selected_half_w[15]}}, selected_half_w};
            default: load_data_o = mem_rdata_i;
        endcase
    end

    always @* begin
        store_data_o  = store_wdata_i;
        store_wstrb_o = 4'b1111;
        case (size_i)
            `BUS_SZ_BYTE: begin
                store_data_o  = {4{store_wdata_i[7:0]}};
                case (addr_lsb_i)
                    2'd0: store_wstrb_o = 4'b0001;
                    2'd1: store_wstrb_o = 4'b0010;
                    2'd2: store_wstrb_o = 4'b0100;
                    default: store_wstrb_o = 4'b1000;
                endcase
            end
            `BUS_SZ_HALF: begin
                store_data_o  = {2{store_wdata_i[15:0]}};
                store_wstrb_o = addr_lsb_i[1] ? 4'b1100 : 4'b0011;
            end
            default: begin end
        endcase
    end

endmodule
