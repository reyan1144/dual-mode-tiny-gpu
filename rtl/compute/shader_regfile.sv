module shader_regfile #(
    parameter int WARP_COUNT = 4,
    parameter int REG_COUNT  = 8,
    parameter int REG_WIDTH  = 16,
    parameter int WARP_ID_WIDTH = $clog2(WARP_COUNT),
    parameter int REG_ADDR_WIDTH = $clog2(REG_COUNT)
) (
input  logic                         clk,
input  logic                         reset,

input  logic [REG_ADDR_WIDTH-1:0]    rs1_addr,
input  logic [REG_ADDR_WIDTH-1:0]    rs2_addr,
input  logic [WARP_ID_WIDTH-1:0]     current_warp,

output logic signed [REG_WIDTH-1:0]  rs1_data,
output logic signed [REG_WIDTH-1:0]  rs2_data,

input  logic                         write_enable,
input  logic [REG_ADDR_WIDTH-1:0]    rd_addr,
input  logic signed [REG_WIDTH-1:0] write_data
);

logic signed [REG_WIDTH-1:0] registers [0:WARP_COUNT-1][0:REG_COUNT-1];

   
assign rs1_data = registers[current_warp][rs1_addr];
assign rs2_data = registers[current_warp][rs2_addr];

integer w;
integer r;

always_ff @(posedge clk) begin
    if (reset) begin
        for (w = 0; w < WARP_COUNT; w = w + 1) begin
            for (r = 0; r < REG_COUNT; r = r + 1) begin
                registers[w][r] <= '0;
            end
        end
    end
    else if (write_enable) begin
        registers[current_warp][rd_addr] <= write_data;
    end
end

endmodule
