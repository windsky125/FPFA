`timescale 1ns / 1ps

module FullConnect #(
    parameter integer BITWIDTH = 8,
    parameter integer LENGTH = 72,        // 展平后的特征长度
    parameter integer FILTERBATCH = 10    // 滤波器数量（输出通道数）
)(
    input wire clk,
    input wire rst_n,
    input wire clken,                    // 时钟使能
    input wire [BITWIDTH-1:0] data_in,    // 输入数据（串行输入）
    input wire data_in_valid,             // 输入数据有效信号
    input wire [BITWIDTH*LENGTH*FILTERBATCH-1:0] weight_in, // 权重矩阵
    input wire [BITWIDTH*FILTERBATCH-1:0] bias_in,          // 偏置向量
    output reg [2*BITWIDTH*FILTERBATCH-1:0] result_out,    // 输出结果
    output reg result_valid_out,          // 结果有效信号
    output reg done                       // 计算完成信号
);
    integer i;
    
    // ========== 寄存器定义 ==========
    reg [10:0] counter;  // 数据计数器
    reg [BITWIDTH-1:0] current_data_in;  // 当前输入数据寄存器
    reg weight_latched;                   // 权重已锁存标志
    
    // 权重和偏置寄存器
    reg [BITWIDTH*LENGTH*FILTERBATCH-1:0] weight_reg;
    reg [BITWIDTH*FILTERBATCH-1:0] bias_reg;
    
    // 累加器
    reg signed [BITWIDTH*2-1:0] accumulator [0:FILTERBATCH-1];

    // ========== 偏置展开 ==========
    wire signed [BITWIDTH-1:0] bias_array [0:FILTERBATCH-1];
    generate
        genvar k;
        for (k = 0; k < FILTERBATCH; k = k + 1) begin : BIAS_GEN
            assign bias_array[k] = $signed(bias_reg[(k+1)*BITWIDTH-1 -: BITWIDTH]);
        end
    endgenerate

    // ========== 乘法单元 ==========
    wire signed [BITWIDTH*2-1:0] mult_out [0:FILTERBATCH-1];
    
    generate
        genvar m;
        for (m = 0; m < FILTERBATCH; m = m + 1) begin : MULT_GEN
            Mult #(
                .BITWIDTH(BITWIDTH)
            ) u_mult (
                .a($signed(current_data_in)),
                .b($signed(weight_reg[((m*LENGTH)+counter)*BITWIDTH +: BITWIDTH])),
                .out(mult_out[m])
            );
        end
    endgenerate

    // ========== 主状态机 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 同步复位
            counter <= 0;
            weight_latched <= 1'b0;
            current_data_in <= {BITWIDTH{1'b0}};
            result_valid_out <= 1'b0;
            result_out<= {BITWIDTH*2*FILTERBATCH{1'b0}};
            done <= 1'b0;
            
            for (i = 0; i < FILTERBATCH; i = i + 1) begin
                accumulator[i] <= {BITWIDTH*2{1'b0}};
            end
        end else if (clken) begin
            // 输入数据寄存
            current_data_in <= data_in;
             result_out <= result_out;
            // 计算控制逻辑
            if (data_in_valid) begin
                // 锁存权重和偏置（只在第一个数据时）
                if (counter == 0 && !weight_latched) begin
                    weight_reg <= weight_in;
                    bias_reg <= bias_in;
                    weight_latched <= 1'b1;
                end
                
                // 累加阶段
                if (counter < LENGTH) begin
                    for (i = 0; i < FILTERBATCH; i = i + 1) begin
                        // 累加当前乘法结果
                        accumulator[i] <= accumulator[i] + mult_out[i];
                    end
                    counter <= counter + 1;
                    done <= 1'b0; // 计算未完成
                end
            end
            
            // 输出阶段
            if (counter == LENGTH && weight_latched) begin
                for (i = 0; i < FILTERBATCH; i = i + 1) begin
                    // 带符号的偏置加法
                    result_out[(i+1)*BITWIDTH*2-1 -: BITWIDTH*2] <= 
                        accumulator[i] + $signed(bias_array[i]);
                end
                result_valid_out <= 1'b1; // 输出有效
                done <= 1'b1; // 计算完成
                counter <= 0; // 重置计数器以准备下一次计算
                // 重置累加器以准备下一次计算
                for (i = 0; i < FILTERBATCH; i = i + 1) begin
                    accumulator[i] <= {BITWIDTH*2{1'b0}}; // 清零累加器
                end
                weight_latched <= 1'b0;  // 准备下一次计算
            end else begin
                result_valid_out <= 1'b0; // 输出无效
                if (!data_in_valid) done <= 1'b0; // 如果输入无效，重置done信号
            end
        end
    end

endmodule

