// File: edrv32_apb_observation_pkg.sv
// Spec: sys-subsys-testplan AB-02/03.
// Description: Passive SETUP counts shared by bound observers and the SB scoreboard.
// Clock domains: observed APB clocks; counters count simulation events atomically.
package edrv32_apb_observation_pkg;
    int setups = 0;
    int used_setups = 0;
    function automatic void setup_seen(
        input bit used_slot
    );
        /* verilator lint_off BLKSEQ */
        setups++;
        if (used_slot) used_setups++;
        /* verilator lint_on BLKSEQ */
    endfunction
endpackage
