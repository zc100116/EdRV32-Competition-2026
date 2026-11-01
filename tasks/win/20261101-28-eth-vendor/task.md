# 任务卡 20261101-28-eth-vendor：收集厂商以太网例程与 PHY 资料

## 1. 目标

卡 26 已确认：网口时好时坏，原因在 **RGMII 接收采样时序**。我们的 RGMII 输入没有时序约束，采样相关的延迟数值是照抄厂商例程的：

| 设置 | 数值 |
|---|---|
| RX 数据 IODELAY | 247 × 10 ps |
| ETH PLL CLKOUT0 相移 | 30° |
| IDDR 模式 | SAME_PIPELINED |
| PHY RXDLY/TXDLY | 未通过 MDIO 设置，使用上电默认的 1/1 |

协调者要用厂商资料确定一套**固定**设置，并补上 RGMII 输入时序约束，让 PDS 每次综合都检查采样裕量。本卡**只收集资料**：不上板、不综合。

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡的提交），拉出 `win/20261101-28-eth-vendor`。
- **厂商资料**：Windows 本地的开发板资料包（`fpga/ip/ip_pll_eth.md` 引用的 `2_Demo/2_11_ethernet_test/` 所在的资料包），以及资料包里的原理图、用户手册和芯片手册目录。

## 3. 环境

只需要文件访问和文本、PDF 阅读，不需要 PDS 和开发板。

## 4. 需要的 IP

无。

## 5. 操作步骤（Windows Codex 完成，遇到找不到的项写“未找到”，不要推测）

1. **以太网例程源码**（`2_Demo/2_11_ethernet_test/`，以及资料包里其他以太网相关例程，例如 UDP、千兆回环）：
   - 复制 RGMII 收发相关的 RTL 原文：例化 `GTP_IDDR*`、`GTP_ODDR*`、`GTP_IODELAY*`、PLL 的模块；
   - 复制 PLL 的 `.idf` 或 IP 配置原文：输入频率、输出相位、反馈或补偿模式；
   - 复制例程的 `.fdc` 全文。特别注意有没有 `set_input_delay`、`set_output_delay`、PLL 或时钟缓冲的位置约束；
   - 例程有没有通过 MDIO 写 PHY 寄存器？如果有，复制写入的寄存器地址和数值，特别是 page 0xd08 的 reg 0x11、0x15，或 page 0xa43 的相关寄存器；
   - 例程的说明文档里关于网口、PHY 延迟、时序的段落原文。
2. **原理图**：RTL8211F 部分的截图（PNG），重点是配置引脚的上下拉：RXDLY、TXDLY、PHYAD、MODE/SELRGV 等；以及 RGMII 走线有没有串联电阻、板上有没有标注延迟。
3. **RTL8211F 数据手册**（如果资料包里有）：
   - RGMII 时序表截图（PNG），以及表中数值抄录：TskewT、TskewR、TsetupT/R、TholdT/R、内部延迟开启时的数值，并注明对应的条件和页码；
   - RXDLY/TXDLY 配置引脚和寄存器说明的截图和页码。
4. **PG2L200H 器件手册或用户指南**（如果资料包里有）：
   - `GTP_IODELAY_E2` 的步进延迟和范围；
   - `GTP_IDDR_E1` 中 SAME_PIPELINED 的采样时序说明；
   - PLL 的补偿或反馈模式（输出时钟相对输入引脚的相位是否被补偿）。

   给出截图和页码。
5. 在 `result.md` 中逐项列出找到的文件路径（Windows 本地）和摘要。

## 6. 产物

放在 `tasks/win/20261101-28-eth-vendor/artifacts/`：

| 产物 | 内容 |
|---|---|
| `demo_rtl/` | 例程中 RGMII、PLL 相关 RTL 原文和 `.idf`（只复制相关文件） |
| `demo_fdc/` | 例程 `.fdc` 原文 |
| `demo_mdio.txt` | 例程对 PHY 的寄存器写入，或“未找到” |
| `schematic_phy.png` | 原理图中 PHY 和配置引脚部分 |
| `rtl8211f_timing.png`、`rtl8211f_timing.txt` | RGMII 时序表截图和抄录（含页码） |
| `pg2l_iodelay_pll.png`、`.txt` | 器件手册相关页截图和摘要（含页码） |

厂商资料只复制本卡需要的部分，单个文件超过几 MB 时在 `result.md` 中说明原因。

## 7. 通过判据

每一项都有原文、截图或“未找到”的明确记录；没有推测的数值。

## 8. result.md 模板

```markdown
# 20261101-28-eth-vendor 结果

| 项 | Windows 本地路径 | 摘要 |
|---|---|---|
| 以太网例程 RTL | | |
| PLL 配置 | | |
| 例程 fdc（是否有 input/output delay、位置约束） | | |
| 例程 MDIO 写 PHY | | |
| 原理图 PHY 配置引脚（RXDLY/TXDLY/PHYAD/MODE） | | |
| RTL8211F RGMII 时序表 | | |
| PG2L IODELAY / IDDR / PLL 补偿 | | |

## 问题与偏离
```
