// ============================================================================
// File        : edrv32_csr_file.v
// Description : Machine-mode CSR state for RV32IMC + Zicsr + Zicntr. Reads
//               are combinational at COMMIT; writes, trap entry and MRET are
//               precise single-cycle side-band operations.
// ============================================================================
`include "edrv32_csr.vh"
`include "edrv32_hpm.vh"

module edrv32_csr_file #(
    parameter integer DUAL_ISSUE = 0,
    parameter integer MULTI_EVENT_ENABLE = DUAL_ISSUE,
    parameter integer CPU_HPM_ENABLE = 1,
    parameter [31:0] MVENDORID = 32'd0,
    parameter [31:0] MARCHID   = 32'd0,
    parameter [31:0] MIMPID    = 32'd0,
    parameter [31:0] MHARTID   = 32'd0
)(
    input  wire        clk_i,
    input  wire        rst_n_i,

    // Combinational CSR read and access-permission check.
    input  wire [11:0] read_addr_i,
    input  wire        read_access_i,
    input  wire        write_intent_i,
    output reg  [31:0] read_data_o,
    output reg         access_illegal_o,

    // Precise architectural write and retirement events from COMMIT.
    input  wire        write_fire_i,
    input  wire [11:0] write_addr_i,
    input  wire [31:0] write_data_i,
    input  wire        retire_i,
    input  wire        retire_second_i,

    // Trap entry and return update the privileged state atomically.
    input  wire        trap_enter_i,
    input  wire [31:0] trap_epc_i,
    input  wire [31:0] trap_cause_i,
    input  wire [31:0] trap_tval_i,
    input  wire        mret_fire_i,

    // External interrupt/time values and optional HPM event pulses.
    input  wire        irq_soft_i,
    input  wire        irq_timer_i,
    input  wire        irq_ext_i,
    input  wire [63:0] time_value_i,
    input  wire [`EDRV32_HPM_EVENT_W-1:0] hpm_events_i,
    input  wire [`EDRV32_HPM_EVENT_W-1:0]   hpm_second_events_i,

    output wire [31:0] mtvec_o,
    output wire [31:0] mepc_o,
    output wire [31:0] mie_o,
    output wire [31:0] mip_o,
    output wire        mstatus_mie_o
);

    // ------------------------------------------------------------------------
    // Architectural constants and stored CSR state
    // ------------------------------------------------------------------------
    localparam [31:0] MISA_VALUE = (32'd1 << 30) |
                                    (32'd1 << 12) |
                                    (32'd1 << 8)  |
                                    (32'd1 << 2);
    localparam [31:0] MIE_MASK = 32'h0000_0888;

    reg mstatus_mie_r;
    reg mstatus_mpie_r;
    reg [31:0] mtvec_r;
    reg [31:0] mie_r;
    reg [31:0] mscratch_r;
    reg [31:0] mepc_r;
    reg [31:0] mcause_r;
    reg [31:0] mtval_r;
    reg [63:0] mcycle_r;
    reg [63:0] minstret_r;
    reg [31:0] mcountinhibit_r;
    reg [10:0] mhpmextrainhibit_r;

    // Read-only views assembled from stored state and external interrupt pins.
    wire [31:0] mstatus_value_w = {19'd0, 2'b11, 3'd0, mstatus_mpie_r,
                                    3'd0, mstatus_mie_r, 3'd0};
    wire [31:0] mip_value_w = {20'd0, irq_ext_i, 3'd0, irq_timer_i,
                                3'd0, irq_soft_i, 3'd0};
    wire read_only_w = (read_addr_i[11:10] == 2'b11) ||
                       (read_addr_i[11:8] == 4'hC);
    reg address_valid_w;

    // Optional HPM counters occupy two contiguous low/high address windows.
    wire read_hpm_low_w = (read_addr_i >= `EDRV32_CSR_MHPMCOUNTER_FIRST) &&
                          (read_addr_i <= `EDRV32_CSR_MHPMCOUNTER_LAST);
    wire read_hpm_high_w =
        (read_addr_i >= `EDRV32_CSR_MHPMCOUNTERH_FIRST) &&
        (read_addr_i <= `EDRV32_CSR_MHPMCOUNTERH_LAST);
    wire read_hpm_event_w = (read_addr_i >= `EDRV32_CSR_MHPMEVENT_FIRST) &&
                            (read_addr_i <= `EDRV32_CSR_MHPMEVENT_LAST);
    wire read_hpm_extra_low_w =
        (read_addr_i >= `EDRV32_CSR_MHPMEXTRA_FIRST) &&
        (read_addr_i <= `EDRV32_CSR_MHPMEXTRA_LAST);
    wire read_hpm_extra_high_w =
        (read_addr_i >= `EDRV32_CSR_MHPMEXTRAH_FIRST) &&
        (read_addr_i <= `EDRV32_CSR_MHPMEXTRAH_LAST);
    wire read_hpm_extra_event_w =
        (read_addr_i >= `EDRV32_CSR_MHPMEXTRAEVENT_FIRST) &&
        (read_addr_i <= `EDRV32_CSR_MHPMEXTRAEVENT_LAST);
    wire read_any_hpm_low_w = read_hpm_low_w || read_hpm_extra_low_w;
    wire read_any_hpm_high_w = read_hpm_high_w || read_hpm_extra_high_w;
    wire read_any_hpm_event_w = read_hpm_event_w || read_hpm_extra_event_w;
    wire [5:0] hpm_read_select_w = read_hpm_extra_low_w
        ? 6'd29 + (read_addr_i - `EDRV32_CSR_MHPMEXTRA_FIRST) :
          read_hpm_extra_high_w
        ? 6'd29 + (read_addr_i - `EDRV32_CSR_MHPMEXTRAH_FIRST) :
          read_hpm_extra_event_w
        ? 6'd29 + (read_addr_i - `EDRV32_CSR_MHPMEXTRAEVENT_FIRST) :
          read_hpm_high_w
        ? (read_addr_i - `EDRV32_CSR_MHPMCOUNTERH_FIRST) :
          read_hpm_event_w
        ? (read_addr_i - `EDRV32_CSR_MHPMEVENT_FIRST) :
          (read_addr_i - `EDRV32_CSR_MHPMCOUNTER_FIRST);
    wire [31:0] hpm_read_low_w;
    wire [31:0] hpm_read_high_w;
    wire [31:0] hpm_read_event_w;

    wire write_hpm_low_w =
                           (write_addr_i >= `EDRV32_CSR_MHPMCOUNTER_FIRST) &&
                           (write_addr_i <= `EDRV32_CSR_MHPMCOUNTER_LAST);
    wire write_hpm_high_w =
                            (write_addr_i >= `EDRV32_CSR_MHPMCOUNTERH_FIRST) &&
                            (write_addr_i <= `EDRV32_CSR_MHPMCOUNTERH_LAST);
    wire write_hpm_event_w =
                             (write_addr_i >= `EDRV32_CSR_MHPMEVENT_FIRST) &&
                             (write_addr_i <= `EDRV32_CSR_MHPMEVENT_LAST);
    wire write_hpm_extra_low_w =
        (write_addr_i >= `EDRV32_CSR_MHPMEXTRA_FIRST) &&
        (write_addr_i <= `EDRV32_CSR_MHPMEXTRA_LAST);
    wire write_hpm_extra_high_w =
        (write_addr_i >= `EDRV32_CSR_MHPMEXTRAH_FIRST) &&
        (write_addr_i <= `EDRV32_CSR_MHPMEXTRAH_LAST);
    wire write_hpm_extra_event_w =
        (write_addr_i >= `EDRV32_CSR_MHPMEXTRAEVENT_FIRST) &&
        (write_addr_i <= `EDRV32_CSR_MHPMEXTRAEVENT_LAST);
    wire [5:0] hpm_write_select_w = write_hpm_extra_low_w
        ? 6'd29 + (write_addr_i - `EDRV32_CSR_MHPMEXTRA_FIRST) :
          write_hpm_extra_high_w
        ? 6'd29 + (write_addr_i - `EDRV32_CSR_MHPMEXTRAH_FIRST) :
          write_hpm_extra_event_w
        ? 6'd29 + (write_addr_i - `EDRV32_CSR_MHPMEXTRAEVENT_FIRST) :
          write_hpm_high_w
        ? (write_addr_i - `EDRV32_CSR_MHPMCOUNTERH_FIRST) :
          write_hpm_event_w
        ? (write_addr_i - `EDRV32_CSR_MHPMEVENT_FIRST) :
          (write_addr_i - `EDRV32_CSR_MHPMCOUNTER_FIRST);

    edrv32_hpm_counters #(
        .MULTI_EVENT_ENABLE(MULTI_EVENT_ENABLE),
        .CPU_HPM_ENABLE(CPU_HPM_ENABLE)
    ) u_hpm_counters (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // Event sampling and selected counter readback.
        .event_i(hpm_events_i),
        .second_event_i(hpm_second_events_i),
        .inhibit_i({mhpmextrainhibit_r, mcountinhibit_r[31:3]}),
        .read_select_i(hpm_read_select_w),
        .read_low_o(hpm_read_low_w),
        .read_high_o(hpm_read_high_w),
        .read_event_o(hpm_read_event_w),

        // Qualified machine-mode counter write.
        .write_fire_i(write_fire_i),
        .write_counter_command_i(write_hpm_low_w || write_hpm_high_w ||
                                 write_hpm_extra_low_w ||
                                 write_hpm_extra_high_w),
        .write_event_command_i(write_hpm_event_w || write_hpm_extra_event_w),
        .write_select_i(hpm_write_select_w),
        .write_high_i(write_hpm_high_w || write_hpm_extra_high_w),
        .write_data_i(write_data_i)
    );

    // ------------------------------------------------------------------------
    // Combinational read decode and legality result
    // ------------------------------------------------------------------------
    always @* begin
        address_valid_w = 1'b1;
        if (read_any_hpm_low_w) begin
            read_data_o = hpm_read_low_w;
        end else if (read_any_hpm_high_w) begin
            read_data_o = hpm_read_high_w;
        end else if (read_any_hpm_event_w) begin
            read_data_o = hpm_read_event_w;
        end else case (read_addr_i)
            `EDRV32_CSR_MSTATUS:   read_data_o = mstatus_value_w;
            `EDRV32_CSR_MISA:      read_data_o = MISA_VALUE;
            `EDRV32_CSR_MIE:       read_data_o = mie_r;
            `EDRV32_CSR_MTVEC:     read_data_o = mtvec_r;
            `EDRV32_CSR_MCOUNTINHIBIT: read_data_o = mcountinhibit_r;
            `EDRV32_CSR_MHPMEXTRAINHIBIT:
                read_data_o = {21'd0, mhpmextrainhibit_r};
            `EDRV32_CSR_MSCRATCH:  read_data_o = mscratch_r;
            `EDRV32_CSR_MEPC:      read_data_o = mepc_r;
            `EDRV32_CSR_MCAUSE:    read_data_o = mcause_r;
            `EDRV32_CSR_MTVAL:     read_data_o = mtval_r;
            `EDRV32_CSR_MIP:       read_data_o = mip_value_w;
            `EDRV32_CSR_MCYCLE,
            `EDRV32_CSR_CYCLE:     read_data_o = mcycle_r[31:0];
            `EDRV32_CSR_MCYCLEH,
            `EDRV32_CSR_CYCLEH:    read_data_o = mcycle_r[63:32];
            `EDRV32_CSR_MINSTRET,
            `EDRV32_CSR_INSTRET:   read_data_o = minstret_r[31:0];
            `EDRV32_CSR_MINSTRETH,
            `EDRV32_CSR_INSTRETH:  read_data_o = minstret_r[63:32];
            `EDRV32_CSR_TIME:       read_data_o = time_value_i[31:0];
            `EDRV32_CSR_TIMEH:      read_data_o = time_value_i[63:32];
            `EDRV32_CSR_MVENDORID:  read_data_o = MVENDORID;
            `EDRV32_CSR_MARCHID:    read_data_o = MARCHID;
            `EDRV32_CSR_MIMPID:     read_data_o = MIMPID;
            `EDRV32_CSR_MHARTID:    read_data_o = MHARTID;
            default: begin
                address_valid_w = 1'b0;
                read_data_o = 32'd0;
            end
        endcase
        access_illegal_o = read_access_i &&
                           (!address_valid_w || (write_intent_i && read_only_w));
    end

    function [31:0] align_mepc;
        input [31:0] value_i;
        begin
            align_mepc = {value_i[31:1], 1'b0};
        end
    endfunction

    // ------------------------------------------------------------------------
    // Privileged state updates
    // ------------------------------------------------------------------------
    // mstatus interrupt-enable stack.  Trap entry has priority over MRET and
    // software writes because the corresponding events are architecturally
    // exclusive at COMMIT.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            mstatus_mie_r  <= 1'b0;
            mstatus_mpie_r <= 1'b0;
        end else if (trap_enter_i) begin
            mstatus_mpie_r <= mstatus_mie_r;
            mstatus_mie_r  <= 1'b0;
        end else if (mret_fire_i) begin
            mstatus_mie_r  <= mstatus_mpie_r;
            mstatus_mpie_r <= 1'b1;
        end else if (write_fire_i && (write_addr_i == `EDRV32_CSR_MSTATUS)) begin
            mstatus_mie_r  <= write_data_i[`EDRV32_MSTATUS_MIE_BIT];
            mstatus_mpie_r <= write_data_i[`EDRV32_MSTATUS_MPIE_BIT];
        end
    end

    // Trap context.  A trap captures all three values together; ordinary CSR
    // writes update only the addressed field.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            mepc_r   <= 32'd0;
            mcause_r <= 32'd0;
            mtval_r  <= 32'd0;
        end else if (trap_enter_i) begin
            mepc_r   <= align_mepc(trap_epc_i);
            mcause_r <= trap_cause_i;
            mtval_r  <= trap_tval_i;
        end else if (write_fire_i) begin
            case (write_addr_i)
                `EDRV32_CSR_MEPC:   mepc_r   <= align_mepc(write_data_i);
                `EDRV32_CSR_MCAUSE: mcause_r <= write_data_i;
                `EDRV32_CSR_MTVAL:  mtval_r  <= write_data_i;
                default: begin end
            endcase
        end
    end

    // Independently writable machine-vector, interrupt-enable and scratch CSRs.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            mtvec_r    <= 32'd0;
            mie_r      <= 32'd0;
            mscratch_r <= 32'd0;
        end else if (write_fire_i) begin
            case (write_addr_i)
                `EDRV32_CSR_MTVEC: mtvec_r <= {write_data_i[31:2],
                                                (write_data_i[1:0] == 2'b01)
                                                ? 2'b01 : 2'b00};
                `EDRV32_CSR_MIE: mie_r <= write_data_i & MIE_MASK;
                `EDRV32_CSR_MSCRATCH: mscratch_r <= write_data_i;
                default: begin end
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Architectural counters
    // ------------------------------------------------------------------------
    // All implemented counters can be frozen atomically. Bit one is reserved;
    // CY/IR and HPM3..31 are the complete writable mask for this core.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            mcountinhibit_r <= 32'd0;
            mhpmextrainhibit_r <= 11'd0;
        end else begin
            if (write_fire_i &&
                (write_addr_i == `EDRV32_CSR_MCOUNTINHIBIT))
                mcountinhibit_r <= write_data_i & 32'hffff_fffd;
            if (write_fire_i &&
                (write_addr_i == `EDRV32_CSR_MHPMEXTRAINHIBIT))
                mhpmextrainhibit_r <= write_data_i[10:0];
        end
    end

    // mcycle increments every cycle unless the corresponding half is written.
    wire write_mcycle_low_w = write_fire_i &&
                              (write_addr_i == `EDRV32_CSR_MCYCLE);
    wire write_mcycle_high_w = write_fire_i &&
                               (write_addr_i == `EDRV32_CSR_MCYCLEH);
    wire [32:0] mcycle_low_increment_w = {1'b0, mcycle_r[31:0]} + 33'd1;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            mcycle_r <= 64'd0;
        end else begin
            if (write_mcycle_low_w)
                mcycle_r[31:0] <= write_data_i;
            else if (!mcountinhibit_r[0])
                mcycle_r[31:0] <= mcycle_low_increment_w[31:0];

            if (write_mcycle_high_w)
                mcycle_r[63:32] <= write_data_i;
            else if (!write_mcycle_low_w && !mcountinhibit_r[0] &&
                     mcycle_low_increment_w[32])
                mcycle_r[63:32] <= mcycle_r[63:32] + 32'd1;
        end
    end

    // minstret increments only on a successful architectural retirement.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            minstret_r <= 64'd0;
        end else if (write_fire_i && (write_addr_i == `EDRV32_CSR_MINSTRET)) begin
            minstret_r[31:0] <= write_data_i;
        end else if (write_fire_i && (write_addr_i == `EDRV32_CSR_MINSTRETH)) begin
            minstret_r[63:32] <= write_data_i;
        end else if (retire_i && !mcountinhibit_r[2]) begin
            minstret_r <= minstret_r +
                (((DUAL_ISSUE != 0) && retire_second_i) ? 64'd2 : 64'd1);
        end
    end

    // Direct architectural-state observations consumed by COMMIT.
    assign mtvec_o       = mtvec_r;
    assign mepc_o        = mepc_r;
    assign mie_o         = mie_r;
    assign mip_o         = mip_value_w;
    assign mstatus_mie_o = mstatus_mie_r;

endmodule
