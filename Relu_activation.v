`timescale 1ns / 1ps

module Relu_activation #(
    parameter integer BITWIDTH = 16,
    parameter integer DATA_WIDTH = 6,
    parameter integer DATA_HEIGHT = 6,
    parameter integer DATA_CHANNELS = 8,
    parameter integer PARALLEL_FACTOR = 4 // 并行处理的元素数量
) (
    input wire clk,
    input wire rst_n,
    input wire clken,
    input wire [BITWIDTH*2*DATA_HEIGHT*DATA_WIDTH*DATA_CHANNELS-1:0] data_in,
    output reg [BITWIDTH*2*DATA_HEIGHT*DATA_WIDTH*DATA_CHANNELS-1:0] data_out,
    output reg relu1_valid_out // 新增输出有效信号
);

    localparam integer TOTAL_ELEMENTS = DATA_HEIGHT * DATA_WIDTH * DATA_CHANNELS;
    localparam integer ITERATIONS = (TOTAL_ELEMENTS + PARALLEL_FACTOR - 1) / PARALLEL_FACTOR; // 向上取整

    // 并行处理寄存器
    reg [BITWIDTH*2-1:0] parallel_in [0:PARALLEL_FACTOR-1];
    reg [BITWIDTH*2-1:0] parallel_out [0:PARALLEL_FACTOR-1];
    reg [31:0] index;
    integer p;
    reg [31:0] cycle_count;

    // 状态控制和输出有效信号
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            index <= 0;
            cycle_count <= 0;
            relu1_valid_out <= 1'b0;
        end else if (clken) begin
            if (index < ITERATIONS - 1) begin
                index <= index + 1;
                cycle_count <= cycle_count + 1;
                relu1_valid_out <= 1'b0; // 仍在处理中
            end else begin
                index <= 0;
                cycle_count <= 0;
                relu1_valid_out <= 1'b1; // 完成一个完整的数据集
            end
        end
    end

    // 数据分发
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (p = 0; p < PARALLEL_FACTOR; p = p + 1) begin
                parallel_in[p] <= 0;
            end
        end else if (clken) begin
            for (p = 0; p < PARALLEL_FACTOR; p = p + 1) begin
                if ((index * PARALLEL_FACTOR + p) < TOTAL_ELEMENTS) begin
                    parallel_in[p] <= data_in[(index * PARALLEL_FACTOR + p) * BITWIDTH*2 +: BITWIDTH*2];
                end else begin
                    parallel_in[p] <= 0; // 超出范围填充0
                end
            end
        end
    end

    // 并行ReLU计算
    generate
        for (genvar g = 0; g < PARALLEL_FACTOR; g = g + 1) begin : relu_units
            always @(*) begin
                if (parallel_in[g][BITWIDTH*2-1] == 1'b0) begin // 正数或零
                    parallel_out[g] = parallel_in[g];
                end else begin // 负数
                    parallel_out[g] = {1'b0, {(BITWIDTH*2-1){1'b0}}}; // 输出0
                end
            end
        end
    endgenerate

    // 数据收集
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out <= 0;
        end else if (clken) begin
            for (p = 0; p < PARALLEL_FACTOR; p = p + 1) begin
                if ((index * PARALLEL_FACTOR + p) < TOTAL_ELEMENTS) begin
                    data_out[(index * PARALLEL_FACTOR + p) * BITWIDTH*2 +: BITWIDTH*2] <= parallel_out[p];
                end
            end
        end
    end

endmodule