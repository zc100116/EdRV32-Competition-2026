# GEO 独立模块验证（V-T4）

依据 `docs/spec/geo-spec.md` v0.1、`docs/testplan/geo-testplan.md` v0.1、SoC
4.2、4.3、7.1–7.3，以及 PIX 2.1 的 RGB565 展开/截断规则实现。起始提交为
`07d786f48426a5fe60ea84259a879863f60d1037`，验证代码提交以本 README 所属提交为准。
V-T4 测试作者没有阅读 `rtl/media/geo/`；V-I3 联调按规格区分 RTL 与测试错误，
所有检查继续只使用公开端口。

V-I3 已将独立验证环境接入真实 RTL（输入提交 `92b340b`，包含 `7ac1a35`）。
联调修改、失败定性、最终回归和性能数字见
[`docs/debug/2026-10-28-geo-block-integration.md`](../../../docs/debug/2026-10-28-geo-block-integration.md)。
根目录 test.yaml 为 smoke 档（53 个向量，清空构建后实测 57 秒，含构建），`selftest/` 也属于 smoke。

## 文件与使用

- `geo_ref.py`：小端字节内存上的逐位参考。描述符先屏蔽忽略位，再执行有符号
  32 位 Q16.16 坐标、向负无穷取整、8 位小数权重、RGB888 展开、四点加权及舍入、
  RGB565 截断。范围检查使用开发初值 BW/BH/PW/PH = 32/16/80/80。
  `matrix()` 只负责浮点生成激励，参考插值运算全部使用整数。
- `vectors.py`：`selections()` 按档位选择 GE 项目，`generate()` 中对应编号分支生成
  定向或随机描述符、源 Surface、随机输出初值和逐字节期望 Surface。图案包含随机像素、
  棋盘格、渐变和编号网格。每次执行生成 `config.txt` 和二进制内存段，全部位于 `build/`。
- `edrv32_geo_memory.sv`：32 MiB 字节寻址 RAM，AW/W/B、AR/R 有序队列，原样返回
  1 位 ID；随机 ARREADY/AWREADY/WREADY、R 间隔及 B 延迟。`read_latency` 是每笔
  AR 到首拍 R 的最小固定延迟，排队、带宽及握手停顿继续计时；`b_delay` 控制 B 延迟。
  `error_kind=1/2/3` 分别注入第一笔描述符读、源读、写响应 SLVERR，也可以直接指定
  从 0 起的 `r_error_transaction` / `b_error_transaction`。每次运行只注入一次错误。
  `bandwidth_limit` 使用共享 R/W 字节额度，每拍增加 9.6 B，每个握手 beat 消耗
  32 B，125 MHz 下限制为 1.2 GB/s；最多积累两个 beat 的额度。
- `edrv32_geo_tb.sv`：媒体 APB 槽 3 驱动、公共 AXI256 检查器、Surface 记分板、
  错误/恢复、ABORT、寄存器检查及帧时间检查。没有 DUT 内部层次引用。
  `compare_surface()` 遍历整个输出 Surface（包括行 padding），失败输出测试号、
  描述符序号、相对矩形坐标、期望像素、实际像素和仿真时刻后 `$fatal`。
  非像素检查用坐标 `(-1,-1)`；`drain_check()` 检查内存队列及公共检查器均排空。
  按协调者补充的第 3 节契约，读写方向分别检查最多 4 笔在途事务；正常 DONE IRQ
  上升时检查全部 R/B 响应已返回。
  `record_perf_bound()` / `check_perf_stopped()` 用相邻 APB STATUS 采样限定 BUSY
  清零的周期区间，并检查 PERF0 落在该区间且随后冻结；错误和 ABORT 也计到 BUSY 清零。
- `run.py`：真实 DUT 编译使用 `-j 1`，随后逐一生成和运行向量，首个失败立即结束。
  `files.f` 使用 `-f ../../../rtl/filelists/geo.f`，`support.f` 只包含公共接口、检查器
  和本验证环境。正式档位没有替身 RTL、缺失文件跳过或降级路径。
- `selftest/test.yaml`：单独运行 Python 参考自测，不依赖 RTL，不运行 GE 功能判定。
- `check.py`：复用 `tools/check/verilog_style.py` 的适用风格规则检查 SV，再以
  `--lint-only --timing -Wall` lint 真实 DUT 和完整功能 testbench。
  `lint.vlt` 仅豁免验证代码的阻塞队列更新、公共 APB 多槽未用位、公共检查器整数索引，
  以及 TB 复位被异步 DUT 和同步 BFM 同时采样的诊断；没有对真实 DUT 屏蔽告警。

## GE 项目映射

全部激励在 `vectors.py:generate()` 的对应编号分支，通用像素与正常完成检查在
`edrv32_geo_tb.sv:compare_surface()`、`check_completion()`。

| 项目 | 实现位置 | 检查点 | 档位 |
|---|---|---|---|
| GE-01 | `number == 1` | 64×32 恒等、整数平移，输出逐位一致 | full（原 smoke 集合） |
| GE-02 | `number in (2,3)` 的旋转分支 | 64×48 绕中心 0/90/180/270/15/45/−30° | full（原 smoke 集合） |
| GE-03 | 同上缩放分支 | 放大 1.5/3/8、缩小 1.25/2、非均匀缩放、双轴分别镜像、错切 | full（原 smoke 集合） |
| GE-04 | `number == 4` | 部分/全部越界、源宽/高为 1 和 0、fx/fy 为 0/255、负一 LSB | full（原 smoke 集合） |
| GE-05 | `number == 5` | RECT_X=0/16/1264、空宽/高、宽 34、强制设置被忽略的低位；矩形外及 padding 不变 | full（原 smoke 集合） |
| GE-06 | `number == 6`、`check_error()` | s=2 的四个直角/全部 24 个角度；s=2.5 的 45°、过大错切、X/Y 范围边界两侧及等号；拒绝时无源读、无写、后续描述符不执行 | full（原 smoke 集合） |
| GE-07 | `number == 7`、`check_completion()`、内存 `check_dependency` | 三条串行依赖，后条读取前条输出；DONE_COUNT/CUR_DESC 逐条前进；新描述符开始读取前，前条写响应已排空 | full（原 smoke 集合） |
| GE-08 | `number == 8`、`masks` | 同一初值的 clean/dirty 描述符；全部忽略字段和字 14/15 随机化后输出相同 | full（原 smoke 集合） |
| GE-09 | `number == 9`、`check_error()` | 描述符 R、源 R、B 的 SLVERR；错误码 1/2、STATUS/CUR_DESC、IRQ mask/RW1C、停止后条、清 ERROR 后原表重启成功 | full（原 smoke 集合） |
| GE-10 | `number == 10`、`ge10_abort()` | 描述符读/源读/写出三个阶段确认有在途事务后 ABORT；排空、IDLE、不置 DONE、不计完成条数，已写字节正确 | full |
| GE-11 | `ge11_registers()`、`reset_registers()` | 复位、ID/RO/保留偏移、CTRL 脉冲位、对齐和位宽、IRQ、零条门铃、忙时门铃忽略、忙/闲 SOFT_RST、PERF 清零和只读 | full（原 smoke 集合） |
| GE-12 | `number == 12`、`check_completion()` | 1280×720，45° s=1/2；固定读延迟 40，R/W 合计 1.2 GB/s；全图逐位一致；PERF0×8 ns ≤16.7/33 ms | perf |
| GE-13 | `number == 13` | 10 种子、每种子 4 描述符；随机尺寸 1–256、矩阵、矩形、BG、存储延迟和握手；全图及协议 | full |

根目录（smoke）共 53 个 RTL 向量；full 子目录增加另外 20 个 s=2 角度、3 个 ABORT 场景和
10 个随机种子，共 33 个向量。`tools/regress.py full` 选择两个目录及 smoke 自测，因此 full
合计 86 个 RTL 向量，并含参考自测；perf 为 2 个向量。没有增加或删除 GE 测试项。
GE-06 的 s=2.5 选 45°，因为规格按覆盖范围公式判定，s=2.5 的 0° 本身可能合法。

自测的独立手算包括恒等和 90° 像素排列、四角等权 RGB565=`0x8410`、红色与黑背景
半权=`0x8000`、负坐标 floor、低 8 位小数忽略、全部越界取 BG、矩形忽略位及外部保持、
空矩形、X/Y 范围相邻 Q16.16 值，以及范围等号与超过一个 LSB。

## 验收命令

环境：Linux、Python 3 标准库、Verilator 5.020；一次只跑一个仿真，构建 `-j 1`。

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py rtl/media/geo
python3 verif/block/geo/check.py
make smoke REGRESS_ARGS='-j 1 --path verif/block/geo'
make full REGRESS_ARGS='-j 1 --path verif/block/geo'
python3 tools/regress.py perf -j 1 --path verif/block/geo
```

最终数字和命令结果统一记在联调记录中。日志位于 `build/geo/lint/lint.log`、
`build/regress/<回归档位>/block/geo/`，真实 RTL 的编译日志和各向量的复现输入、
期望图及运行日志保存在 `build/geo/<向量集合名>/`。已有真实二进制后，可用
`build/geo/obj/sim +CONFIG=<向量目录绝对路径>/config.txt` 单独复现，保持串行执行。
GE-12 打印 PERF0、帧时间（ns）、门限及 PERF4/PERF5 等待周期。
