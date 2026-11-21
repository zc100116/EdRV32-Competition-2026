// axi256_eval.cpp: timed AXI256 storage for legacy performance evaluation.
// SoC spec 8.9; all times are source-clock cycles, no FPGA IP or RTL edits.
#include "Vlegacy_eval_top.h"
#include "verilated.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

struct Burst {
    uint32_t address;
    unsigned left;
    unsigned id;
    uint64_t due;
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    const unsigned latency = std::stoul(argv[1]);
    const double bandwidth = std::stod(argv[2]);
    const unsigned stop_step = std::stoul(argv[3]);
    const std::string prefix = argv[4];
    Vlegacy_eval_top dut;
    // Address-preserving, zero-initialized 64 MiB storage. Zero weights and
    // quantization records are legal: this experiment measures control timing.
    std::vector<std::array<uint32_t, 8>> memory(64 * 1024 * 1024 / 32);
    std::deque<Burst> reads, writes, responses;
    std::array<std::array<uint64_t, 10>, 74> stages{};
    std::array<uint64_t, 74> cycles{};
    double credit = 0;
    bool prefer_read = true;
    uint64_t cycle = 0;
    uint64_t window_r = 0, window_w = 0, peak_window = 0;
    uint64_t pending_r = 0, pending_w = 0, pending_b = 0;
    std::array<uint64_t, 9> counters{};
    std::ofstream live(prefix + "_live.csv");
    live << "index,CY,MC,RB,WB,AR,RW,AW,WW,BW\n";
    dut.clk_i = 0;
    dut.rst_n_i = 0;
    dut.start_i = 0;
    dut.profile_step_i = 0;
    dut.m_rresp_i = 0;
    dut.m_bresp_i = 0;
    for (unsigned i = 0; i < 5; ++i) {
        dut.clk_i = 0; dut.eval();
        dut.clk_i = 1; dut.eval();
    }
    dut.rst_n_i = 1;
    dut.start_i = 1;
    unsigned previous_step = 0;
    bool finished = false;
    while (!finished) {
        dut.clk_i = 0;
        dut.eval();
        const bool active = cycle > 0;
        credit = std::min(64.0, credit + bandwidth * 1e9 / 150e6);
        bool read_available = !reads.empty() && reads.front().due <= cycle;
        bool write_available = !writes.empty() && dut.m_wvalid_o;
        bool serve_read = read_available &&
            (!write_available || prefer_read);
        bool serve_write = write_available && !serve_read;
        dut.m_arready_i = reads.size() < 4;
        dut.m_awready_i = writes.size() + responses.size() < 4;
        dut.m_rvalid_i = serve_read && credit >= 32;
        dut.m_wready_i = serve_write && credit >= 32;
        dut.m_bvalid_i = !responses.empty() && responses.front().due <= cycle;
        dut.m_bid_i = responses.empty() ? 0 : responses.front().id;
        dut.m_rid_i = reads.empty() ? 0 : reads.front().id;
        dut.m_rlast_i = !reads.empty() && reads.front().left == 1;
        if (!reads.empty()) {
            const auto& word = memory.at(reads.front().address / 32);
            for (unsigned i = 0; i < 8; ++i) dut.m_rdata_i[i] = word[i];
        }
        dut.eval();
        const unsigned step = dut.step_o;
        const bool ar = dut.m_arvalid_o && dut.m_arready_i;
        const bool r = dut.m_rvalid_i && dut.m_rready_o;
        const bool aw = dut.m_awvalid_o && dut.m_awready_i;
        const bool w = dut.m_wvalid_o && dut.m_wready_i;
        const bool b = dut.m_bvalid_i && dut.m_bready_o;
        if (active) {
            ++cycles[step];
            ++stages[step][dut.stage_o];
            ++counters[0];
            counters[1] += dut.mac_beat_o;
            counters[2] += r;
            counters[3] += w;
            counters[4] += dut.m_arvalid_o && !dut.m_arready_i;
            counters[5] += pending_r && !r;
            counters[6] += dut.m_awvalid_o && !dut.m_awready_i;
            counters[7] += dut.m_wvalid_o && !dut.m_wready_i;
            counters[8] += pending_b && !pending_w && !b;
        }
        if (ar) pending_r += dut.m_arlen_o + 1;
        if (r) --pending_r;
        if (aw) { pending_w += dut.m_awlen_o + 1; ++pending_b; }
        if (w) --pending_w;
        if (b) --pending_b;
        if (b) responses.pop_front();
        if (r) {
            reads.front().address += 32;
            if (--reads.front().left == 0) reads.pop_front();
            credit -= 32;
            prefer_read = false;
            ++window_r;
        }
        if (w) {
            auto& word = memory.at(writes.front().address / 32);
            for (unsigned byte = 0; byte < 32; ++byte) {
                if ((dut.m_wstrb_o >> byte) & 1) {
                    unsigned lane = byte / 4;
                    unsigned shift = (byte % 4) * 8;
                    uint32_t mask = 255u << shift;
                    word[lane] = (word[lane] & ~mask) | (dut.m_wdata_o[lane] & mask);
                }
            }
            writes.front().address += 32;
            if (--writes.front().left == 0) {
                responses.push_back({0, 0, writes.front().id, cycle + latency + 1});
                writes.pop_front();
            }
            credit -= 32;
            prefer_read = true;
            ++window_w;
        }
        if (ar) reads.push_back({dut.m_araddr_o, unsigned(dut.m_arlen_o) + 1,
                                dut.m_arid_o, cycle + latency + 1});
        if (aw) writes.push_back({dut.m_awaddr_o, unsigned(dut.m_awlen_o) + 1,
                                  dut.m_awid_o, cycle + 1});
        const bool done = dut.done_o;
        if (dut.error_o) { std::cerr << "RTL error step " << step << '\n'; return 1; }
        dut.clk_i = 1;
        dut.eval();
        dut.start_i = 0;
        ++cycle;
        if (cycle % 1024 == 0) {
            peak_window = std::max(peak_window, window_r + window_w);
            window_r = window_w = 0;
        }
        if (active && (dut.step_o != previous_step || done)) {
            live << previous_step;
            for (auto v : counters) live << ',' << v;
            live << std::endl;
            std::cout << "STEP " << previous_step << " CY " << counters[0]
                      << " elapsed cycles " << cycle << std::endl;
            counters.fill(0);
            if (previous_step == stop_step) finished = true;
            previous_step = dut.step_o;
        }
        if (done) finished = true;
    }
    // Read the actual legacy profiler's synchronous RAM after it settles.
    std::ofstream csv(prefix + ".csv");
    csv << "index,CY,MC,RB,WB,AR,RW,AW,WW,BW";
    const char* stage_names[] = {"control", "quant", "weight", "feature", "mac",
        "write_drain", "write_response", "patch_pipeline", "row_prepare", "nonconv"};
    for (const auto* s : stage_names) csv << ',' << s;
    csv << '\n';
    for (unsigned step = 0; step <= stop_step; ++step) {
        dut.profile_step_i = step;
        for (unsigned j = 0; j < 3; ++j) {
            dut.clk_i = 0; dut.eval(); dut.clk_i = 1; dut.eval();
        }
        csv << step << ',' << dut.profile_cycles_o << ',' << dut.profile_mac_o
            << ',' << dut.profile_rbeats_o << ',' << dut.profile_wbeats_o
            << ',' << dut.profile_arstall_o << ',' << dut.profile_rwait_o
            << ',' << dut.profile_awstall_o << ',' << dut.profile_wstall_o
            << ',' << dut.profile_bwait_o;
        for (auto v : stages[step]) csv << ',' << v;
        csv << '\n';
    }
    std::ofstream meta(prefix + "_memory.txt");
    meta << "latency=" << latency << " bandwidth_gbps=" << bandwidth
         << " source_mhz=150 peak_1024cycle_beats=" << peak_window << '\n';
    std::cout << "PASS cycles=" << cycle - 1 << '\n';
    return 0;
}
