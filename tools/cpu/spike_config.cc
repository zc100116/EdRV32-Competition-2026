// File: spike_config.cc; Spec: cpu-spec 5; Clock: instruction reference.
// Match EdRV32 implementation-identification CSRs through Spike's extension API.
#include <riscv/extension.h>
#include <riscv/csrs.h>

class edrv32_config_t : public extension_t {
 public:
    std::vector<insn_desc_t> get_instructions(const processor_t& proc) override {
        auto& configured = const_cast<processor_t&>(proc);
        for (auto& csr : get_csrs(configured))
            configured.get_state()->add_csr(csr->address, csr);
        return {};
    }
    std::vector<disasm_insn_t*> get_disasms(const processor_t* = nullptr) override { return {}; }
    const char* name() const override { return "edrv32_config"; }
    std::vector<csr_t_p> get_csrs(processor_t& proc) const override {
        return {std::make_shared<const_csr_t>(&proc, CSR_MARCHID, 0),
                std::make_shared<const_csr_t>(&proc, CSR_MIMPID, 0),
                std::make_shared<const_csr_t>(&proc, CSR_MVENDORID, 0)};
    }
};
REGISTER_EXTENSION(edrv32_config, []() { return new edrv32_config_t; })
