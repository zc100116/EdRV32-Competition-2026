# W-1a BSP / GPU SoC 验证

实现 commit：`166c00a27`（初版 `b8cf85cda`）。
环境：用户提供的仿真主机（环境不记录）。

驱动、程序、模型和 ST-10–14 场景已实现；现有视觉驱动未修改。
GPU 命令 32 B，列表 64 B 对齐；寄存器和记录字段使用生成头。
GPU/AUD 使用 DDR 物理字节偏移；CPU cached/uncached 别名由驱动换算。
GPU 完成后 invalidate 结果范围；AUD clean 样本后发布 WR_PTR。
ES8156 使用 I2C0 端口 0，27 次寄存器写，I2S 从机、48 kHz、16 位。
A-3：06=00、10=00 与手册描述不同，协调者确认保留厂家开发初值，实际器件待上板确认。

| 检查 | 结果 |
| --- | --- |
| 3 个驱动、6 个 RV32 程序 C11 严格构建 | PASS，0 告警 |
| S-0c mmio 改造 | 14 个程序、2 套 host 检查 PASS，0 告警；monitor 缺 CoreMark，未记通过 |
| host 驱动检查 | PASS：cache 调用、环回写、错误保留、81 个 I2C 字节命令 |
| I2C 接收模型独立仿真 | PASS：2 次寄存器写及 ACK，620 us 仿真时间 |
| 本任务 7 个 SV 文件风格检查 | PASS，0 告警 |
| 5 个 SoC 场景接口 lint | PASS，0 告警，仅 lint 使用明确授权的 idle GPU |
| ST-10 参考图生成 | PASS：2 条、230400 个源像素 |
| ST-09 GPU 槽位/PLIC 源 13 | 等待真实 GPU 集成；后续删除占位并重跑全项 |
| ST-10 / ST-11 完整 SoC | 等待真实 GPU 集成 |
| ST-12 / ST-13 / ST-14 完整 SoC | 等待真实 GPU 集成；首次 RTL lint 退出，未进入仿真 |

ST-10 比对模型生成图像放大后的全部 921600 个 HDMI 像素。
ST-11 软件检查 DONE、PLIC、对象写回、命中和释放列表的 cache 交接。
ST-12 场景检查 27 次 ES8156 配置和 256 个正弦左声道/方波右声道样本。
ST-13 经真实 BIOS Ethernet 前门加载程序及 DDR 段，再执行视觉 SC-06 的 64 KiB RX 检查。
ST-14 检查 GPU/AUD 初始复位顺序与媒体软复位，并由软件检查寄存器复位值。
上述场景定义不表示完整 SoC 仿真已经通过。

复现命令（仓库根目录）：

```sh
make -C sw/tests/gpu_drivers test
make -C sw/tests/drivers_build test
for p in drivers_build demo demo_vision demo_npu demo_vnpu; do
    make -C sw PROGRAM=$p MEMORY=sram -j1
done
make -C sw PROGRAM=bootloader -j1
for p in gpu_drivers gpu_audio gpu_eth gpu_irq gpu_render gpu_reset; do
    make -C sw PROGRAM=$p SOC=gpu MEMORY=sram -j1
done
python3 sw/tests/gpu_drivers/check_style.py
python3 sw/tests/gpu_drivers/lint.py
python3 verif/soc/gpu_audio/run_model.py
mkdir -p build/gpu_soc/gpu_render
python3 verif/soc/gpu_render/prepare.py build/gpu_soc/gpu_render
python3 tools/regress.py full --path verif/soc/gpu_regs -j 1
python3 tools/regress.py full --path verif/soc/gpu_audio -j 1
python3 tools/regress.py full --path verif/soc/gpu_eth -j 1
python3 tools/regress.py full --path verif/soc/gpu_reset -j 1
python3 tools/regress.py full --path verif/soc/gpu_render -j 1
python3 tools/regress.py full --path verif/soc/gpu_irq -j 1
```
