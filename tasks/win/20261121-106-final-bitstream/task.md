# 卡 106：回传决赛比特流，放入正式版

## 1. 目标

把决赛演示用的比特流（卡 75 生成）提交到结果分支，由协调者放进 main 的 `发布/`（`m2-final-release`）。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | 用 `git log -1 --format=%H origin/zc100116/b3 -- tasks/win/20261121-106-final-bitstream` 找到本卡的提交，从它拉出 `win/20261121-106-final-bitstream` |
| 比特流 | 卡 75 结果中记录的文件：`G:/codex_project/EdRV32-FPGA/EdRV32-B3F-POST/generate_bitstream/edrv32_fpga_board_full_top.sbit`，9,188,552 字节 |

## 3. 环境、IP

不需要 PDS 运行，不需要 IP。

## 4. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | C | 按第 2 节拉分支 |
| 1 | C | 确认比特流文件存在、大小为 9,188,552 字节；不是这个大小就停下来问用户 |
| 2 | C | 复制到 `tasks/win/20261121-106-final-bitstream/artifacts/edrv32_fpga_board_full_top.sbit` |
| 3 | C | 填写 result.md，提交 `win: 20261121-106-final-bitstream results`，推送分支 |

## 5. 产物

`artifacts/edrv32_fpga_board_full_top.sbit`。本卡是例外：比特流需要入库。

## 6. 通过判据

文件大小为 9,188,552 字节。

## 7. result.md 模板

```markdown
# 卡 106 结果

| 项 | 内容 |
|---|---|
| 分支 HEAD | |
| 比特流原路径 | |
| 文件大小（字节） | |
| 文件修改时间 | |
```
