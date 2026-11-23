# DISP GPU L0_X2 验证结果

环境：用户提供的仿真主机（环境不记录）。
提交：`disp: L0 2x upscale variant for the GPU SoC`，即本报告的引入提交。
定位提交：`git log -1 --format=%H -- verif/block/disp_gpu/results.md`。

- ST-04：原 DS-01～19 的 75 个实例及 Python/SV 混合参考比对全部 PASS。
- ST-05：640×360 源窗口、SCROLL=(32,3)，921,600 个接收像素一致；
  720 行、每行 40 beat、共 28,800 beat，全部 AR 地址和长度一致；smoke 仿真约 40 秒。
- ST-06：四个扫描帧，X2→原尺寸→X2、L1 混合、读空、禁用帧偿还欠账、恢复对齐全部 PASS；
  L0/L1 分别观察到 23,840/91,217 个缺失 beat，恢复帧不再增加缺失数。
- ST-07：X2 水位 39 有效、40/80 无效；原尺寸 80 有效、81 无效；
  模式帧锁存、空位 39 不准入/40 准入、精确填满 512 beat，全部 PASS。
- 完整块级 runner：77 PASS、0 FAIL，另有 ST-07 和独立混合参考 PASS。
- GPU 单元 reader/regs/scan/scan-X2/layers：5 PASS；复用 control/timing/tmds_enc：3 PASS。
- 本机 RTL 风格：4 文件、0 告警；RTL 顶层 `--lint-only -Wall`：0 告警。
- 仿真进程与构建目录已清理；视觉项目文件未修改，control/timing/TMDS 等直接复用。

相对原文件的 diff 统计（包含文件头与模块改名；单位：行）：

| GPU 文件 | 增加 | 删除 |
|---|---:|---:|
| `rtl/media/disp/edrv32_disp_gpu.v` | 11 | 11 |
| `rtl/media/disp/edrv32_disp_regs_gpu.v` | 10 | 10 |
| `rtl/media/disp/edrv32_disp_reader_gpu.v` | 15 | 10 |
| `rtl/media/disp/edrv32_disp_scan_gpu.v` | 14 | 11 |
| `rtl/filelists/disp_gpu.f`（对比 disp.f） | 4 | 4 |

复现命令（完整块级档位包含 smoke；独立用例可用 `run.py smoke` / `run.py x2full`）：

```sh
python3 tools/regress.py full -j 1 --path verif/block/disp_gpu
for u in reader_gpu regs_gpu scan_gpu layers_gpu; do
    python3 tools/regress.py full -j 1 --path verif/unit/disp_$u || exit $?
done
python3 - <<'PYCODE'
from pathlib import Path
from tools.regress import read_test, run_test
for name in ('control', 'timing', 'tmds_enc'):
    p = Path('verif/unit/disp_' + name + '/test.yaml').resolve()
    cfg = read_test(p)
    cfg['verilator_flags'] = '-Wno-ZERODLY'
    if not run_test(p, cfg, 'verilator', 'full', jobs=1):
        raise SystemExit(1)
PYCODE
python3 tools/check/verilog_style.py rtl/media/disp/*_gpu.v
verilator --lint-only -Wall +define+SIM_MODE --top-module edrv32_disp_gpu -F rtl/filelists/disp_gpu.f
```

主机与本机的 TB 诊断存在差异：GPU TB 沿用原行为豁免并增加 PROCASSINIT/ZERODLY；
复用 control 的变量时钟同样需要 ZERODLY 豁免，原测试文件保持只读。
主机 Python 缺少 int.bit_count，GPU TMDS 参考改用等价二进制字符串计数；TMDS 比对 PASS。
