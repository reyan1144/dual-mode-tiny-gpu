module shader_imem (
    input  logic        clk,

   
    input  logic        program_write_enable,
    input  logic [3:0]  program_write_addr,
    input  logic [15:0] program_write_data,

   
    input  logic [3:0]  fetch_addr,
    output logic [15:0] instruction
);

    logic [15:0] memory [0:15];
    always_ff @(posedge clk) begin
        if (program_write_enable) begin
            memory[program_write_addr] <= program_write_data;
        end
    end
    
    assign instruction = memory[fetch_addr];

endmodule