`timescale 1ns / 1ps

module ConvKernel #(
    parameter integer BITWIDTH     = 8,       // 数据位宽
    parameter integer DATACHANNEL  = 3,       // 输入通道数
    parameter integer FILTERHEIGHT = 5,       // 滤波器高度
    parameter integer FILTERWIDTH  = 5        // 滤波器宽度
)(
    input wire clk,
    input wire clken,                 // 时钟使能
    input wire valid_in,              // 输入有效标志
    
    // 输入数据窗口 [C×H×W]
    input wire [BITWIDTH*DATACHANNEL*FILTERHEIGHT*FILTERWIDTH-1:0] data,
    // 权重参数 [C×H×W] 
    input wire [BITWIDTH*DATACHANNEL*FILTERHEIGHT*FILTERWIDTH-1:0] weight,
    input wire [BITWIDTH-1:0] bias,   // 偏置
    
    output reg signed [BITWIDTH*2-1:0] result,  // 卷积结果（带符号）
    output reg valid_out
);

    // ============= 参数声明 =============
    localparam integer KERNEL_SIZE = FILTERHEIGHT * FILTERWIDTH * DATACHANNEL;
    localparam integer ACC_WIDTH = BITWIDTH*2 + $clog2(KERNEL_SIZE);

    // ============= 第一级：乘法阵列 =============
    wire signed [BITWIDTH*2-1:0] mult_out [0:KERNEL_SIZE-1];
    generate
        genvar i;
        for(i = 0; i < KERNEL_SIZE; i = i + 1) begin : mult_gen
            Mult#(.BITWIDTH(BITWIDTH)) mult_inst(
                .a(data[(i+1)*BITWIDTH-1 : i*BITWIDTH]),
                .b(weight[(i+1)*BITWIDTH-1 : i*BITWIDTH]),
                .out(mult_out[i])
            );
        end
    endgenerate

    // ============= 第二级：累加器 =============
    reg signed [ACC_WIDTH-1:0] acc_result;
    reg valid_stage1;
    integer j;

    always @(posedge clk) begin
        if (!clken) begin
            acc_result   <= {ACC_WIDTH{1'b0}};
            valid_stage1 <= 1'b0;
        end
        else begin
            if (valid_in) begin
                acc_result <= {ACC_WIDTH{1'b0}};  // 使用位宽明确的清零
                for (j=0; j<KERNEL_SIZE; j=j+1) begin
                    acc_result <= acc_result + mult_out[j];
                end
                valid_stage1 <= 1'b1;
            end
            else begin
                valid_stage1 <= 1'b0;
            end
        end
    end

    // ============= 第三级：偏置加法 =============
    always @(posedge clk) begin
        if (!clken) begin
            result    <= {BITWIDTH*2{1'b0}};
            valid_out <= 1'b0;
        end
        else begin
            result <= (valid_stage1) ? (acc_result + $signed({{(ACC_WIDTH-BITWIDTH){bias[BITWIDTH-1]}}, bias})) 
                              : {BITWIDTH*2{1'b0}};
            valid_out <= valid_stage1;
        end
    end

endmodule