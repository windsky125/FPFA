`timescale 1ns / 1ps

module FullConnect #(
    parameter integer BITWIDTH = 8,
    parameter integer LENGTH = 72,        // չƽ�����������
    parameter integer FILTERBATCH = 10    // �˲������������ͨ������
)(
    input wire clk,
    input wire rst_n,
    input wire clken,                    // ʱ��ʹ��
    input wire [BITWIDTH-1:0] data_in,    // �������ݣ��������룩
    input wire data_in_valid,             // ����������Ч�ź�
    input wire [BITWIDTH*LENGTH*FILTERBATCH-1:0] weight_in, // Ȩ�ؾ���
    input wire [BITWIDTH*FILTERBATCH-1:0] bias_in,          // ƫ������
    output reg [2*BITWIDTH*FILTERBATCH-1:0] result_out,    // ������
    output reg result_valid_out,          // �����Ч�ź�
    output reg done                       // ��������ź�
);
    integer i;
    
    // ========== �Ĵ������� ==========
    reg [10:0] counter;  // ���ݼ�����
    reg [BITWIDTH-1:0] current_data_in;  // ��ǰ�������ݼĴ���
    reg weight_latched;                   // Ȩ���������־
    
    // Ȩ�غ�ƫ�üĴ���
    reg [BITWIDTH*LENGTH*FILTERBATCH-1:0] weight_reg;
    reg [BITWIDTH*FILTERBATCH-1:0] bias_reg;
    
    // �ۼ���
    reg signed [BITWIDTH*2-1:0] accumulator [0:FILTERBATCH-1];

    // ========== ƫ��չ�� ==========
    wire signed [BITWIDTH-1:0] bias_array [0:FILTERBATCH-1];
    generate
        genvar k;
        for (k = 0; k < FILTERBATCH; k = k + 1) begin : BIAS_GEN
            assign bias_array[k] = $signed(bias_reg[(k+1)*BITWIDTH-1 -: BITWIDTH]);
        end
    endgenerate

    // ========== �˷���Ԫ ==========
    wire signed [BITWIDTH*2-1:0] mult_out [0:FILTERBATCH-1];
    
    generate
        genvar m;
        for (m = 0; m < FILTERBATCH; m = m + 1) begin : MULT_GEN
            Mult #(
                .BITWIDTH(BITWIDTH)
            ) u_mult (
                .a($signed(current_data_in)),
                .b($signed(weight_reg[((m*LENGTH)+counter)*BITWIDTH +: BITWIDTH])),
                .out(mult_out[m])
            );
        end
    endgenerate

    // ========== ��״̬�� ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // ͬ����λ
            counter <= 0;
            weight_latched <= 1'b0;
            current_data_in <= {BITWIDTH{1'b0}};
            result_valid_out <= 1'b0;
            result_out<= {BITWIDTH*2*FILTERBATCH{1'b0}};
            done <= 1'b0;
            
            for (i = 0; i < FILTERBATCH; i = i + 1) begin
                accumulator[i] <= {BITWIDTH*2{1'b0}};
            end
        end else if (clken) begin
            // �������ݼĴ�
            current_data_in <= data_in;
             result_out <= result_out;
            // ��������߼�
            if (data_in_valid) begin
                // ����Ȩ�غ�ƫ�ã�ֻ�ڵ�һ������ʱ��
                if (counter == 0 && !weight_latched) begin
                    weight_reg <= weight_in;
                    bias_reg <= bias_in;
                    weight_latched <= 1'b1;
                end
                
                // �ۼӽ׶�
                if (counter < LENGTH) begin
                    for (i = 0; i < FILTERBATCH; i = i + 1) begin
                        // �ۼӵ�ǰ�˷����
                        accumulator[i] <= accumulator[i] + mult_out[i];
                    end
                    counter <= counter + 1;
                    done <= 1'b0; // ����δ���
                end
            end
            
            // ����׶�
            if (counter == LENGTH && weight_latched) begin
                for (i = 0; i < FILTERBATCH; i = i + 1) begin
                    // �����ŵ�ƫ�üӷ�
                    result_out[(i+1)*BITWIDTH*2-1 -: BITWIDTH*2] <= 
                        accumulator[i] + $signed(bias_array[i]);
                end
                result_valid_out <= 1'b1; // �����Ч
                done <= 1'b1; // �������
                counter <= 0; // ���ü�������׼����һ�μ���
                // �����ۼ�����׼����һ�μ���
                for (i = 0; i < FILTERBATCH; i = i + 1) begin
                    accumulator[i] <= {BITWIDTH*2{1'b0}}; // �����ۼ���
                end
                weight_latched <= 1'b0;  // ׼����һ�μ���
            end else begin
                result_valid_out <= 1'b0; // �����Ч
                if (!data_in_valid) done <= 1'b0; // ���������Ч������done�ź�
            end
        end
    end

endmodule

