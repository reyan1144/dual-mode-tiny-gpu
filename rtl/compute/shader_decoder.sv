module shader_decoder (
    input  logic [15:0] instruction,
    output logic [1:0]  opcode,
    output logic [2:0]  rd,
    output logic [2:0]  rs1,
    output logic [2:0]  rs2,
    output logic [1:0]  alu_op,
    output logic        reg_write
);

    always_comb begin
        opcode = instruction[15:14];
        rd     = instruction[13:11];
        rs1    = instruction[10:8];
        rs2    = instruction[7:5];

        alu_op    = 2'b00;
        reg_write = 1'b0;

        unique case (instruction[15:14])
            2'b00: begin
                alu_op    = 2'b00; // ADD
                reg_write = 1'b1;
            end

            2'b01: begin
                alu_op    = 2'b01; // SUB
                reg_write = 1'b1;
            end

            2'b10: begin
                alu_op    = 2'b10; // MUL
                reg_write = 1'b1;
            end

            2'b11: begin
                alu_op    = 2'b11; // MOV
                reg_write = 1'b1;
            end

            default: begin
                alu_op    = 2'b00;
                reg_write = 1'b0;
            end
        endcase
    end

endmodule