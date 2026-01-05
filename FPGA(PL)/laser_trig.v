`timescale 1ns/1ns

module laser_trig
#(
    // ================= 时序参数 (基于 100MHz 时钟, 1cnt = 10ns) =================
    // 50kHz 周期 = 20us = 2000 * 10ns
    parameter CNT_MAX           = 16'd2000,     // 2000 对应 50kHz
    
    // 激光参数
    parameter PULSE_WIDTH       = 16'd100,      // 激光脉冲宽度 (1us = 100cnt)
    
    // 扫描振镜参数 (与采集一致)
    parameter SCAN_DELAY_COUNTS = 16'd1300,     // 与 ADC 初始延时一致
    parameter SCAN_PULSE_WIDTH  = 16'd4,        // 与 ADC 脉宽一致 (40ns)
    
    // ADC 采集参数
    parameter ADC_TRIG_WIDTH    = 16'd4,        // ADC触发脉宽 (40ns)，确保跨时钟域稳定
    parameter ADC_DELAY_INITIAL = 16'd1300,     // 初始 ADC 延时 (13us)
    
    // 调节参数
    parameter PHASE_STEP        = 16'd100       // 按键调节步进 (1us)
)
(
    input  wire        clk_in,       // 100MHz 系统主时钟
    input  wire        rst_n,
    
    input  wire        S3_flag,      // 相位调节按键 (异步信号)
    input  wire        trig_50k,     // 50kHz 触发信号
    
    output reg         laser_pulse,  // (TRI_CLK) 激光触发
    output reg         scan_trig,    // (dac_trig) 振镜触发
    output reg         sample_trig   // (adc_trig) ADC采集触发
);

    // ============================================================
    // 1. 跨时钟域处理 (CDC) & 边缘检测
    // ============================================================
    reg s3_d1, s3_d2, s3_d3;
    reg trig_d1, trig_d2;
    wire s3_rising_edge;
    wire trig_rising_edge;

    always @(posedge clk_in or negedge rst_n) begin
        if(!rst_n) begin
            s3_d1   <= 1'b0;
            s3_d2   <= 1'b0;
            s3_d3   <= 1'b0;
            trig_d1 <= 1'b0;
            trig_d2 <= 1'b0;
        end
        else begin
            // S3_flag 同步打拍 (3级以确保边缘检测准确，防止亚稳态)
            s3_d1 <= S3_flag;
            s3_d2 <= s3_d1;
            s3_d3 <= s3_d2;

            // trig_50k 同步打拍 (2级，确保相位对齐)
            trig_d1 <= trig_50k;
            trig_d2 <= trig_d1;
        end
    end
    
    // 提取上升沿 (同步后的信号)
    assign s3_rising_edge   = (s3_d2 && !s3_d3);
    assign trig_rising_edge = (trig_d1 && !trig_d2);

    // ============================================================
    // 2. 延时调节逻辑 (UI 控制层)
    // ============================================================
    reg [15:0] ui_target_phase;  // 用户设定的目标延时

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            ui_target_phase <= ADC_DELAY_INITIAL;
        end
        else if (s3_rising_edge) begin
            // 简单的防溢出加法 (循环调节或饱和调节)
            // 如果加了步进超过周期，归零
            if (ui_target_phase + PHASE_STEP >= CNT_MAX) 
                ui_target_phase <= 16'd0; 
            else 
                ui_target_phase <= ui_target_phase + PHASE_STEP;
        end
    end

    // ============================================================
    // 3. 核心时序发生器 (物理执行层)
    // ============================================================
    reg [15:0] cnt;
    reg        running;
    reg [15:0] active_adc_delay; // 【影子寄存器】当前周期实际生效的延时

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            cnt              <= 16'd0;
            running          <= 1'b0;
            laser_pulse      <= 1'b0;
            scan_trig        <= 1'b0;
            sample_trig      <= 1'b0;
            active_adc_delay <= ADC_DELAY_INITIAL;
        end
        else begin
            // --- A. 触发开始 (T=0) ---
            // 只有在触发的瞬间，才更新 active_adc_delay
            // 这样保证了在一个周期内，延时绝对不会突变，防止毛刺
            if (trig_rising_edge) begin
                cnt              <= 16'd0;
                running          <= 1'b1;
                active_adc_delay <= ui_target_phase; 
            end
            
            // --- B. 计数运行中 ---
            else if (running) begin
                cnt <= cnt + 1'b1;

                // 1. 激光触发 (TRI_CLK)
                // 逻辑：0 到 PULSE_WIDTH 期间为高
                if (cnt < PULSE_WIDTH)
                    laser_pulse <= 1'b1;
                else
                    laser_pulse <= 1'b0;

                // 2. 扫描触发 (振镜)
                // 逻辑：在 SCAN_DELAY_COUNTS 时刻拉高，持续 SCAN_PULSE_WIDTH (4个周期)
                if (cnt >= SCAN_DELAY_COUNTS && cnt < SCAN_DELAY_COUNTS + SCAN_PULSE_WIDTH)
                    scan_trig <= 1'b1;
                else
                    scan_trig <= 1'b0;

                // 3. ADC 采集触发 (关键稳定性优化)
                // 逻辑：使用锁存后的 active_adc_delay
                // 宽度：ADC_TRIG_WIDTH (40ns)，确保 ltc2208_ctrl 能抓到
                if (cnt >= active_adc_delay && cnt < active_adc_delay + ADC_TRIG_WIDTH)
                    sample_trig <= 1'b1;
                else
                    sample_trig <= 1'b0;

                // 周期结束保护
                if (cnt >= CNT_MAX) begin
                    running <= 1'b0;
                    cnt     <= 16'd0;
                end
            end
            
            // --- C. 空闲状态 (复位输出) ---
            else begin
                laser_pulse <= 1'b0;
                scan_trig   <= 1'b0;
                sample_trig <= 1'b0;
            end
        end
    end

endmodule