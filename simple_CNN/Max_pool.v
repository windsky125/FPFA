`timescale 1ns / 1ps 

module Max_pool #(
    parameter integer BITWIDTH = 16,             // ��������λ��
    parameter integer DATAWIDTH = 8,            // ����ͼ����
    parameter integer DATAHEIGHT = 8,           // ����ͼ��߶�
    parameter integer DATACHANNEL = 3,           // ����ͨ����
    parameter integer KWIDTH = 2,                // ����˿��
    parameter integer KHEIGHT = 2                // ����˸߶�
)(
    input wire clk,                              // ʱ���ź�
    input wire rst_n,                            // �첽��λ������Ч
    input wire clken,                            // ʹ���ź�
    input wire [BITWIDTH*DATAWIDTH*DATAHEIGHT*DATACHANNEL-1:0] data_in, // ��ƽ��һ����ͼƬ����
    output reg [BITWIDTH*(DATAWIDTH/KWIDTH)*(DATAHEIGHT/KHEIGHT)*DATACHANNEL-1:0] result_out, // �ػ�������
    output reg result_valid_out                  // ��������Ч�ź�
);

    // �������ͼ�ĳߴ�
    localparam integer OUTPUT_WIDTH  = DATAWIDTH / KWIDTH;
    localparam integer OUTPUT_HEIGHT = DATAHEIGHT / KHEIGHT;
    localparam integer TOTAL_OUTPUTS = OUTPUT_WIDTH * OUTPUT_HEIGHT * DATACHANNEL;

    // ��ʱ�Ĵ�������ŵ�ǰ2x2���ڵ�4������
    reg [BITWIDTH-1:0] pool_reg[0:3];
    
    // �Ƚ����Ĵ����������Ƚ��м���
    reg [BITWIDTH-1:0] stage1_max0, stage1_max1;
    reg [BITWIDTH-1:0] final_max; // ��ǰ�ػ����ڵ����ֵ

    // �С��С�ͨ���������Ĵ���
    reg [4:0] channel_idx;
    reg [7:0] row_idx;
    reg [7:0] col_idx;
    reg [31:0] out_idx; // ������ݼ���������ƽ�����

    // ȡ����ǰ2x2���ڵ��ĸ�Ԫ�أ���ƽ��һάdata_in����ȡ��
    wire [BITWIDTH-1:0] d00, d01, d10, d11;
    
    assign d00 = data_in[ ((channel_idx*DATAHEIGHT*DATAWIDTH) + (row_idx*2)*DATAWIDTH + (col_idx*2)) * BITWIDTH +: BITWIDTH ];
    assign d01 = data_in[ ((channel_idx*DATAHEIGHT*DATAWIDTH) + (row_idx*2)*DATAWIDTH + (col_idx*2+1)) * BITWIDTH +: BITWIDTH ];
    assign d10 = data_in[ ((channel_idx*DATAHEIGHT*DATAWIDTH) + (row_idx*2+1)*DATAWIDTH + (col_idx*2)) * BITWIDTH +: BITWIDTH ];
    assign d11 = data_in[ ((channel_idx*DATAHEIGHT*DATAWIDTH) + (row_idx*2+1)*DATAWIDTH + (col_idx*2+1)) * BITWIDTH +: BITWIDTH ];
    
    // -------------------
    // �ػ���ˮ�߲���
    // -------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pool_reg[0] <= 0;
            pool_reg[1] <= 0;
            pool_reg[2] <= 0;
            pool_reg[3] <= 0;
            stage1_max0 <= 0;
            stage1_max1 <= 0;
            final_max   <= 0;
        end else if (clken) begin
            // ��һ�������洰��Ԫ��
            pool_reg[0] <= d00;
            pool_reg[1] <= d01;
            pool_reg[2] <= d10;
            pool_reg[3] <= d11;
            
            // �ڶ����������Ƚ�
            stage1_max0 <= (pool_reg[0] > pool_reg[1]) ? pool_reg[0] : pool_reg[1];
            stage1_max1 <= (pool_reg[2] > pool_reg[3]) ? pool_reg[2] : pool_reg[3];
            
            // ���������������ֵ
            final_max   <= (stage1_max0 > stage1_max1) ? stage1_max0 : stage1_max1;
        end
    end

    // -------------------
    // ��������ͨ������
    // -------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            channel_idx <= 0;
            row_idx <= 0;
            col_idx <= 0;
            out_idx <= 0;
            result_out <= 0;
            result_valid_out <= 0;
        end else if (clken) begin
            if (out_idx < TOTAL_OUTPUTS) begin
                // �ѳػ�������ֵд�����result_out�Ķ�Ӧλ��
                result_out[out_idx*BITWIDTH +: BITWIDTH] <= final_max;
                out_idx <= out_idx + 1;

                // �м��������˻���
                if (col_idx == OUTPUT_WIDTH-1) begin
                    col_idx <= 0;
                    if (row_idx == OUTPUT_HEIGHT-1) begin
                        row_idx <= 0;
                        // ��Ҳ���ˣ���ͨ��
                        if (channel_idx == DATACHANNEL-1) begin
                            channel_idx <= 0;
                            result_valid_out <= 1; // ȫ������������valid
                        end else begin
                            channel_idx <= channel_idx + 1;
                        end
                    end else begin
                        row_idx <= row_idx + 1;
                    end
                end else begin
                    col_idx <= col_idx + 1;
                end
            end else begin
                result_valid_out <= 0; // ��ɺ�����valid
            end
        end
    end

endmodule
