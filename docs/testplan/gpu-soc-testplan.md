# GPU SoC 验证方案

| 项 | 内容 |
|---|---|
| 版本 | v0.1 |
| 日期 | 2026-11-23 |
| 对应规格 | `docs/spec/gpu-soc-spec.md` v0.1；`gpu-spec.md` v0.1；`aud-spec.md` v0.1；视觉规格中沿用的条款 |

## 1. 验证对象和范围

- **沿用模块的改动**：mem_xbar 改为 5 个端口、DISP 的 L0 2 倍放大、reset_ctrl 的改名和新增复位。
- **SoC 级**：`edrv32_gpu_soc_top` 的连接、启动、GPU 端到端渲染、放音、ETH。
- **上板**：Windows 任务卡。

沿用而未改动的模块（CPU、cache、DDR 网关、ETH、dma2d）不重新做模块级验证，只在 SoC 级做连接性测试。

## 2. 验证环境

- **mem_xbar**：沿用视觉项目 `verif/unit/mem_xbar`、`verif/block/mem_subsys` 的测试，复制到本项目目录后按 5 个端口改写。
- **DISP**：沿用视觉项目 `verif/block/disp` 的测试和模型，在本项目目录下增加 L0_X2 的测试项。
- **SoC 级**：`verif/soc/gpu_*`；软件由 `sw/Makefile` 构建，后门预加载；SYSCTRL `SIM_EXIT` 判定结果；使用 DDR、HDMI 接收、UART、I2S 接收、ETH 对端模型。

## 3. 测试项清单

| 编号 | 对象 | 测试内容 | 检查 | 档位 |
|---|---|---|---|---|
| ST-01 | mem_xbar | 视觉项目的 mem_xbar 单元和模块级测试，按 5 个端口改写后全部运行 | 全部 PASS | smoke |
| ST-02 | mem_xbar | 端口号映射：下游 ID 的端口号 0–4；ETH 在 P4 上限速；p = 5、6 的寄存器地址读为 0 | 定向检查 | smoke |
| ST-03 | mem_xbar | 5 个端口同时满负荷，随机延迟 | 无死锁；协议检查通过；P0、P1 紧急优先 | full |
| ST-04 | DISP | 视觉项目 DISP 测试全部运行（`L0_X2` = 0 时行为不变） | 全部 PASS | smoke |
| ST-05 | DISP | `L0_X2` = 1：640 × 360 测试图，SCROLL 非零（16 的倍数） | 接收模型恢复的 1280 × 720 画面与放大后的源图逐像素一致；L0 读事务的地址和长度 | smoke |
| ST-06 | DISP | 帧间切换 `L0_X2`；`L0_X2` = 1 与 L1 叠加；`L0_X2` = 1 时读空和欠账 | 逐像素；ERR_CODE | full |
| ST-07 | DISP | `L0_X2` = 1 时的 `urgent_o` 阈值（40 beat） | 定向检查 | full |
| ST-08 | SoC | 启动：bootloader 打印启动信息，CHIP_ID = 0xED32_0002；监控程序菜单 | UART 日志 | smoke |
| ST-09 | SoC | 寄存器连通：媒体 APB 槽 1、5–8 的 ID；预留槽回 SLVERR；PLIC 源 8、12–15 | 软件自检 | smoke |
| ST-10 | SoC | GPU 端到端：软件生成一帧 3D + 四边形 + 对象场景，GPU RESOLVE，DISP `L0_X2` = 1 显示 | HDMI 接收模型画面与 GPU 参考模型结果逐像素一致 | smoke |
| ST-11 | SoC | GPU 中断、DONE 计数、命中列表，按视觉规格 7.4 做 cache 维护后由 CPU 读取 | 软件自检 | smoke |
| ST-12 | SoC | AUD 端到端：软件写正弦波和方波样本，LOW 中断补充；I2C0 端口 0 写 ES8156 配置序列 | I2S 接收模型得到的样本与软件写入一致；I2C 模型收到的寄存器序列 | smoke |
| ST-13 | SoC | ETH 回归：视觉项目的 ETH SoC 测试（程序加载、接收窗口） | PASS | full |
| ST-14 | SoC | 复位顺序：rst_gpu_n、rst_aud_n 的释放顺序；SYSCTRL 媒体软复位 | 定向检查 | full |
| ST-15 | 上板 | Windows 任务卡：综合、布局布线、时序和资源报告；上板运行三部分演示；示波器或耳机检查放音 | 报告和日志 | — |

## 4. 参考模型

- GPU 画面：`tools/gpu/model/`。
- DISP：视觉项目 DISP 测试的参考模型，加上 `L0_X2` 的放大规则。
- 音频：软件写入的样本序列。

## 5. 覆盖目标

`gpu-soc-spec.md` 第 3、5、6、8 节的每一条至少对应一个测试项。

## 6. 通过判据和回归档位

全部 PASS；lint 0 告警。smoke：ST-01、02、04、05、08–12；full：全部仿真项。

## 7. 待定事项与变更记录

| 日期 | 版本 | 内容 |
|---|---|---|
| 2026-11-23 | v0.1 | 初稿 |
