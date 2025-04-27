`timescale 1ns / 1ps 

module Max_pool #(
    parameter integer BITWIDTH = 16,             // 单个像素位宽
    parameter integer DATAWIDTH = 8,            // 输入图像宽度
    parameter integer DATAHEIGHT = 8,           // 输入图像高度
    parameter integer DATACHANNEL = 3,           // 输入通道数
    parameter integer KWIDTH = 2,                // 卷积核宽度
    parameter integer KHEIGHT = 2                // 卷积核高度
)(
    input wire clk,                              // 时钟信号
    input wire rst_n,                            // 异步复位，低有效
    input wire clken,                            // 使能信号
    input wire [BITWIDTH*DATAWIDTH*DATAHEIGHT*DATACHANNEL-1:0] data_in, // 打平的一整张图片输入
    output reg [BITWIDTH*(DATAWIDTH/KWIDTH)*(DATAHEIGHT/KHEIGHT)*DATACHANNEL-1:0] result_out, // 池化后的输出
    output reg result_valid_out                  // 输出结果有效信号
);

    // 输出特征图的尺寸
    localparam integer OUTPUT_WIDTH  = DATAWIDTH / KWIDTH;
    localparam integer OUTPUT_HEIGHT = DATAHEIGHT / KHEIGHT;
    localparam integer TOTAL_OUTPUTS = OUTPUT_WIDTH * OUTPUT_HEIGHT * DATACHANNEL;

    // 临时寄存器：存放当前2x2窗口的4个像素
    reg [BITWIDTH-1:0] pool_reg[0:3];
    
    // 比较树寄存器：两两比较中间结果
    reg [BITWIDTH-1:0] stage1_max0, stage1_max1;
    reg [BITWIDTH-1:0] final_max; // 当前池化窗口的最大值

    // 行、列、通道的索引寄存器
    reg [4:0] channel_idx;
    reg [7:0] row_idx;
    reg [7:0] col_idx;
    reg [31:0] out_idx; // 输出数据计数器（扁平输出）

    // 取出当前2x2窗口的四个元素（打平的一维data_in中提取）
    wire [BITWIDTH-1:0] d00, d01, d10, d11;
    
    assign d00 = data_in[ ((channel_idx*DATAHEIGHT*DATAWIDTH) + (row_idx*2)*DATAWIDTH + (col_idx*2)) * BITWIDTH +: BITWIDTH ];
    assign d01 = data_in[ ((channel_idx*DATAHEIGHT*DATAWIDTH) + (row_idx*2)*DATAWIDTH + (col_idx*2+1)) * BITWIDTH +: BITWIDTH ];
    assign d10 = data_in[ ((channel_idx*DATAHEIGHT*DATAWIDTH) + (row_idx*2+1)*DATAWIDTH + (col_idx*2)) * BITWIDTH +: BITWIDTH ];
    assign d11 = data_in[ ((channel_idx*DATAHEIGHT*DATAWIDTH) + (row_idx*2+1)*DATAWIDTH + (col_idx*2+1)) * BITWIDTH +: BITWIDTH ];
    
    // -------------------
    // 池化流水线部分
    // -------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pool_reg[0] <= 0;
            pool_reg[1] <= 0;
            pool_reg[2] <= 0;
            pool_reg[3] <= 0;
            stage1_max0 <= 0;
            stage1_max1 <= 0;
            final_max   <= 0;
        end else if (clken) begin
            // 第一级：保存窗口元素
            pool_reg[0] <= d00;
            pool_reg[1] <= d01;
            pool_reg[2] <= d10;
            pool_reg[3] <= d11;
            
            // 第二级：两两比较
            stage1_max0 <= (pool_reg[0] > pool_reg[1]) ? pool_reg[0] : pool_reg[1];
            stage1_max1 <= (pool_reg[2] > pool_reg[3]) ? pool_reg[2] : pool_reg[3];
            
            // 第三级：最终最大值
            final_max   <= (stage1_max0 > stage1_max1) ? stage1_max0 : stage1_max1;
        end
    end

    // -------------------
    // 控制行列通道遍历
    // -------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            channel_idx <= 0;
            row_idx <= 0;
            col_idx <= 0;
            out_idx <= 0;
            result_out <= 0;
            result_valid_out <= 0;
        end else if (clken) begin
            if (out_idx < TOTAL_OUTPUTS) begin
                // 把池化后的最大值写到输出result_out的对应位置
                result_out[out_idx*BITWIDTH +: BITWIDTH] <= final_max;
                out_idx <= out_idx + 1;

                // 列计数，满了换行
                if (col_idx == OUTPUT_WIDTH-1) begin
                    col_idx <= 0;
                    if (row_idx == OUTPUT_HEIGHT-1) begin
                        row_idx <= 0;
                        // 行也满了，换通道
                        if (channel_idx == DATACHANNEL-1) begin
                            channel_idx <= 0;
                            result_valid_out <= 1; // 全部结束，拉高valid
                        end else begin
                            channel_idx <= channel_idx + 1;
                        end
                    end else begin
                        row_idx <= row_idx + 1;
                    end
                end else begin
                    col_idx <= col_idx + 1;
                end
            end else begin
                result_valid_out <= 0; // 完成后拉低valid
            end
        end
    end

endmodule
