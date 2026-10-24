// ============================================================================
// File        : edrv32_hpm_counters.v
// Description : Forty programmable 64-bit HPM counters. The first twenty-nine
//               use standard mhpmcounter3..31; eleven use EdRV32 custom CSRs.
// Notes       : Event zero disables a counter. Unsupported selector values are
//               coerced to zero (WARL). Disable removes all counter/selector
//               registers and preserves a read-zero/write-ignore CSR ABI.
// ============================================================================
`include "edrv32_hpm.vh"

module edrv32_hpm_counters #(
    parameter integer MULTI_EVENT_ENABLE = 0,
    parameter integer CPU_HPM_ENABLE = 1,
    parameter integer COUNTER_COUNT = 40,
    parameter integer EVENT_COUNT = `EDRV32_HPM_EVENT_W,
    parameter integer SELECT_W = 7
) (
    input  wire                       clk_i,
    input  wire                       rst_n_i,
    input  wire [EVENT_COUNT-1:0]     event_i,
    input  wire [EVENT_COUNT-1:0]           second_event_i,
    input  wire [COUNTER_COUNT-1:0]   inhibit_i,
    input  wire [5:0]                 read_select_i,
    output wire [31:0]                read_low_o,
    output wire [31:0]                read_high_o,
    output wire [31:0]                read_event_o,
    input  wire                       write_fire_i,
    input  wire                       write_counter_command_i,
    input  wire                       write_event_command_i,
    input  wire [5:0]                 write_select_i,
    input  wire                       write_high_i,
    input  wire [31:0]                write_data_i
);

    generate
        if (CPU_HPM_ENABLE != 0) begin : gen_hpm_enabled
            reg [31:0] counter_low_r [0:COUNTER_COUNT-1];
            reg [31:0] counter_high_r [0:COUNTER_COUNT-1];
            reg [SELECT_W-1:0] event_select_r [0:COUNTER_COUNT-1];
            // HPM is a timing boundary: capture every platform event once,
            // then perform the programmable selection locally.  Forty
            // counters made a single captured event bit a cross-region
            // fanout-40 net, so keep four functionally identical physical
            // samples and let each one serve only a quarter of the counters.
            // The preserve attributes are intentionally limited to these
            // four timing-boundary registers; without them synthesis can
            // merge the equivalent samples back into the original long net.
            localparam integer EVENT_BANK_COUNT = 4;
            localparam integer COUNTERS_PER_EVENT_BANK =
                (COUNTER_COUNT + EVENT_BANK_COUNT - 1) / EVENT_BANK_COUNT;
            (* syn_preserve = 1 *) reg [EVENT_COUNT-1:0] event_sample_bank0_r;
            (* syn_preserve = 1 *) reg [EVENT_COUNT-1:0] second_sample_bank0_r;
            (* syn_preserve = 1 *) reg [EVENT_COUNT-1:0] event_sample_bank1_r;
            (* syn_preserve = 1 *) reg [EVENT_COUNT-1:0] second_sample_bank1_r;
            (* syn_preserve = 1 *) reg [EVENT_COUNT-1:0] event_sample_bank2_r;
            (* syn_preserve = 1 *) reg [EVENT_COUNT-1:0] second_sample_bank2_r;
            (* syn_preserve = 1 *) reg [EVENT_COUNT-1:0] event_sample_bank3_r;
            (* syn_preserve = 1 *) reg [EVENT_COUNT-1:0] second_sample_bank3_r;
            reg [COUNTER_COUNT-1:0] inhibit_sample_r;
            reg [SELECT_W-1:0] event_select_sample_r [0:COUNTER_COUNT-1];
            // CSR validation presents a stable command one cycle before its
            // architectural write fires.  Register the decode here so the
            // retirement decision does not traverse address-range and target
            // decode before reaching every counter.
            reg [COUNTER_COUNT-1:0] write_counter_target_r;
            reg [COUNTER_COUNT-1:0] write_event_target_r;
            reg write_high_r;
            integer counter_index;

            wire [COUNTER_COUNT-1:0] selected_event_w;
            wire [COUNTER_COUNT-1:0] selected_second_w;
            wire [1:0] increment_w [0:COUNTER_COUNT-1];
            wire [COUNTER_COUNT-1:0] write_select_oh_w;
            genvar event_counter;
            for (event_counter = 0; event_counter < COUNTER_COUNT;
                 event_counter = event_counter + 1) begin : gen_event_select
                wire [EVENT_COUNT-1:0] local_event_sample_w;
                wire [EVENT_COUNT-1:0] local_second_sample_w;
                if (event_counter < COUNTERS_PER_EVENT_BANK) begin : gen_bank0
                    assign local_event_sample_w = event_sample_bank0_r;
                    assign local_second_sample_w = second_sample_bank0_r;
                end else if (event_counter < (2 * COUNTERS_PER_EVENT_BANK))
                        begin : gen_bank1
                    assign local_event_sample_w = event_sample_bank1_r;
                    assign local_second_sample_w = second_sample_bank1_r;
                end else if (event_counter < (3 * COUNTERS_PER_EVENT_BANK))
                        begin : gen_bank2
                    assign local_event_sample_w = event_sample_bank2_r;
                    assign local_second_sample_w = second_sample_bank2_r;
                end else begin : gen_bank3
                    assign local_event_sample_w = event_sample_bank3_r;
                    assign local_second_sample_w = second_sample_bank3_r;
                end
                assign selected_event_w[event_counter] =
                    (event_select_sample_r[event_counter] != {SELECT_W{1'b0}}) &&
                    (event_select_sample_r[event_counter] <= EVENT_COUNT) &&
                    local_event_sample_w[
                        event_select_sample_r[event_counter] - 1'b1];
                assign selected_second_w[event_counter] = (MULTI_EVENT_ENABLE != 0) &&
                    (event_select_sample_r[event_counter] != {SELECT_W{1'b0}}) &&
                    (event_select_sample_r[event_counter] <= EVENT_COUNT) &&
                    local_second_sample_w[event_select_sample_r[event_counter] - 1'b1];
                assign increment_w[event_counter] =
                    {1'b0, selected_event_w[event_counter]} +
                    {1'b0, selected_second_w[event_counter]};
                assign write_select_oh_w[event_counter] =
                    (write_select_i == event_counter);
            end

            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    event_sample_bank0_r <= {EVENT_COUNT{1'b0}};
                    second_sample_bank0_r <= {EVENT_COUNT{1'b0}};
                    event_sample_bank1_r <= {EVENT_COUNT{1'b0}};
                    second_sample_bank1_r <= {EVENT_COUNT{1'b0}};
                    event_sample_bank2_r <= {EVENT_COUNT{1'b0}};
                    second_sample_bank2_r <= {EVENT_COUNT{1'b0}};
                    event_sample_bank3_r <= {EVENT_COUNT{1'b0}};
                    second_sample_bank3_r <= {EVENT_COUNT{1'b0}};
                    inhibit_sample_r <= {COUNTER_COUNT{1'b1}};
                    write_counter_target_r <= {COUNTER_COUNT{1'b0}};
                    write_event_target_r <= {COUNTER_COUNT{1'b0}};
                    write_high_r <= 1'b0;
                    // Constant-value bulk reset; blocking assignment keeps the
                    // loop verilator-compatible (reset and normal branches are
                    // mutually exclusive).
                    for (counter_index = 0; counter_index < COUNTER_COUNT;
                         counter_index = counter_index + 1) begin
                        counter_low_r[counter_index] = 32'd0;
                        counter_high_r[counter_index] = 32'd0;
                        event_select_r[counter_index] = counter_index + 1;
                        event_select_sample_r[counter_index] =
                            counter_index + 1;
                    end
                end else begin
                    event_sample_bank0_r <= event_i;
                    second_sample_bank0_r <= (MULTI_EVENT_ENABLE != 0)
                        ? second_event_i : {EVENT_COUNT{1'b0}};
                    event_sample_bank1_r <= event_i;
                    second_sample_bank1_r <= (MULTI_EVENT_ENABLE != 0)
                        ? second_event_i : {EVENT_COUNT{1'b0}};
                    event_sample_bank2_r <= event_i;
                    second_sample_bank2_r <= (MULTI_EVENT_ENABLE != 0)
                        ? second_event_i : {EVENT_COUNT{1'b0}};
                    event_sample_bank3_r <= event_i;
                    second_sample_bank3_r <= (MULTI_EVENT_ENABLE != 0)
                        ? second_event_i : {EVENT_COUNT{1'b0}};
                    inhibit_sample_r <= inhibit_i;
                    // Predecode the validated CSR command into per-counter
                    // registered write enables.  The architectural write-fire
                    // cycle then contains only a local two-input qualification,
                    // not forty replicated six-bit selector comparisons.
                    write_counter_target_r <= write_select_oh_w &
                        {COUNTER_COUNT{write_counter_command_i}};
                    write_event_target_r <= write_select_oh_w &
                        {COUNTER_COUNT{write_event_command_i}};
                    write_high_r <= write_high_i;
                    // The per-counter loop body uses blocking assignment so
                    // the delayed array writes stay verilator-compatible.
                    // The carry test reads the pre-increment low word and is
                    // therefore evaluated before the low word advances.
                    for (counter_index = 0; counter_index < COUNTER_COUNT;
                         counter_index = counter_index + 1) begin
                        event_select_sample_r[counter_index] =
                            event_select_r[counter_index];
                        if (write_fire_i &&
                            write_event_target_r[counter_index]) begin
                            event_select_r[counter_index] =
                                (write_data_i[31:SELECT_W] == 0) &&
                                (write_data_i[SELECT_W-1:0] <= EVENT_COUNT)
                                    ? write_data_i[SELECT_W-1:0]
                                    : {SELECT_W{1'b0}};
                        end

                        if (write_fire_i &&
                            write_counter_target_r[counter_index]) begin
                            if (write_high_r)
                                counter_high_r[counter_index] = write_data_i;
                            else
                                counter_low_r[counter_index] = write_data_i;
                        end else if (!inhibit_sample_r[counter_index] &&
                                     (increment_w[counter_index] != 2'd0)) begin
                            // +2 also carries from fffffffe. Read before increment.
                            if ((counter_low_r[counter_index] == 32'hffff_ffff) ||
                                ((increment_w[counter_index] == 2'd2) &&
                                 (counter_low_r[counter_index] == 32'hffff_fffe)))
                                counter_high_r[counter_index] =
                                    counter_high_r[counter_index] + 32'd1;
                            counter_low_r[counter_index] =
                                counter_low_r[counter_index] +
                                {30'd0, increment_w[counter_index]};
                        end
                    end
                end
            end

            reg [31:0] read_low_r;
            reg [31:0] read_high_r;
            reg [31:0] read_event_r;
            always @* begin
                read_low_r = 32'd0;
                read_high_r = 32'd0;
                read_event_r = 32'd0;
                if (read_select_i < COUNTER_COUNT) begin
                    read_low_r = counter_low_r[read_select_i];
                    read_high_r = counter_high_r[read_select_i];
                    read_event_r = {32-SELECT_W{1'b0}} |
                                   event_select_r[read_select_i];
                end
            end
            assign read_low_o = read_low_r;
            assign read_high_o = read_high_r;
            assign read_event_o = read_event_r;
        end else begin : gen_hpm_disabled
            assign read_low_o = 32'd0;
            assign read_high_o = 32'd0;
            assign read_event_o = 32'd0;
            wire unused_hpm_inputs_w = ^{clk_i, rst_n_i, event_i, inhibit_i,
                read_select_i, write_fire_i, write_counter_command_i,
                write_event_command_i, write_select_i, write_high_i,
                write_data_i};
        end
    endgenerate

endmodule
