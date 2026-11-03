# 任务卡 20261103-50-ui-pages-review：在 Windows 上评审 showcase v2 的 9 个页面（B 浅色风格）

## 1. 目标

用户在 Windows 上运行模拟器，逐页查看 9 个应用页面的布局、内容和操作，并提出修改意见。设计依据：`docs/design/2026-11-03-showcase-ui.md` 第 4 节。

不涉及 PDS 或上板。模拟器中的数字和画面都是示意，真实数据在上板阶段接入。

## 2. 输入

- **代码**：`origin/zc100116/b3` 上包含本卡的提交，拉出 `win/20261103-50-ui-pages-review`。
- **本卡 `src/`**：

| 文件 | 内容 |
|---|---|
| `showcase_sim.exe` | 模拟器，由 Linux 用 Zig 0.17.0 从 `6be4bbcc` 交叉编译，单个文件，只依赖 Windows 系统 DLL |
| `shots/*.png` | 19 张同一程序的 Linux 截图，可以先在 GitHub 上预览 |

## 3. 环境

Windows 10/11 x64。exe 没有签名，SmartScreen 拦截时点"更多信息 → 仍要运行"。

## 4. 需要的 IP

无。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261103-50-ui-pages-review origin/zc100116/b3`，记录 HEAD。 |
| 1 | 用户（U） | 双击 `tasks/win/20261103-50-ui-pages-review/src/showcase_sim.exe`。 |
| 2 | U | 首页用 ← → 选择应用，Enter 进入，Esc 返回首页；鼠标点击等同于选中后按 Enter。按 **F1** 在"全部模块"和"VRN（无 PIX/GEO）"之间切换，查看"图像处理"置灰的效果。 |
| 3 | U | 逐页查看：视觉识别、图片识别、图像处理、图形引擎（3 个页签）、游戏（30 款，可滚动）、系统监控、芯片信息（可运行 CoreMark）、调试助手（串口/网口两个页签）。 |
| 4 | U | 对每页提出意见：布局、文字、配色、信息是否多余或缺少、操作是否顺手。 |
| 5 | C | 按第 8 节模板整理进 result.md，尽量保留用户原话；用户想标注的界面截图放 `artifacts/`。提交并推送 `win/20261103-50-ui-pages-review`。 |

## 6. 产物

- `result.md`；
- 可选：`artifacts/*.png`。

## 7. 通过判据

模拟器能正常运行；每页都有用户的意见，或明确写"无意见"。

## 8. result.md 模板

```markdown
# 20261103-50-ui-pages-review 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| exe 是否正常运行 | |

## 逐页意见（尽量用用户原话；没有意见写"无意见"）
| 页面 | 意见 |
|---|---|
| 首页 | |
| 视觉识别 | |
| 图片识别 | |
| 图像处理 | |
| 图形引擎 | |
| 游戏 | |
| 系统监控 | |
| 芯片信息 | |
| 调试助手 | |
| 整体 / 操作 | |

## 其他问题
```
