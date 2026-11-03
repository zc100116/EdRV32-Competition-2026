# 卡51：F CPU125MHz上板结果

| 项 | 内容 |
|---|---|
| 代码 commit | ff96efc918694eb0dae28aced0fcb447739f8b65 |
| 比特流 | 卡48归档EdRV32-F-cpu125m.sbit，来源origin/win/20261103-48-vrn-f-rnd1slim:fpga/bitstreams/EdRV32-F-cpu125m.sbit；本次下载副本G:/codex_project/EdRV32-Competition-2026/build/board/card51/EdRV32-F-cpu125m.sbit |
| CLK_SYS_HZ | 启动及应用串口均125000000；MEM_READY=1；I/D-cache各8192B |
| 连接 | COM7@115200，PC192.168.1.2:6000，板192.168.1.10:5000，应用PEER一致 |
| 整体结论 | 用户报告其他功能正常、除此前已知缺陷；demo_npu图片检测未通过。基本运行已有证据，但卡要求的三次重复/完整长时稳定性没有全部原文，不能判定完整稳定性验收通过 |

## 卡48 F列项目

| 项目 | 结果 | 关键数字/证据 |
|---|---|---|
| 5.0 BIOS / 网口 | 启动正常、网口加载PASS；5轮接收验收未取得 | 会话含eth_diag、PHY千兆全双工及应用加载；只见一次r发送，没有5组各10秒PERF1/PERF3配对，不写5/5 |
| 5N NPU自检 | 一次完整39/39通过 | C-YOLO PERF0=6105103，MAC5347440，40.700ms/frame，24.569fps，CRC32=0738f96e；D01～D20全部PASS同CRC |
| 5E 图片检测 | **未通过** | 模型EDNM: loaded；3次猫图上传后均先超时1s，后收到detections=2。用户换图后工具仍显示猫图，发送路径也仍为cat_000000015497.jpg，见下文 |
| 5R RND CRC | **10/10匹配** | 各ERR_CODE=0，RND display ready；逐项见rnd_crc_check.txt；用户反馈画面正常，已知缺陷除外 |
| 5R showcase benchmark | 全部场景运行完，官方fps字段存在已知计数问题 | 官方average fps=0；ALL split frames1470，render33.201ms、rnd6.415ms、sw9.151ms、other17.634ms；全部场景及split保留benchmark.txt |
| 5R NES / 图层 | 用户反馈正常、除已知缺陷 | NES仅5条性能采样：模拟均58.920fps，显示均38.940fps；范围见下文。LAYERS4及返回启动器有记录；没有把此前已知蓝紫竖条记为已经修复 |
| 5C CoreMark | 一次菜单启动通过 | 5000迭代，两轮内部HPM采集CRC均PASS，最终CoreMark result PASS，450.408 iterations/sec、3.603 CoreMark/MHz |
| 5F 图像/几何处理 | 用户反馈模式切换正常 | demo_vision、两路OV5640 ID0x5640、PIX/GEO设置命令及output both有原文，status CH0 overflow=0 |
| 5VN 摄像头识别 | 用户反馈正常、除既有缺陷 | demo_vnpu模型已加载；两次status推理次数56→590，第二次NPU6193989周期、post2903484周期、3框、overlay1412325周期，CH0/CH2 overflow=0，Video skips=0，Monitor dropped records=0 |
| 5VN 批量40张 / 停止后单张 / 3次图片摄像头切换 | 用户总体反馈正常；逐项协议记录未取得 | 最终会话未见40张完整队列、停止后单张及3次camera命令/恢复记录，不填写40/40或3/3 |

## 稳定性证据范围

用户在被询问RND画面、NES约5分钟、PIX/GEO切换、摄像头识别约15分钟及图片/摄像头切换后，回答：“正常，除了这些程序之前测试过的已知缺陷”。保留该主观实测结论；下表将串口可证明的部分分开。

| 测试 | 卡要求 | 已保存原文 | 结论 |
|---|---|---|---|
| board_npu | 完整3次，每次39/39及D20CRC一致 | 1次39/39、D组20帧 | 本次通过；另2次原文未取得，不判3/3 |
| CoreMark | 5000迭代重复3次 | 1次菜单启动、内部两轮CRC PASS | 本次通过；内部两轮不算两次稳定性测试；另2次原文未取得 |
| 摄像头识别 | 连续15分钟、每5分钟status | 用户反馈正常；2次status及遥测快照 | 连续15分钟无异常的完整记录未取得，不宣称日志验证通过 |
| showcase benchmark | 完整1遍 | ALL及全部场景结束输出 | 已完成，官方fps统计错误单列 |
| NES | 运行5分钟 | 用户反馈正常；5条fps日志 | 画面/操作按用户反馈记录；完整5分钟性能序列未取得 |

NES5条采样：模拟58.7～59.1fps、显示36.4～41.3fps，CPU93～103%。103%是日志中的异常统计值，保留原文，不当作可信的物理CPU占用。均值仅针对这5条，不能当5分钟平均。

CoreMark参考CRC seed=e9f5、list=e714、matrix=1fd7、state=8e3a均PASS，两轮CRC final均bd59；final仅记录值，不添加不存在的固定CRC验收值。比分取实际串口，不以CPU100MHz结果换算。

## demo_npu已知/复现问题

详细事实和源码线索见artifacts/demo_npu_no_boxes.md、uart/demo_npu_no_boxes.log。

1. 模型已上传3247136B并打印EDNM: loaded，因此这次不是此前漏传模型的情况。
2. 单张图片每次1843200B发送完成后，工具先报“回传未结束（超时1s）”；随后板端分别打印frame_id0/1/2、detections=2，PERF0=6117993/6121432/6122116。板端推理完成不等于GUI完整回传通过。
3. 首次上传完成到板端打印约3.190秒；其中工具先超时约2.158秒后才出现检测日志。NPU核心仅约40.8ms，不能把3.190秒全部归为NPU计算时间。
4. 工具超时会清空capture、取消接收并更新epoch，旧epoch回传被丢弃，界面没有完整capture就不绘制框。这解释无框现象；为什么完整返回迟于超时仍需定位。
5. 用户原话：“我第一次发送的时猫咪图片，工具上只显示没框的猫咪，但是我换了一个图片后，工具仍显示猫咪”。实际三次UDP发送路径仍是猫图，提示文件选择、预览、发送源状态可能未同步；尚未确认具体根因，不能将新图显示记为成功。
6. 本次没有RGB565 image length或DEMO stopped原文；不要将卡45的另一种错误硬套成本次实际报错。没有修改工具超时、程序、RTL或PHY延迟。

## 日志、遥测和缺失资料

- uart/final_session_snapshot.log含本次工具buffer seq1～1989，覆盖当前采集会话；先前boot和中途快照也保留。CoreMark/NPU/网口/视频/showcase另有摘录，完整会话为权威原文。NPU D08行被ETH peer打印插入，PERF字段分段，不能据摘录误判CRC失败。
- benchmark.txt保存官方场景fps、split及RND分类计数；cpu_nes.csv为逐条采样。ALL split的render_ms是该统计口径下的每帧时间，不将1000/render_ms直接命名为官方benchmark平均fps。
- edtm_final.csv为30832条type1记录、约7.77MB，保留完整会话遥测供Claude复核带宽/拥塞。场景0有5136行、场景1有25696行；它没有host timestamp列，不能把所有行都归为单一程序或直接证明15分钟识别。覆盖说明见telemetry_coverage.txt。
- tool/保存最终串口、网口、烧录状态；它们只代表最终快照，不代替每次加载过程。
- 本轮未取得新HDMI照片，不复制其他比特流的照片充当本次证据。
- 归档硬件仍有CPU -0.033ns、NPU -0.120ns、mem -0.010ns setup违例，RGMII hold -0.242ns；本次基本功能正常不等于时序违例已消除。完整实现报告在卡48结果分支。

## 给Claude的后续事项

优先检查demo_npu回传事务和工具文件选择/发送状态同步；同时沿用已记录showcase官方fps计数、中文字体、颜色/图层等已知软件问题的修复计划。三次重复与长时稳定性证据不足的项目不要标为全部通过。本卡未修改实现流程和板端代码。
