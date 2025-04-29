module Mult #(
    parameter integer BITWIDTH = 16
)(
    input wire signed [BITWIDTH-1:0] a,
    input wire signed [BITWIDTH-1:0] b,
    output reg signed [BITWIDTH*2-1:0] out
);

    always @(*) begin
        if (^a === 1'bx || ^b === 1'bx) begin
            out = {BITWIDTH*2{1'b0}};  // ���� x ����ʱ��Ĭ����� 0����ֹ������
        end else begin
            out = a * b;
        end
    end

endmodule
