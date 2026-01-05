`timescale 1ns/1ns
module chnl_tester #(
  parameter C_PCI_DATA_WIDTH = 9'd64,
  parameter PCIE_TX_LEN = 32'd65536 
)
(
  // riffa接受数据通道
  input CLK,                  //系统时钟
  input RST,                  //系统复位
  output CHNL_RX_CLK,         //接受时钟
  input CHNL_RX,              //开始接受数据
  output CHNL_RX_ACK,         //接受数据应答
  input CHNL_RX_LAST,         //最后一个数据
  input [31:0] CHNL_RX_LEN,   //接受数据长度，以32位为单位
  input [30:0] CHNL_RX_OFF,   //剩余接受数据
  input [C_PCI_DATA_WIDTH-1:0] CHNL_RX_DATA, //数据
  input CHNL_RX_DATA_VALID,   //接受数据有效
  output CHNL_RX_DATA_REN,

  // riffa发送数据通道
  output CHNL_TX_CLK,         //发送数据时钟
  output CHNL_TX,             //触发发送
  input CHNL_TX_ACK,          //发送应答
  output CHNL_TX_LAST,        //发送最后一个数据
  output [31:0] CHNL_TX_LEN,  //发送数据长度,以32位为单位
  output [30:0] CHNL_TX_OFF,  //剩余发送数据
  output [C_PCI_DATA_WIDTH-1:0] CHNL_TX_DATA, //发送数据
  output CHNL_TX_DATA_VALID,  //发送数据有效
  input CHNL_TX_DATA_REN,

  // 用户fifo接口
  output fifo_wr_clk,
  output fifo_we,
  output [C_PCI_DATA_WIDTH-1:0] fifo_wr_data, 

  output fifo_rd_clk,
  output fifo_re,
  input  [C_PCI_DATA_WIDTH-1:0] fifo_rd_data, 
  input  fifo_rd_data_valid,

  // ADC 控制脉冲
  output phase_cmd_pulse, 
  output start_cmd_pulse
);


  // 内部寄存器
  //接受数据寄存器
  reg [C_PCI_DATA_WIDTH-1:0] rData = {C_PCI_DATA_WIDTH{1'b0}};
  //接受数据长度寄存器
  reg [31:0] rLen = 0;
  //已接受数据长度计数器寄存器
  reg [31:0] rCount = 0;
  //状态机
  reg [1:0]  rState = 0;

  // 命令解析变量
  reg [1:0] cmd_state = 0;
  wire is_cmd_packet = (CHNL_RX_LEN == 32'd1); // 判断是否为命令包

  // 脉冲展宽变量
  reg phase_cmd_stretched;
  reg [3:0] phase_stretch_cnt; 
  reg start_cmd_stretched; 
  reg [3:0] start_stretch_cnt; 

  // FIFO 连接
  assign fifo_wr_clk = CLK;
  assign fifo_wr_data = CHNL_RX_DATA;
  // 【逻辑微调】如果是命令包，禁止写入 FIFO，防止图像错位
  assign fifo_we = CHNL_RX & CHNL_RX_DATA_VALID & !is_cmd_packet;

  assign CHNL_RX_CLK = CLK;
  assign CHNL_RX_ACK = (rState == 2'd1);
  assign CHNL_RX_DATA_REN = (rState == 2'd1);

  assign CHNL_TX_CLK = CLK;
  assign CHNL_TX = (rState == 2'd3);
  assign CHNL_TX_LAST = 1;
  assign CHNL_TX_LEN = PCIE_TX_LEN;
  assign CHNL_TX_OFF = 0;
  assign CHNL_TX_DATA = fifo_rd_data;
  assign CHNL_TX_DATA_VALID = (rState == 2'd3 && fifo_rd_data_valid);
  assign fifo_re = CHNL_TX_DATA_REN & CHNL_TX_DATA_VALID;
  assign fifo_rd_clk = CLK;

  // 输出脉冲连接
  assign phase_cmd_pulse = phase_cmd_stretched; 
  assign start_cmd_pulse = start_cmd_stretched;

  // =========================================================
  // 触发机制：收到上位机 Start 命令 -> RX结束 -> 触发 TX
  // =========================================================
  always @(posedge CLK or posedge RST) begin
    if (RST) begin
      rLen <= #1 0;
      rCount <= #1 0;
      rState <= #1 0;
      rData <= #1 0;
    end
    else begin
      case (rState)
      
      // State 0: Wait for start of RX
      2'd0: begin 
        if (CHNL_RX) begin
          rLen <= #1 CHNL_RX_LEN;
          rCount <= #1 0;
          rState <= #1 2'd1;
        end
      end
      
      // State 1: Receiving Data/Command
      2'd1: begin 
        if (CHNL_RX_DATA_VALID) begin
          rData <= #1 CHNL_RX_DATA;
          rCount <= #1 rCount + (C_PCI_DATA_WIDTH/32);
        end
        if (rCount >= rLen) begin
            // 如果收到的数据是 32'd20 (Phase命令)，直接回 IDLE，不要发数据！
            if (rData[31:0] == 32'd20 || (CHNL_RX_DATA_VALID && CHNL_RX_DATA[31:0] == 32'd20)) begin
                rState <= #1 2'd0; // 回家待命，不发数据 -> 防止蓝屏
            end
            else begin
                // 如果是 Start (10) 或其他，才去准备发送
                rState <= #1 2'd2; 
            end
          end 
      end

      // State 2: Prepare for TX
      2'd2: begin 
        rCount <= #1 (C_PCI_DATA_WIDTH/32);
        rState <= #1 2'd3;
      end

      // State 3: Start TX
      2'd3: begin 
        if (CHNL_TX_DATA_REN & CHNL_TX_DATA_VALID) begin
          rCount <= #1 rCount + (C_PCI_DATA_WIDTH/32);
          // 使用 PCIE_TX_LEN 判断结束
          if (rCount >= PCIE_TX_LEN)
            rState <= #1 2'd0;
        end
      end
      
      endcase
    end
  end

  // =========================================================
  // 命令解析逻辑
  // =========================================================
  always @(posedge CLK or posedge RST) begin
    if (RST)
        cmd_state <= 0;
    // 当接收完成 (LAST) 且数据有效时进行判断
    else if (CHNL_RX_LAST && CHNL_RX_DATA_VALID) begin
      if (is_cmd_packet) begin
        if (CHNL_RX_DATA[31:0] == 32'd20) 
            cmd_state <= 1; // Phase
        else if (CHNL_RX_DATA[31:0] == 32'd10) 
            cmd_state <= 2; // Start
      end
      else 
        cmd_state <= 0;
    end
    else 
        cmd_state <= 0;
  end

  // =========================================================
  // 信号展宽逻辑 (统一 15 个周期)
  // =========================================================
  always @(posedge CLK or posedge RST) begin
    if (RST) begin
        phase_cmd_stretched <= 0; phase_stretch_cnt <= 0;
        start_cmd_stretched <= 0; start_stretch_cnt <= 0;
    end
    else begin
        // Phase Command (展宽 15 周期)
        if (cmd_state == 1) begin 
            phase_cmd_stretched <= 1; 
            phase_stretch_cnt <= 4'd15; 
        end 
        else if (phase_stretch_cnt > 0) begin
            phase_stretch_cnt <= phase_stretch_cnt - 1; 
            phase_cmd_stretched <= 1; 
        end 
        else 
            phase_cmd_stretched <= 0;
        
        // Start Command (展宽 15 周期)
        if (cmd_state == 2) begin 
            start_cmd_stretched <= 1; 
            start_stretch_cnt <= 4'd15; 
        end 
        else if (start_stretch_cnt > 0) begin
            start_stretch_cnt <= start_stretch_cnt - 1; 
            start_cmd_stretched <= 1; 
        end 
        else 
            start_cmd_stretched <= 0;
    end
  end

endmodule