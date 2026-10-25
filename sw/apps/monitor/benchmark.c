/* File: benchmark.c
 * Spec: edrv32-soc-spec 7.5; cpu-spec 7.1.
 * Description: Initialize upstream CoreMark and report CRC, performance and HPM fields.
 *              Reuse the existing timing/seeds port and upstream iterate().
 * Clock domain: clk_sys.
 */
#include "monitor.h"

extern volatile ee_s32 seed1_volatile;
extern volatile ee_s32 seed2_volatile;
extern volatile ee_s32 seed3_volatile;
static ee_u8 work_memory[TOTAL_DATA_SIZE] __attribute__((aligned(4)));

void monitor_core_init(core_results *result, uint32_t iterations)
{
    result->seed1 = (ee_s16)seed1_volatile;
    result->seed2 = (ee_s16)seed2_volatile;
    result->seed3 = (ee_s16)seed3_volatile;
    result->iterations = iterations;
    result->execs = ALL_ALGORITHMS_MASK;
    result->size = TOTAL_DATA_SIZE / NUM_ALGORITHMS;
    result->memblock[0] = work_memory;
    for (unsigned int algorithm = 0u; algorithm < NUM_ALGORITHMS; ++algorithm) {
        result->memblock[algorithm + 1u] = work_memory + result->size * algorithm;
    }
    result->list = core_list_init(result->size, result->memblock[1], result->seed1);
    core_init_matrix(result->size, result->memblock[2],
                     (ee_s32)result->seed1 | ((ee_s32)result->seed2 << 16), &result->mat);
    core_init_state(result->size, result->seed1, result->memblock[3]);
}

static int crc_field(const char *key, uint16_t actual, uint16_t expected)
{
    info_hex(key, actual);
    return actual == expected;
}

int monitor_core_crc(const core_results *result)
{
    uint16_t seed_crc = crc16(result->seed1, 0u);
    seed_crc = crc16(result->seed2, seed_crc);
    seed_crc = crc16(result->seed3, seed_crc);
    seed_crc = crc16((ee_s16)result->size, seed_crc);
    /* Upstream core_main.c known_id=3: 2K performance seeds (0,0,0x66). */
    int seed_ok = crc_field("CRC seed", seed_crc, 0xe9f5u);
    int list_ok = crc_field("CRC list", result->crclist, 0xe714u);
    int matrix_ok = crc_field("CRC matrix", result->crcmatrix, 0x1fd7u);
    int state_ok = crc_field("CRC state", result->crcstate, 0x8e3au);
    info_hex("CRC final", result->crc);
    info_text("CRC seed result", seed_ok ? "PASS" : "FAIL");
    info_text("CRC list result", list_ok ? "PASS" : "FAIL");
    info_text("CRC matrix result", matrix_ok ? "PASS" : "FAIL");
    info_text("CRC state result", state_ok ? "PASS" : "FAIL");
    int valid = seed_ok && list_ok && matrix_ok && state_ok;
    info_text("CRC result", valid ? "PASS" : "FAIL");
    return valid;
}

void monitor_metrics(const uint64_t cycles[2], uint64_t instructions, const uint64_t events[16])
{
    /* Rates are fractions, not percentages. Event indexes below are code-1.
     * IPC = retired instructions / round-1 cycles.
     * Dual retire ratio = dual-retirement cycles / round-1 cycles.
     * Load-use/divide/device/frontend ratios = stall cycles / round-2 cycles.
     * Mispredict rate = event16 (round 2) / event4 (round 1).
     * MPKI = 1000 * cache misses / round-1 retired instructions.
     * The cross-round metrics use two freshly initialized equivalent workloads;
     * cache warmness and the event window overhead can differ between rounds.
     */
    info_ratio("IPC", instructions, cycles[0]);
    info_ratio("Dual retire ratio", events[0], cycles[0]);
    info_ratio("Load-use stall ratio", events[8], cycles[1]);
    info_ratio("Divide stall ratio", events[9], cycles[1]);
    info_ratio("Device wait ratio", events[10], cycles[1]);
    info_ratio("Frontend empty ratio", events[11], cycles[1]);
    info_ratio("Branch mispredict rate", events[15], events[3]);
    info_ratio("I-cache MPKI", events[12] * 1000u, instructions);
    info_ratio("D-cache MPKI", events[13] * 1000u, instructions);
}

void monitor_coremark(uint32_t iterations, uint32_t clock_hz)
{
    uint64_t events[16];
    uint64_t cycles[2];
    uint64_t instructions[2];
    int valid = 1;
    coremark_set_clock(clock_hz);
    info_number("Iterations", iterations);
    info_number("HPM rounds", MONITOR_HPM_ROUNDS);
    for (unsigned int round = 0u; round < MONITOR_HPM_ROUNDS; ++round) {
        core_results result;
        monitor_core_init(&result, iterations);
        monitor_hpm_prepare(round);
        start_time();
        monitor_hpm_start();
        iterate(&result);
        monitor_hpm_stop();
        stop_time();
        cycles[round] = get_time();
        monitor_hpm_read(&events[round * 8u], &instructions[round]);
        monitor_hpm_release();
        info_number("HPM round", round + 1u);
        info_number("HPM first event", round * 8u + 1u);
        info_number("HPM last event", round * 8u + 8u);
        info_number("HPM round cycles", cycles[round]);
        info_number("HPM round instructions", instructions[round]);
        /* Report each run independently, so a failing second run stays visible. */
        if (!monitor_core_crc(&result)) {
            valid = 0;
        }
    }
    info_number("Cycles", cycles[0]);
    info_number("Instructions", instructions[0]);
    info_ratio("Iterations/Sec", (uint64_t)iterations * clock_hz, cycles[0]);
    info_ratio("CoreMark/MHz", (uint64_t)iterations * 1000000u, cycles[0]);
    info_text("Score status", cycles[0] >= (uint64_t)clock_hz * 10u
              ? "duration >= 10 s; see CoreMark reporting rules"
              : "short diagnostic run (<10 s); not a publishable CoreMark score");
    for (unsigned int event = 0u; event < 16u; ++event) {
        info_number(monitor_hpm_names[event], events[event]);
    }
    monitor_metrics(cycles, instructions[0], events);
    info_text("Compiler version", BUILD_COMPILER);
    info_text("Compiler flags", BUILD_CFLAGS);
    info_text("ISA", BUILD_ISA);
    info_text("CoreMark result", valid ? "PASS" : "FAIL");
}
