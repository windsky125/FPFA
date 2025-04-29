`timescale 1ns / 1ps

module Conv2d #(
    // ��������
    parameter integer BITWIDTH = 8,                      // ����λ��
    parameter integer DATAWIDTH = 8,                   // �������ݿ��
    parameter integer DATAHEIGHT = 8,                  // �������ݸ߶�
    parameter integer DATACHANNEL = 1,                  // ��������ͨ����
    
    // ����˲���
    parameter integer FILTERHEIGHT = 3,                 // ����˸߶�
    parameter integer FILTERWIDTH = 3,                  // ����˿��
    parameter integer FILTERBATCH = 16,                 // ���������
    
    // �������
    parameter integer STRIDEHEIGHT = 1,                 // ��ֱ����
    parameter integer STRIDEWIDTH = 1,                  // ˮƽ����
    parameter integer PADDINGENABLE = 0,                // �Ƿ��������
    
    // ���м������
    parameter integer PARALLEL_OUT = 4,                 // ����㲢�ж�
    parameter integer PARALLEL_FILTER = 4               // �˲������ж�
) (
    input wire clk,                                     // ʱ���ź�
    input wire rst_n,                                   // ��λ�ź�
    input wire clken,                                   // ʹ���ź�
    
    // ��������
    input wire [BITWIDTH*DATAWIDTH*DATAHEIGHT*DATACHANNEL-1:0] data_in,
    
    // �����Ȩ��
    input wire [BITWIDTH*FILTERHEIGHT*FILTERWIDTH*DATACHANNEL*FILTERBATCH-1:0] filterWeight_in,
    
    // �����ƫ��
    input wire [BITWIDTH*FILTERBATCH-1:0] filterBias_in,
    
    // ������
    output reg [(BITWIDTH*2)*FILTERBATCH*((PADDINGENABLE==0)?(DATAWIDTH-FILTERWIDTH+1)/STRIDEWIDTH:(DATAWIDTH/STRIDEWIDTH))
                *((PADDINGENABLE==0)?(DATAHEIGHT-FILTERHEIGHT+1)/STRIDEHEIGHT:(DATAHEIGHT/STRIDEHEIGHT))-1:0] result_out,
    
    output reg result_valid_out                         // �����Ч�ź�
);

    // =============================================
    // ��������ߴ�
    // =============================================
    localparam OUT_WIDTH = (PADDINGENABLE == 0) ? 
                         ((DATAWIDTH - FILTERWIDTH + 1 + STRIDEWIDTH - 1) / STRIDEWIDTH) : 
                         (DATAWIDTH / STRIDEWIDTH);
                         
    localparam OUT_HEIGHT = (PADDINGENABLE == 0) ? 
                          ((DATAHEIGHT - FILTERHEIGHT + 1 + STRIDEHEIGHT - 1) / STRIDEHEIGHT) : 
                          (DATAHEIGHT / STRIDEHEIGHT);
    
    localparam OUTPUT_SIZE = OUT_WIDTH * OUT_HEIGHT;

    // =============================================
    // �������ݽ��
    // =============================================
    reg [BITWIDTH-1:0] input_data [0:DATACHANNEL-1][0:DATAHEIGHT-1][0:DATAWIDTH-1];
    reg [BITWIDTH-1:0] filter_weight [0:FILTERBATCH-1][0:DATACHANNEL-1][0:FILTERHEIGHT-1][0:FILTERWIDTH-1];
    reg [BITWIDTH-1:0] filter_bias [0:FILTERBATCH-1];

    // �����������
    integer c, h, w, f, fh, fw;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (c = 0; c < DATACHANNEL; c = c + 1) begin
                for (h = 0; h < DATAHEIGHT; h = h + 1) begin
                    for (w = 0; w < DATAWIDTH; w = w + 1) begin
                        input_data[c][h][w] <= 0;
                    end
                end
            end
        end else if (clken) begin
            for (c = 0; c < DATACHANNEL; c = c + 1) begin
                for (h = 0; h < DATAHEIGHT; h = h + 1) begin
                    for (w = 0; w < DATAWIDTH; w = w + 1) begin
                        input_data[c][h][w] <= data_in[((c*DATAHEIGHT*DATAWIDTH + h*DATAWIDTH + w)*BITWIDTH) +: BITWIDTH];
                    end
                end
            end
        end
    end

    // ����˲���Ȩ�غ�ƫ��
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (f = 0; f < FILTERBATCH; f = f + 1) begin
                filter_bias[f] <= 0;
                for (c = 0; c < DATACHANNEL; c = c + 1) begin
                    for (fh = 0; fh < FILTERHEIGHT; fh = fh + 1) begin
                        for (fw = 0; fw < FILTERWIDTH; fw = fw + 1) begin
                            filter_weight[f][c][fh][fw] <= 0;
                        end
                    end
                end
            end
        end else if (clken) begin
            for (f = 0; f < FILTERBATCH; f = f + 1) begin
                filter_bias[f] <= filterBias_in[f*BITWIDTH +: BITWIDTH];
                for (c = 0; c < DATACHANNEL; c = c + 1) begin
                    for (fh = 0; fh < FILTERHEIGHT; fh = fh + 1) begin
                        for (fw = 0; fw < FILTERWIDTH; fw = fw + 1) begin
                            filter_weight[f][c][fh][fw] <= 
                                filterWeight_in[((f*DATACHANNEL*FILTERHEIGHT*FILTERWIDTH + c*FILTERHEIGHT*FILTERWIDTH + fh*FILTERWIDTH + fw)*BITWIDTH) +: BITWIDTH];
                        end
                    end
                end
            end
        end
    end

    // =============================================
    // ���о������
    // =============================================
    reg [(BITWIDTH*2)-1:0] conv_result [0:FILTERBATCH-1][0:OUT_HEIGHT-1][0:OUT_WIDTH-1];
    reg [1:0] compute_state;
    reg [31:0] compute_counter;
    reg [31:0] out_h_idx, out_w_idx;
    reg [31:0] filter_idx;
    
    // ����������Ҫ�ı���
    integer p, q;  // ���м�������
    reg signed [BITWIDTH-1:0] pixel;  // ��������ֵ
    reg signed [BITWIDTH-1:0] weight; // Ȩ��ֵ
    reg signed [(BITWIDTH*2)-1:0] parallel_sum [0:PARALLEL_FILTER-1][0:PARALLEL_OUT-1];
    reg [31:0] current_h [0:PARALLEL_OUT-1];
    reg [31:0] current_w [0:PARALLEL_OUT-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            compute_state <= 0;
            compute_counter <= 0;
            out_h_idx <= 0;
            out_w_idx <= 0;
            filter_idx <= 0;
            result_valid_out <= 0;
            
            for (f = 0; f < FILTERBATCH; f = f + 1) begin
                for (h = 0; h < OUT_HEIGHT; h = h + 1) begin
                    for (w = 0; w < OUT_WIDTH; w = w + 1) begin
                        conv_result[f][h][w] <= 0;
                    end
                end
            end
        end else if (clken) begin
            case (compute_state)
                0: begin
                    compute_counter <= 0;
                    out_h_idx <= 0;
                    out_w_idx <= 0;
                    filter_idx <= 0;
                    result_valid_out <= 0;
                    compute_state <= 1;
                end
                
                1: begin
                    for (q = 0; q < PARALLEL_FILTER; q = q + 1) begin
                        for (p = 0; p < PARALLEL_OUT; p = p + 1) begin
                            parallel_sum[q][p] = 0;
                            current_h[p] = out_h_idx;
                            current_w[p] = out_w_idx + p;
                            
                            if (current_w[p] >= OUT_WIDTH) begin
                                current_h[p] = current_h[p] + 1;
                                current_w[p] = current_w[p] - OUT_WIDTH;
                            end
                            
                            if (current_h[p] < OUT_HEIGHT && current_w[p] < OUT_WIDTH) begin
                                for (c = 0; c < DATACHANNEL; c = c + 1) begin
                                    for (fh = 0; fh < FILTERHEIGHT; fh = fh + 1) begin
                                        for (fw = 0; fw < FILTERWIDTH; fw = fw + 1) begin
                                            // ��ȡ�������غ�Ȩ��
                                            pixel = input_data[c][current_h[p]*STRIDEHEIGHT+fh][current_w[p]*STRIDEWIDTH+fw];
                                            weight = filter_weight[filter_idx + q][c][fh][fw];
                                            parallel_sum[q][p] = parallel_sum[q][p] + pixel * weight;
                                        end
                                    end
                                end
                                
                                conv_result[filter_idx + q][current_h[p]][current_w[p]] <= 
                                    parallel_sum[q][p] + filter_bias[filter_idx + q];
                            end
                        end
                    end
                    
                    out_w_idx = out_w_idx + PARALLEL_OUT;
                    if (out_w_idx >= OUT_WIDTH) begin
                        out_w_idx = out_w_idx - OUT_WIDTH;
                        out_h_idx = out_h_idx + 1;
                        
                        if (out_h_idx >= OUT_HEIGHT) begin
                            out_h_idx = 0;
                            filter_idx = filter_idx + PARALLEL_FILTER;
                            
                            if (filter_idx >= FILTERBATCH) begin
                                compute_state <= 2;
                            end
                        end
                    end
                end
                
                2: begin
                    for (f = 0; f < FILTERBATCH; f = f + 1) begin
                        for (h = 0; h < OUT_HEIGHT; h = h + 1) begin
                            for (w = 0; w < OUT_WIDTH; w = w + 1) begin
                                result_out[((f*OUT_HEIGHT*OUT_WIDTH + h*OUT_WIDTH + w)*(BITWIDTH*2)) +: (BITWIDTH*2)] 
                                    <= conv_result[f][h][w];
                            end
                        end
                    end
                    
                    result_valid_out <= 1;
                    compute_state <= 0;
                end
            endcase
        end else begin
            result_valid_out <= 0;
        end
    end

endmodule