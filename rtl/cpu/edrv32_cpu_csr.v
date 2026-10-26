// File: edrv32_cpu_csr.v
// Spec: cpu-spec 5, 7.1
// Description: Maintain machine CSRs, interrupt state and architectural counters.
// Apply CSR access permissions, WARL masks and precise trap/MRET updates.
// Clock domain: clk_sys.
module edrv32_cpu_csr #(
    parameter RVC_EN = 1
) (
    // Clock and architectural reset.
    input wire clk_i,
    input wire rst_n_i,
    // M-stage access: write_i denotes an actual, committed CSR write.
    // command: 1=write, 2=set, 3=clear; zero=read only.
    input wire access_valid_i,
    input wire [11:0] addr_i,
    input wire write_i,
    input wire commit_i,
    input wire [1:0] command_i,
    input wire [31:0] write_data_i,
    output reg [31:0] read_data_o,
    output wire illegal_o,
    // Retirement and HPM counts: two bits per event, code 1 in [1:0].
    input wire [1:0] retire_count_i,
    input wire [31:0] event_count_i,
    // Precise trap and MRET updates. Trap has priority over CSR and MRET.
    input wire trap_i,
    input wire [31:0] trap_pc_i,
    input wire [31:0] trap_cause_i,
    input wire [31:0] trap_value_i,
    input wire mret_i,
    output wire [31:0] mstatus_o,
    output wire [31:0] mie_o,
    output wire [31:0] mtvec_o,
    output wire [31:0] mepc_o,
    // Synchronized interrupt levels and CLINT time.
    input wire irq_meip_i,
    input wire irq_msip_i,
    input wire irq_mtip_i,
    input wire [63:0] mtime_i
);
    localparam [31:0] MISA = RVC_EN ? 32'h40001104 : 32'h40001100;
    localparam [31:0] EPC_MASK = RVC_EN ? 32'hfffffffe : 32'hfffffffc;
    reg [31:0] mstatus_r;
    reg [31:0] mie_r;
    reg [31:0] mtvec_r;
    reg [31:0] mscratch_r;
    reg [31:0] mepc_r;
    reg [31:0] mcause_r;
    reg [31:0] mtval_r;
    reg [31:0] inhibit_r;
    reg [4:0] event_r [0:7];
    reg [63:0] cycle_r;
    reg [63:0] instret_r;
    reg [63:0] counter_r [0:7];
    reg [31:0] event_count_r;
    reg implemented_w;
    reg readonly_w;
    reg [31:0] write_data_w;
    wire write_enable_w;
    integer read_idx;
    integer update_idx;
    assign mstatus_o = mstatus_r;
    assign mie_o = mie_r;
    assign mtvec_o = mtvec_r;
    assign mepc_o = mepc_r;
    assign illegal_o = access_valid_i && (!implemented_w || (write_i && readonly_w));
    assign write_enable_w = access_valid_i && write_i && commit_i && !illegal_o;
    always @(*) begin
        read_data_o = 0;
        implemented_w = 1'b1;
        readonly_w = 1'b0;
        case (addr_i)
            12'h300: read_data_o = mstatus_r;
            12'h301: read_data_o = MISA; // WARL: writes ignored, coordinator clarification.
            12'h304: read_data_o = mie_r;
            12'h305: read_data_o = mtvec_r;
            12'h320: read_data_o = inhibit_r;
            12'h340: read_data_o = mscratch_r;
            12'h341: read_data_o = mepc_r;
            12'h342: read_data_o = mcause_r;
            12'h343: read_data_o = mtval_r;
            12'h344: begin
                read_data_o = {20'b0, irq_meip_i, 3'b0, irq_mtip_i, 3'b0, irq_msip_i, 3'b0};
                readonly_w = 1'b1;
            end
            12'hb00: read_data_o = cycle_r[31:0];
            12'hb80: read_data_o = cycle_r[63:32];
            12'hb02: read_data_o = instret_r[31:0];
            12'hb82: read_data_o = instret_r[63:32];
            12'hc00: begin read_data_o = cycle_r[31:0]; readonly_w = 1'b1; end
            12'hc80: begin read_data_o = cycle_r[63:32]; readonly_w = 1'b1; end
            12'hc02: begin read_data_o = instret_r[31:0]; readonly_w = 1'b1; end
            12'hc82: begin read_data_o = instret_r[63:32]; readonly_w = 1'b1; end
            12'hc01: begin read_data_o = mtime_i[31:0]; readonly_w = 1'b1; end
            12'hc81: begin read_data_o = mtime_i[63:32]; readonly_w = 1'b1; end
            12'hf11, 12'hf12, 12'hf13, 12'hf14: begin
                read_data_o = 0;
                readonly_w = 1'b1;
            end
            default: implemented_w = 1'b0;
        endcase
        begin
            for (read_idx = 0; read_idx < 8; read_idx = read_idx + 1) begin
                if (addr_i == 12'h323 + read_idx[11:0]) begin
                    read_data_o = {27'b0, event_r[read_idx]};
                    implemented_w = 1'b1;
                end
                if (addr_i == 12'hb03 + read_idx[11:0] ||
                    addr_i == 12'hc03 + read_idx[11:0]) begin
                    read_data_o = counter_r[read_idx][31:0];
                    implemented_w = 1'b1;
                    readonly_w = addr_i[10];
                end
                if (addr_i == 12'hb83 + read_idx[11:0] ||
                    addr_i == 12'hc83 + read_idx[11:0]) begin
                    read_data_o = counter_r[read_idx][63:32];
                    implemented_w = 1'b1;
                    readonly_w = addr_i[10];
                end
            end
        end
    end
    always @(*) begin
        write_data_w = write_data_i;
        case (command_i)
            2'd2: write_data_w = read_data_o | write_data_i;
            2'd3: write_data_w = read_data_o & ~write_data_i;
            default: write_data_w = write_data_i;
        endcase
    end
    // cpu-spec 7.1: event generation ends here, before selection and the 64-bit increment.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            event_count_r <= 0;
        else
            event_count_r <= event_count_i;
    end
    // Architectural state has specified reset values, unlike execution data registers.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            mstatus_r <= 32'h1800;
            mie_r <= 0;
            mtvec_r <= 0;
            mscratch_r <= 0;
            mepc_r <= 0;
            mcause_r <= 0;
            mtval_r <= 0;
            inhibit_r <= 0;
            cycle_r <= 0;
            instret_r <= 0;
            for (update_idx = 0; update_idx < 8; update_idx = update_idx + 1) begin
                event_r[update_idx] <= 0;
                counter_r[update_idx] <= 0;
            end
        end else begin
            if (!inhibit_r[0])
                cycle_r <= cycle_r + 1'b1;
            if (!inhibit_r[2])
                instret_r <= instret_r + {62'b0, retire_count_i};
            for (update_idx = 0; update_idx < 8; update_idx = update_idx + 1) begin
                if (!inhibit_r[update_idx + 3] && event_r[update_idx] >= 1 &&
                    event_r[update_idx] <= 16)
                    counter_r[update_idx] <= counter_r[update_idx] +
                        {62'b0, event_count_r[(event_r[update_idx] - 1'b1) * 2 +: 2]};
            end
            if (write_enable_w && !trap_i) begin
                case (addr_i)
                    12'h300: mstatus_r <= (write_data_w & 32'h88) | 32'h1800;
                    12'h304: mie_r <= write_data_w & 32'h888;
                    12'h305: mtvec_r <= {write_data_w[31:2], 1'b0,
                        write_data_w[1:0] == 1};
                    12'h320: inhibit_r <= write_data_w & 32'h7fd;
                    12'h340: mscratch_r <= write_data_w;
                    12'h341: mepc_r <= write_data_w & EPC_MASK;
                    12'h342: mcause_r <= write_data_w;
                    12'h343: mtval_r <= write_data_w;
                    12'hb00: cycle_r <= {cycle_r[63:32], write_data_w};
                    12'hb80: cycle_r <= {write_data_w, cycle_r[31:0]};
                    12'hb02: instret_r <= {instret_r[63:32], write_data_w};
                    12'hb82: instret_r <= {write_data_w, instret_r[31:0]};
                    default: begin end
                endcase
                begin
                    for (update_idx = 0; update_idx < 8; update_idx = update_idx + 1) begin
                        if (addr_i == 12'h323 + update_idx[11:0])
                            event_r[update_idx] <= write_data_w[4:0];
                        if (addr_i == 12'hb03 + update_idx[11:0])
                            counter_r[update_idx] <= {counter_r[update_idx][63:32], write_data_w};
                        if (addr_i == 12'hb83 + update_idx[11:0])
                            counter_r[update_idx] <= {write_data_w, counter_r[update_idx][31:0]};
                    end
                end
            end
            if (trap_i) begin
                mepc_r <= trap_pc_i & EPC_MASK;
                mcause_r <= trap_cause_i;
                mtval_r <= trap_value_i;
                mstatus_r <= 32'h1800 | {24'b0, mstatus_r[3], 7'b0};
            end else if (mret_i) begin
                mstatus_r <= 32'h1880 | {28'b0, mstatus_r[7], 3'b0};
            end
        end
    end
endmodule
