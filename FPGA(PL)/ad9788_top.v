module ad9788_top
#(
    // parameter   TRIMAX = 'd65536,
    parameter   F1_WORD = 32'd4194,
    parameter   F2_WORD = 32'd16,
    parameter   P1_WORD = 14'd12288,
    parameter   P2_WORD = 14'd0
)
(
    input   wire            clk_10m         ,
    input   wire            clk_100m        ,
    input   wire            sys_rst_n       ,
    //DDS接口
    // input   wire            key_flag        ,
    input   wire            EXclkl          ,
    input   wire            dac_outclk      ,
    // input   wire     [23:0] AD_triggercnt   ,
    input   wire            dds_en          ,
    output  wire            dac_clk         ,
    output  wire     [15:0] dac_data1       ,
    output  wire     [15:0] dac_data2       ,
    output  wire     [15:0] dac_data3       ,
    //DAC初始化接口
    output  wire            spi_clk         ,
    output  wire            spi_cs_n        ,
    output  wire            spi_sdio        
);
//DAC初始化
dac_init dac_init_inst
(
    .clk_100m        (clk_100m),
    .clk_10m         (clk_10m),
    .sys_rst_n       (sys_rst_n),

    .spi_clk         (spi_clk),
    .spi_cs_n        (spi_cs_n),
    .spi_sdio        (spi_sdio)
);
//DDS函数发生器
dds
#(
    // .TRIMAX     (TRIMAX),
    .F1_WORD    (F1_WORD),
    .F2_WORD    (F2_WORD),
    .P1_WORD    (P1_WORD),
    .P2_WORD    (P2_WORD)
)dds_inst
(
    .sys_clk    (clk_100m),
    .sys_rst_n  (sys_rst_n),
    // .key_flag   (key_flag),
    .EXclkl     (EXclkl),
    .dac_outclk (dac_outclk),
    // .AD_triggercnt(AD_triggercnt),
    .dds_en     (dds_en),
    
    .dac_clk    (dac_clk),
    .dac_data1  (dac_data1),
    .dac_data2  (dac_data2),
    .dac_data3  (dac_data3)
);

endmodule