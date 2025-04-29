module top_module (
    input  clk,                      // 系统时钟
    input  rst_n,                    // 低电平有效的复位信号

    // 视频输入接口
    input  axis_video_aclk,          // 视频数据流的时钟
    input  axis_video_aresetn,       // 视频数据流的低电平有效复位
    input  axis_video_tvalid,        // 视频数据有效信号，高电平表示 tdata 上的数据有效
    output wire axis_video_tready,   // 注意这里是 wire，由 `video_to_axi_driver` 模块驱动
    input  [23:0] axis_video_tdata, // 输入的 24 位 RGB888 视频数据
    input  axis_video_tlast,         // 指示当前传输是否是帧的最后一个数据包

    // 连接到 SmartConnect 的 AXI Master 接口
    output wire [31:0] axi_awaddr,  // AXI 写地址输出
    output wire [2:0]  axi_awprot,  // AXI 写保护控制信号输出
    output wire        axi_awvalid, // AXI 写地址有效信号输出
    input  wire        axi_awready, // SmartConnect 准备好接收写地址的信号输入

    output wire [23:0] axi_wdata,   // AXI 写数据输出
    output wire [2:0]  axi_wstrb,   // AXI 写字节使能信号输出 (3'b111 表示所有字节都使能)
    output wire        axi_wvalid,  // AXI 写数据有效信号输出
    input  wire        axi_wready,  // SmartConnect 准备好接收写数据的信号输入
    output wire        axi_wlast,   // 指示当前写数据是否是 Burst 的最后一个数据包输出

    input  wire        axi_bvalid,  // AXI 写响应有效信号输入
    output wire        axi_bready,  // 模块准备好接收写响应的信号输出
    input  wire [1:0]  axi_bresp    // AXI 写响应 (例如 OKAY, SLVERR, DECERR) 输入
);

    // -------------------- 参数 --------------------
    localparam DATA_WIDTH      = 24;       // 定义数据宽度为 24 位 (RGB888)
    localparam AXIS_DATA_WIDTH = 24;       // 定义 AXI Stream 数据宽度为 24 位
    localparam AXIS_ADDR_WIDTH = 32;       // 定义 AXI 地址宽度为 32 位
    localparam BUFFER_DEPTH    = 1024;     // 定义每个乒乓 Buffer 的深度

    // -------------------- 内部信号 --------------------
    wire [AXIS_ADDR_WIDTH-1:0] driver_awaddr;     // 连接 `video_to_axi_driver` 的 AXI 写地址
    wire [2:0]                driver_awprot;     // 连接 `video_to_axi_driver` 的 AXI 写保护控制信号
    wire                       driver_awvalid;    // 连接 `video_to_axi_driver` 的 AXI 写地址有效信号
    wire                       driver_awready;    // 连接 `video_to_axi_driver` 的 AXI 写地址就绪信号

    wire [AXIS_DATA_WIDTH/8-1:0] driver_wstrb;    // 连接 `video_to_axi_driver` 的 AXI 写字节使能信号
    wire [AXIS_DATA_WIDTH-1:0] driver_wdata;      // 连接 `video_to_axi_driver` 的 AXI 写数据
    wire                       driver_wvalid;     // 连接 `video_to_axi_driver` 的 AXI 写数据有效信号
    wire                       driver_wready;     // 连接 `video_to_axi_driver` 的 AXI 写数据就绪信号
    wire                       driver_wlast;      // 连接 `video_to_axi_driver` 的 AXI 写最后一个数据包信号

    wire                       driver_bvalid;     // 连接 `video_to_axi_driver` 的 AXI 写响应有效信号
    reg                        driver_bready;     // 连接 `video_to_axi_driver` 的 AXI 写响应就绪信号 (在顶层控制)
    wire [1:0]                driver_bresp;      // 连接 `video_to_axi_driver` 的 AXI 写响应

    wire [AXIS_ADDR_WIDTH-1:0] ctrl_axi_write_addr; // 连接 `axi_write_controller` 的 AXI 写起始地址
    wire                       buffer_full_a_sig;   // 连接 `video_to_axi_driver` 的 Buffer A 满信号
    wire                       buffer_full_b_sig;   // 连接 `video_to_axi_driver` 的 Buffer B 满信号

    // -------------------- 模块实例化 --------------------
    video_to_axi_driver #(                      // 实例化 `video_to_axi_driver` 模块
        .DATA_WIDTH      (DATA_WIDTH),
        .AXIS_DATA_WIDTH (AXIS_DATA_WIDTH),
        .AXIS_ADDR_WIDTH (AXIS_ADDR_WIDTH),
        .BUFFER_DEPTH    (BUFFER_DEPTH)
    ) u_video_to_axi_driver (
        .clk               (clk),
        .rst_n             (rst_n),

        .axis_video_aclk   (axis_video_aclk),
        .axis_video_aresetn(axis_video_aresetn),
        .axis_video_tvalid (axis_video_tvalid),
        .axis_video_tready (axis_video_tready),
        .axis_video_tdata  (axis_video_tdata),
        .axis_video_tlast  (axis_video_tlast),

        .awaddr            (driver_awaddr),
        .awprot            (driver_awprot),
        .awvalid           (driver_awvalid),
        .awready           (driver_awready),

        .wstrb             (driver_wstrb),
        .wdata             (driver_wdata),
        .wvalid            (driver_wvalid),
        .wready            (driver_wready),
        .wlast             (driver_wlast),

        .bvalid            (driver_bvalid),
        .bready            (driver_bready),
        .bresp             (driver_bresp)
    );

    axi_write_controller #(                  // 实例化 `axi_write_controller` 模块
        .AXIS_ADDR_WIDTH (AXIS_ADDR_WIDTH)
    ) u_axi_write_controller (
        .clk             (clk),
        .rst_n           (rst_n),
        .buffer_full_a   (u_video_to_axi_driver.buffer_a_full), // 将 Buffer A 满信号连接到控制器
        .buffer_full_b   (u_video_to_axi_driver.buffer_b_full), // 将 Buffer B 满信号连接到控制器
        .axi_write_addr  (ctrl_axi_write_addr)                  // 将控制器输出的写地址连接到内部信号
    );

    // 连接到 SmartConnect 的 AXI Master 接口
    assign axi_awaddr  = driver_awaddr;    // 将驱动模块的写地址输出到 SmartConnect
    assign axi_awprot  = driver_awprot;    // 将驱动模块的写保护信号输出到 SmartConnect
    assign axi_awvalid = driver_awvalid;   // 将驱动模块的写地址有效信号输出到 SmartConnect
    assign driver_awready = axi_awready;   // 将 SmartConnect 的写地址就绪信号连接到驱动模块

    assign axi_wdata   = driver_wdata;     // 将驱动模块的写数据输出到 SmartConnect
    assign axi_wstrb   = driver_wstrb;     // 将驱动模块的写字节使能信号输出到 SmartConnect
    assign axi_wvalid  = driver_wvalid;    // 将驱动模块的写数据有效信号输出到 SmartConnect
    assign driver_wready = axi_wready;    // 将 SmartConnect 的写数据就绪信号连接到驱动模块
    assign axi_wlast   = driver_wlast;     // 将驱动模块的写最后一个数据包信号输出到 SmartConnect

    assign driver_bvalid = axi_bvalid;     // 将 SmartConnect 的写响应有效信号连接到驱动模块
    assign axi_bready  = driver_bready;    // 将顶层模块的写响应就绪信号输出到 SmartConnect
    // 注意：这里将 SmartConnect 的响应连接回驱动模块
    assign u_video_to_axi_driver.bresp = axi_bresp;

    // 将控制模块产生的地址连接到驱动模块的当前 AXI 写地址输入
    assign u_video_to_axi_driver.current_axi_addr = ctrl_axi_write_addr;

    // 顶层模块控制 bready 信号
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            driver_bready <= 0;          // 复位时，不准备好接收响应
        end else begin
            driver_bready <= axi_bvalid; // 当 SmartConnect 的 BVALID 有效时，表示有响应，我们就准备好接收
        end
    end

endmodule