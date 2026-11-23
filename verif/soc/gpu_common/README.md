# GPU SoC shared harness

Derived from `verif/soc/common/edrv32_soc_tb.sv`; reuses its DDR, UART,
HDMI and Ethernet models, image packing and logged command runner.
Environment: 用户提供的仿真主机（环境不记录）。

Each test owns `files.f`, `test.yaml`, `run.py`, and a module named
`edrv32_gpu_scenario(output bit checks_complete_o,
output wire [1:0] model_sda_oe_o)` in its own directory.
Its `files.f` includes `-f ../gpu_common/files.f` and its scenario file.
The shared top is `edrv32_gpu_soc_tb`; instance names are `u_dut`, `u_ddr`,
`u_uart`, `u_hdmi`, `u_eth`, `u_scenario`. HDMI receiver runs from the
external reset and exposes its frame_pixels queue for scenario comparisons. Scenario code may reference the
shared top through `$root.edrv32_gpu_soc_tb`. It asserts checks_complete_o
when its external checks finish; drive model_sda_oe_o = 0 unless an I2C
slave model drives ACK/data (bit 0 connects ES8156, bit 1 unused); the shared harness checks SYSCTRL SIM_EXIT
is zero and checks_complete_o is asserted before printing PASS ST-NN.

The top exposes `case_number`, `data_dir`, `uart_log`, clocks/resets,
`gpio_i`, I2S pins and the existing external models. Clocks in MHz are
sys/mem/gpu/pix/aud/ETH = 125/125/180/74.25/12.288/125.
Plusargs: required `+CASE=N`, `+DATA_DIR=...`; image args `+ROM_HEX=...`,
`+SRAM_HEX=...`, optional byte-addressed `+DDR_HEX=...`; `+GPU_PARTIAL=1`
marks the explicitly requested placeholder build. Timeout is 600 ms simulated.
Scenarios add their own models/files/plusargs in their owned directories.

Python API (repository root on sys.path):

```python
from verif.soc.gpu_common.run import run
run(here, number, placeholder=False, bios=False,
    software_sources=None, plusargs=())
```

Default software is `sw/tests/<directory-name>/main.c`, uart.c and plic.c,
linked in SRAM with `SOC=gpu`, rv32im_zicsr_zifencei and BSP startup.
`software_sources` replaces that source string. `program.mk` supports extra
per-program build rules. With bios=False, ROM jumps to the preloaded SRAM
program; bios=True builds the unchanged real bootloader and requires UART
interaction. `SOC=gpu` selects the generated gpu_soc_map.h for reused drivers.
Output and command logs are in `build/gpu_soc/<directory-name>/`.

Normal builds consume `rtl/filelists/gpu_soc.f`, including `-f gpu.f`.
`placeholder=True` explicitly replaces only gpu.f with this directory's idle
`edrv32_gpu.v`; it never goes into an RTL filelist. Authorized use: lint,
ST-08 and ST-09 non-GPU subset only (coordinator confirmed). ST-09 skips
slot 6 and PLIC source 13 in that mode; neither is reported as verified.
Real integration uses `python3 verif/soc/gpu_regs/run.py` without the flag.

```sh
python3 tools/regress.py full --path verif/soc/gpu_boot -j 1
python3 tools/regress.py full --path verif/soc/gpu_regs -j 1
```

Reset hierarchy for ST-14 (under edrv32_gpu_soc_tb):
`u_dut.rst_sys_n_w`, `rst_mem_core_n_w`, `rst_mem_n_w`, `rst_pix_n_w`,
`rst_gpu_n_w`, `rst_aud_n_w` are reset-controller outputs.
System region copies: `u_dut.u_sys.rst_sys_{xbar,rom,sram,clint,plic,uart,i2c}_n_w`.
The real GPU core instance is `u_dut.u_gpu.u_core`.
GPU boundary copies: `u_dut.u_gpu.rst_gpu_n_w` and `rst_mem_n_w`.
AUD copies: `u_dut.u_aud.rst_mem_n_w` and `rst_aud_n_w`.
System media APB copy: `u_dut.u_sys.rst_mem_core_bus_n_w`.
Memory fabric copies: `u_dut.u_mem.rst_sys_gateway_n_w`,
`rst_mem_core_ctrl_n_w[0]`, `rst_mem_gateway_n_w[0]`, `rst_mem_regs_n_w[0]`;
statistics copies are `rst_mem_stat0_n_w[0]` through `rst_mem_stat4_n_w[0]`.
DISP control/scan copies: `u_dut.u_disp.rst_mem_ctrl_n_w`, `rst_pix_scan_n_w`.
