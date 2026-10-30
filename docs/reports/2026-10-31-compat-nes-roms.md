# NES ROM 合集兼容性（T-NES3，主机）

基线 `d240547f`；实现为本报告所在提交（`git log -1 -- docs/reports/2026-10-31-compat-nes-roms.md`）。
nofrendo `693e378`，Linux GCC 13.3 / xPack RV32 GCC 15.2 / Spike 1.1.1-dev；未跑 SoC 仿真或上板。
只使用入库的 926 个文件；未下载或改动合集 ROM、未修改子模块。
方法：按 nofrendo 头解析规则和打补丁后的 49 种 mapper 注册表清点，槽为 2097168 B；
先无输入跑 600 帧，最后 5 张 PPM 颜色数均为 1 时，在第 120 帧后按 Start 一帧重跑。
“有画面”只证明启动画面非单色，不代表整局可玩；NES 2.0 仍按上游 iNES 规则解析。
原始数据：`docs/reports/assets/2026-10-31-nes-rom-survey.tsv`；`no_input` / `start` 保留两次结论。

| 分类 | 改前 | 改后 |
|---|---:|---:|
| 有画面 | 710 | 847 |
| 单色（含 Start 复测） | 42 | 26 |
| 主机崩溃 | 13 | 0 |
| mapper 未实现 | 145 | 45 |
| 超过 ROM 槽 | 8 | 0 |
| FDS（不处理） | 8 | 8 |
| 合计 | 926 | 926 |

mapper 19 的 15 个全部退出 0，原 13 个 CIRAM 空指针崩溃归零；名称表改用 PPU 内部 2 KiB RAM。
新 mapper：74、192、195、191、199、245、69、30，以及 140、87、91、10、71、88、198。
MMC3 修复禁用期间计数/自动重载、$C001 延迟重载、零值 IRQ、模式切换及 CHR-RAM 分页。
单色主因是 APU IRQ：SEI 期间的旧请求未随 $4015 读/$4017 bit6 确认而清除，CLI 后错误跳转；
现把 APU/mapper IRQ 独立保持到确认。原 42 个中 32 个恢复（mapper 4×29、1×2、85×1）；
基线 42 个单独加 Start 全部仍单色，修复后另有 mapper 19 的两份沙罗曼蛇必须加 Start 才出画面。
原 8 个超大 ROM 全部能装入；其中 4 个出画面，4 个 MMC5 仍单色；未改变 ROM 或改写 mapper 号。

原有 710 个有画面全部保留；新增 137 个有画面，其中两份 mapper 19 沙罗曼蛇由 Start 复测救回。
剩余：45 个未实现 mapper 仍走上游报错，8 个 FDS；26 个单色为 mapper 5×7、19×3、198×3，
25/4/16/74 各 2，0/245/69/191/199 各 1。19 的三份三国志2停在 $FB2A，核心缺 Namco IRQ/读回；
MMC5 仍缺完整银行模式/ExRAM。原 42 个余 10 个中，6 个 CPU JAM（5/25/16 各 2），
4 个仍在初始化/IRQ/空画面循环（0×1、4×2、5×1）；首次跑偏点及其余新增 mapper 余项尚未定位，
需要继续跟踪 6502/PPU/mapper；未加入 ROM 特例。逐 ROM 的 PC/SP/JAM/IRQ/PPU 状态见 TSV `detail`。
MMC3/91 仍按扫描行近似 A12 时钟，69 在寄存器/hblank 同步 CPU 周期；未实现周期精确 PPU/APU。
69 无扩展音频、30 无闪存编程；91 只实现 JY/submapper 0，不以游戏名称/哈希作兼容分支。

复现（所有构建、检查、Spike、清点均用 `flock /tmp/edrv32-sim.lock` 串行包装，make `-j1`）：

```sh
make -C sw/apps/nes -j1
python3 tools/nes/rom_survey.py third_party/nes build/nes/rom-survey.tsv
python3 sw/apps/nes/check_mapper19.py
python3 sw/apps/nes/check_mmc3.py
python3 sw/apps/nes/check_irq.py
python3 sw/apps/nes/check_mappers.py
python3 sw/apps/nes/check_trainer.py
python3 sw/apps/nes/check_blit.py
. ~/.local/opt/edrv32/env.sh
make -C sw -j1 PROGRAM=nes MEMORY=ddr_app
make -C sw -j1 PROGRAM=nes MEMORY=ddr_app NES_DISPLAY=0 OUT=$PWD/build/sw/nes-nodisplay
python3 -m unittest discover tools/board/tests
python3 sw/apps/nes/run_spike.py
```

以上检查全部 PASS；主机/RV32 两配置编译链接零告警，board 工具 11 项通过，Spike 四组退出 0。
模板 60/120/180 三张 PPM 均与 `d240547f` 构建逐字节相同；日志/帧在 `build/nes/compat/`。
`cmp build/nes/compat/{before,after}/frame-000180.ppm`（60/120 帧同样比较）。
槽 `nm -S`：显示版 `905f61c0`–`907f61d0`，非显示版 `90261200`–`90461210`，大小均 `00200010`。
