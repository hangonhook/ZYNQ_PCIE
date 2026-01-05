module  dac_init
(
    input   wire    clk_100m,
    input   wire    clk_10m,
    input   wire    sys_rst_n,

    output  reg     spi_clk,
    output  reg     spi_cs_n,
    output  reg     spi_sdio

);

//----------------------------------辅助Aux DAC参数
parameter   I_gain   = 10'b00_0000_0000;   //I通道增益 10 位
parameter   Q_gain   = 10'b00_0000_0000;   //Q通道增益 10 位
parameter   I_scale  =  9'b0_1000_0000;    //I、Q通道输出比例因子   scale[8:0]/128 -> 0~3.9921875 输出的倍数
parameter   Q_scale  =  9'b0_1000_0000;    //
parameter   I_bias   = 10'b00_0000_0000;   //dac1 输出共模电压  根据原理图，AUX2_P给CH1(I)偏置   [15:13]='b000 [9:0]=I通道直流偏置
parameter   Q_bias   = 10'b00_0000_0000;   //dac2 输出共模电压  AUX1_P给CH2(Q)偏置

//----------------------------------DAC初始化
reg [39:0] WR_data;
reg [5:0] R_len;
reg [3:0] init_order;
reg init_flag;
//----------------------------------SPI
reg [5:0] i1;
reg [1:0] spi_cnt;
reg set_end;        //SPI发送完成信号

//init_flag:初始化完成标志信号，初始化完成后拉高
always @(posedge clk_10m or negedge sys_rst_n) 
    if (sys_rst_n == 1'b0)
        init_flag <= 1'b0;
    else if (init_order == 4'd9)
        init_flag <= 1'b1;

always @(posedge clk_10m or negedge sys_rst_n) 
    if (sys_rst_n == 1'b0)
        begin
            spi_cs_n        <= 1'b1;
            R_len           <= 6'd0;
            init_order      <= 4'h0;
            WR_data         <= 40'd0;
        end 
    else if (set_end == 1'b1)
        spi_cs_n <= 1'b1;
    else if (spi_cs_n == 1'b1)
        begin
            if (init_flag == 1'b0)
                begin
                    case (init_order)
                        0   :begin R_len=6'd16;WR_data={8'h0,8'h22,24'h0};spi_cs_n=1'b0;end//通信（COMM）寄存器,一字节  *[5]软件复位拉高，相当于用代码进行复位
                        1   :begin R_len=6'd16;WR_data={8'h0,8'h2,24'h0};spi_cs_n=1'b0;end//通信（COMM） *[5]软件复位拉低
                        2   :begin R_len=6'd24;WR_data={8'h1,8'h1,8'h00,16'h0};spi_cs_n=1'b0;end//[8]=1:DATACLK输出，[5]:0 二进制补码  [5]=1 偏移二进制，[4]=1:单端口 .两字节, [7:6]=01 2×插值
                        3   :begin R_len=6'd24;WR_data={8'h5,6'h0,I_gain[9:0],16'h0};spi_cs_n=1'b0;end//I  增益控制寄存器 两字节
                        4   :begin R_len=6'd24;WR_data={8'h7,6'h0,Q_gain[9:0],16'h0};spi_cs_n=1'b0;end//Q  增益控制寄存器 两字节
                        5   :begin R_len=6'd32;WR_data={8'hC,6'h0,Q_scale[8:0],I_scale[8:0],8'h0};spi_cs_n=1'b0;end//Q/I 振幅比例因子（ASF）三字节
                        6   :begin R_len=6'd24;WR_data={8'h2,8'h70,8'h1C,16'h0};spi_cs_n=1'b0;end//数据同步控制寄存器（DSCR）两字节    DATACLK延迟 3.3nS *[2]需要拉高
                        7   :begin R_len=6'd24;WR_data={8'hD,16'd0,16'd0};spi_cs_n=1'b0;end//Q/I 输出偏移（OOF）四字节
                        8   :begin R_len=6'd24;WR_data={8'h8,6'h0,I_bias[9:0],16'h0};spi_cs_n=1'b0;end
                        9   :begin R_len=6'd24;WR_data={8'h6,6'h0,Q_bias[9:0],16'h0};spi_cs_n=1'b0;end
                        
                    endcase
                    
                    init_order <= init_order + 1'd1;
                    
                end 
        end 


//------------------------------SPI通信
always @(posedge clk_10m or negedge sys_rst_n or posedge spi_cs_n) 
    if ((sys_rst_n == 1'b0) || (spi_cs_n == 1'b1))  
        begin 
            i1      = 6'd0;
            spi_cnt = 2'd0;
            set_end = 1'b0;
            spi_clk = 1'b1;
        end 
    else if (i1 < R_len)
        begin
            case (spi_cnt)                          //四分频 spi_clk=2.5MHz
                2'd0: spi_clk   = 1'b0;
                2'd1: spi_sdio  = WR_data[6'd39-i1];//高位在前 MSB先行
                2'd2: spi_clk   = 1'b1;
                2'd3: i1        = i1+1'b1;
            endcase
            spi_cnt=spi_cnt+1'b1;
        end
    else
        set_end=1'b1;   //SPI发送完成


endmodule