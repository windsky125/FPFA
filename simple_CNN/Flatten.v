`timescale 1ns / 1ps

module Flatten #(
  parameter integer BITWIDTH    = 16,
  parameter integer DATAWIDTH   = 6,
  parameter integer DATAHEIGHT  = 6,
  parameter integer DATACHANNEL = 3,
  parameter integer CNT_WIDTH    = 10
)(
  input  wire                             clk,
  input  wire                             rst_n,
  input  wire                             clken,
  
  // 输入接口
  input  wire [BITWIDTH*DATAWIDTH*DATAHEIGHT*DATACHANNEL-1:0] data_in,
  input  wire                             data_in_valid,
  
  // 输出接口
  output reg  [BITWIDTH-1:0]              data_out,
  output reg                              data_out_valid,
  output reg                              done
  
  // 调试接口（可选）
  //output wire [CNT_WIDTH-1:0]             output_count
);

  // 计算常量
  localparam integer TOTAL_DATA = DATAWIDTH * DATAHEIGHT * DATACHANNEL; // 总数据量

  // 状态定义
  localparam [1:0]
    IDLE       = 2'b00,
    LOAD_DATA  = 2'b01,
    SEND_DATA  = 2'b10;

  // 内部寄存器
  reg [1:0] state;
  reg [CNT_WIDTH-1:0] output_counter;
  reg [BITWIDTH*TOTAL_DATA-1:0] data_buffer; // 缓存数据
  reg buffer_full; // 标志位：表示数据是否完全接收并缓存完毕

  assign output_count = output_counter;

 always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 重置状态
        state <= IDLE;
        output_counter <= 0;
        data_buffer <= 0;
        data_out <= 0;
        data_out_valid <= 0;
        done <= 0;
        buffer_full <= 0;
    end else if (clken) begin
        // 默认设置
        data_out_valid <= 0; // 默认输出无效
        done <= 0;

        case (state)
            IDLE: begin
                if (data_in_valid) begin
                    // 接收数据并缓存
                    data_buffer <= data_in;
                    buffer_full <= 1'b1;
                    state <= SEND_DATA; // 直接转到发送数据状态
                    output_counter <= 0; // 重置输出计数器
                end
            end

            SEND_DATA: begin
                if (buffer_full) begin
                    // 输出当前数据
                    data_out <= data_buffer[output_counter*BITWIDTH +: BITWIDTH];
                    data_out_valid <= 1'b1; // 拉高输出有效信号
                    
                    if (output_counter == TOTAL_DATA - 1) begin
                        // 所有数据已输出
                        done <= 1'b1;
                        buffer_full <= 1'b0;

                        // 检查 data_in_valid 信号
                        if (data_in_valid) begin
                            // 如果仍然有效，保持状态为 SEND_DATA
                            // 这里可以选择继续处理新的数据
                            // 例如，您可以将 data_buffer 更新为新的输入数据
                            data_buffer <= data_in; // 更新数据
                            output_counter <= 0; // 重置输出计数器
                        end else begin
                            // 如果无效，回到空闲状态
                            state <= IDLE; // 回到空闲状态
                        end
                    end else begin
                        output_counter <= output_counter + 1; // 移动到下一个数据
                    end
                end
            end

            default: state <= IDLE;
        endcase
    end
end


endmodule
