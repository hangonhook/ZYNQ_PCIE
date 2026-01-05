module data_packer (
    input  wire        clk,         // ADC 时钟 (DCOA)
    input  wire        rst_n,
    
    // --- 新增接口：同步与包头 ---
    input  wire        flush,       // 强制复位计数器 (用于触发开始时对齐)
    input  wire        header_en,   // 写入包头使能
    input  wire [63:0] header_data, // 包头数据 (0xAAAA5555_TriggerCnt)
    
    // --- 原始 ADC 数据流 ---
    input  wire        wr_en_in,    // 来自 ltc2208_ctrl 的 ADC 数据有效
    input  wire [15:0] data_in,     // ADC 原始数据
    
    // --- 输出到 FIFO ---
    output reg         wr_en_out,
    output reg  [63:0] data_out
);

    reg [1:0]  byte_cnt;
    reg [15:0] buf0, buf1, buf2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_cnt   <= 2'd0;
            wr_en_out  <= 1'b0;
            data_out   <= 64'd0;
            buf0       <= 16'd0;
            buf1       <= 16'd0;
            buf2       <= 16'd0;
        end
        else begin
            wr_en_out <= 1'b0; // 默认为低

            // 优先级1：强制复位 (触发开始瞬间)
            if (flush) begin
                byte_cnt <= 2'd0;
            end
            
            // 优先级2：写入包头 (直接透传，不经过拼包逻辑)
            else if (header_en) begin
                data_out  <= header_data;
                wr_en_out <= 1'b1;
                byte_cnt  <= 2'd0; // 写完头后，计数器归零，准备接后面的 ADC 数据
            end
            
            // 优先级3：ADC 数据拼包
            else if (wr_en_in) begin
                case (byte_cnt)
                    2'd0: begin
                        buf0 <= data_in;
                        byte_cnt <= 2'd1;
                    end
                    2'd1: begin
                        buf1 <= data_in;
                        byte_cnt <= 2'd2;
                    end
                    2'd2: begin
                        buf2 <= data_in;
                        byte_cnt <= 2'd3;
                    end
                    2'd3: begin
                        // 攒够4个，拼接输出 (Little Endian: [最新]...[最旧])
                        data_out  <= {data_in, buf2, buf1, buf0}; 
                        wr_en_out <= 1'b1;
                        byte_cnt  <= 2'd0;
                    end
                endcase
            end
        end
    end

endmodule