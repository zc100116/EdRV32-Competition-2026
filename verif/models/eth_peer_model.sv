// File: eth_peer_model.sv
// Spec: eth 2.2, 2.6; eth-testplan 2.
// Description: MAC-side frame source with wire-error injection and checked frame sink.
// Clock domain: independent rx_clk_i (source) and tx_clk_i (sink).
`timescale 1ns/1ps
module eth_peer_model (
    input logic rx_clk_i,
    input logic tx_clk_i,
    input logic rst_n_i,
    output logic [7:0] rxd_o,
    output logic rx_dv_o,
    output logic rx_er_o,
    input logic [7:0] txd_i,
    input logic tx_en_i,
    input logic tx_er_i
);
    byte unsigned received[$];
    byte unsigned capture[$];
    int frame_count = 0;
    bit [31:0] received_fcs;
    int idle_cycles = 12;
    int source_count = 0;
    bit frame_done = 0;
    realtime frame_start;
    realtime frame_end;
    realtime source_end;

    function automatic bit [31:0] crc32(input byte unsigned bytes_i[$]);
        bit [31:0] crc;
        crc = 32'hffffffff;
        foreach (bytes_i[i]) begin
            crc ^= {24'b0, bytes_i[i]};
            repeat (8) crc = (crc >> 1) ^ (crc[0] ? 32'hedb88320 : 32'b0);
        end
        return ~crc;
    endfunction

    // Input excludes preamble/SFD/FCS; corruption is applied after FCS generation.
    // flip/er use wire byte indices, starting at the first preamble byte.
    task automatic send_frame(input byte unsigned bytes_i[$],
        input int gap_i = 12,
        input int flip_i = -1,
        input int er_i = -1,
        input int trim_i = 0,
        input int extend_i = 0);
        byte unsigned wire_bytes[$];
        bit [31:0] crc;
        wire_bytes.delete();
        repeat (7) wire_bytes.push_back(8'h55);
        wire_bytes.push_back(8'hd5);
        foreach (bytes_i[i]) wire_bytes.push_back(bytes_i[i]);
        crc = crc32(bytes_i);
        for (int i = 0; i < 4; i++) wire_bytes.push_back(8'(crc >> (8*i)));
        repeat (trim_i) void'(wire_bytes.pop_back());
        repeat (extend_i) wire_bytes.push_back(0);
        repeat (gap_i) @(negedge rx_clk_i);
        foreach (wire_bytes[i]) begin
            rxd_o = wire_bytes[i] ^ (i == flip_i ? 8'h01 : 8'h00);
            rx_dv_o = 1;
            rx_er_o = i == er_i;
            @(negedge rx_clk_i);
        end
        rx_dv_o = 0;
        rx_er_o = 0;
        rxd_o = 0;
        source_count++;
        source_end = $realtime;
    endtask

    initial begin
        rxd_o = 0;
        rx_dv_o = 0;
        rx_er_o = 0;
    end

    always @(posedge tx_clk_i) begin : sink
        byte unsigned body[$];
        bit [31:0] crc;
        frame_done = 0;
        if (!rst_n_i) begin
            capture.delete();
            received.delete();
            frame_count = 0;
            idle_cycles = 12;
        end else if (tx_en_i) begin
            if (capture.size() == 0) begin
                if (idle_cycles < 12)
                    $fatal(1, "FAIL frame=%0d IFG expected>=12 actual=%0d time=%0t",
                        frame_count, idle_cycles, $time);
                frame_start = $realtime;
            end
            if (tx_er_i)
                $fatal(1, "FAIL frame=%0d byte=%0d tx_er expected=0 actual=1 time=%0t",
                    frame_count, capture.size(), $time);
            capture.push_back(txd_i);
            idle_cycles = 0;
        end else begin
            idle_cycles++;
            if (capture.size() != 0) begin
                if (capture.size() < 72 || capture.size() > 1526)
                    $fatal(1, "FAIL frame=%0d length expected=72..1526 actual=%0d time=%0t",
                        frame_count, capture.size(), $time);
                for (int i = 0; i < 8; i++) begin
                    if (capture[i] != (i == 7 ? 8'hd5 : 8'h55))
                        $fatal(1, "FAIL frame=%0d byte=%0d expected=%h actual=%h time=%0t",
                            frame_count, i, (i == 7 ? 8'hd5 : 8'h55), capture[i], $time);
                end
                body.delete();
                for (int i = 8; i < capture.size()-4; i++) body.push_back(capture[i]);
                crc = crc32(body);
                for (int i = 0; i < 4; i++) begin
                    received_fcs[i*8+:8] = capture[capture.size()-4+i];
                    if (capture[capture.size()-4+i] != 8'(crc >> (8*i)))
                        $fatal(1, "FAIL frame=%0d FCS byte=%0d expected=%h actual=%h time=%0t",
                            frame_count, i, 8'(crc >> (8*i)),
                            capture[capture.size()-4+i], $time);
                end
                received = body;
                frame_count++;
                frame_end = $realtime;
                frame_done = 1;
                capture.delete();
            end
        end
    end
endmodule
