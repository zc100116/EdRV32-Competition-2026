# NPU 参考模型

`ref/npu_ref.py` 是 NPU 的逐层参考模型，`yolo_post_ref.py` 是 YOLOv8n 后处理的参考实现。调试工具在“运行参考模型并比对”功能中调用它们，与板端的识别结果逐项比对。

NPU 的行为见 [NPU 规格](../../docs/spec/npu-spec.md)。
