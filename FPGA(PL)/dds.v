module  dds
#(
    // parameter TRIMAX = 24'd65536,
    parameter F1_WORD = 32'd4194,
    parameter F2_WORD = 32'd16,
    parameter P1_WORD = 14'd12288,
    parameter P2_WORD = 14'd0
)
(
    input   wire    sys_clk,     //100MHz
    input   wire    sys_rst_n,
    // input   wire    key_flag,
    input   wire    EXclkl,
    input   wire    dac_outclk,  //DAC输出到FPGA的时钟
    // input   wire    [23:0]  AD_triggercnt,
    input   wire    dds_en  ,

    output  wire    dac_clk,
    output  wire    [15:0]  dac_data1,
    output  wire    [15:0]  dac_data2,
    output  wire    [15:0]  dac_data3
    
);

assign  dac_clk = ~sys_clk;     //使DAC读取稳定状态下的数据,相当于延时半个周期

dds_ctrl 
#(
    // .TRIMAX     (TRIMAX),
    .F1_WORD    (F1_WORD),
    .F2_WORD    (F2_WORD),
    .P1_WORD    (P1_WORD),
    .P2_WORD    (P2_WORD)
)dds_ctrl_inst
(
    .sys_clk    (sys_clk),
    .sys_rst_n  (sys_rst_n),
    // .key_flag   (key_flag),
    .EXclkl     (EXclkl),
    // .AD_triggercnt(AD_triggercnt),
    .dds_en     (dds_en),

    .dac_data1  (dac_data1),
    .dac_data2  (dac_data2),
    .dac_data3  (dac_data3)
);


endmodule