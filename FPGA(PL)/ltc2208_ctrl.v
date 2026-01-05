module ltc2208_ctrl
#(
    parameter SAMP        = 512, // 每次触发采集点数
    parameter BSCAN_POINT = 256, // 单行触发次数
    parameter BSCAN_NUM   = 256  // 总行数
)
(
    input           rst_n,
    input           clk_100m,       
    input           DCOA,           // ADC时钟 (本模块主时钟)
    input           EXclk,          // 50kHz 触发信号 (从顶层传入的 adc_trig)
    input   [15:0]  AAD_Din,        // ADC 数据输入
    
    // --- 启动控制 ---
    // 这里连接顶层的 samp_tri 信号
    input           PL_KEY1_flag,   
    
    output reg      Rend,           // 采集完成信号
    
    // --- Header & Packer 接口 ---
    output wire [63:0] header_data,
    output reg      header_en,
    output reg      packer_flush,
    
    // --- 数据流接口 ---
    output reg      alldata_en,
    output reg [15:0] alldata_out,
    
    // --- 状态监测 ---
    output reg [31:0] triggercnt,   // 总数据量计数
    output wire       Collctr_out   // 正在运行标志
);

    // -----------------------------------------------------------
    // 1. 参数与变量
    // -----------------------------------------------------------
    // 计算总共需要的触发次数
    localparam [31:0] TOTAL_TRIGGERS = BSCAN_POINT * BSCAN_NUM;

    // 状态机状态定义
    localparam S_IDLE   = 3'd0;
    localparam S_FLUSH  = 3'd1;  // 用于 Flush
    localparam S_HEADER = 3'd2;  // 用于 Header
    localparam S_RUN    = 3'd3;  // 所有值采集
    localparam S_DONE   = 3'd4;

    reg [2:0]  state;
    reg [31:0] trig_counter;     // 当前已触发次数 (0 ~ TOTAL_TRIGGERS)
    reg [10:0] samp_counter;     // 当前burst内的点数 (0 ~ SAMP)
    reg [31:0] frame_id;         // 帧计数器 (每次实验+1)

    // -----------------------------------------------------------
    // 2. CDC 跨时钟域同步 & 边缘检测
    // -----------------------------------------------------------
    (* ASYNC_REG = "TRUE" *)reg [2:0] start_sync;
    (* ASYNC_REG = "TRUE" *)reg [2:0] exclk_sync;
    
    // EXclk (50kHz) 上升沿检测
    wire exclk_pulse = exclk_sync[1] & ~exclk_sync[2]; 

    // 启动信号上升沿检测
    wire start_pulse = start_sync[1] & ~start_sync[2];

    always @(posedge DCOA or negedge rst_n) begin
        if(!rst_n) begin
            start_sync <= 3'd0;
            exclk_sync <= 3'd0;
        end else begin
            // 移位寄存器打3拍，消除亚稳态并提取边缘
            start_sync <= {start_sync[1:0], PL_KEY1_flag};
            exclk_sync <= {exclk_sync[1:0], EXclk};
        end
    end

    // -----------------------------------------------------------
    // 3. 逻辑输出赋值
    // -----------------------------------------------------------
    // 包头：高32位固定魔数，低32位为帧ID
    assign header_data = {32'hAAAA_5555, frame_id}; 
    // 只要不是 IDLE 或 DONE，都视为忙碌状态 (包括 FLUSH 和 HEADER 阶段)
    assign Collctr_out = (state == S_RUN) || (state == S_FLUSH) || (state == S_HEADER); 

    // -----------------------------------------------------------
    // 4. 主状态机
    // -----------------------------------------------------------
    always @(posedge DCOA or negedge rst_n) begin
        if(!rst_n) begin
            state        <= S_IDLE;
            packer_flush <= 0;
            header_en    <= 0;
            alldata_en   <= 0;
            alldata_out  <= 0;
            Rend         <= 0;
            triggercnt   <= 0;
            
            frame_id     <= 0;
            trig_counter <= 0;
            samp_counter <= 11'd2047; // 初始设为大值，防止误触发
        end
        else begin
            // 默认控制信号复位 (脉冲型信号，每拍自动归零)
            packer_flush <= 0;
            header_en    <= 0;
            alldata_en   <= 0;
            Rend         <= 0;

            case(state)
                S_IDLE: begin
                    // 检测启动信号
                    if(start_pulse) begin
                        state        <= S_FLUSH;      // 第一步：去 Flush
                        frame_id     <= frame_id + 1; // 帧号递增
                        triggercnt   <= 0;            // 总数据计数清零
                        trig_counter <= 0;            // 触发次数清零
                    end
                end

                // 【状态拆分 1】: 复位 Packer 逻辑
                S_FLUSH: begin
                    packer_flush <= 1; 
                    state        <= S_HEADER;
                end

                // 【状态拆分 2】: 发送包头
                // 此时 flush 已经变回 0，header_en 能够生效
                S_HEADER: begin
                    header_en    <= 1;    
                    state        <= S_RUN;
                    samp_counter <= 11'd2047; // 保持禁止采样状态
                end

                S_RUN: begin
                    // 1. 触发检测：等待 50kHz 节拍
                    if(exclk_pulse && (trig_counter < TOTAL_TRIGGERS)) begin
                        samp_counter <= 0;                // 开启采集窗口
                        trig_counter <= trig_counter + 1; // 触发次数 +1
                    end

                    // 2. 数据采集：存入 FIFO
                    if(samp_counter < SAMP) begin
                        alldata_out  <= AAD_Din;
                        alldata_en   <= 1;
                        samp_counter <= samp_counter + 1;
                        triggercnt   <= triggercnt + 1; // 记录总数据量
                    end
                    
                    // 3. 自动停止条件
                    // 当触发次数满了，并且最后一次数据也发完了
                    if((trig_counter >= TOTAL_TRIGGERS) && (samp_counter == SAMP)) begin
                        state <= S_DONE;
                    end
                end
                
                S_DONE: begin
                    // 发送结束信号 (持续一个周期)
                    Rend  <= 1;      
                    state <= S_IDLE; // 回到空闲，等待下一次 samp_tri
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule