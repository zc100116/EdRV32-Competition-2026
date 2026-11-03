# showcase现场反馈（测试进行中）

- 用户认为启动器首界面不美观，要求后续改善设计。照片：photos/showcase_launcher.jpg。
- LVGL性能monitor未显示。源码sw/apps/showcase/lvgl/lv_conf.h设置LV_USE_PERF_MONITOR=0、LV_USE_PERF_MONITOR_LOG_MODE=0，属于配置关闭。
- 启动器部分中文及符号显示方框；大标题、应用标题和部分汉字正常。源码字符串为可读中文，默认使用source_han_sans_sc_16_cjk，标题使用自定义中文子集。现象优先指向字库覆盖不足或字体fallback配置；尚未逐字核验字体cmap，不认定已确认根因。
- 用户反馈组件示例整体偏黄，照片photos/showcase_widgets.jpg。照片不足以区分渲染颜色、显示器色温及拍摄白平衡；记录为待查，尚未确认根因。
- 串口快照：uart/showcase_session_snapshot.log，已保存2112条工具会话记录（含本轮之前的操作），截至seq2112。
- 日志已出现benchmark全部场景和average fps=0，同时运行过程Showcase CPU行有非零GUI fps（例如13、10、7）。这组benchmark官方fps字段不能作为真实零帧率结论；保留原文及split统计，后续由Linux协调者排查计数配置。
- 下一步：图层示例进入/退出；NES试玩60秒、两级退出；系统状态页拍照。不得把这些未完成项目写为通过。

## 图层与系统状态补充

- 用户反馈图层示例第一个画面左上区域有竖条；照片中红色区有局部蓝紫竖线，记录为显示异常待定位，未归因为拍摄摩尔纹。照片：photos/showcase_layers_stripes.jpg。
- 系统状态页同样有中文缺字方框。照片：photos/showcase_status_missing_glyphs.jpg。页面可见通信CPU3%、应用0%、GUI1%、空闲95%、GUI0fps；link UP；RX3707、TX16570；串口显示115199。PEER文字含缺字，不能仅据照片完整转录。
- 最新串口快照已更新；NES完整60秒及两级退出是否完成尚待用户确认。
