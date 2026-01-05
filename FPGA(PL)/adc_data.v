module adc_data
(
    input   wire    clk_100m        , //两时钟相差180度
    input   wire    clk_100m_1      , //两时钟相差180度
    input   wire    rst_n           ,
    input   wire    CLKOUTA         ,
    input   wire    [15:0]   AD_DATA_A,
    
    output  wire    AD_CS           ,
    input   wire    AD_ORA          ,
    output  wire    AD_DIR          ,
    output  wire    AD_SCLK         ,
    inout   wire    AD_SDIO         ,
    output  wire    AD_OEB          ,
    
    output  wire    AD_CLK          ,
    output  wire    AD_PDWN         ,
    output  wire    DCOA            , //读数据时钟
    output  wire    [15:0]   AD_DATA 
    
);
reg         Read_En;
wire        Rdempty;
reg         wr_en_reg;
reg         rst_n_d1, rst_n_d2;

//AD9268
assign  AD_CLK      = clk_100m  ;
assign  AD_SCLK     = 1'b0      ;
assign  AD_CS       = 1'b1      ;
assign  AD_PDWN     = 1'b0      ;
assign  AD_OEB      = 1'b0      ;//1:输出高阻    0:输出使能
assign  AD_DIR      = 1'b1      ;//DIR=0 SPI写参数到ADC寄存器，DIR=1 SPI读ADC寄存器
assign  DCOA        = clk_100m_1;

// 将异步复位 rst_n 同步到 CLKOUTA 域
always @(posedge CLKOUTA or negedge rst_n) begin
    if (!rst_n) begin
        rst_n_d1 <= 1'b0;
        rst_n_d2 <= 1'b0;
        wr_en_reg <= 1'b0;
    end 
    else begin
        rst_n_d1 <= 1'b1;
        rst_n_d2 <= rst_n_d1;
        wr_en_reg <= rst_n_d2; // 复位释放后两拍，允许写入
    end
end

// 功能：FIFO的读使能
always @(posedge DCOA or negedge rst_n) begin 
    if (rst_n == 1'b0) begin 
        Read_En <= 1'b0;
    end 
    else begin 
        Read_En <= ~Rdempty;
    end 
end 

// 功能：跨时钟域处理，将CLKOUTA时钟数据转换为DCOA时钟数据
Fifo_16to8 Fifo_16to8_inst
(
    .rst    (~rst_n     ),        // 复位
    .wr_clk (CLKOUTA    ),        // 写时钟
    .wr_en  (wr_en_reg  ),        // 写使能
    .din    (AD_DATA_A  ),        // 写数据
    
    .rd_clk (DCOA       ),        // 读时钟
    .rd_en  (Read_En    ),        // 读使能
    .dout   (AD_DATA    ),        // 读数据
    .empty  (Rdempty    )         // 读空
);

endmodule