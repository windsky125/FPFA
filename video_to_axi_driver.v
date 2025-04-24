module video_to_axi_driver #(
    parameter DATA_WIDTH                = 24,       // RGB888: 每个像素 3 个字节 (红、绿、蓝)
    parameter AXIS_DATA_WIDTH           = 24,       // AXI Stream 数据总线宽度，应与 DATA_WIDTH 匹配
    parameter AXIS_ADDR_WIDTH           = 32,       // AXI 地址总线宽度
    parameter BUFFER_DEPTH              = 1024      // 每个乒乓 Buffer 的深度，决定了可以缓存多少个像素 (根据视频尺寸调整)
) (
    input  clk,                      // 系统时钟
    input  rst_n,                    // 低电平有效的复位信号

    // 视频输入接口 (假设是 AXI Stream 接口)
    input  axis_video_aclk,          // 视频数据流的时钟
    input  axis_video_aresetn,       // 视频数据流的低电平有效复位
    input  axis_video_tvalid,        // 视频数据有效信号，高电平表示 tdata 上的数据有效
    output reg axis_video_tready,   // 模块准备好接收视频数据的信号，高电平表示可以接收
    input  [AXIS_DATA_WIDTH-1:0] axis_video_tdata, // 输入的视频数据
    input  axis_video_tlast,         // 指示当前传输是否是帧的最后一个数据包

    // AXI Write Master 接口
    output reg  [AXIS_ADDR_WIDTH-1:0]   awaddr,  // AXI 写地址
    output reg  [2:0]                   awprot,  // AXI 写保护控制信号
    output reg                          awvalid, // AXI 写地址有效信号
    input                               awready, // SmartConnect 准备好接收写地址的信号

    output reg  [AXIS_DATA_WIDTH/8-1:0] wstrb, // AXI 写字节使能信号 (对于 RGB888，通常全为 1)
    output reg  [AXIS_DATA_WIDTH-1:0]   wdata,  // AXI 写数据
    output reg                          wvalid,  // AXI 写数据有效信号
    input                               wready,  // SmartConnect 准备好接收写数据的信号
    output reg                          wlast,   // 指示当前写数据是否是 Burst 的最后一个数据包

    input                               bvalid,  // AXI 写响应有效信号
    output reg                          bready,  // 模块准备好接收写响应的信号
    input   [1:0]                       bresp    // AXI 写响应 (例如 OKAY, SLVERR, DECERR)
);

    // -------------------- 内部信号 --------------------
    reg [DATA_WIDTH-1:0]            buffer_a [0:BUFFER_DEPTH-1]; // 乒乓 Buffer A
    reg [DATA_WIDTH-1:0]            buffer_b [0:BUFFER_DEPTH-1]; // 乒乓 Buffer B

    reg [clog2(BUFFER_DEPTH)-1:0]   write_ptr_a; // 指向 Buffer A 的写指针 (使用 clog2 计算位宽)
    reg [clog2(BUFFER_DEPTH)-1:0]   write_ptr_b; // 指向 Buffer B 的写指针
    reg                             current_write_buffer; // 当前正在写入的 Buffer 选择 (0: Buffer A, 1: Buffer B)

    reg [clog2(BUFFER_DEPTH)-1:0]   read_ptr_a;  // 指向 Buffer A 的读指针
    reg [clog2(BUFFER_DEPTH)-1:0]   read_ptr_b;  // 指向 Buffer B 的读指针
    reg                             current_read_buffer;   // 当前正在读取的 Buffer 选择 (0: Buffer A, 1: Buffer B)

    reg                             buffer_a_full; // 标记 Buffer A 是否已满
    reg                             buffer_b_full; // 标记 Buffer B 是否已满

    reg                             transfer_active;           // 标记当前是否有 AXI 写传输正在进行
    reg [AXIS_ADDR_WIDTH-1:0]       current_axi_addr; // 当前 AXI 传输的起始地址 (由控制模块提供)
    reg [clog2(BUFFER_DEPTH)-1:0]   transfer_count; // 当前 AXI Burst 传输的计数器

    // -------------------- 视频数据输入逻辑 --------------------
    // 当模块准备好接收 (tready) 且视频数据有效 (tvalid) 时，接收数据
    assign axis_video_tready = (current_write_buffer == 0 && !buffer_a_full) || (current_write_buffer == 1 && !buffer_b_full);

    always @(posedge axis_video_aclk or negedge axis_video_aresetn) begin
        if (!axis_video_aresetn) begin
            // 复位时，写指针和当前写 Buffer 选择清零，Buffer 未满
            write_ptr_a                 <= 0;
            write_ptr_b                 <= 0;
            current_write_buffer        <= 0;
            buffer_a_full               <= 0;
            buffer_b_full               <= 0;
        end else if (axis_video_tvalid && axis_video_tready) begin
            // 根据当前写入的 Buffer 选择，将数据写入相应的 Buffer
            if (current_write_buffer == 0) begin
                buffer_a[write_ptr_a]   <= axis_video_tdata;
                // 当 Buffer A 写满 (达到深度 - 1) 或接收到帧的最后一个数据包 (tlast) 时，标记为满
                if (write_ptr_a == BUFFER_DEPTH - 1 || axis_video_tlast) begin
                    buffer_a_full       <= 1;
                end else begin
                    write_ptr_a         <= write_ptr_a + 1; // 增加写指针
                end
            end else begin
                buffer_b[write_ptr_b]   <= axis_video_tdata;
                // 当 Buffer B 写满或接收到帧的最后一个数据包时，标记为满
                if (write_ptr_b == BUFFER_DEPTH - 1 || axis_video_tlast) begin
                    buffer_b_full       <= 1;
                end else begin
                    write_ptr_b         <= write_ptr_b + 1; // 增加写指针
                end
            end

            // 当接收到帧的最后一个数据包时，切换写 Buffer，并重置相应 Buffer 的写指针和满标志
            if (axis_video_tlast) begin
                current_write_buffer    <= ~current_write_buffer; // 切换 Buffer (0 -> 1, 1 -> 0)
                if (current_write_buffer == 0) begin
                    write_ptr_a         <= 0;
                    buffer_a_full       <= 0;
                end else begin
                    write_ptr_b         <= 0;
                    buffer_b_full       <= 0;
                end
            end
        end
    end

    // -------------------- AXI Write 控制逻辑 --------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位时，读指针、当前读 Buffer 选择、传输活动标志、AXI 信号等都清零
            read_ptr_a                  <= 0;
            read_ptr_b                  <= 0;
            current_read_buffer         <= 1; // 初始状态假设 Buffer A 已经准备好被写入数据
            transfer_active             <= 0;
            awvalid                     <= 0;
            wvalid                      <= 0;
            wlast                       <= 0;
            bready                      <= 0;
            current_axi_addr            <= '0;
            transfer_count              <= 0;
        end else begin
            bready                      <= bvalid; // 简单地在响应有效时准备好接收响应

            if (transfer_active) begin
                // AXI Write 数据传输阶段
                if (wvalid && wready) begin
                    // 当写数据有效且 SmartConnect 准备好接收时
                    transfer_count      <= transfer_count + 1; // 增加传输计数

                    // 根据当前读取的 Buffer 选择，将数据发送到 AXI 总线
                    if (current_read_buffer == 0) begin
                        wdata           <= buffer_a[read_ptr_a];
                        // 当读取到 Buffer A 的最后一个数据时，标记为 Burst 的最后一个数据包
                        if (read_ptr_a == BUFFER_DEPTH - 1) begin
                            wlast       <= 1;
                        end else begin
                            read_ptr_a  <= read_ptr_a + 1; // 增加读指针
                            wlast       <= 0;
                        end
                    end else begin
                        wdata           <= buffer_b[read_ptr_b];
                        // 当读取到 Buffer B 的最后一个数据时，标记为 Burst 的最后一个数据包
                        if (read_ptr_b == BUFFER_DEPTH - 1) begin
                            wlast       <= 1;
                        end else begin
                            read_ptr_b  <= read_ptr_b + 1; // 增加读指针
                            wlast       <= 0;
                        end
                    end

                    // 当传输完一个 Buffer 的所有数据后，停止发送写数据
                    if (transfer_count == BUFFER_DEPTH - 1) begin
                        wvalid          <= 0;
                    end
                end

                // AXI Write 地址通道握手
                // 当地址无效且当前读取的 Buffer 已满时，发送写地址
                if (!awvalid && ((current_read_buffer == 0 && buffer_a_full) || (current_read_buffer == 1 && buffer_b_full))) begin
                    awaddr              <= current_axi_addr; // 设置起始地址 (由控制模块提供)
                    awprot              <= 3'b000; // 设置保护控制信号为默认值
                    awvalid             <= 1;    // 使地址有效
                end else if (awvalid && awready) begin
                    // 当地址有效且 SmartConnect 准备好接收时，地址发送完成，开始发送数据
                    awvalid             <= 0;
                    wvalid              <= 1;
                    transfer_count      <= 0; // 重置传输计数
                    // 重置读指针
                    if (current_read_buffer == 0) begin
                        read_ptr_a      <= 0;
                    end else begin
                        read_ptr_b      <= 0;
                    end
                end

                // 等待 AXI Write 响应
                if (bvalid && bready) begin
                    // 当接收到有效的写响应时，结束当前传输
                    transfer_active     <= 0;
                    // 切换读 Buffer，使得刚刚写入的 Buffer 可以被新的视频数据填充
                    current_read_buffer <= ~current_read_buffer;
                    // 清空刚刚发送完的 Buffer 的满标志
                    if (current_read_buffer == 0) begin
                        buffer_a_full   <= 0;
                    end else begin
                        buffer_b_full   <= 0;
                    end
                end
            end else begin
                // 启动新的 AXI 传输
                // 当一个 Buffer 写满且当前没有正在进行的传输时，启动传输
                if ((current_read_buffer == 0 && buffer_a_full) || (current_read_buffer == 1 && buffer_b_full)) begin
                    transfer_active     <= 1;
                end
            end

            // 设置写字节使能，对于 24 位数据，所有字节都使能
            wstrb                       <= {AXIS_DATA_WIDTH/8{1'b1}};
        end
    end

    // 计算 clog2 (ceiling of log base 2)
    function integer clog2 (input integer depth);
        for (clog2=0; depth>1; clog2=clog2+1)
            depth                       = depth >> 1;
    endfunction

endmodule
