module  key_filter
#(
    parameter   M = 25'd999_999                     //注意位数
)
(
    input   wire           sys_clk      ,           //50MHz
    input   wire           sys_rst_n    ,
    input   wire           key_in       ,

    output  reg            key_flag
);

reg     [24:0]      cnt_20ms;

// 计数器逻辑保持不变
always@(posedge sys_clk or negedge sys_rst_n)
    if (sys_rst_n == 1'b0)
        cnt_20ms <= 25'd0;
    else if (key_in == 1'b1)
        cnt_20ms <= 25'd0;
    else if (cnt_20ms == M)
        cnt_20ms <= M;
    else
        cnt_20ms <= cnt_20ms + 1'd1;

// 修改 key_flag 生成逻辑
always@(posedge sys_clk or negedge sys_rst_n)
    if (sys_rst_n == 1'b0)
        key_flag <= 1'b0;
    // 修改处：当计数器等于 M-2 或 M-1 时都拉高，这样就会连续拉高两个周期
    else if (cnt_20ms == (M - 25'd2) || cnt_20ms == (M - 25'd1))
        key_flag <= 1'b1;
    else
        key_flag <= 1'b0;

endmodule