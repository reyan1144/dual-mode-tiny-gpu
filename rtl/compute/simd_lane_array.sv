module simd_lane_array #(
    parameter int LANES      = 4,
    parameter int WARP_COUNT = 4,
    parameter int REG_COUNT  = 8,
    parameter int REG_WIDTH  = 16
)(
    input  logic clk,
    input  logic reset,

    // ---- shared control: same for every lane, every cycle -------------
    // (this is exactly what shader_decoder + shader_pc will drive once
    //  this block is wired into shader_core)
    input  logic [$clog2(WARP_COUNT)-1:0] current_warp,
    input  logic [$clog2(REG_COUNT)-1:0]  rs1_addr,
    input  logic [$clog2(REG_COUNT)-1:0]  rs2_addr,
    input  logic [$clog2(REG_COUNT)-1:0]  rd_addr,
    input  logic [1:0]                    alu_op,

    // real SIMD execution: all lanes write back in lockstep this cycle
    // (no active-mask gating yet -- deliberately deferred, see chat)
    input  logic                          exec_write_enable,

    // ---- per-lane initial-load / readback, for seeding test data ------
    input  logic                          load_enable,
    input  logic [$clog2(LANES)-1:0]      load_lane,
    input  logic signed [REG_WIDTH-1:0]   load_data,

    // ---- outputs, exposed per lane for debug/testbench visibility -----
    output logic signed [REG_WIDTH-1:0]   lane_result [0:LANES-1],
    output logic signed [REG_WIDTH-1:0]   lane_rs1    [0:LANES-1],
    output logic signed [REG_WIDTH-1:0]   lane_rs2    [0:LANES-1]
);

    genvar g;
    generate
        for (g = 0; g < LANES; g++) begin : lane

            logic write_en;
            logic signed [REG_WIDTH-1:0] write_data;

            // during exec: every lane writes its own ALU result together.
            // during load: only the addressed lane writes, using load_data.
            // (mirrors the same "gate write_enable per index" trick we used
            //  for input_load_warp in V10 -- same shared bus, one lane at a time)
            assign write_en    = exec_write_enable || (load_enable && (load_lane == g));
            assign write_data  = (load_enable && (load_lane == g)) ? load_data : lane_result[g];

            shader_regfile #(
                .WARP_COUNT(WARP_COUNT),
                .REG_COUNT (REG_COUNT),
                .REG_WIDTH (REG_WIDTH)
            ) u_regfile (
                .clk          (clk),
                .reset        (reset),
                .rs1_addr     (rs1_addr),
                .rs2_addr     (rs2_addr),
                .current_warp (current_warp),
                .rs1_data     (lane_rs1[g]),
                .rs2_data     (lane_rs2[g]),
                .write_enable (write_en),
                .rd_addr      (rd_addr),
                .write_data   (write_data)
            );

            shader_alu u_alu (
                .a      (lane_rs1[g]),
                .b      (lane_rs2[g]),
                .alu_op (alu_op),
                .result (lane_result[g])
            );

        end
    endgenerate

endmodule