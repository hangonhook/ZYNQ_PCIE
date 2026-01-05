module  work_led
#(
    parameter   CNT_MAX = 17'd999_99        //10MHz对应10ms 999_99
)
(
    input   wire        clk_in  ,   //输入时钟10MHz
    input   wire        Erst_n  ,
    
    output  reg         rst_n   ,
    output  reg         WORK_LED,
    output  reg [7:0]   start   
);

//------------------------------------------
reg [16:0]  cnt_10ms;
reg [3:0]   rst_cnt ;
reg [5:0]   led_cnt ;
reg         led_flag;

//系统复位后，start 10mS一个脉冲，持续255个序列信号(start=1、2、3...255),供系统外设初始化使用

//cnt_10ms：10ms计数器，输入时钟周期0.1us*100000=10ms
always@(posedge clk_in or negedge Erst_n)
    if(Erst_n == 1'b0)
        cnt_10ms    <=  17'd0;
    else    if(cnt_10ms == CNT_MAX)
        cnt_10ms    <=  17'd0;
    else
        cnt_10ms    <=  cnt_10ms    +   1'd1;


//------------复位信号------------------------
//rst_cnt：延迟100ms，用于使复位信号rst_n保持一段时间低电平后拉高
always@(posedge clk_in or negedge Erst_n)
    if(Erst_n == 1'b0)
        rst_cnt     <=  4'd0;
    else    if((rst_cnt < 4'd9) && (cnt_10ms == CNT_MAX))
        rst_cnt     <=  rst_cnt     +   1'd1;
    else
        rst_cnt     <=  rst_cnt;

//rst_n：复位信号，延迟100ms后拉高
always@(posedge clk_in or negedge Erst_n)
    if(Erst_n == 1'b0)
        rst_n       <=  1'b0;
    else    if((rst_cnt == 4'd9) && (cnt_10ms == CNT_MAX))
        rst_n       <=  1'b1;
    else
        rst_n       <=  rst_n;


//------------LED---------------------------
//led_cnt：延迟500ms，用于使LED每1秒闪烁一次，占空比50%
always@(posedge clk_in or negedge Erst_n)
    if(Erst_n == 1'b0)
        led_cnt     <=  6'd0;
    else    if((led_cnt == 6'd49) && (cnt_10ms == CNT_MAX))
        led_cnt     <=  6'd0;
    else    if(cnt_10ms == CNT_MAX)
        led_cnt     <=  led_cnt     +   1'd1;
    else
        led_cnt     <=  led_cnt;

//led_flag：LED状态翻转标志，led_cnt计数到48拉高10ms
always@(posedge clk_in or negedge Erst_n)
    if(Erst_n == 1'b0)
        led_flag    <=  1'b0;
    else    if((led_cnt == 6'd48) && (cnt_10ms == CNT_MAX))
        led_flag    <=  1'b1;
    else    if((led_cnt == 6'd49) && (cnt_10ms == CNT_MAX))
        led_flag    <=  1'b0;
    else
        led_flag    <=  led_flag;

//LED每隔500ms状态翻转一次
always@(posedge clk_in or negedge Erst_n)
    if(Erst_n == 1'b0)
        WORK_LED    <=  1'd1;
    else    if((led_flag == 1'b1) && (cnt_10ms == CNT_MAX))
        WORK_LED    <=  ~WORK_LED;
    else
        WORK_LED    <=  WORK_LED;


//------------启动顺序-----------------------
//start:启动顺序，rst_n拉高后，start每10ms自加1，生成255个
always@(posedge clk_in or negedge Erst_n)
    if(Erst_n == 1'b0)
        start       <=  8'd0;
    else    if((start < 8'd255) && (cnt_10ms == CNT_MAX) &&(rst_n == 1'b1))
        start       <=  start   +   1'd1;
    else
        start       <=  start;


endmodule