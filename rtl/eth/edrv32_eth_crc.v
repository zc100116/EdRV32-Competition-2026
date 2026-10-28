// File: edrv32_eth_crc.v
// Spec: eth 2.2, 2.6, 5.1.
// Description: Ethernet reflected CRC32 update for one octet, including FCS octets.
//              Initial remainder is all ones; transmit complements the remainder.
// Clock domain: combinational.
module edrv32_eth_crc (
    // Byte and prior remainder.
    input wire [31:0] crc_i,
    input wire [7:0] data_i,
    output reg [31:0] crc_o
);
    integer idx;
    always @(*) begin
        crc_o = crc_i ^ {24'd0, data_i};
        for (idx = 0; idx < 8; idx = idx + 1) begin
            if (crc_o[0])
                crc_o = (crc_o >> 1) ^ 32'hedb88320;
            else
                crc_o = crc_o >> 1;
        end
    end
endmodule
