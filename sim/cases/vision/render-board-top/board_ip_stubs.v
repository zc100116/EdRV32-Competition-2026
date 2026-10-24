module ddr #(
 
   parameter MEM_ROW_WIDTH       = 15          ,
    
   parameter MEM_COLUMN_WIDTH    = 10          ,
   
   parameter MEM_BANK_WIDTH      = 3           ,
  
  parameter MEM_DQ_WIDTH         =  32         ,
  
  parameter MEM_DM_WIDTH         =  4         ,
  
  parameter MEM_DQS_WIDTH        =  4         ,
   
   parameter CTRL_ADDR_WIDTH     = MEM_ROW_WIDTH + MEM_COLUMN_WIDTH + MEM_BANK_WIDTH        
  )(                                                              
   input                              ref_clk                       ,    
   input                              resetn                        ,            
   output                             core_clk                      ,            
   output                             pll_lock                      ,    
   output                             phy_pll_lock                  ,
   output                             gpll_lock                     ,        
   output                             rst_gpll_lock                 ,            
   output                             ddrphy_cpd_lock               ,      
   output                             ddr_init_done                 ,            

   input  [CTRL_ADDR_WIDTH-1:0]       axi_awaddr                    ,
   input                              axi_awuser_ap                 ,
   input  [3:0]                       axi_awuser_id                 ,
   input  [3:0]                       axi_awlen                     ,
   output                             axi_awready                   ,
   input                              axi_awvalid                   ,

   input  [8*MEM_DQ_WIDTH-1:0]        axi_wdata                     ,
   input  [MEM_DQ_WIDTH-1:0]          axi_wstrb                     ,
   output                             axi_wready                    ,
   output [3:0]                       axi_wusero_id                 ,
   output                             axi_wusero_last               ,

   input  [CTRL_ADDR_WIDTH-1:0]       axi_araddr                    ,
   input                              axi_aruser_ap                 ,
   input  [3:0]                       axi_aruser_id                 ,
   input  [3:0]                       axi_arlen                     ,
   output                             axi_arready                   ,
   input                              axi_arvalid                   ,

   output [8*MEM_DQ_WIDTH-1:0]        axi_rdata                     ,
   output [3:0]                       axi_rid                       ,
   output                             axi_rlast                     ,
   output                             axi_rvalid                    ,

   input                              apb_clk                       ,
   input                              apb_rst_n                     ,
   input                              apb_sel                       ,
   input                              apb_enable                    ,
   input  [7:0]                       apb_addr                      ,
   input                              apb_write                     ,
   output                             apb_ready                     ,
   input  [15:0]                      apb_wdata                     ,
   output [15:0]                      apb_rdata                     ,


   output                             mem_cs_n                      ,

   output                             mem_rst_n                     ,                       
   output                             mem_ck                        ,
   output                             mem_ck_n                      ,
   output                             mem_cke                       ,
   output                             mem_ras_n                     ,
   output                             mem_cas_n                     ,
   output                             mem_we_n                      , 
   output                             mem_odt                       ,
   output [MEM_ROW_WIDTH-1:0]         mem_a                         ,   
   output [MEM_BANK_WIDTH-1:0]        mem_ba                        ,   
   inout  [MEM_DQS_WIDTH-1:0]         mem_dqs                       ,
   inout  [MEM_DQS_WIDTH-1:0]         mem_dqs_n                     ,
   inout  [MEM_DQ_WIDTH-1:0]          mem_dq                        ,
   output [MEM_DM_WIDTH-1:0]          mem_dm                        , 

   //debug
   input                              dbg_gate_start                ,
   input                              dbg_cpd_start                 ,
   input                              dbg_ddrphy_rst_n              ,
   input                              dbg_gpll_scan_rst             ,

   input                              samp_position_dyn_adj         ,
   input  [8*MEM_DQS_WIDTH-1:0]       init_samp_position_even       ,
   input  [8*MEM_DQS_WIDTH-1:0]       init_samp_position_odd        ,

   input                              wrcal_position_dyn_adj        ,
   input  [8*MEM_DQS_WIDTH-1:0]       init_wrcal_position           ,
 
   input                              force_read_clk_ctrl           ,
   input  [4*MEM_DQS_WIDTH-1:0]       init_slip_step                ,  
   input  [3*MEM_DQS_WIDTH-1:0]       init_read_clk_ctrl            ,

   output [33:0]                      debug_calib_ctrl              ,
   output [17*MEM_DQS_WIDTH -1:0]     dbg_slice_status              ,
   output [22*MEM_DQS_WIDTH -1:0]     dbg_slice_state               ,
   output [69*MEM_DQS_WIDTH -1:0]     debug_data                    ,
   output [1:0]                       dbg_dll_upd_state             ,
   output [8:0]                       debug_gpll_dps_phase          ,
   
   output [2:0]                       dbg_rst_dps_state             ,
   output [5:0]                       dbg_tran_err_rst_cnt          ,
   output                             dbg_ddrphy_init_fail          , 
   
   input                              debug_cpd_offset_adj          ,
   input                              debug_cpd_offset_dir          ,
   input  [9:0]                       debug_cpd_offset              ,  
   output [9:0]                       debug_dps_cnt_dir0            , 
   output [9:0]                       debug_dps_cnt_dir1            ,

   input                              ck_dly_en                     ,
   input  [7:0]                       init_ck_dly_step              ,
   output [7:0]                       ck_dly_set_bin                ,
  
   output                             align_error                   ,
   output [3:0]                       debug_rst_state               ,
   output [3:0]                       debug_cpd_state               
);
endmodule
module hdmi_pll (
    
    output wire clkout0,
    
    output wire clkout1,
    
    input wire clkin1,
    
    output wire lock           
    );
endmodule
module pll0 (
    
    output wire clkout0,
    
    input wire clkin1,
    
    output wire lock           
    );
endmodule
module GTP_INBUFDS(output wire O, input wire I, input wire IB); assign O = I; endmodule
module GTP_OUTBUFDS #(parameter IOSTANDARD = "TMDS") (
    output wire O, output wire OB, input wire I
);
    assign O = I;
    assign OB = ~I;
endmodule
module GTP_OSERDES_E2 #(
    parameter GRS_EN = "TRUE", OSERDES_MODE = "DDR10TO1",
    TSERDES_EN = "FALSE", UPD0_SHIFT_EN = "FALSE",
    UPD1_SHIFT_EN = "FALSE", INIT_SET = 2'b00,
    GRS_TYPE_DQ = "RESET", LRS_TYPE_DQ0 = "ASYNC_RESET",
    LRS_TYPE_DQ1 = "ASYNC_RESET", LRS_TYPE_DQ2 = "ASYNC_RESET",
    LRS_TYPE_DQ3 = "ASYNC_RESET", GRS_TYPE_TQ = "RESET",
    LRS_TYPE_TQ0 = "ASYNC_RESET", LRS_TYPE_TQ1 = "ASYNC_RESET",
    LRS_TYPE_TQ2 = "ASYNC_RESET", LRS_TYPE_TQ3 = "ASYNC_RESET",
    TRI_EN = "FALSE", TBYTE_EN = "FALSE", MIPI_EN = "FALSE",
    OCASCADE_EN = "FALSE"
) (
    input wire RST, OCE, TCE, OCLKDIV, SERCLK, OCLK,
    input wire MIPI_CTRL, UPD0_SHIFT, UPD1_SHIFT,
    input wire OSHIFTIN0, OSHIFTIN1,
    input wire [7:0] DI,
    input wire TI, TBYTE_IN,
    output wire OSHIFTOUT0, OSHIFTOUT1, DO, TQ
);
endmodule
module hdmi_fifo (
    input wire wr_clk, wr_rst, wr_en,
    input wire [255:0] wr_data,
    output wire wr_full,
    output wire [9:0] wr_water_level,
    input wire rd_clk, rd_rst, rd_en,
    output wire [255:0] rd_data,
    output wire almost_full, rd_empty,
    output wire [9:0] rd_water_level,
    output wire almost_empty
);
endmodule
module render_fifo_ram (
    input wire [255:0] wr_data,
    input wire [5:0] wr_addr,
    input wire wr_en, wr_clk, wr_rst,
    input wire [5:0] rd_addr,
    output wire [255:0] rd_data,
    input wire rd_clk, rd_clk_en, rd_rst
);
endmodule
