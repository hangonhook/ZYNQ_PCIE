module clk_50k_gen
(
    input   wire    clk_in,      // 100 MHz
    input   wire    rst_n   ,    // 复位

    output  reg     clk_50k      // 输出单周期脉冲
);

// 参数：50kHz 周期 = 20us = 2000 个 10ns 周期
parameter CNT_MAX = 15'd2000;   

reg [14:0] cnt;

always @(posedge clk_in or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        cnt <= 15'd0;
        clk_50k <= 1'b0;
    end
    else begin
        // 计数器逻辑
        if (cnt == CNT_MAX - 1'b1) begin
            cnt <= 15'd0;
            clk_50k <= 1'b1; // 计满归零时，拉高一个周期
        end
        else begin
            cnt <= cnt + 1'b1;
            clk_50k <= 1'b0; // 其他时间保持低电平
        end
    end
end

endmodule