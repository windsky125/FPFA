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

    // ��������
    localparam TOTAL_ELEMENTS = DATA_HEIGHT * DATA_WIDTH * DATA_CHANNELS;
    localparam ELEMENT_WIDTH = BITWIDTH * 2;
    localparam ITERATIONS = (TOTAL_ELEMENTS + PARALLEL_FACTOR - 1) / PARALLEL_FACTOR;

    // �Ĵ�������
    reg [ELEMENT_WIDTH-1:0] internal_data_out [0:TOTAL_ELEMENTS-1];
    reg [31:0] process_index;
    reg [1:0] state;
    
    // ѭ�������������������always���ⲿ��
    integer j, k, p;
    integer current_idx, store_idx;

    // ״̬����
    localparam IDLE       = 2'b00;
    localparam PROCESSING = 2'b01;
    localparam OUTPUT     = 2'b10;

    // ���д����ź�
    reg [ELEMENT_WIDTH-1:0] parallel_in [0:PARALLEL_FACTOR-1];
    wire [ELEMENT_WIDTH-1:0] parallel_out [0:PARALLEL_FACTOR-1];

    // ���ɲ���ReLU��Ԫ
    genvar i;
    generate
        for (i = 0; i < PARALLEL_FACTOR; i = i + 1) begin : RELU_UNITS
            assign parallel_out[i] = parallel_in[i][ELEMENT_WIDTH-1] ? 
                                   {ELEMENT_WIDTH{1'b0}} : parallel_in[i];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // ��λ�߼�
            process_index <= 0;
            state <= IDLE;
            relu1_valid_out <= 1'b0;
            data_out <= 0;
            
            // ��ʼ���洢����ʹ��Ԥ������ѭ������j��
            for (j = 0; j < TOTAL_ELEMENTS; j = j + 1) begin
                internal_data_out[j] <= 0;
            end
            
            // ��ʼ���������루ʹ��Ԥ������ѭ������k��
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
                        // �������ݵ����е�Ԫ
                        for (p = 0; p < PARALLEL_FACTOR; p = p + 1) begin
                            current_idx = process_index * PARALLEL_FACTOR + p;
                            if (current_idx < TOTAL_ELEMENTS) begin
                                parallel_in[p] <= data_in[current_idx*ELEMENT_WIDTH +: ELEMENT_WIDTH];
                            end
                            else begin
                                parallel_in[p] <= 0;
                            end
                        end
                        
                        // �洢�������ˮ����ƣ�
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
                        // �洢���һ������
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
                    // ������ת��Ϊ������
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