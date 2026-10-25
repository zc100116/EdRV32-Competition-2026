#include "Vtb_soc.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <chrono>

static vluint64_t sim_time = 0;
double sc_time_stamp() { return sim_time; }
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    auto *top = new Vtb_soc;
    vluint64_t limit = 600000000;
    for (int i=1; i<argc; ++i)
        if (!std::strncmp(argv[i], "+CYCLE_LIMIT=", 13))
            limit = std::strtoull(argv[i]+13, nullptr, 10);
    auto start = std::chrono::steady_clock::now();
    for (vluint64_t cycle=0; cycle<limit && !Verilated::gotFinish(); ++cycle) {
        top->rst_n = cycle >= 8;
        top->clk = 0; top->eval(); sim_time += 5;
        top->clk = 1; top->eval(); sim_time += 5;
    }
    bool finished = Verilated::gotFinish();
    top->final(); delete top;
    double sec = std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
    std::printf("SIM_DRIVER finished=%d clocks=%llu wall_seconds=%.3f\n",
                finished, static_cast<unsigned long long>(sim_time/10), sec);
    return finished ? 0 : 2;
}
