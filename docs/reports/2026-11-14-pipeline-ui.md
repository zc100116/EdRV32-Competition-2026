# 视觉流水线 UI 验收（2026-11-14）

- 实现提交：`694df475`；已 rebase 到 `zc100116/b3` 的 `ea8d7ed1`。
- 依据：`docs/design/2026-11-14-showcase-vision-pipeline.md` 第 4、7 节。
- 环境：Linux，GCC 13.3.0，Python 3.12.3，仓库锁定的 LVGL 9.6.0。

## 完成内容

- 新增 1280×720 流水线页：8 个预设、来源/HDMI、160×90 缩略图、主画面、
  可滚动参数面板、硬件跳表、端到端延迟、帧率、DDR 带宽条。
- 主画面使用 L0，L1 半透明显示控件；看此级提交 chain.view，来源原图为 0xFE。
- 同一次 PIX 用底色分组、共用输出缩略图；链首标注摄像头融合，入口耗时显示随摄像头帧。
- 支持按键菜单、插入/删除/换功能、参数、检测设置、中文拒绝原因和 PC 图片翻页。
- 首页改为六个应用入口；删除视觉识别、图片识别、图像处理三个旧页面。
- 模拟器实现冻结链接口、合法性拒绝、8 个预设、粗略跳表和各级图像预览。
- 本分支删除接口：`ui_process_config_t`、`ui_data_process_config`、`ui_data_process_set`、
  `ui_data_process_defaults`、`ui_data_process`、全部 `UI_PROC_*`、`UI_APP_IMAGE`、`UI_APP_PROCESS`。
  冻结的 7.2 新声明保持不变，app 值 2、3 保留不用。

## 验证

- 命令：`. ~/.local/opt/edrv32/env.sh` 后 `make -C sw/apps/showcase/sim shots -j1`。
- 结果：退出码 0；UI/模拟器以 C11、`-Wall -Wextra -Werror` 构建，无告警。
- 真实 LVGL keypad 覆盖移动、插入删除、换功能、参数、看此级、预设、原子拒绝与提示；
  同时覆盖检测门槛、PC 翻页、来源原图、空链/满链、长链滚动和 Esc 菜单返回。
- 截图递归检查缺字、标签越界和流水线标签重叠，全部通过；既有其他页面操作测试通过。
- 日志：`build/sim/pipeline-ui-test.log`；`git diff --check` 通过。
- 四张截图：`docs/design/assets/pipeline-{standard,rotation,filter,menu}.png`，均为 1280×720。

## 限制

- 跳耗时、帧率、DDR 为固定模拟数字；检测使用固定框，界面叠加使用示意条。
- 缩略图每 200 ms 刷新；静态照片仅在链内容变化时重算，不代表硬件实测性能。
- 未运行 SoC 仿真、板端构建或上板测试；板端旧实现删除、实际合成及性能由集成与上板验收。
