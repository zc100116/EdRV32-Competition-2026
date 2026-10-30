# 任务卡 20261030-11-b3-device-map：导出器件硬块分布、B3V 布局和 APM/DRM 手册（为全局区域规划准备数据）

## 1. 目标

在已经布好的 B3V 工程上导出布局位置和器件坐标对应关系，并从 PDS 安装目录找出 APM、DRM 的用户手册，供 Linux 端做 CPU/NPU/RND/PIX/mem 的全局区域规划。**本卡不综合、不布局布线、不生成 bitstream。**

背景：卡 10 的 B3VN/B3R/B3F 布线 80–100 分钟仍未收敛（APM 61–77%、DRM 64–79%，RND 有大负裕量）。用户决定先停掉这三个工程，先优化 NPU/RND/PIX 的结构和资源，再给大模块统一做区域约束，最后只跑一次。区域约束需要 APM/DRM 列和 IO 在 floorplan 坐标中的精确位置（IO 和已用 APM/DRM 的站点由布局导出给出，本卡只补站点 ↔ floorplan 坐标的换算样点），现有资料只到时钟区域级别（`docs/guides/pds-floorplan.md` 1.2、1.3 节，6.1 节 R-W01）。

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
| 4 | 用户（GUI，PCE） | 打开 PCE（Physical Constraint Editor），floorplan view，打开 Properties 窗口（工具栏 Properties 按钮，保持 Automatically update）。只点 **6 个器件**，每个截一张 Properties 页（要能看到 name、site(x,y)、(x,y) 三项）：<br>a. 芯片**左下角附近**的一个 APM 和**右上角附近**的一个 APM；<br>b. 左下、右上附近的 DRM 各一个；<br>c. 左下、右上附近的 CLMA 各一个。<br>不必是空闲器件，已占用的也可以。截图名 `pce-<apm/drm/clma>-<ll/ur>.png`。<br>用途：B3V 布局导出中已有全部已用 APM/DRM 的站点名，Linux 端用这 6 个样点拟合"站点坐标 ↔ floorplan 坐标"的换算，不需要逐列点选。 |
| 5 | 用户（GUI，PCE Console） | 建 1 个与时钟区域 X1,Y2 相同的 region，截它的 Properties → Statistics（各类资源数量）：<br>`region -in`<br>`region -create cr_x1y2 -value (124,238,100,149)`<br>截图名 `pce-region-cr_x1y2.png`。用途：确认 region 坐标与 `docs/guides/pds-floorplan.md` 1.2 节的时钟区域表是同一套坐标（该区应为 APM 100、DRM 50）。**截图后关闭 PCE，不保存约束。** |
| 6 | Windows Codex（C） | 在 PDS 安装目录（含其下的 `doc`、`help`、`ipcore`、IP Compiler 文档目录）中查找 Logos2/PG2L 的 APM、DRM 用户手册（文件名或标题含 APM、DRM、算术、存储、Arithmetic、Memory、UG 等），以及 APM/DRM 相关 IP（如乘法器、乘加、SDPRAM）的 IP 说明文档。列出找到的全部文件（完整路径、大小、标题、版本），把 APM 和 DRM 的用户手册各一份及 APM 乘法/乘加 IP 的说明复制到 `artifacts/manuals/`。找不到就写"未找到"并列出查过的目录，**不要从网上下载**。 |
| 7 | Windows Codex（C） | 把步骤 3 的 4 个文件、步骤 4/5 的截图复制到 `artifacts/`。按截图整理 `artifacts/pce_devices.tsv`：`类型	位置(ll/ur)	name	site_x	site_y	fp_x	fp_y	截图文件`；把 region 统计原样抄进 `result.md`。数字一律从截图原文抄，看不清的写"未取得"。 |
| 8 | Windows Codex（C） | 填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261030-11-b3-device-map results`，推送 `win/20261030-11-b3-device-map`。 |

## 6. 产物

| 产物 | 内容 | 位置 |
|---|---|---|
| `stopped_route_progress.tsv` | 三个停掉的工程最后一次迭代的进度和停止时间 | `artifacts/` |
| `b3v-placement.pcf`、`b3v-apm.pcf`、`b3v-drm.pcf`、`b3v-placement.fdc` | B3V 布局导出原文（可能数 MB，属必要产物） | `artifacts/` |
| `pce-*.png` | 6 张器件 Properties 截图、1 张 region 统计截图 | `artifacts/pce/` |
| `pce_devices.tsv` | 6 个样点的整理表 | `artifacts/` |
| `manuals/` | APM、DRM 用户手册及 APM IP 说明（PDF 原文） | `artifacts/manuals/` |

## 7. 通过判据

- 4 个导出文件都存在，`b3v-apm.pcf` 中的 APM 实例数为 161，`b3v-drm.pcf` 的 DRM 数与 B3V 资源报告（109）的口径一致或在 `result.md` 中说明差异。
- `pce_devices.tsv` 有 6 个样点，每个都有 site(x,y) 和 (x,y)。
- cr_x1y2 的统计已取得，并与指南 1.2 节的 X1,Y2 行对比（一致或说明差异）。
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

## 坐标样点
| 类型 | 位置 | name | site(x,y) | fp(x,y) |
|---|---|---|---|---|

## region cr_x1y2 统计与指南 1.2 节对比
| CLMA | CLMS | APM | DRM | 与指南一致？ |
|---|---|---|---|---|

## APM/DRM 手册
| 文件 | 完整路径 | 版本/日期 | 是否复制 |
|---|---|---|---|
查过的目录：

## 完整文件在 Windows 本地的路径

## 备注
```

## 9. 补充（2026-10-30，看过 87b5a6af 之后）

布局导出已经足够，不用重做。还缺下面三项，其中用户只需做 A 和 B（都在 PCE 的 Tcl Console 里输入命令，不用在图上找器件）。

**A. 坐标换算样点（用户，5 张截图）。** 已有 `APM_65_120 → site(18,22)` 一个样点。在 PCE Console 中逐条输入下面的命令，每条执行后 Properties 会切到该器件，截图（要看得到 name、site(x,y)、(x,y)）：

```
select -dev_instance CLMA_21_486
select -dev_instance CLMA_717_1225
select -dev_instance DRM_226_366
select -dev_instance DRM_694_732
select -dev_instance APM_587_1008
```

截图名 `pce-<器件名>.png`。

**B. 未占用列探测（用户，不用截图）。** B3V 只占用了 7 条 APM 列（名称 x = 65、161、311、413、461、527、587）和 8 条 DRM 列（226、280、334、436、490、550、622、694）。CLMA 名称 x 序列在 33/39、135/141、357、657 附近有空缺，可能还有未被使用的 APM/DRM 列。逐条输入下面的命令，只记录每条是"选中了器件"还是"报错"（报错原文抄一条即可）：

```
select -dev_instance APM_33_582
select -dev_instance APM_39_582
select -dev_instance APM_135_582
select -dev_instance APM_141_582
select -dev_instance APM_357_582
select -dev_instance APM_657_582
select -dev_instance DRM_33_582
select -dev_instance DRM_39_582
select -dev_instance DRM_135_582
select -dev_instance DRM_141_582
select -dev_instance DRM_357_582
select -dev_instance DRM_657_582
```

如果 Windows Codex 在 PDS 安装目录的器件架构数据中找到了 PG2L200H 的完整站点列表（含 APM/DRM 全部站点名），B 可以不做，改为提交该列表（只提交 APM、DRM、IO 和时钟区域相关部分）。

**C. 原卡未完成的项目（Windows Codex）。** 第 5 步的 region 统计截图（用户 1 张）、第 6 步的手册查找、第 1 步的停止进度。

APM 155 与 161 的差异不影响区域规划，在 `result.md` 中保留"未查明"即可，不需要追查。
