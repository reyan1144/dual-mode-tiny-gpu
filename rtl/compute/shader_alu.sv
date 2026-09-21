module shader_alu (
    input  logic signed [15:0] a,
    input  logic signed [15:0] b,
    input  logic        [1:0]  alu_op,
    output logic signed [15:0] result
);

    localparam logic [1:0] ALU_ADD = 2'b00;
    localparam logic [1:0] ALU_SUB = 2'b01;
    localparam logic [1:0] ALU_MUL = 2'b10;
    localparam logic [1:0] ALU_MOV = 2'b11;

    logic signed [31:0] multiply_result;

    always_comb begin
        multiply_result = a * b;

        unique case (alu_op)
            ALU_ADD: result = a + b;
            ALU_SUB: result = a - b;
            ALU_MUL: result = multiply_result[15:0];
            ALU_MOV: result = a;
            default: result = '0;
        endcase
    end

endmodule
