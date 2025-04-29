module axi_write_controller #(
    parameter AXIS_ADDR_WIDTH                       = 32 // AXI 地址总线宽度
) (
    input  clk,                      // 系统时钟
    input  rst_n,                    // 低电平有效的复位信号

    // 来自视频驱动模块的 Buffer 满信号，用于触发 AXI 写传输
    input  buffer_full_a,
    input  buffer_full_b,

    // 输出给视频驱动模块的 AXI 写起始地址
    output reg [AXIS_ADDR_WIDTH-1:0] axi_write_addr
);

    reg [AXIS_ADDR_WIDTH-1:0] current_address; // 当前的 AXI 写地址

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位时，将当前地址和输出地址都清零
            current_address                         <= 'h00000000;
            axi_write_addr                          <= 'h00000000;
        end else begin
            // 当任何一个 Buffer 满时，更新 AXI 写地址
            if (buffer_full_a || buffer_full_b) begin
                axi_write_addr                      <= current_address; // 将当前地址输出给驱动模块
                current_address                     <= current_address + (BUFFER_DEPTH * (DATA_WIDTH / 8)); // 假设视频数据在内存中是连续存储的，计算下一个 Buffer 的起始地址
                // BUFFER_DEPTH 是每个 Buffer 存储的像素数量
                // DATA_WIDTH / 8 是每个像素的字节数 (24 / 8 = 3)
            end
        end
    end

    // 定义 DATA_WIDTH，如果在顶层模块中定义了，这里可以省略
    localparam DATA_WIDTH                           = 24;

endmodule