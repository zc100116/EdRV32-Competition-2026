# CPU v2 关键路径探针时序与资源（卡 110）

| 项 | 内容 |
|---|---|
| 源码 | 工程 A（整数）f723be4c6（RTL 380c93e49）；工程 B（FMA）8a507b0f8（RTL e1fd27d5c） |
| 工具 / 器件 | PDS 2022.2-SP6.1 build 138931；PG2L200H-6 FBB676 |
| 约束 | 单时钟 6.667 ns（150 MHz），默认 P&R 参数，无 multicycle |
| 原始数据 | `origin/win/20261127-110-cpu2-probes` 的 `tasks/win/20261127-110-cpu2-probes/artifacts/{int,fma}/` |
| 结构说明 | `docs/design/2026-11-27-cpu-v2-probes.md` |

## 汇总

| 工程 | 慢角 WNS / TNS | WHS | 估算 Fmax | LUT / FF | DRM36K 等效 | APM | 分布式 RAM LUT |
|---|---|---|---:|---|---:|---:|---:|
| A 整数 | +0.151 / 0 | +0.142 | 153.5 MHz | 4194 / 2676 | 26.5（16×36K + 21×18K） | 0 | 502 |
| B FMA | +0.356 / 0 | +0.212 | 158.5 MHz | 1836 / 1070 | 0 | 2 | 0 |

资源含探针顶层的激励和观察寄存器。A 组第 1 轮在 PDS Compile 崩溃（多个 always 写同一 reg 数组，与卡 109 同类），380c93e49 改写后通过。

## 关键段：实测与规格估算

估算 = cpu-v2-spec 7 / fpu-spec 7.1 的段值（已含 0.450 ns 余量）；实测 = 6.667 − 该组最差裕量。

| 关键段 | 估算 ns | 实测 ns | 级数 | 逻辑 / 布线 ns | 最差端点 |
|---|---:|---:|---:|---|---|
| 双 bank F2 → LVT 候选（IB） | 6.196 | 6.516 | 7 | 2.732 / 3.457 | I$ tag DRM → `ib_candidates_r` |
| 待写训练命中前置 | 6.093 | 6.372 | 10 | 2.404 / 3.702 | `pending_indices_r` → `f2_shadow_tag_r` |
| TAGE F2 方向 | 5.992 | 5.877 | 4 | 2.292 / 3.241 | TAGE DRM → `tage_f2_provider_r` |
| ID 注册 owner → AGU | 6.186 | < 6.093 | — | — | 不在最差 200 条内（第 200 条 +0.574） |
| DRM load → 操作数捕获 | 5.250 | 4.987 | 3 | 2.209 / 2.376 | D$ tag DRM → `operand_data_r` |
| FMA E6 加法 / LZA | 6.206 | 4.582 | 4 | 1.091 / 3.258 | tail APM → `e6_forward_count1_r` |
| FMA E7 规格化粗移 | 6.093 | 5.817 | 5 | 1.208 / 4.312 | `e6_forward_hit0_r` → `e7_magnitude_r` |
| FMA E8 细移 / 舍入 / 打包 | — | 6.311 | 9 | 2.063 / 3.981 | `e7_shift_r` → `result_o` |
| APM CPO → CPI 级联 | — | 1.807 | 0 | 0.581 / 0 | head → tail 专线 |

## 要点

- 五个探针在独立工程中全部满足 150 MHz。模型估算与实测相差在 −5%～+5% 之间，没有出现系统性低估。
- 整数工程最差 200 条中有 178 条终点是 `ib_candidates_r`，即 F2 读 I$ tag 后的路选择、LVT 查询、写入 IB 候选 owner。
- Yosys 级数偏高：FMA E8 Yosys 17 级，PDS 9 级。
- 独立探针不含整片布线拥塞。按 `timing-margin` 经验（CPU 独立 131.7 MHz、整片 125 MHz，约 −5%），整数 153.5 MHz 与 FMA 158.5 MHz 进入整片后可能低于 150 MHz。
- RAM 映射与估算一致：26.5 DRM36K；LUTRAM 实测 502 LUT，估算按每 LUT 32 bit 计为 1324，PDS 实际按每 LUT 64 bit 打包。
