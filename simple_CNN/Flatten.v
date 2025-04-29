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
  
  // ����ӿ�
  input  wire [BITWIDTH*DATAWIDTH*DATAHEIGHT*DATACHANNEL-1:0] data_in,
  input  wire                             data_in_valid,
  
  // ����ӿ�
  output reg  [BITWIDTH-1:0]              data_out,
  output reg                              data_out_valid,
  output reg                              done
  
  // ���Խӿڣ���ѡ��
  //output wire [CNT_WIDTH-1:0]             output_count
);

  // ���㳣��
  localparam integer TOTAL_DATA = DATAWIDTH * DATAHEIGHT * DATACHANNEL; // ��������

  // ״̬����
  localparam [1:0]
    IDLE       = 2'b00,
    LOAD_DATA  = 2'b01,
    SEND_DATA  = 2'b10;

  // �ڲ��Ĵ���
  reg [1:0] state;
  reg [CNT_WIDTH-1:0] output_counter;
  reg [BITWIDTH*TOTAL_DATA-1:0] data_buffer; // ��������
  reg buffer_full; // ��־λ����ʾ�����Ƿ���ȫ���ղ��������

  assign output_count = output_counter;

 always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // ����״̬
        state <= IDLE;
        output_counter <= 0;
        data_buffer <= 0;
        data_out <= 0;
        data_out_valid <= 0;
        done <= 0;
        buffer_full <= 0;
    end else if (clken) begin
        // Ĭ������
        data_out_valid <= 0; // Ĭ�������Ч
        done <= 0;

        case (state)
            IDLE: begin
                if (data_in_valid) begin
                    // �������ݲ�����
                    data_buffer <= data_in;
                    buffer_full <= 1'b1;
                    state <= SEND_DATA; // ֱ��ת����������״̬
                    output_counter <= 0; // �������������
                end
            end

            SEND_DATA: begin
                if (buffer_full) begin
                    // �����ǰ����
                    data_out <= data_buffer[output_counter*BITWIDTH +: BITWIDTH];
                    data_out_valid <= 1'b1; // ���������Ч�ź�
                    
                    if (output_counter == TOTAL_DATA - 1) begin
                        // �������������
                        done <= 1'b1;
                        buffer_full <= 1'b0;

                        // ��� data_in_valid �ź�
                        if (data_in_valid) begin
                            // �����Ȼ��Ч������״̬Ϊ SEND_DATA
                            // �������ѡ����������µ�����
                            // ���磬�����Խ� data_buffer ����Ϊ�µ���������
                            data_buffer <= data_in; // ��������
                            output_counter <= 0; // �������������
                        end else begin
                            // �����Ч���ص�����״̬
                            state <= IDLE; // �ص�����״̬
                        end
                    end else begin
                        output_counter <= output_counter + 1; // �ƶ�����һ������
                    end
                end
            end

            default: state <= IDLE;
        endcase
    end
end


endmodule
