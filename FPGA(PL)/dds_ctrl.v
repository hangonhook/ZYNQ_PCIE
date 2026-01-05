module dds_ctrl
(
    input   wire        sys_clk ,       // 100MHz
    input   wire        sys_rst_n,
    input   wire        EXclkl,         // 50kHz 触发 (连接 adc_trig)
    input   wire        dds_en  ,       // 运行使能 (连接 Collctr_out)
    
    output  reg [15:0] dac_data1,
    output  reg [15:0] dac_data2,
    output  wire [15:0] dac_data3
);

    parameter   F1_WORD = 32'd4194;
    parameter   F2_WORD = 32'd16;
    parameter   P1_WORD = 14'd12288;
    parameter   P2_WORD = 14'd0;

    // 1. 同步 EXclkl 到 sys_clk 域
    reg ex_sync1, ex_sync2;
    wire ex_pulse_sys;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            ex_sync1 <= 0; ex_sync2 <= 0;
        end else begin
            ex_sync1 <= EXclkl;
            ex_sync2 <= ex_sync1;
        end
    end
    assign ex_pulse_sys = ex_sync1 & ~ex_sync2; // 上升沿检测

    // 2. 跨时钟域同步 dds_en
    reg dds_en_sync1, dds_en_sync2;
    always @(posedge sys_clk) begin
        dds_en_sync1 <= dds_en;
        dds_en_sync2 <= dds_en_sync1;
    end

    // 3. DDS 核心逻辑 (关键修改！)
    reg [31:0]  fre1_add;
    reg [13:0]  rom1_addr;
    reg [31:0]  fre2_add;
    reg [13:0]  rom2_addr;
    wire [15:0] dac_data1_raw;
    wire [15:0] dac_data2_raw;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            fre1_add <= 32'h0; rom1_addr <= 14'h0;
            fre2_add <= 32'h0; rom2_addr <= 14'h0;
        end
        // 【逻辑修改】：如果 dds_en 无效，强制复位归零
        else if (!dds_en_sync2) begin
            fre1_add <= 32'h0;
            // 注意：这里设为初始相位
            rom1_addr <= P1_WORD; 
            
            fre2_add <= 32'h0;
            rom2_addr <= P2_WORD;
        end
        // 【逻辑修改】：只有在 50kHz 脉冲到来时，才步进
        else if (ex_pulse_sys) begin
            fre1_add <= fre1_add + F1_WORD;
            rom1_addr <= fre1_add[31:18] + P1_WORD;
            
            fre2_add <= fre2_add + F2_WORD;
            rom2_addr <= fre2_add[31:18] + P2_WORD;
        end
    end

    // ROM 实例化 (不变)
    rom_16x16384_wave1 rom_wave1_inst (.clka(sys_clk), .addra(rom1_addr), .douta(dac_data1_raw));
    rom_16x16384_wave2 rom_wave2_inst (.clka(sys_clk), .addra(rom2_addr), .douta(dac_data2_raw));

    // 4. 输出更新 ( Sample & Hold )
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            dac_data1 <= 0; dac_data2 <= 0;
        end
        else if (!dds_en_sync2) begin
            dac_data1 <= 0; dac_data2 <= 0;
        end
        // 只有 50kHz 脉冲到来时，才更新输出
        else if (ex_pulse_sys) begin
            dac_data1 <= dac_data1_raw;
            dac_data2 <= dac_data2_raw;
        end
    end

    assign dac_data3 = (dac_data1 * dac_data2) >> 16;

endmodule