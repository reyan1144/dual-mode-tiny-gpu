module shader_ir (
    input  logic        clk,
    input  logic        reset,
    input  logic        ir_load,
    input  logic [15:0] instruction_in,
    output logic [15:0] instruction_out
);

    always_ff @(posedge clk) begin
        if (reset) begin
            instruction_out <= 16'd0;
        end
        else if (ir_load) begin
            instruction_out <= instruction_in;
        end
    end

endmodule