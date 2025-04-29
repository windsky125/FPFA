`timescale 1ns / 1ps

module Relu_activation #(
    parameter BITWIDTH        = 16,
    parameter DATA_WIDTH     = 6,
    parameter DATA_HEIGHT    = 6,
    parameter DATA_CHANNELS  = 8,
    parameter PARALLEL_FACTOR = 4
) (
    input wire clk,
    input wire rst_n,
    input wire clken,
    input wire [BITWIDTH*2*DATA_HEIGHT*DATA_WIDTH*DATA_CHANNELS-1:0] data_in,
    output reg [BITWIDTH*2*DATA_HEIGHT*DATA_WIDTH*DATA_CHANNELS-1:0] data_out,
    output reg relu1_valid_out
);

    // 参数计算
    localparam TOTAL_ELEMENTS = DATA_HEIGHT * DATA_WIDTH * DATA_CHANNELS;
    localparam ELEMENT_WIDTH = BITWIDTH * 2;
    localparam ITERATIONS = (TOTAL_ELEMENTS + PARALLEL_FACTOR - 1) / PARALLEL_FACTOR;

    // 寄存器声明
    reg [ELEMENT_WIDTH-1:0] internal_data_out [0:TOTAL_ELEMENTS-1];
    reg [31:0] process_index;
    reg [1:0] state;
    
    // 循环变量声明（必须放在always块外部）
    integer j, k, p;
    integer current_idx, store_idx;

    // 状态定义
    localparam IDLE       = 2'b00;
    localparam PROCESSING = 2'b01;
    localparam OUTPUT     = 2'b10;

    // 并行处理信号
    reg [ELEMENT_WIDTH-1:0] parallel_in [0:PARALLEL_FACTOR-1];
    wire [ELEMENT_WIDTH-1:0] parallel_out [0:PARALLEL_FACTOR-1];

    // 生成并行ReLU单元
    genvar i;
    generate
        for (i = 0; i < PARALLEL_FACTOR; i = i + 1) begin : RELU_UNITS
            assign parallel_out[i] = parallel_in[i][ELEMENT_WIDTH-1] ? 
                                   {ELEMENT_WIDTH{1'b0}} : parallel_in[i];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位逻辑
            process_index <= 0;
            state <= IDLE;
            relu1_valid_out <= 1'b0;
            data_out <= 0;
            
            // 初始化存储器（使用预声明的循环变量j）
            for (j = 0; j < TOTAL_ELEMENTS; j = j + 1) begin
                internal_data_out[j] <= 0;
            end
            
            // 初始化并行输入（使用预声明的循环变量k）
            for (k = 0; k < PARALLEL_FACTOR; k = k + 1) begin
                parallel_in[k] <= 0;
            end
        end
        else if (clken) begin
            case (state)
                IDLE: begin
                    process_index <= 0;
                    state <= PROCESSING;
                    relu1_valid_out <= 1'b0;
                end
                
                PROCESSING: begin
                    if (process_index < ITERATIONS) begin
                        // 加载数据到并行单元
                        for (p = 0; p < PARALLEL_FACTOR; p = p + 1) begin
                            current_idx = process_index * PARALLEL_FACTOR + p;
                            if (current_idx < TOTAL_ELEMENTS) begin
                                parallel_in[p] <= data_in[current_idx*ELEMENT_WIDTH +: ELEMENT_WIDTH];
                            end
                            else begin
                                parallel_in[p] <= 0;
                            end
                        end
                        
                        // 存储结果（流水线设计）
                        if (process_index > 0) begin
                            for (p = 0; p < PARALLEL_FACTOR; p = p + 1) begin
                                store_idx = (process_index-1)*PARALLEL_FACTOR + p;
                                if (store_idx < TOTAL_ELEMENTS) begin
                                    internal_data_out[store_idx] <= parallel_out[p];
                                end
                            end
                        end
                        
                        process_index <= process_index + 1;
                    end
                    else begin
                        // 存储最后一批数据
                        for (p = 0; p < PARALLEL_FACTOR; p = p + 1) begin
                            store_idx = (ITERATIONS-1)*PARALLEL_FACTOR + p;
                            if (store_idx < TOTAL_ELEMENTS) begin
                                internal_data_out[store_idx] <= parallel_out[p];
                            end
                        end
                        state <= OUTPUT;
                    end
                end
                
                OUTPUT: begin
                    // 将数组转换为打包输出
                    for (j = 0; j < TOTAL_ELEMENTS; j = j + 1) begin
                        data_out[j*ELEMENT_WIDTH +: ELEMENT_WIDTH] <= internal_data_out[j];
                    end
                    relu1_valid_out <= 1'b1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule