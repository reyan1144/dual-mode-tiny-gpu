module multicore_core_array #(
    parameter int NUM_CORES  = 4,
    parameter int WARP_COUNT = 4,
    parameter int LANES      = 4,
    parameter int REG_COUNT  = 8,
    parameter int REG_WIDTH  = 16
)(
    input  logic                         clk,
    input  logic                         reset,

    // Per-core start
    input  logic [NUM_CORES-1:0]         core_start,

    // Common program
    input  logic [4:0]                   program_length,
    input  logic                         program_write_enable,
    input  logic [3:0]                   program_write_addr,
    input  logic [15:0]                  program_write_data,

    // Core-select for input loading
    input  logic [$clog2(NUM_CORES)-1:0] input_core_select,
    input  logic                         input_load_enable,
    input  logic [$clog2(WARP_COUNT)-1:0] input_load_warp,
    input logic [$clog2(LANES)-1:0]       input_load_lane,
    input logic [$clog2(REG_COUNT)-1:0]   input_load_addr,
    input logic signed [REG_WIDTH-1:0]    input_load_data,

    // Register readback
    input logic [$clog2(NUM_CORES)-1:0]  read_core_select,
    input logic [$clog2(WARP_COUNT)-1:0] read_register_warp,
    input logic [$clog2(LANES)-1:0]      read_register_lane,
    input logic [$clog2(REG_COUNT)-1:0]  read_register_addr,

    output logic signed [REG_WIDTH-1:0]  read_register_data,

    // Per-core status
    output logic [NUM_CORES-1:0]         core_busy,
    output logic [NUM_CORES-1:0]         core_done
);

    // ------------------------------------------------
    // Per-core input-load enables
    // ------------------------------------------------

    logic [NUM_CORES-1:0] core_input_load_enable;

    always_comb begin
        core_input_load_enable = '0;

        if (input_load_enable)
            core_input_load_enable[input_core_select] = 1'b1;
    end

    // ------------------------------------------------
    // Per-core readback data
    // ------------------------------------------------

    logic signed [REG_WIDTH-1:0]
        core_read_data [0:NUM_CORES-1];

    // ------------------------------------------------
    // Generate four V11 SIMD shader cores
    // ------------------------------------------------

    genvar i;

    generate
        for (i = 0; i < NUM_CORES; i = i + 1) begin : GEN_SHADER_CORES

            simd_shader_core #(
                .WARP_COUNT(WARP_COUNT),
                .LANES     (LANES),
                .REG_COUNT (REG_COUNT),
                .REG_WIDTH (REG_WIDTH)
            ) u_simd_shader_core (

                .clk(clk),
                .reset(reset),

                .start(core_start[i]),
                .program_length(program_length),

                // Common program interface
                .program_write_enable(program_write_enable),
                .program_write_addr(program_write_addr),
                .program_write_data(program_write_data),

                // Input loading
                .input_load_enable(core_input_load_enable[i]),
                .input_load_warp(input_load_warp),
                .input_load_lane(input_load_lane),
                .input_load_addr(input_load_addr),
                .input_load_data(input_load_data),

                // Register readback
                .read_register_warp(read_register_warp),
                .read_register_lane(read_register_lane),
                .read_register_addr(read_register_addr),
                .read_register_data(core_read_data[i]),

                // Status
                .busy(core_busy[i]),
                .done(core_done[i])
            );

        end
    endgenerate

    // ------------------------------------------------
    // Select register readback from one core
    // ------------------------------------------------

    always_comb begin
        read_register_data = core_read_data[read_core_select];
    end

endmodule