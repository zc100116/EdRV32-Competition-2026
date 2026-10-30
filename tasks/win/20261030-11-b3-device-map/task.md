# 任务卡 20261030-11-b3-device-map：导出器件硬块分布、B3V 布局和 APM/DRM 手册（为全局区域规划准备数据）

## 1. 目标

在已经布好的 B3V 工程上导出布局位置和器件坐标对应关系，并从 PDS 安装目录找出 APM、DRM 的用户手册，供 Linux 端做 CPU/NPU/RND/PIX/mem 的全局区域规划。**本卡不综合、不布局布线、不生成 bitstream。**

背景：卡 10 的 B3VN/B3R/B3F 布线 80–100 分钟仍未收敛（APM 61–77%、DRM 64–79%，RND 有大负裕量）。用户决定先停掉这三个工程，先优化 NPU/RND/PIX 的结构和资源，再给大模块统一做区域约束，最后只跑一次。区域约束需要 APM/DRM 列和 IO bank 在 floorplan 坐标中的精确位置，现有资料只到时钟区域级别（`docs/guides/pds-floorplan.md` 1.2、1.3 节，6.1 节 R-W01）。

## 2. 输入

- 分支 `origin/zc100116/b3`（包含本卡的提交）。Windows Codex 从这里拉出 `win/20261030-11-b3-device-map`。
- B3V 工程：卡 10 已经布好的 `G:/codex_project/EdRV32-FPGA/EdRV32-B3V`（实际目录以卡 10 `result.md` 为准），RTL 为 `05088f4b`。**不要重新综合**，直接打开已有的布线结果。
- 参考：`docs/guides/pds-floorplan.md` 4.5 节（导出命令）；PCE 手册第 3.6 节（Properties 中 gate device 显示 `site(x,y)` 和 floorplan `(x,y)`）、4.13 节（PCE Tcl `region -create`）。

## 3. 环境

- PDS 2022.2-SP6.1，PG2L200H-6 FBB676。
- 本卡开始前，卡 10 中 B3VN、B3R、B3F 的 PnR 已经由用户停掉。

## 4. 需要的 IP

无。

## 5. 操作步骤

| 步 | 执行者 | 内容 |
|---|---|---|
| 1 | Windows Codex（C） | 从三个已停工程的 `place_route/run.log` 中各取最后一次迭代的路由进度行（与卡 10 `route_progress.tsv` 同格式），写入 `artifacts/stopped_route_progress.tsv`，并记下停止时间。日志不存在就写"未取得"。 |
| 2 | 用户（GUI） | 打开 B3V 工程，确认 Place & Route 显示已完成；打开 PDS Console。告诉 Codex 工程路径。 |
| 3 | 用户（GUI，Console 中粘贴） | 在 B3V 工程目录下依次执行：<br>`generate_constraint -file {b3v-placement.pcf}`<br>`generate_constraint -file {b3v-apm.pcf} -device {APM}`<br>`generate_constraint -file {b3v-drm.pcf} -device {DRM}`<br>`generate_constraint -file {b3v-placement.fdc} -logic`<br>告诉 Codex 生成文件所在目录。 |
| 4 | 用户（GUI，PCE） | 打开 PCE（Physical Constraint Editor），floorplan view，打开 Properties 窗口（工具栏 Properties 按钮，保持 Automatically update）。逐个点选下面的器件，每个都截图 Properties 页（含 name、site(x,y)、(x,y)）：<br>a. **每一条 APM 列**：列内最下面一个和最上面一个 APM（从左到右逐列，直到最右侧）；<br>b. **每一条 DRM 列**：同上；<br>c. 3 个相距较远的 CLMA，3 个 CLMS；<br>d. 每个 IO bank（L3、L4、L5、L6、R4、R5，以及视图中能看到的其他 bank）各点一个 IO pad。<br>截图文件名用 `pce-<类型>-<序号>.png`，类型为 apm/drm/clma/clms/io，列从左到右编号。另外整体截两张 floorplan view：一张只高亮 APM 和 DRM，一张显示 I/O Banks 和 Clock Region 边界。 |
| 5 | 用户（GUI，PCE Console） | 用 Tcl 建 10 个与时钟区域相同的 region，读每个 region 的 Properties → Statistics（各类资源数量）并截图：<br>`region -in`<br>`region -create cr_x0y0 -value (0,91,0,49)`<br>`region -create cr_x0y1 -value (0,121,50,99)`<br>`region -create cr_x0y2 -value (0,121,100,149)`<br>`region -create cr_x0y3 -value (0,121,150,199)`<br>`region -create cr_x0y4 -value (0,91,200,249)`<br>`region -create cr_x1y0 -value (157,238,0,49)`<br>`region -create cr_x1y1 -value (124,238,50,99)`<br>`region -create cr_x1y2 -value (124,238,100,149)`<br>`region -create cr_x1y3 -value (124,238,150,199)`<br>`region -create cr_x1y4 -value (157,238,200,249)`<br>截图名 `pce-region-<名>.png`。**截图后关闭 PCE，不保存约束**（这些 region 只用来读数，不进入工程）。 |
| 6 | Windows Codex（C） | 在 PDS 安装目录（含其下的 `doc`、`help`、`ipcore`、IP Compiler 文档目录）中查找 Logos2/PG2L 的 APM、DRM 用户手册（文件名或标题含 APM、DRM、算术、存储、Arithmetic、Memory、UG 等），以及 APM/DRM 相关 IP（如乘法器、乘加、SDPRAM）的 IP 说明文档。列出找到的全部文件（完整路径、大小、标题、版本），把 APM 和 DRM 的用户手册各一份及 APM 乘法/乘加 IP 的说明复制到 `artifacts/manuals/`。找不到就写"未找到"并列出查过的目录，**不要从网上下载**。 |
| 7 | Windows Codex（C） | 把步骤 3 的 4 个文件、步骤 4/5 的截图复制到 `artifacts/`。按截图整理 `artifacts/pce_devices.tsv`：`类型	列号	位置(下/上)	name	site_x	site_y	fp_x	fp_y	截图文件`；整理 `artifacts/pce_regions.tsv`：`region	CLMA	CLMS	APM	DRM	其他资源（原样）	截图文件`。数字一律从截图原文抄，看不清的写"未取得"。 |
| 8 | Windows Codex（C） | 填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261030-11-b3-device-map results`，推送 `win/20261030-11-b3-device-map`。 |

## 6. 产物

| 产物 | 内容 | 位置 |
|---|---|---|
| `stopped_route_progress.tsv` | 三个停掉的工程最后一次迭代的进度和停止时间 | `artifacts/` |
| `b3v-placement.pcf`、`b3v-apm.pcf`、`b3v-drm.pcf`、`b3v-placement.fdc` | B3V 布局导出原文（可能数 MB，属必要产物） | `artifacts/` |
| `pce-*.png` | 器件 Properties 截图、两张整体 floorplan 截图、10 张 region 统计截图 | `artifacts/pce/` |
| `pce_devices.tsv`、`pce_regions.tsv` | 截图数字的整理表 | `artifacts/` |
| `manuals/` | APM、DRM 用户手册及 APM IP 说明（PDF 原文） | `artifacts/manuals/` |

## 7. 通过判据

- 4 个导出文件都存在，`b3v-apm.pcf` 中的 APM 实例数为 161，`b3v-drm.pcf` 的 DRM 数与 B3V 资源报告（109）的口径一致或在 `result.md` 中说明差异。
- `pce_devices.tsv` 覆盖视图中全部 APM 列和 DRM 列（每列上下各一项）。
- 10 个 region 的 APM/DRM 统计都已取得，并与 `docs/guides/pds-floorplan.md` 1.2 节的时钟区域表逐项对比（一致或说明差异）。
- APM/DRM 手册：找到则已复制，找不到则列出查过的目录。

## 8. result.md 模板

```markdown
# 20261030-11-b3-device-map 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| B3V 工程路径 | |
| PDS 版本 | |
| 卡 10 三个工程停止时间 | |

## 布局导出
| 文件 | 行数 | 大小 | APM/DRM 实例数 |
|---|---|---|---|

## APM/DRM 列（按 floorplan x 从左到右）
| 类型 | 列号 | fp_x | fp_y 下 | fp_y 上 | site_x | site_y 下 | site_y 上 |
|---|---|---|---|---|---|---|---|

## 时钟区域统计（PCE region）与指南 1.2 节对比
| region | CLMA | CLMS | APM | DRM | 与指南一致？ |
|---|---|---|---|---|---|

## IO bank 位置
| bank | pad | site(x,y) | fp(x,y) |
|---|---|---|---|

## APM/DRM 手册
| 文件 | 完整路径 | 版本/日期 | 是否复制 |
|---|---|---|---|
查过的目录：

## 完整文件在 Windows 本地的路径

## 备注
```
