`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// ��˾:
// ����ʦ:
//
// ��������: 2025/04/26 16:07:25
// �������: Simple_CNN
// ģ������: Simple_CNN
// ��Ŀ����:
// Ŀ������:
// ���߰汾:
// ����: һ���򵥵ľ�������磬����һ������㡢ReLU ������ػ���һ��ȫ���Ӳ� (������ˮ��).
//
// ����: Conv2d, Relu_activation, Max_pool, FullConnect ģ��.
//
// �޶�:
// �޶� 0.08 - �����û��ṩ��ģ�岹ȫ����
// ����ע��:
// ------------------ ����ṹ���� ------------------
//
// input_image -> Conv2d_inst (�ӳ�) -> conv1_out_reg (valid)
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
    parameter integer BITWIDTH = 8,                                             // ����λ��
    parameter integer IMAGE_WIDTH = 8,                                        // ����ͼ����
    parameter integer IMAGE_HEIGHT = 8,                                       // ����ͼ��߶�
    parameter integer IMAGE_CHANNELS = 3,                                      // ����ͼ��ͨ����
    parameter integer CONV1_FILTER_SIZE = 3,                                   // ����� 1 �˲����ߴ�
    parameter integer CONV1_OUTPUT_CHANNELS = 8,                               // ����� 1 ���ͨ����
    parameter integer POOL1_KERNEL_SIZE = 2,                                   // �ػ��� 1 �˳ߴ�
    parameter integer FC1_OUTPUT_UNITS = 10                                    // ȫ���Ӳ� 1 �����Ԫ��
)(
    input wire clk,                                                           // ʱ���ź�
    input wire rst_n,                                                         // ��λ�ź� (����Ч)
    input wire clken,                                                         // ʱ��ʹ���ź�
    input wire [BITWIDTH*IMAGE_HEIGHT*IMAGE_WIDTH*IMAGE_CHANNELS-1:0] input_image, // ����ͼ������
    input wire [BITWIDTH*CONV1_FILTER_SIZE*CONV1_FILTER_SIZE*IMAGE_CHANNELS*CONV1_OUTPUT_CHANNELS-1:0] conv1_weight, // ����� 1 Ȩ��
    input wire [BITWIDTH*CONV1_OUTPUT_CHANNELS-1:0] conv1_bias,                // ����� 1 ƫ��
    input wire [2*BITWIDTH*((IMAGE_WIDTH-CONV1_FILTER_SIZE+1)/POOL1_KERNEL_SIZE)*((IMAGE_HEIGHT-CONV1_FILTER_SIZE+1)/POOL1_KERNEL_SIZE)*CONV1_OUTPUT_CHANNELS*FC1_OUTPUT_UNITS-1:0] fc1_weight, // ȫ���Ӳ� 1 Ȩ��
    input wire [2*BITWIDTH*FC1_OUTPUT_UNITS-1:0] fc1_bias,                       // ȫ���Ӳ� 1 ƫ��
    output reg [BITWIDTH*4*FC1_OUTPUT_UNITS-1:0] output_scores,                // ����÷�
    output reg output_valid                                                   // �����Ч�ź�
);

    // ��������
    localparam integer CONV1_OUT_WIDTH = (IMAGE_WIDTH - CONV1_FILTER_SIZE + 1);
    localparam integer CONV1_OUT_HEIGHT = (IMAGE_HEIGHT - CONV1_FILTER_SIZE + 1);
    localparam integer POOL1_OUT_WIDTH = CONV1_OUT_WIDTH / POOL1_KERNEL_SIZE;
    localparam integer POOL1_OUT_HEIGHT = CONV1_OUT_HEIGHT / POOL1_KERNEL_SIZE;
    localparam integer FLATTEN_LENGTH = POOL1_OUT_WIDTH * POOL1_OUT_HEIGHT * CONV1_OUTPUT_CHANNELS;

    // ״̬������
    localparam [3:0]  // �޸�״̬���壬���� FLATTEN ״̬
        IDLE    = 4'b0000,   // ����״̬
        CONV    = 4'b0001,   // ���״̬
        RELU    = 4'b0010,   // ReLU ����״̬
        POOL    = 4'b0011,   // �ػ�״̬
        FLATTEN_PC = 4'b0100,   // չƽ_ȫ����״̬
        OUTPUT      = 4'b0101;   // ���

    reg [3:0] state_reg, state_next;  // �޸�״̬�Ĵ���Ϊ 4 λ

    // �м��źźͼĴ���
    wire [BITWIDTH*2*CONV1_OUT_HEIGHT*CONV1_OUT_WIDTH*CONV1_OUTPUT_CHANNELS-1:0] conv1_out_wire;  // ����� 1 �����
    wire conv1_valid_out;                                                                         // ����� 1 �����Ч�ź�

    wire [BITWIDTH*2*CONV1_OUT_HEIGHT*CONV1_OUT_WIDTH*CONV1_OUTPUT_CHANNELS-1:0] relu1_out_wire;  // ReLU ����������
    wire relu1_valid_out;                                                                         // Rlu�����Ч�ź�

    wire [BITWIDTH*2*POOL1_OUT_HEIGHT*POOL1_OUT_WIDTH*CONV1_OUTPUT_CHANNELS-1:0] pool1_out_wire; // �ػ������
    wire pool1_valid_out;                                                     // �ػ������valid

    wire [BITWIDTH*2 - 1:0] flatten_out_wire; // չƽ����� (����)
    wire flatten_valid_out;                   // չƽ����� valid

    wire [BITWIDTH*4*FC1_OUTPUT_UNITS-1:0] fc1_out_wire;                         // ȫ���Ӳ� 1 �����
    wire pc_out_done;
    wire fc_valid_out;
    reg [2:0] output_delay_counter; // �����ӳ�����ļ�����
    reg delayed_output_valid;
    
    // ʵ��������� 1
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
        .clken(clken && (state_reg == CONV)),                                     // ֻ���� CONV ״̬��ʹ��
        .data_in(input_image),
        .filterWeight_in(conv1_weight),
        .filterBias_in(conv1_bias),
        .result_out(conv1_out_wire),
        .result_valid_out(conv1_valid_out)
    );

    // ʵ���� ReLU �����
    Relu_activation #(
        .BITWIDTH(BITWIDTH),                                                    // λ���������ƥ��
        .DATA_WIDTH(CONV1_OUT_WIDTH),
        .DATA_HEIGHT(CONV1_OUT_HEIGHT),
        .DATA_CHANNELS(CONV1_OUTPUT_CHANNELS),
        .PARALLEL_FACTOR(4)                                                       // ���д�������
    ) relu1_inst (
        .clk(clk),
        .rst_n(rst_n),
        .clken(clken && (state_reg == RELU)),                  // ֻ���� RELU ״̬�Ҿ����ɲ�ʹ��
        .data_in(conv1_out_wire),                                                 // ���վ��������
        .data_out(relu1_out_wire),                                                // ReLU �����
        .relu1_valid_out(relu1_valid_out)                                         // �����µ� valid ���
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
        .clken(clken),  // ����ʹ���ź�
        .data_in(pool1_out_wire),                 // ���Գػ�������
        .data_in_valid(pool1_valid_out),          //����������Ч
        .data_out(flatten_out_wire),              // չƽ����������
        .data_out_valid(flatten_valid_out),       // չƽ�����Ч�ź�
        .done()
    );
    
    // ʵ����ȫ���Ӳ�
    FullConnect #(
        .BITWIDTH(BITWIDTH*2),
        .LENGTH(FLATTEN_LENGTH),
        .FILTERBATCH(FC1_OUTPUT_UNITS)
    ) fc1_inst (
        .clk(clk),
        .rst_n(rst_n),
        .clken(clken && (state_reg == FLATTEN_PC)),  // ����ʹ���ź�
        .data_in(flatten_out_wire),           // ����չƽ�������
        .data_in_valid(flatten_valid_out),             // ����չƽ��� valid �ź�
        .weight_in(fc1_weight),
        .bias_in(fc1_bias),
        .result_out(fc1_out_wire),
        .result_valid_out(fc_valid_out),
        .done(pc_out_done)
    );
    // ״̬��ʱ���߼�
   always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg <= IDLE;
            output_delay_counter <= 0; // ��ʼ���ӳټ�����
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

    // �޸�״̬ת���߼�

    always @(*) begin
        state_next = state_reg;                      // Ĭ�ϱ��ֵ�ǰ״̬
        case (state_reg)
            IDLE: if (clken) state_next = CONV;      // ʹ��ʱ������״̬
            CONV: if (conv1_valid_out && clken) state_next = RELU;  // ��������ʹ��ʱ���� ReLU
            RELU: if (relu1_valid_out && clken) state_next = POOL;  // ReLU �����ʹ��ʱ����ػ�
            POOL: if (pool1_valid_out && clken) state_next =  FLATTEN_PC;  // �ػ������ʹ��ʱ����չƽ
            FLATTEN_PC: if (pc_out_done && clken) state_next = OUTPUT;      // չƽ����ʹ��ʱ����ȫ����
            OUTPUT: if (delayed_output_valid) state_next = IDLE;     // ��������ʹ��ʱ���� IDLE
            default: state_next = IDLE;
        endcase
    end
    

    

    // ����߼�
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_scores <= 0;                                           // ��λʱ������
            output_valid <= 0;                                            // �����Ч�ź�����
        end else if (state_reg == OUTPUT) begin
            output_scores <= fc1_out_wire;                                 // ���ȫ���Ӳ�Ľ��
            output_valid <= 1;                                            // �����Ч�ź�
        end else begin
            output_valid <= 0;                                            // �����״̬ʱ��Ч
        end
    end

endmodule
