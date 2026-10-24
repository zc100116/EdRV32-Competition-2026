+define+EDRV32_TEST_ONE_STAGE_MUL
-s tb_mdu
+incdir+rtl/include
rtl/cpu/datapath/edrv32_full_adder.v
rtl/cpu/datapath/edrv32_adder32.v
rtl/cpu/datapath/edrv32_adder64.v
rtl/cpu/datapath/edrv32_wallace_compress_3to2.v
rtl/cpu/mdu/edrv32_mul_booth4_wallace.v
rtl/cpu/mdu/edrv32_mul_low32_pipe2.v
rtl/cpu/mdu/edrv32_mul_low32_pipe1.v
rtl/cpu/mdu/edrv32_div_nonrestoring.v
rtl/cpu/mdu/edrv32_mdu.v
sim/cases/cpu/mdu/tb_mdu.sv
