# 卡25软件复测：N连接故障与R的S3性能补测

- 工作分支：win/20261101-25-b3-sw；任务输入78e5a3de。
- 沿用卡23比特流，不重新综合或生成IP。
- 本次先回传N应用网口连接失败；卡25其余项目不据此标为完成。

## B3N

串口加载新版demo_npu.bin成功，Load result: PASS、Run: 0x10000000，程序打印网络初始化端点。工具发送连接请求后未取得PEER。源地址绑定ARP返回SendARP error 67，PC邻居为Unreachable；PC有线地址192.168.1.2/24、1Gbps，到板子的选中路由走有线if5。

用户重新下载卡23 N比特流并重新加载程序后仍未连接；工具历史10690包计数没有增加。之前模型发送没有EDNM: loaded确认，不能视为模型加载成功。单张/批量图片复测及BIOS网口诊断未完成，不填成功数或fps。

完整两次状态、串口缓冲及最新网络信息见 [N连接失败报告](artifacts/b3n/network_unreachable/result.md)。Clash/TUN按用户要求保持开启，未修改网络配置；无抓包，根因尚未确定。本轮没有修改RTL、软件或工具。

## 其他工程

2026-11-01补测R的S3：串口ELF加载PASS；取得完整16场景Benchmark Summary，全部fps非零，程序汇总平均25fps；Widgets demo 16fps，最慢Containers with opa_layer 3fps。保存17条LVGL split（含ALL）全部性能字段和完整239条工具日志。RN-17有一条汇总PASS，LAYERS 5 claimed=9/unclaimed=0；无EDTM样本及本轮照片，不据此宣称全部视觉和交互验收通过。详见[S3性能补测报告](artifacts/b3r/s3_supplement/result.md)。V复测结果未收集，本报告不宣称卡25整体验收通过。
