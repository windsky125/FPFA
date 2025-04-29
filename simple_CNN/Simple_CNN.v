`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 公司:
// 工程师:
//
// 创建日期: 2025/04/26 16:07:25
// 设计名称: Simple_CNN
// 模块名称: Simple_CNN
// 项目名称:
// 目标器件:
// 工具版本:
// 描述: 一个简单的卷积神经网络，包含一个卷积层、ReLU 激活、最大池化和一个全连接层 (顶层流水线).
//
// 依赖: Conv2d, Relu_activation, Max_pool, FullConnect 模块.
//
// 修订:
// 修订 0.08 - 按照用户提供的模板补全代码
// 附加注释:
// ------------------ 网络结构流程 ------------------
//
// input_image -> Conv2d_inst (延迟) -> conv1_out_reg (valid)
//                                     |
//                                     v
// conv1_out_reg (valid) -> Relu_activation_inst -> relu1_out_reg
//                                     |
//                                     v
// relu1_out_reg -> Max_pool_inst -> pool1_out_reg
//                                     |
//                                     v
// pool1_out_reg -> flatten_out_reg
//                                     |
//                                     v
// flatten_out_reg -> FullConnect_inst -> fc1_out_reg
//                                      \
//                                       V
//                                    output_scores, output_valid
// --------------------------------------------------
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module SimpleCNN #(
    parameter integer BITWIDTH = 8,                                             // 数据位宽
    parameter integer IMAGE_WIDTH = 8,                                        // 输入图像宽度
    parameter integer IMAGE_HEIGHT = 8,                                       // 输入图像高度
    parameter integer IMAGE_CHANNELS = 3,                                      // 输入图像通道数
    parameter integer CONV1_FILTER_SIZE = 3,                                   // 卷积层 1 滤波器尺寸
    parameter integer CONV1_OUTPUT_CHANNELS = 8,                               // 卷积层 1 输出通道数
    parameter integer POOL1_KERNEL_SIZE = 2,                                   // 池化层 1 核尺寸
    parameter integer FC1_OUTPUT_UNITS = 10                                    // 全连接层 1 输出单元数
)(
    input wire clk,                                                           // 时钟信号
    input wire rst_n,                                                         // 复位信号 (低有效)
    input wire clken,                                                         // 时钟使能信号
    input wire [BITWIDTH*IMAGE_HEIGHT*IMAGE_WIDTH*IMAGE_CHANNELS-1:0] input_image, // 输入图像数据
    input wire [BITWIDTH*CONV1_FILTER_SIZE*CONV1_FILTER_SIZE*IMAGE_CHANNELS*CONV1_OUTPUT_CHANNELS-1:0] conv1_weight, // 卷积层 1 权重
    input wire [BITWIDTH*CONV1_OUTPUT_CHANNELS-1:0] conv1_bias,                // 卷积层 1 偏置
    input wire [2*BITWIDTH*((IMAGE_WIDTH-CONV1_FILTER_SIZE+1)/POOL1_KERNEL_SIZE)*((IMAGE_HEIGHT-CONV1_FILTER_SIZE+1)/POOL1_KERNEL_SIZE)*CONV1_OUTPUT_CHANNELS*FC1_OUTPUT_UNITS-1:0] fc1_weight, // 全连接层 1 权重
    input wire [2*BITWIDTH*FC1_OUTPUT_UNITS-1:0] fc1_bias,                       // 全连接层 1 偏置
    output reg [BITWIDTH*4*FC1_OUTPUT_UNITS-1:0] output_scores,                // 输出得分
    output reg output_valid                                                   // 输出有效信号
);

    // 参数计算
    localparam integer CONV1_OUT_WIDTH = (IMAGE_WIDTH - CONV1_FILTER_SIZE + 1);
    localparam integer CONV1_OUT_HEIGHT = (IMAGE_HEIGHT - CONV1_FILTER_SIZE + 1);
    localparam integer POOL1_OUT_WIDTH = CONV1_OUT_WIDTH / POOL1_KERNEL_SIZE;
    localparam integer POOL1_OUT_HEIGHT = CONV1_OUT_HEIGHT / POOL1_KERNEL_SIZE;
    localparam integer FLATTEN_LENGTH = POOL1_OUT_WIDTH * POOL1_OUT_HEIGHT * CONV1_OUTPUT_CHANNELS;

    // 状态机定义
    localparam [3:0]  // 修改状态定义，增加 FLATTEN 状态
        IDLE    = 4'b0000,   // 空闲状态
        CONV    = 4'b0001,   // 卷积状态
        RELU    = 4'b0010,   // ReLU 激活状态
        POOL    = 4'b0011,   // 池化状态
        FLATTEN_PC = 4'b0100,   // 展平_全连接状态
        OUTPUT      = 4'b0101;   // 输出

    reg [3:0] state_reg, state_next;  // 修改状态寄存器为 4 位

    // 中间信号和寄存器
    wire [BITWIDTH*2*CONV1_OUT_HEIGHT*CONV1_OUT_WIDTH*CONV1_OUTPUT_CHANNELS-1:0] conv1_out_wire;  // 卷积层 1 的输出
    wire conv1_valid_out;                                                                         // 卷积层 1 输出有效信号

    wire [BITWIDTH*2*CONV1_OUT_HEIGHT*CONV1_OUT_WIDTH*CONV1_OUTPUT_CHANNELS-1:0] relu1_out_wire;  // ReLU 激活函数的输出
    wire relu1_valid_out;                                                                         // Rlu输出有效信号

    wire [BITWIDTH*2*POOL1_OUT_HEIGHT*POOL1_OUT_WIDTH*CONV1_OUTPUT_CHANNELS-1:0] pool1_out_wire; // 池化层输出
    wire pool1_valid_out;                                                     // 池化层输出valid

    wire [BITWIDTH*2 - 1:0] flatten_out_wire; // 展平层输出 (串行)
    wire flatten_valid_out;                   // 展平层输出 valid

    wire [BITWIDTH*4*FC1_OUTPUT_UNITS-1:0] fc1_out_wire;                         // 全连接层 1 的输出
    wire pc_out_done;
    wire fc_valid_out;
    reg [2:0] output_delay_counter; // 用于延迟输出的计数器
    reg delayed_output_valid;
    
    // 实例化卷积层 1
    Conv2d #(
        .BITWIDTH(BITWIDTH),
        .DATAWIDTH(IMAGE_WIDTH),
        .DATAHEIGHT(IMAGE_HEIGHT),
        .DATACHANNEL(IMAGE_CHANNELS),
        .FILTERHEIGHT(CONV1_FILTER_SIZE),
        .FILTERWIDTH(CONV1_FILTER_SIZE),
        .FILTERBATCH(CONV1_OUTPUT_CHANNELS),
        .STRIDEHEIGHT(1),
        .STRIDEWIDTH(1),
        .PADDINGENABLE(0),
        .PARALLEL_OUT(4),
        .PARALLEL_FILTER(4)
    ) conv1_inst (
        .clk(clk),
        .rst_n(rst_n),
        .clken(clken && (state_reg == CONV)),                                     // 只有在 CONV 状态才使能
        .data_in(input_image),
        .filterWeight_in(conv1_weight),
        .filterBias_in(conv1_bias),
        .result_out(conv1_out_wire),
        .result_valid_out(conv1_valid_out)
    );

    // 实例化 ReLU 激活函数
    Relu_activation #(
        .BITWIDTH(BITWIDTH),                                                    // 位宽与卷积输出匹配
        .DATA_WIDTH(CONV1_OUT_WIDTH),
        .DATA_HEIGHT(CONV1_OUT_HEIGHT),
        .DATA_CHANNELS(CONV1_OUTPUT_CHANNELS),
        .PARALLEL_FACTOR(4)                                                       // 并行处理因子
    ) relu1_inst (
        .clk(clk),
        .rst_n(rst_n),
        .clken(clken && (state_reg == RELU)),                  // 只有在 RELU 状态且卷积完成才使能
        .data_in(conv1_out_wire),                                                 // 接收卷积层的输出
        .data_out(relu1_out_wire),                                                // ReLU 的输出
        .relu1_valid_out(relu1_valid_out)                                         // 连接新的 valid 输出
    );

    Max_pool #(
        .BITWIDTH(BITWIDTH*2),
        .DATAWIDTH(CONV1_OUT_WIDTH),
        .DATAHEIGHT(CONV1_OUT_HEIGHT),
        .DATACHANNEL(CONV1_OUTPUT_CHANNELS),
        .KWIDTH(POOL1_KERNEL_SIZE),
        .KHEIGHT(POOL1_KERNEL_SIZE)
    ) pool1_inst (
        .clk(clk),
        .rst_n(rst_n),
        .clken(clken && (state_reg == POOL)),
        .data_in(relu1_out_wire),
        .result_out(pool1_out_wire),
        .result_valid_out(pool1_valid_out)
    );

    Flatten #(
        .BITWIDTH(BITWIDTH*2),
        .DATAWIDTH(POOL1_OUT_WIDTH),
        .DATAHEIGHT(POOL1_OUT_HEIGHT),
        .DATACHANNEL(CONV1_OUTPUT_CHANNELS)
    ) flatten_inst (
        .clk(clk),
        .rst_n(rst_n),
        .clken(clken),  // 控制使能信号
        .data_in(pool1_out_wire),                 // 来自池化层的输出
        .data_in_valid(pool1_valid_out),          //输入数据有效
        .data_out(flatten_out_wire),              // 展平后的数据输出
        .data_out_valid(flatten_valid_out),       // 展平后的有效信号
        .done()
    );
    
    // 实例化全连接层
    FullConnect #(
        .BITWIDTH(BITWIDTH*2),
        .LENGTH(FLATTEN_LENGTH),
        .FILTERBATCH(FC1_OUTPUT_UNITS)
    ) fc1_inst (
        .clk(clk),
        .rst_n(rst_n),
        .clken(clken && (state_reg == FLATTEN_PC)),  // 控制使能信号
        .data_in(flatten_out_wire),           // 来自展平层的数据
        .data_in_valid(flatten_valid_out),             // 来自展平层的 valid 信号
        .weight_in(fc1_weight),
        .bias_in(fc1_bias),
        .result_out(fc1_out_wire),
        .result_valid_out(fc_valid_out),
        .done(pc_out_done)
    );
    // 状态机时序逻辑
   always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg <= IDLE;
            output_delay_counter <= 0; // 初始化延迟计数器
            delayed_output_valid <= 1'b0;
        end else begin
            state_reg <= state_next;
            if (state_reg == OUTPUT) begin
                if (output_delay_counter < 5) begin
                    output_delay_counter <= output_delay_counter + 1;
                    delayed_output_valid <= 1'b0;
                end else begin
                    output_delay_counter <= 0;
                    delayed_output_valid <= 1'b1;
                end
            end else begin
                output_delay_counter <= 0;
                delayed_output_valid <= 1'b0;
            end
        end
    end

    // 修改状态转移逻辑

    always @(*) begin
        state_next = state_reg;                      // 默认保持当前状态
        case (state_reg)
            IDLE: if (clken) state_next = CONV;      // 使能时进入卷积状态
            CONV: if (conv1_valid_out && clken) state_next = RELU;  // 卷积完成且使能时进入 ReLU
            RELU: if (relu1_valid_out && clken) state_next = POOL;  // ReLU 完成且使能时进入池化
            POOL: if (pool1_valid_out && clken) state_next =  FLATTEN_PC;  // 池化完成且使能时进入展平
            FLATTEN_PC: if (pc_out_done && clken) state_next = OUTPUT;      // 展平后且使能时进入全连接
            OUTPUT: if (delayed_output_valid) state_next = IDLE;     // 输出完成且使能时返回 IDLE
            default: state_next = IDLE;
        endcase
    end
    

    

    // 输出逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_scores <= 0;                                           // 复位时清空输出
            output_valid <= 0;                                            // 输出有效信号清零
        end else if (state_reg == OUTPUT) begin
            output_scores <= fc1_out_wire;                                 // 输出全连接层的结果
            output_valid <= 1;                                            // 输出有效信号
        end else begin
            output_valid <= 0;                                            // 非输出状态时无效
        end
    end

endmodule
