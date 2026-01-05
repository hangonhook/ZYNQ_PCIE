`timescale  1ns/1ns
module  adc2pcie
#(
    //ADC
    parameter   SAMP   = 512,                   //必须是4的倍数，data_packer中4个16位组成64位
    parameter   BSCAN_POINT = 256,
    parameter   BSCAN_NUM = 256,
    //PCIE
    parameter   C_NUM_CHNL = 1,
    parameter   C_NUM_LANES =  4,
    parameter   C_PCI_DATA_WIDTH = 64,
    parameter   C_MAX_PAYLOAD_BYTES = 128,
    parameter   C_LOG_NUM_TAGS = 5,
    //DAC
    parameter   F1_WORD = 8388608,         //50khz触发下对应8388608,100Mhz触发下对应4194
    parameter   F2_WORD = 32768,           //50khz触发下对应32768,100Mhz触发下对应16
    parameter   P1_WORD = 12288,
    parameter   P2_WORD = 0,
    //激光触发
    parameter   PULSE_WIDTH = 100,         // 1 us 的激光脉冲宽度
    parameter   PHASE_STEP = 100,         // 每次按键增加的延时，单位为10ns，100即1us
    parameter   SCAN_DELAY_COUNTS = 1000, // 扫描延时1000个周期(10us)
    parameter   ADC_DELAY_INITIAL = 1000  // 采集延时1000个周期(10us)
)
(
    input   wire    sys_clk          , //系统时钟
    input   wire    sys_rst_n        ,//系统复位，低电平有效
    
    // input   wire    locked           ,
    // input   wire    clk_200m         ,
    // input   wire    clk_100m         ,
    // input   wire    clk_10m          ,
    // input   wire    clk_out4         ,
    
//****************************************ADC ltc2208
    output  wire    AD_CLK,
    output  wire    AD_CS,

    input   wire    CLKOUTA,    //ADC通道A输出的时钟
    // input   wire    CLKOUTB,    //ADC通道B输出的时钟
    input   wire    AD_ORA,
    input   [15:0]   AD_DATA_A,
    // input   [15:0]   AD_DATA_B,
    output  wire    AD_SCLK,
    inout   wire    AD_SDIO,
    output  wire    AD_OEB,
    
    // input           EXclk,      //外部触发输入
    // input           scan_trig,  //扫描触发输入
    // input           scan_flag,  //扫描触发输入
//****************************************DAC AD9788
    input           DAC1_outclk,
    input           DAC2_outclk,
    
    output  wire    DAC1_CLK,
    output  wire    DAC2_CLK,
    output  wire    [15:0]  DAC1_DATA,
    output  wire    [15:0]  DAC2_DATA,
    output  wire    [15:0]  DAC3_DATA,
    output  wire    [15:0]  DAC4_DATA,
//DAC-spi  两片DAC的SPI接口
    // output  wire    DA1_SDIO,
    // output  wire    DA1_SCK,
    // output  wire    DA1_CS,
    // output  wire    DA2_SDIO,
    // output  wire    DA2_SCK,
    // output  wire    DA2_CS,
    
//****************************************按键和灯
    input           PL_KEY1,//启动命令
    input           PL_KEY2,
    input           EX_KEY1,//外部额外按键
    input           EX_KEY2,

    output          pl_led1,
    output          pl_led2, 
    output          pl_led3, 
    output          pl_led4,

//****************************************脉冲输出
    output  wire    TRI_CLK,
    // output  wire    tripulse_high,
//PCIE接口
    output wire    [(C_NUM_LANES - 1) : 0] PCI_EXP_TXP  ,   //pcie发送引脚
    output wire    [(C_NUM_LANES - 1) : 0] PCI_EXP_TXN  ,   //pcie发送引脚
    input  wire    [(C_NUM_LANES - 1) : 0] PCI_EXP_RXP  ,   //pcie接受引脚
    input  wire    [(C_NUM_LANES - 1) : 0] PCI_EXP_RXN  ,   //pcie接受引脚
    input  wire         PCIE_REFCLK_P,   //pcie时钟
    input  wire         PCIE_REFCLK_N,   //pcie时钟
    input  wire         PCIE_RESET_N,    //pcie复位信号
    
// DDR3 外挂接口 - 写通道 (发送给 Block Design)
    output wire         ext_fifo_wr_clk, // 写时钟 (DCOA)
    output wire [63:0]  ext_fifo_din,    // 写数据
    output wire         ext_fifo_wr_en,  // 写使能
    input  wire         ext_fifo_full,   // 外部 FIFO 满信号 (用于 system_busy)
    output wire         ext_fifo_last,   // 每包数据结束标志 (每128个64位数据拉高一次)
    output wire         ext_fifo_rst_n,  // 写FIFO复位信号
    
// DDR3 外挂接口 - 读通道 (从 Block Design 接收)
    output wire         ext_fifo_rd_clk, // 读时钟 (PCIe Clock)
    output wire         ext_fifo_rd_en,  // 读使能
    input  wire [63:0]  ext_fifo_dout,   // 读数据
    input  wire         ext_fifo_empty   // 外部 FIFO 空信号

//DDR3接口
    // inout [31:0]       ddr3_dq     ,     //数据线
    // inout [3:0]        ddr3_dqs_n  ,     //数据选取脉冲差分信号
    // inout [3:0]        ddr3_dqs_p  ,     //数据选取脉冲差分信号
    // output [14:0]      ddr3_addr   ,     //地址线
    // output [2:0]       ddr3_ba     ,     //bank线
    // output             ddr3_ras_n  ,     //行使能信号，低电平有效
    // output             ddr3_cas_n  ,     //列使能信号，低电平有效
    // output             ddr3_we_n   ,     //写使能信号，低电平有效
    // output             ddr3_reset_n,     //ddr3复位
    // output [0:0]       ddr3_ck_p   ,     //ddr3差分时钟
    // output [0:0]       ddr3_ck_n   ,     //ddr3差分时钟
    // output [0:0]       ddr3_cke    ,     //ddr3时钟使能信号
    // output [0:0]       ddr3_cs_n   ,     //ddr3片选信号
    // output [3:0]       ddr3_dm     ,     //ddr3掩码
    // output [0:0]       ddr3_odt          //odt阻抗

);

//参数定义
//clk
wire            locked          ;
wire            clk_200m        ;
wire            clk_100m        ;
wire            clk_10m         ;
wire            clk_out4        ;
wire            clk_50k         ;
// wire            clk_195hz       ;
wire            rst_n           ;
// wire            fifo_adcdata_rst;

//key_filter
wire            PL_KEY1_flag    ;
wire            PL_KEY2_flag    ;

//adc_data
wire    [15:0]  AD_DATA         ;

//fifo缓冲
wire            fifo_empty      ;
wire            fifo_full       ;
wire            system_busy     ;

//ltc2208_ctrl
wire            DCOA            ;
wire            Rend            ;
wire    [63:0]  header_data     ;
wire            header_en       ;
wire            packer_flush    ;
wire            Collctr_out     ;
wire    [31:0]  AD_triggercnt   ;
wire            alldata_en      ; 
wire    [15:0]  alldata_out     ;

//data_packer
wire            packed_wr_en    ; // 64位打包后使能
wire    [63:0]  packed_data     ; // 64位打包后数据

//ddr
// wire            ui_rst          ; //ddr产生的复位信号
// wire            ui_clk          ; //DDR3的读写时钟
// wire            ddr3_init_done  ; //DDR3初始化完成
// wire   [15:0]   ad_rd_data      ; //ddr读数据64位
// wire   [31:0]   ad_rd_data1     ; 
// wire   [31:0]   ad_rd_data2     ;

//pcie
wire            samp_tri        ; //根据按键或pcie写入数据触发采集
wire            laserphase_tri  ; //根据按键或PCIE写入数据触发激光相位增加
wire            phase_cmd_pulse;  //接收到相位增加命令(展宽后20ms)
wire            start_cmd_pulse;  //接收到开始采集命令(展宽后120ns)
wire            fifo_wr_clk     ;
wire            fifo_we         ;
wire   [63:0]   fifo_wr_data    ;
wire            fifo_rd_clk     ;
wire            fifo_re         ;
wire   [63:0]   fifo_rd_data    ;
wire            data_rd_valid   ;
wire   [2:0]    LED             ;

//laser_trig
wire            dac_trig        ;
wire            adc_trig        ;

//********************************************************************//
//***************************** Main Code ****************************//
//********************************************************************//

parameter [23:0] TRIALL = BSCAN_POINT * BSCAN_NUM;

parameter [31:0] DATA_LEN_WORDS = (TRIALL * SAMP) >> 1; //右移1位等于除以2，数据单位为32位

//有效数据量DATA_LEN_WORDS个32位数据 加上 数据包头(64位=2个32位)
parameter [31:0] PCIE_TX_LEN_VAL = DATA_LEN_WORDS + 2; 

assign rst_n = locked ; //全局总复位 等待ddr初始化完成& ddr3_init_done

// 观察pcie的读时钟fifo_rd_clk
reg [25:0] heartbeat_cnt;
always @(posedge ext_fifo_rd_clk) begin
    heartbeat_cnt <= heartbeat_cnt + 1;
end

// 锁存system_busy，方便LED观察
reg led_overflow_latch;
always @(posedge DCOA or negedge rst_n) begin
if(!rst_n) begin
    led_overflow_latch <= 1'b0;
end
else if(global_flush) begin
    // 点击“开始”时熄灭
    led_overflow_latch <= 1'b0; 
end
else if(ext_fifo_full) begin
    // 捕捉溢出：只要 DCOA 边沿检测到 full 为高，就永久锁死为 1
    led_overflow_latch <= 1'b1;
end
// else 保持原值 (Latch)
end
    
assign pl_led4 = heartbeat_cnt[25]; //指示pcie的读时钟fifo_rd_clk
assign pl_led3 = LED[1]; //指示pcie的user_reset
assign pl_led2 = LED[2]; //指示pcie的user_lnk_up
assign pl_led1 = led_overflow_latch; //指示fifo_adcdata接近满信号

//根据上位机写入数据(32'd10或32'd20)触发采集和扫描
//接收到的数据为10时拉高触发信号，模拟按键按下一次
// 修改后的代码：增加互锁 (Lockout)
// 1. 定义软件相位信号
wire sw_phase_active = phase_cmd_pulse; 

// 2. 激光相位触发：物理按键 OR 软件长脉冲
assign laserphase_tri = (sw_phase_active || PL_KEY1_flag);

// 3. 采集触发：(开始命令 OR 物理按键) AND (当前没有在调节相位)
// 如果软件正在发相位指令，强制屏蔽采集触发，防止误触导致蓝屏。
assign samp_tri = (start_cmd_pulse || PL_KEY2_flag) && (~sw_phase_active);

// ============================================================
// 生成全局对齐信号 global_flush
// 目的：只在上位机点击“开始”时复位一次，防止采集过程中误复位导致断层
// ============================================================
reg start_cmd_d1;
reg start_cmd_d2;
wire global_flush; 

// 将 start_cmd_pulse (来自 PCIe 域) 同步到 DCOA (数据域)
always @(posedge DCOA or negedge rst_n) begin
    if(!rst_n) begin
        start_cmd_d1 <= 1'b0;
        start_cmd_d2 <= 1'b0;
    end
    else begin
        start_cmd_d1 <= start_cmd_pulse; 
        start_cmd_d2 <= start_cmd_d1;
    end
end

// 生成 global_flush：仅使用上位机命令，不受按键或 ADC 状态机干扰
assign global_flush = start_cmd_d2; 
// ============================================================


//时钟模块
clk_wiz_1 clk_wiz_inst
( 
    .clk_out1(clk_200m  ), //ddr时钟实际输出200mhz，对应MIGip设置界面input clock period
    .clk_out2(clk_out2  ), //输出与clk_out4相位差180度
    .clk_out3(clk_10m   ), //实际输出10mhz
    .clk_out4(clk_out4  ), //实际输出100mhz
    .resetn  (sys_rst_n ), //连接PS端的复位信号
    .locked  (locked    ), //时钟输出稳定
    .clk_in1 (sys_clk   )  //输入时钟
);

//-----------------------按键消抖------------------------
key_filter
#(
    .M        (25'd1_999_999)         //20ms
)key_filter_PL_KEY1
(
    .sys_clk  (clk_out4     )   ,
    .sys_rst_n(rst_n        )   ,
    .key_in   (PL_KEY1      )   ,

    .key_flag (PL_KEY1_flag )         //持续2个周期
);

key_filter
#(
    .M        (25'd1_999_999)         //20ms
)key_filter_PL_KEY2
(
    .sys_clk  (clk_out4     )   ,
    .sys_rst_n(rst_n        )   ,
    .key_in   (PL_KEY2      )   ,

    .key_flag (PL_KEY2_flag )         //持续2个周期
);

//-----------------------AD采集模块------------------------
//采集数据缓冲（跨时钟域处理）
adc_data adc_data_inst
(
    .clk_100m   (clk_out4   ),
    .clk_100m_1 (clk_out2   ),
    .rst_n      (rst_n      ),
    .CLKOUTA    (CLKOUTA    ),
    .AD_DATA_A  (AD_DATA_A  ),
    .AD_CS      (AD_CS      ),
    .AD_ORA     (AD_ORA     ),
    .AD_DIR     ( ),
    .AD_SCLK    (AD_SCLK    ),
    .AD_SDIO    (AD_SDIO    ),
    .AD_OEB     (AD_OEB     ),
    
    .AD_CLK     (AD_CLK     ),
    .AD_PDWN    ( ),
    .DCOA       (DCOA       ),
    .AD_DATA    (AD_DATA    )
);

//实际使用ADC芯片：AD9268
ltc2208_ctrl
#(
    .SAMP           (SAMP           ),
    .BSCAN_POINT    (BSCAN_POINT    ),
    .BSCAN_NUM      (BSCAN_NUM      )
) ltc2208_ctrl_inst
(
    .rst_n          (rst_n          ),
    .clk_100m       (clk_out4       ),
    .DCOA           (DCOA           ), //ADC写入时钟
    .EXclk          (adc_trig       ),
    .AAD_Din        (AD_DATA        ),
    
    .PL_KEY1_flag   (samp_tri       ), //samp_tri
    .Rend           (Rend           ), //采集完成拉高一个周期
    
    .header_data    (header_data    ), //数据包头{32'hAAAA_5555, frame_id}
    .header_en      (header_en      ), //数据包头使能
    .packer_flush   (   ), //*packer_flush
    
    .triggercnt     (AD_triggercnt  ), //总数据量计数
    .Collctr_out    (Collctr_out    ), //正在运行标志
    
    .alldata_en     (alldata_en     ), //输出所有值使能
    .alldata_out    (alldata_out    )  //输出所有值
);

//数据拼接：4个16位数据拼接1个64位，便于PCIe传输
//格式：[最新数据][buf2][buf1][最早数据] (Little Endian 风格)
data_packer data_packer_inst (
    .clk        (DCOA),             // 时钟域跟随 ADC 写时钟
    .rst_n      (rst_n),
    
    //同步与包头
    .flush      (global_flush), //*packer_flush
    .header_en  (header_en),
    .header_data(header_data),
    
    // 输入接 ltc2208_ctrl
    .wr_en_in   (alldata_en),
    .data_in    (alldata_out),
    
    // 输出接 fifo_adcdata
    .wr_en_out  (packed_wr_en),
    .data_out   (packed_data)
);

//数据缓冲FIFO: 连接 data_packer 和 pcie
/* fifo_adcdata fifo_adcdata_inst (
  .rst      (fifo_adcdata_rst), // input wire rst
  .wr_clk   (DCOA),             // input wire wr_clk
  .rd_clk   (fifo_rd_clk),      // input wire rd_clk *fifo_rd_clk
  .din      (packed_data),      // input wire [63 : 0] din
  .wr_en    (packed_wr_en),     // input wire wr_en
  .rd_en    (fifo_re),          // input wire rd_en *fifo_re
  .dout     (fifo_rd_data),     // output wire [63 : 0] dout
  .full     (fifo_full),        // output wire full
  .prog_full(system_busy),      // output wire prog_full 阈值设置为131060
  .empty    (fifo_empty)        // output wire empty
); */

    // ============================================================
    // 外挂 DDR3 桥接逻辑
    // ============================================================
    
    // 1. 写通道：把 data_packer 的数据送出去
    assign ext_fifo_wr_clk = DCOA;
    assign ext_fifo_din    = packed_data;
    assign ext_fifo_wr_en  = packed_wr_en;
    assign ext_fifo_rst_n  = locked; //写FIFO复位信号
    
    // --- TLAST 生成逻辑 ---
    // 计数器：每传输 128 个 64位数据 (1KB) 就拉高一次 TLAST
    // *使用 global_flush 复位计数器
    reg [6:0] pkt_cnt; 
    always @(posedge DCOA or negedge rst_n) begin
        if(!rst_n) 
            pkt_cnt <= 0;
        else if(global_flush) //packer_flush
            pkt_cnt <= 0;
        else if(packed_wr_en) 
            pkt_cnt <= pkt_cnt + 1;
    end
    // 当计数到 127 且当前数据有效时，标记为一包结束
    assign ext_fifo_last = (pkt_cnt == 7'd127) && packed_wr_en;

    // system_busy 原本连的是 internal_fifo_full
    // 现在连外部进来的 prog_full 
    assign system_busy     = ext_fifo_full; 
    

    // 2. 读通道：把外部进来的数据送给 RIFFA (chnl_tester/XC7035)
    // 注意：XC7035 模块里会产生 fifo_rd_clk 和 fifo_re
    assign ext_fifo_rd_clk = fifo_rd_clk; 
    assign ext_fifo_rd_en  = fifo_re;
    
    // 把外部读回的数据给 PCIe
    assign fifo_rd_data    = ext_fifo_dout;
    
    // data_rd_valid 告诉 PCIe 数据可用
    // 在 FWFT 模式下，只要非空 ，数据就是可用的
    assign data_rd_valid   = ~fifo_empty; 
    
    assign fifo_empty      = ext_fifo_empty; 
    
    // ============================================================

/* //------------- ddr_rw_inst -------------
//DDR读写控制部分
axi_ddr_top #(
.DDR_WR_LEN(128),//写突发长度 最大128个64bit
.DDR_RD_LEN(128)//读突发长度 最大128个64bit
) 
ddr_rw_inst(
  .ddr3_clk     (clk_200m           ),
  .sys_rst_n    (locked             ),
  .pingpang     (1'b0               ),
   //写用户接口
  .user_wr_clk (DCOA                ), //写时钟
  .data_wren   (alldata_en          ), //写使能，高电平有效
  .data_wr     (alldata_out         ), //写数据8位
  .wr_b_addr   (30'd0               ), //写起始地址
  .wr_e_addr   (TRIALL*SAMP         ), //写结束地址,8位一字节对应一个地址
  .wr_rst      (1'b0                ), //写地址复位 wr_rst
  //读用户接口
  .user_rd_clk (fifo_rd_clk         ), //读时钟
  .data_rden   (fifo_re             ), //读使能，高电平有效
  .data_rd     (ad_rd_data          ), //读数据16位 8位alldata_out *2个有效数据 =16位
  .rd_b_addr   (30'd0               ), //读起始地址
  .rd_e_addr   (TRIALL*SAMP         ), //写结束地址,8位一字节对应一个地址
  .rd_rst      (1'b0                ), //读地址复位 rd_rst
  .read_enable (read_enable         ),
  .data_rd_valid(data_rd_valid      ),
   
  .ui_rst       (ui_rst             ), //ddr产生的复位信号
  .ui_clk       (ui_clk             ), //ddr操作时钟125m
  .calib_done   (ddr3_init_done     ), //代表ddr初始化完成
  
  //物理接口
  .ddr3_dq   (ddr3_dq   ),    //数据线
  .ddr3_dqs_n(ddr3_dqs_n),    //数据选取脉冲差分信号
  .ddr3_dqs_p(ddr3_dqs_p),    //数据选取脉冲差分信号
  .ddr3_addr (ddr3_addr ),    //地址线
  .ddr3_ba   (ddr3_ba   ),    //bank线
  .ddr3_ras_n(ddr3_ras_n),    //行使能信号，低电平有效
  .ddr3_cas_n(ddr3_cas_n),    //列使能信号，低电平有效
  .ddr3_we_n (ddr3_we_n ),    //写使能信号，低电平有效
  .ddr3_reset_n(ddr3_reset_n),//ddr3复位
  .ddr3_ck_p (ddr3_ck_p ),    //ddr3差分时钟
  .ddr3_ck_n (ddr3_ck_n ),    //ddr3差分时钟
  .ddr3_cke  (ddr3_cke  ),    //ddr3时钟使能信号
  .ddr3_cs_n (ddr3_cs_n ),    //ddr3片选信号
  .ddr3_dm   (ddr3_dm   ),    //ddr3掩码
  .ddr3_odt  (ddr3_odt  )     //odt阻抗
   

); */

//------------- pcie_riffa_inst -------------
//pcie顶层模块
XC7035_Gen1x4If64 #(
.PCIE_TX_LEN        (PCIE_TX_LEN_VAL),
.C_NUM_CHNL         (C_NUM_CHNL),
.C_NUM_LANES        (C_NUM_LANES),
.C_PCI_DATA_WIDTH   (C_PCI_DATA_WIDTH),
.C_MAX_PAYLOAD_BYTES(C_MAX_PAYLOAD_BYTES),
.C_LOG_NUM_TAGS     (C_LOG_NUM_TAGS)
)XC7035_Gen1x4If64_inst
(
  .PCI_EXP_TXP  (PCI_EXP_TXP  )  ,//pcie发送引脚
  .PCI_EXP_TXN  (PCI_EXP_TXN  )  ,//pcie发送引脚
  .PCI_EXP_RXP  (PCI_EXP_RXP  )  ,//pcie接受引脚
  .PCI_EXP_RXN  (PCI_EXP_RXN  )  ,//pcie接受引脚
  .LED          (LED          )  ,//led[0]指示pcie时钟信号,[1]复位[2]lnk_up
  .PCIE_REFCLK_P(PCIE_REFCLK_P)  ,//pcie时钟
  .PCIE_REFCLK_N(PCIE_REFCLK_N)  ,//pcie时钟
  .PCIE_RESET_N (PCIE_RESET_N )  ,//pcie复位信号
  .phase_cmd_pulse(phase_cmd_pulse), //接收到相位增加命令(展宽后120ns)
  .start_cmd_pulse(start_cmd_pulse), //接收到开始采集命令(展宽后120ns)
  .fifo_wr_clk  (fifo_wr_clk  )  ,//pcie写数据到外部的时钟信号 
  .fifo_we      (fifo_we      )  ,//pcie写数据的使能信号 
  .fifo_wr_data (fifo_wr_data )  ,//pcie写数据到外部 
  .fifo_rd_clk  (fifo_rd_clk  )  ,//pcie从外部读取数据时钟 
  .fifo_re      (fifo_re      )  ,//pcie从外部读取数据使能 
  .fifo_rd_data(fifo_rd_data),//pcie读数据 
  .fifo_rd_data_valid(data_rd_valid)//外部数据可读有效 
);

//-----------------------DAC模块 ad9788_top------------------------
ad9788_top 
#(
    // .TRIMAX         (TRIALL),
    .F1_WORD        (F1_WORD),
    .F2_WORD        (F2_WORD),
    .P1_WORD        (P1_WORD),
    .P2_WORD        (P2_WORD)
)ad9788_top_inst
(
    .clk_10m         (clk_10m),
    .clk_100m        (clk_out4),
    .sys_rst_n       (rst_n),
    .EXclkl          (adc_trig),
    .dac_outclk      (DAC1_outclk),
    .dds_en          (Collctr_out),
    .dac_clk         (DAC1_CLK),
    .dac_data1       (DAC1_DATA),
    .dac_data2       (DAC2_DATA),
    .dac_data3       ( ),
    .spi_clk         ( ),
    .spi_cs_n        ( ),
    .spi_sdio        ( )
);

//-----------------------激光脉冲触发模块------------------------
laser_trig
#(
    .PULSE_WIDTH        (PULSE_WIDTH),
    .PHASE_STEP         (PHASE_STEP),
    .SCAN_DELAY_COUNTS  (SCAN_DELAY_COUNTS),
    .ADC_DELAY_INITIAL  (ADC_DELAY_INITIAL)
) laser_trig_inst
(
    .clk_in             (clk_out4),       //input 
    .rst_n              (rst_n),          //input 
    .S3_flag            (laserphase_tri), //input 
    .trig_50k           (clk_50k),        //input 
    // .fifo_full_flag     (system_busy),    //input 缓冲fifo满暂停采集和扫描

    .laser_pulse        (TRI_CLK),        //output 激光触发
    .scan_trig          ( ),       //output 扫描触发
    .sample_trig        (adc_trig)        //output 采集触发

);
//-----------------------内触发50khz时钟生成模块------------------------
clk_50k_gen clk_50k_inst
(
    .clk_in  (clk_out4),    // 100 MHz 时钟输入 （周期 10 ns）
    .rst_n   (rst_n),       // 复位信号，低有效

    .clk_50k (clk_50k)      // 输出单周期脉冲信号(10ns)
);

endmodule
