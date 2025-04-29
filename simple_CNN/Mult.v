module Mult #(
    parameter integer BITWIDTH = 16
)(
    input wire signed [BITWIDTH-1:0] a,
    input wire signed [BITWIDTH-1:0] b,
    output reg signed [BITWIDTH*2-1:0] out
);

    always @(*) begin
        if (^a === 1'bx || ^b === 1'bx) begin
            out = {BITWIDTH*2{1'b0}};  // 遇到 x 输入时，默认输出 0（防止传播）
        end else begin
            out = a * b;
        end
    end

endmodule
