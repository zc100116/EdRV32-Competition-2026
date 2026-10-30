# 任务卡 20261030-12-apm-primitive：取 GTP_APM_E2 原语的仿真模型和原语说明

## 1. 目标

从本机 PDS 安装目录取出 APM 原语 `GTP_APM_E2` 的仿真模型和原语说明，用于判断 NPU MAC 阵列能否在 SIMD 双乘模式下用 APM 内部后加器/级联（CPI/CPO）求和。**全部由 Windows Codex 完成，不需要用户操作，不运行 PDS 流程。**

背景：卡 11 取回的 UG041003 是 IP 层面的说明（乘法器、乘加器、乘累加器），没有写原语 `GTP_APM_E2` 在 `USE_SIMD=1` 时 `USE_POSTADD`、`MODEZ`、`CPI/CPO` 的行为。NPU 现在的用法见 `rtl/tech/edrv32_mul_npu_int8_pair.v`。

## 2. 输入

- 分支 `origin/zc100116/b3`（包含本卡）。Windows Codex 从这里拉出 `win/20261030-12-apm-primitive`。
- PDS 安装目录 `G:/Program/pango/PDS_2022.2-SP6.1`（卡 11 已确认）。

## 3. 环境

PDS 2022.2-SP6.1。

## 4. 需要的 IP

无。

## 5. 操作步骤

| 步 | 执行者 | 内容 |
|---|---|---|
| 1 | Windows Codex（C） | 在安装目录中递归查找文件名或内容含 `GTP_APM_E2` 的文件（重点：`arch/vendor/pango/verilog/` 及其下的 simulation/synthesis 目录、`ip/module_ip/ipm2l_flex_apm/` 生成器中的 rtl 模板）。列出全部命中文件的路径、大小、是否明文。 |
| 2 | Windows Codex（C） | 把 `GTP_APM_E2` 的**明文**仿真模型（`.v`/`.vp` 若为明文）复制到 `artifacts/model/`。若模型是加密的，不复制，记录"加密"和文件头前 5 行。 |
| 3 | Windows Codex（C） | 查找 Logos2 原语（GTP）说明文档：文件名或标题含 `GTP`、`原语`、`Primitive`、`Library`、`UG0400`、`UG0410` 的 PDF/HTML/CHM。列出全部，把涉及 APM 原语的那一份复制到 `artifacts/manuals/`。找不到写"未找到"并列出查过的目录。 |
| 4 | Windows Codex（C） | 在 `ipm2l_flex_apm` 的 IP 生成器目录中找到 Multiply-Adder / Multiply-Accumulator 的 RTL 模板（生成 IP 时使用的 `.v` 或模板文件），若为明文，复制其中例化 `GTP_APM_E2` 的文件到 `artifacts/ip_rtl/`。 |
| 5 | Windows Codex（C） | 填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261030-12-apm-primitive results`，推送 `win/20261030-12-apm-primitive`。 |

## 6. 产物

| 产物 | 内容 | 位置 |
|---|---|---|
| `model/` | `GTP_APM_E2` 明文仿真模型 | `artifacts/model/` |
| `manuals/` | 原语说明（如有） | `artifacts/manuals/` |
| `ip_rtl/` | APM IP 生成器中例化 `GTP_APM_E2` 的明文模板 | `artifacts/ip_rtl/` |
| `search.tsv` | 全部命中文件：路径、大小、是否明文、用途判断 | `artifacts/` |

## 7. 通过判据

- 步骤 1 的命中列表完整；
- 明文模型或明文 IP 模板至少取得一项，或明确说明全部加密、无原语文档。

## 8. result.md 模板

```markdown
# 20261030-12-apm-primitive 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| PDS 安装目录 | |

## GTP_APM_E2 命中文件
| 路径 | 大小 | 明文/加密 | 用途 |
|---|---|---|---|

## 已复制
| 文件 | 来源路径 | 说明 |
|---|---|---|

## 原语文档
查过的目录：

## 备注
```
