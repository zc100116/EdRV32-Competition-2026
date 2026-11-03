# 卡46：精简RND v1 B3R实现及上板

代码2acec66c050c4a12f55822e1712babbde2d1f59a；工程G:/codex_project/EdRV32-FPGA/EdRV32-B3R-RND1S；PDS2022.2-SP6.1、PG2L200H-6 FBB676、ADS、94个RTL、18个IP、不插ILA。

## 实现与资源

综合5m04s/峰值2552MB；Map53s/1382MB；PnR29m19s、CPU2m40s/进程CPU4m48s、峰值6576MB；最后第171轮0未布通/0过用。时序及bitstream完成。
完整原文在本地工程compile/synthesize/device_map/place_route/report_timing；精简阶段时间、消息、资源层次、高扇出、首尾拥塞和原生报告gzip见artifacts/R。

| 资源 | 本卡精简RND（综合层次） | 卡43 VRN原版v1（综合层次） | 本卡整机Map |
|---|---:|---:|---:|
| LUT |16877|18145|53233|
| FF |11296|14712|43475|
| APM |68|82|79|
| DRM |58|60|111|

Map另有分布式RAM704、IO109。层次值包含子模块，不能相加。PnR对照卡24为4h21m/639轮，但当前整机/软件/选项等条件不全部相同，不将改善全部归因于RND裁剪。

慢角setup全部满足：clk_mem最差+0.220ns、clk_sys+0.759ns。慢角hold已知RGMII输入例外-0.361ns、THS-1.698ns/5端点；其他域slow/fast和recovery/removal见artifacts/R/timing_summary.txt，详细违例及正裕度路径一并保留。

## 上板

- rnd_board.elf：10/10 CRC匹配卡46期望日志，10次ERR_CODE=0，RND display ready。HDMI上下两排、每排五组与精简版要求相符。原文、逐项比较和照片见artifacts/uart、photos。
- showcase-test.elf：已进入启动器、组件、benchmark、图层、NES及系统状态。未将“能进入”替代所有功能验收；NES移动/跳跃、满60秒及两级退出未取得用户逐项确认。
- NES串口近期模拟约51fps、显示约41～45fps、CPU97%，完整采样原文在showcase_session_snapshot.log；非固定60秒同条件统计结论。
- benchmark各场景及average fps=0；同时CPU行GUI fps有非零值。保存原始split及CPU会话，不将官方字段0当作真实零帧率。
- 本轮网口加载信息见会话原文，不补写未取得的eth_diag五轮诊断数据。

## 软件问题与用户反馈（请求Claude重建）

1. 用户认为启动器首界面不美观，要求改善；保留照片。
2. 源码lv_conf.h明确LV_USE_PERF_MONITOR=0，性能monitor关闭；用户希望开启。benchmark官方fps为0需同时检查统计配置。
3. 启动器和系统状态页部分中文显示方框；标题及部分字正常。优先怀疑默认中文字库覆盖/fallback配置，未逐字核验cmap，不宣称编码问题已定位。
4. 组件示例肉眼偏黄，记录为显示颜色异常待查，照片不能排除显示器或拍摄白平衡因素。
5. 图层示例首屏红色左上区域存在局部蓝紫竖条，记录用户实际观察及照片，未归因为摩尔纹、未确认硬件或软件根因。
6. 系统状态照片文字缺字；可见CPU通信3%、应用0%、GUI1%、空闲95%、GUI0fps、link UP、RX3707/TX16570、串口115199。

完整问题记录见artifacts/showcase_issues.md。图片只作现场现象证据，不能当作逐像素正确性验证。

## 工程准备偏离

初次仅复制IP并删减PDS结构，被用户反馈打不开；后已改完整复制原B3R工程目录，保留原PDS流程结构，更新源列表及初始化配置并清零旧流程状态。本卡报告取本次用户实际运行的结果。未自行启动实现流程。

## 时序与性能原文补充

从本卡已完成pnr.adf只读补导 -delay_type min_max -max_path 200 -nworst 1 -input_pins TRUE 成功，未运行实现流程；扩展原生RTR以gzip回传供多路径复核，数量覆盖见artifacts/R/timing_coverage.txt，另有危险正裕度列表。CPU/NES各行已提取artifacts/cpu.csv，场景和split原文见benchmark.txt。原生完整报告保存在本地工程目录，本次不上传数据库、bitstream或IP。
