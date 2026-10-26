// File: edrv32_mem_xbar_rbuf.v
// Spec: mem-subsys-spec 2.2; edrv32-soc-spec 6.4.4.
// Description: Shared 128-beat DRM with exact burst credit reservation.
// Per-ID linked queues preserve AXI ordering while accepting every downstream R beat.
// Credits are released only by upstream handshakes, including output staging registers.
// Clock: clk_mem.
module edrv32_mem_xbar_rbuf (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Reservation from the scheduler. Illegal reads use the same ordered queue.
    input wire reserve_i,
    input wire [2:0] reserve_port_i,
    input wire reserve_id_i,
    input wire [4:0] reserve_beats_i,
    input wire reserve_error_i,
    output reg [7:0] free_cnt_o,

    // Unconditionally accepted DDR data.
    input wire [3:0] ddr_rid_i,
    input wire [255:0] ddr_rdata_i,
    input wire [1:0] ddr_rresp_i,
    input wire ddr_rlast_i,
    input wire ddr_rvalid_i,

    // Seven upstream read channels, little-endian port slices.
    output wire [6:0] rid_o,
    output wire [1791:0] rdata_o,
    output wire [13:0] rresp_o,
    output wire [6:0] rlast_o,
    output wire [6:0] rvalid_o,
    input wire [6:0] rready_i
);
    reg [127:0] free_r;
    reg [127:0] arrived_r;
    reg [127:0] error_r;
    reg [127:0] last_r;
    reg [6:0] next_r [0:127];
    reg [6:0] return_next_r [0:127];
    reg [6:0] head_r [0:13];
    reg [6:0] tail_r [0:13];
    reg [7:0] count_r [0:13];
    reg [6:0] return_head_r [0:13];
    reg [6:0] return_tail_r [0:13];
    reg [7:0] return_count_r [0:13];
    reg [6:0] skid_valid_r;
    reg [258:0] skid_data_r [0:6];
    reg [6:0] skid_addr_r [0:6];
    reg [6:0] skid_id_r;
    reg [6:0] id_turn_r;
    reg pending_r;
    reg [3:0] pending_queue_r;
    reg [6:0] pending_addr_r;
    reg pending_error_r;
    reg pending_last_r;
    reg [2:0] read_turn_r;
    wire [258:0] ram_data_w;
    wire [258:0] pending_data_w;
    wire [3:0] reserve_queue_w;
    reg [6:0] alloc_addr_w [0:15];
    reg [127:0] alloc_mask_w;
    reg [127:0] release_mask_w;
    reg fetch_w;
    reg [3:0] fetch_queue_w;
    reg [6:0] fetch_addr_w;
    reg [3:0] release_cnt_w;
    reg [6:0] take_w;
    integer alloc_idx;
    integer alloc_count;
    integer choose_step;
    integer choose_port;
    integer choose_id;
    reg [3:0] choose_queue;
    integer release_port;
    integer queue_idx;
    integer link_idx;
    integer port_idx;
    genvar p;

    assign reserve_queue_w = {reserve_port_i, reserve_id_i};
    assign pending_data_w = pending_error_r ? {pending_last_r, 2'b10, 256'b0} : ram_data_w;

    edrv32_ram_mem_xbar_r u_ram (
        .clk_i(clk_i),
        .wr_en_i(ddr_rvalid_i),
        .wr_addr_i(return_head_r[ddr_rid_i]),
        .wr_data_i({ddr_rlast_i, ddr_rresp_i, ddr_rdata_i}),
        .rd_en_i(fetch_w),
        .rd_addr_i(fetch_addr_w),
        .rd_data_o(ram_data_w)
    );

    generate
        for (p = 0; p < 7; p = p + 1) begin : g_output
            wire pending_here_w;
            wire [258:0] data_w;
            assign pending_here_w = pending_r && pending_queue_r[3:1] == p;
            assign data_w = skid_valid_r[p] ? skid_data_r[p] : pending_data_w;
            assign rvalid_o[p] = rst_n_i && (skid_valid_r[p] || pending_here_w);
            assign rid_o[p] = skid_valid_r[p] ? skid_id_r[p] : pending_queue_r[0];
            assign rdata_o[p*256 +: 256] = data_w[255:0];
            assign rresp_o[p*2 +: 2] = data_w[257:256];
            assign rlast_o[p] = data_w[258];
        end
    endgenerate

    // Allocate only the requested number of free beats; no fixed 16-beat slot wastage.
    always @(*) begin
        alloc_count = 0;
        alloc_mask_w = 128'b0;
        for (alloc_idx = 0; alloc_idx < 16; alloc_idx = alloc_idx + 1) begin
            alloc_addr_w[alloc_idx] = 7'b0;
        end
        for (alloc_idx = 0; alloc_idx < 128; alloc_idx = alloc_idx + 1) begin
            if (reserve_i && free_r[alloc_idx] && alloc_count < {27'b0, reserve_beats_i})
            begin
                alloc_addr_w[alloc_count] = alloc_idx[6:0];
                alloc_mask_w[alloc_idx] = 1'b1;
                alloc_count = alloc_count + 1;
            end
        end
    end

    always @(*) begin
        release_mask_w = 128'b0;
        release_cnt_w = 4'b0;
        take_w = rvalid_o & rready_i;
        for (release_port = 0; release_port < 7; release_port = release_port + 1) begin
            if (take_w[release_port]) begin
                release_mask_w[skid_valid_r[release_port] ? skid_addr_r[release_port] :
                                pending_addr_r] = 1'b1;
                release_cnt_w = release_cnt_w + 4'd1;
            end
        end
    end

    // One shared DRM read per cycle. The RAM output bypasses into the selected port;
    // if that port stalls it is captured in its skid register before the next read.
    always @(*) begin
        fetch_w = 1'b0;
        fetch_queue_w = 4'b0;
        fetch_addr_w = 7'b0;
        choose_port = 0;
        choose_queue = 0;
        for (choose_step = 0; choose_step < 7; choose_step = choose_step + 1) begin
            choose_port = {29'b0, read_turn_r} + choose_step;
            if (choose_port >= 7) begin
                choose_port = choose_port - 7;
            end
            for (choose_id = 0; choose_id < 2; choose_id = choose_id + 1) begin
                choose_queue = {choose_port[2:0], id_turn_r[choose_port] ^ (choose_id != 0)};
                if (!fetch_w && rst_n_i && count_r[choose_queue] != 0 &&
                    arrived_r[head_r[choose_queue]] &&
                    (!rvalid_o[choose_port] || rready_i[choose_port])) begin
                    fetch_w = 1'b1;
                    fetch_queue_w = choose_queue[3:0];
                    fetch_addr_w = head_r[choose_queue];
                end
            end
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            free_cnt_o <= 8'd128;
            free_r <= {128{1'b1}};
            arrived_r <= 128'b0;
            error_r <= 128'b0;
            last_r <= 128'b0;
            pending_r <= 1'b0;
            pending_queue_r <= 4'b0;
            pending_addr_r <= 7'b0;
            pending_error_r <= 1'b0;
            pending_last_r <= 1'b0;
            skid_valid_r <= 7'b0;
            id_turn_r <= 7'b0;
            read_turn_r <= 3'b0;
            for (queue_idx = 0; queue_idx < 14; queue_idx = queue_idx + 1) begin
                head_r[queue_idx] <= 7'b0;
                tail_r[queue_idx] <= 7'b0;
                count_r[queue_idx] <= 8'b0;
                return_head_r[queue_idx] <= 7'b0;
                return_tail_r[queue_idx] <= 7'b0;
                return_count_r[queue_idx] <= 8'b0;
            end
        end else begin
            free_r <= (free_r | release_mask_w) & ~alloc_mask_w;
            free_cnt_o <= free_cnt_o + {4'b0, release_cnt_w} -
                            (reserve_i ? {3'b0, reserve_beats_i} : 8'b0);
            pending_r <= fetch_w;
            if (fetch_w) begin
                pending_queue_r <= fetch_queue_w;
                pending_addr_r <= fetch_addr_w;
                pending_error_r <= error_r[fetch_addr_w];
                pending_last_r <= last_r[fetch_addr_w];
                arrived_r[fetch_addr_w] <= 1'b0;
                id_turn_r[fetch_queue_w[3:1]] <= !fetch_queue_w[0];
                read_turn_r <= fetch_queue_w[3:1] == 3'd6 ?
                                3'b0 : fetch_queue_w[3:1] + 3'd1;
            end
            if (ddr_rvalid_i) begin
                arrived_r[return_head_r[ddr_rid_i]] <= 1'b1;
            end
            if (reserve_i) begin
                for (link_idx = 0; link_idx < 16; link_idx = link_idx + 1) begin
                    if (link_idx < {27'b0, reserve_beats_i}) begin
                        arrived_r[alloc_addr_w[link_idx]] <= reserve_error_i;
                        error_r[alloc_addr_w[link_idx]] <= reserve_error_i;
                        last_r[alloc_addr_w[link_idx]] <=
                            link_idx == {27'b0, reserve_beats_i} - 1;
                        if (link_idx < {27'b0, reserve_beats_i} - 1) begin
                            next_r[alloc_addr_w[link_idx]] <= alloc_addr_w[link_idx+1];
                            if (!reserve_error_i) begin
                                return_next_r[alloc_addr_w[link_idx]] <= alloc_addr_w[link_idx+1];
                            end
                        end
                    end
                end
                if (count_r[reserve_queue_w] != 0) begin
                    next_r[tail_r[reserve_queue_w]] <= alloc_addr_w[0];
                end
                if (!reserve_error_i && return_count_r[reserve_queue_w] != 0) begin
                    return_next_r[return_tail_r[reserve_queue_w]] <= alloc_addr_w[0];
                end
            end
            for (queue_idx = 0; queue_idx < 14; queue_idx = queue_idx + 1) begin
                count_r[queue_idx] <= count_r[queue_idx] +
                    ((reserve_i && {28'b0, reserve_queue_w} == queue_idx) ?
                        {3'b0, reserve_beats_i} : 8'b0) -
                    ((fetch_w && {28'b0, fetch_queue_w} == queue_idx) ? 8'd1 : 8'd0);
                if (fetch_w && {28'b0, fetch_queue_w} == queue_idx) begin
                    head_r[queue_idx] <= next_r[fetch_addr_w];
                end
                if (reserve_i && {28'b0, reserve_queue_w} == queue_idx) begin
                    tail_r[queue_idx] <= alloc_addr_w[reserve_beats_i-1];
                    if (count_r[queue_idx] == 0 ||
                        (count_r[queue_idx] == 1 && fetch_w &&
                            fetch_queue_w == reserve_queue_w)) begin
                        head_r[queue_idx] <= alloc_addr_w[0];
                    end
                end
                return_count_r[queue_idx] <= return_count_r[queue_idx] +
                    ((reserve_i && !reserve_error_i &&
                        {28'b0, reserve_queue_w} == queue_idx) ?
                        {3'b0, reserve_beats_i} : 8'b0) -
                    ((ddr_rvalid_i && {28'b0, ddr_rid_i} == queue_idx) ? 8'd1 : 8'd0);
                if (ddr_rvalid_i && {28'b0, ddr_rid_i} == queue_idx) begin
                    return_head_r[queue_idx] <= return_next_r[return_head_r[queue_idx]];
                end
                if (reserve_i && !reserve_error_i && {28'b0, reserve_queue_w} == queue_idx)
                begin
                    return_tail_r[queue_idx] <= alloc_addr_w[reserve_beats_i-1];
                    if (return_count_r[queue_idx] == 0 ||
                        (return_count_r[queue_idx] == 1 && ddr_rvalid_i &&
                            ddr_rid_i == reserve_queue_w)) begin
                        return_head_r[queue_idx] <= alloc_addr_w[0];
                    end
                end
            end
            for (port_idx = 0; port_idx < 7; port_idx = port_idx + 1) begin
                if (take_w[port_idx]) begin
                    skid_valid_r[port_idx] <= 1'b0;
                end
                if (pending_r && {29'b0, pending_queue_r[3:1]} == port_idx &&
                    !rready_i[port_idx]) begin
                    skid_valid_r[port_idx] <= 1'b1;
                end
            end
        end
    end

    // Payload registers have no reset; skid_valid_r owns their validity.
    always @(posedge clk_i) begin
        if (pending_r && !rready_i[pending_queue_r[3:1]]) begin
            skid_data_r[pending_queue_r[3:1]] <= pending_data_w;
            skid_addr_r[pending_queue_r[3:1]] <= pending_addr_r;
            skid_id_r[pending_queue_r[3:1]] <= pending_queue_r[0];
        end
    end
endmodule
