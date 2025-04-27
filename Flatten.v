`timescale 1ns / 1ps

module Flatten #(
  parameter BITWIDTH = 16,
  parameter DATAWIDTH = 14,
  parameter DATAHEIGHT = 14,
  parameter DATACHANNEL = 3
)(
  input wire clk,
  input wire rst_n,
  input wire clken,

  // ����ӿ�
  input wire [BITWIDTH*DATAWIDTH*DATAHEIGHT*DATACHANNEL-1:0] data_in,
  input wire data_in_valid,

  // ����ӿ�
  output reg [BITWIDTH-1:0] data_out,
  output reg data_out_valid,
  output reg done
);

  // ��άչ������
  localparam TOTAL_OUTPUTS = DATAWIDTH * DATAHEIGHT * DATACHANNEL;

  // ״̬�Ĵ���
  reg processing;
  reg [9:0] out_idx; // ֧����� 1024 �����
  reg [BITWIDTH*DATAWIDTH*DATAHEIGHT*DATACHANNEL-1:0] data_latch;

  // �������
  wire [9:0] ch = out_idx / (DATAHEIGHT * DATAWIDTH);     
  wire [9:0] y  = (out_idx % (DATAHEIGHT * DATAWIDTH)) / DATAWIDTH; 
  wire [9:0] x  = out_idx % DATAWIDTH;

  // ���� bit ƫ��
  wire [31:0] bit_offset = ((ch * DATAHEIGHT * DATAWIDTH) + (y * DATAWIDTH) + x) * BITWIDTH;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      processing <= 1'b0;
      data_latch <= {BITWIDTH*DATAWIDTH*DATAHEIGHT*DATACHANNEL{1'b0}};
      out_idx <= 10'd0;
      data_out <= {BITWIDTH{1'b0}};
      data_out_valid <= 1'b0;
      done <= 1'b0;
    end else if (clken) begin
      // ����������Ч����������
      if (data_in_valid) begin
        data_latch <= data_in;
        processing <= 1'b1;
        out_idx <= 10'd0;
        done <= 1'b0;
      end
      
      if (processing) begin
        data_out <= data_latch[bit_offset +: BITWIDTH];
        data_out_valid <= 1'b1;
        
        if (out_idx == TOTAL_OUTPUTS - 1) begin
          processing <= 1'b0;
          done <= 1'b1;
        end else begin
          out_idx <= out_idx + 1'b1;
        end
      end else begin
        data_out_valid <= 1'b0;
      end
    end
  end

endmodule
