`timescale 1ns/1ps
// Simulation-only PLL and input buffer models for the YOLO DDR board top.
module yolo_pll(output wire clkout0, output wire lock, input wire clkin1);
    reg sim_clk_r = 1'b0;
    always #3.333 sim_clk_r = !sim_clk_r;
    assign clkout0 = sim_clk_r;
    assign lock = 1'b1;
endmodule
module GTP_INBUFDS(output wire O, input wire I, input wire IB);
    assign O = I;
endmodule
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
    reg [5:0] init_count_r = 6'd0;
    wire unused_rerror_w;
    wire [31:0] unused_write_count_w;
    wire [31:0] unused_read_count_w;
    always @(posedge ref_clk or negedge resetn) begin
        if (!resetn) init_count_r <= 6'd0;
        else if (init_count_r != 6'd20) init_count_r <= init_count_r + 6'd1;
    end
    assign core_clk = ref_clk;
    assign pll_lock = resetn;
    assign phy_pll_lock = resetn;
    assign gpll_lock = resetn;
    assign rst_gpll_lock = resetn;
    assign ddrphy_cpd_lock = resetn;
    assign ddr_init_done = init_count_r == 6'd20;
    pango_ddr_ui_model #(.MEMORY_LINES(8192), .RANDOM_STALL(1)) u_ui_model (
        .clk_i(core_clk), .rst_n_i(resetn), .init_done_i(ddr_init_done),
        .awvalid_i(axi_awvalid), .awready_o(axi_awready),
        .awaddr_i(axi_awaddr), .awlen_i(axi_awlen), .awid_i(axi_awuser_id),
        .wdata_i(axi_wdata), .wstrb_i(axi_wstrb),
        .wready_o(axi_wready), .wusero_id_o(axi_wusero_id),
        .wusero_last_o(axi_wusero_last),
        .arvalid_i(axi_arvalid), .arready_o(axi_arready),
        .araddr_i(axi_araddr), .arlen_i(axi_arlen), .arid_i(axi_aruser_id),
        .rvalid_o(axi_rvalid), .rdata_o(axi_rdata),
        .rid_o(axi_rid), .rlast_o(axi_rlast), .rerror_o(unused_rerror_w),
        .write_count_o(unused_write_count_w),
        .read_count_o(unused_read_count_w)
    );
    assign apb_ready = 1'b0;
    assign apb_rdata = 16'd0;
    assign mem_cs_n = 1'b1;
    assign mem_rst_n = resetn;
    assign mem_ck = 1'b0;
    assign mem_ck_n = 1'b1;
    assign mem_cke = 1'b0;
    assign mem_ras_n = 1'b1;
    assign mem_cas_n = 1'b1;
    assign mem_we_n = 1'b1;
    assign mem_odt = 1'b0;
    assign mem_a = {MEM_ROW_WIDTH{1'b0}};
    assign mem_ba = {MEM_BANK_WIDTH{1'b0}};
    assign mem_dqs = {MEM_DQS_WIDTH{1'bz}};
    assign mem_dqs_n = {MEM_DQS_WIDTH{1'bz}};
    assign mem_dq = {MEM_DQ_WIDTH{1'bz}};
    assign mem_dm = {MEM_DM_WIDTH{1'b0}};
    assign debug_calib_ctrl = 34'd0;
    assign dbg_slice_status = {17*MEM_DQS_WIDTH{1'b0}};
    assign dbg_slice_state = {22*MEM_DQS_WIDTH{1'b0}};
    assign debug_data = {69*MEM_DQS_WIDTH{1'b0}};
    assign dbg_dll_upd_state = 2'd0;
    assign debug_gpll_dps_phase = 9'd0;
    assign dbg_rst_dps_state = 3'd0;
    assign dbg_tran_err_rst_cnt = 6'd0;
`ifdef TEST_PHY_TRANSIENT
    assign dbg_ddrphy_init_fail = init_count_r >= 6'd5 &&
                                   init_count_r <= 6'd10;
`else
    assign dbg_ddrphy_init_fail = 1'b0;
`endif
    assign debug_dps_cnt_dir0 = 10'd0;
    assign debug_dps_cnt_dir1 = 10'd0;
    assign ck_dly_set_bin = 8'd0;
`ifdef TEST_PHY_TRANSIENT
    assign align_error = init_count_r == 6'd12;
`elsif TEST_PHY_POST_ERROR
    assign align_error = init_count_r == 6'd20;
`else
    assign align_error = 1'b0;
`endif
    assign debug_rst_state = 4'd0;
    assign debug_cpd_state = 4'd0;
endmodule
