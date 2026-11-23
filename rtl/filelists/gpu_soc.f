# GPU SoC; GPU core list is supplied by the GPU integration task.
-f cpu_subsys.f
-f sys_subsys_gpu.f
-f mem_subsys_gpu.f
-f disp_gpu.f
-f aud.f
-f gpu.f
-f eth.f
../common/edrv32_axi256_async_bridge.v
../soc/edrv32_soc_gpu_boundary_gpu.v
../soc/edrv32_gpu_soc_top.v
