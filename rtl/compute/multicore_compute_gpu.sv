module multicore_compute_gpu #(
    parameter int NUM_CORES  = 4,
    parameter int WARP_COUNT = 4,
    parameter int LANES      = 4,
    parameter int REG_COUNT  = 8,
    parameter int REG_WIDTH  = 16
)(
    input  logic                         clk,
    input  logic                         reset,

    // ------------------------------------------------
    // Global work control
    // ------------------------------------------------
    input  logic                         start,
    input  logic [4:0]                   program_length,

    // ------------------------------------------------
    // Program loading
    // Broadcast to all V11 cores
    // ------------------------------------------------
    input  logic                         program_write_enable,
    input  logic [3:0]                   program_write_addr,
    input  logic [15:0]                  program_write_data,

    // ------------------------------------------------
    // Initial register loading
    // ------------------------------------------------
    input  logic [$clog2(NUM_CORES)-1:0] input_core_select,
    input  logic                         input_load_enable,
    input  logic [$clog2(WARP_COUNT)-1:0] input_load_warp,
    input  logic [$clog2(LANES)-1:0]      input_load_lane,
    input  logic [$clog2(REG_COUNT)-1:0]  input_load_addr,
    input  logic signed [REG_WIDTH-1:0]   input_load_data,

    // ------------------------------------------------
    // Register readback
    // ------------------------------------------------
    input  logic [$clog2(NUM_CORES)-1:0] read_core_select,
    input logic [$clog2(WARP_COUNT)-1:0] read_register_warp,
    input logic [$clog2(LANES)-1:0]      read_register_lane,
    input logic [$clog2(REG_COUNT)-1:0]  read_register_addr,

    output logic signed [REG_WIDTH-1:0]  read_register_data,

    // ------------------------------------------------
    // GPU status
    // ------------------------------------------------
    output logic                         busy,
    output logic                         done
);

    // =================================================
    // Controller ↔ Core Array signals
    // =================================================

    logic [NUM_CORES-1:0] core_start;
    logic [NUM_CORES-1:0] core_busy;
    logic [NUM_CORES-1:0] core_done;

    // =================================================
    // Multicore Controller
    // =================================================

    multicore_controller #(
        .NUM_CORES(NUM_CORES)
    ) u_controller (
        .clk       (clk),
        .reset     (reset),

        .start     (start),

        .core_busy (core_busy),
        .core_done (core_done),

        .core_start(core_start),

        .busy      (busy),
        .done      (done)
    );

    // =================================================
    // Four V11 SIMD Shader Cores
    // =================================================

    multicore_core_array #(
        .NUM_CORES (NUM_CORES),
        .WARP_COUNT(WARP_COUNT),
        .LANES     (LANES),
        .REG_COUNT (REG_COUNT),
        .REG_WIDTH (REG_WIDTH)
    ) u_core_array (

        .clk(clk),
        .reset(reset),

        // Controller
        .core_start(core_start),

        // Program
        .program_length(program_length),
        .program_write_enable(program_write_enable),
        .program_write_addr(program_write_addr),
        .program_write_data(program_write_data),

        // Input loading
        .input_core_select(input_core_select),
        .input_load_enable(input_load_enable),
        .input_load_warp(input_load_warp),
        .input_load_lane(input_load_lane),
        .input_load_addr(input_load_addr),
        .input_load_data(input_load_data),

        // Register readback
        .read_core_select(read_core_select),
        .read_register_warp(read_register_warp),
        .read_register_lane(read_register_lane),
        .read_register_addr(read_register_addr),
        .read_register_data(read_register_data),

        // Status back to controller
        .core_busy(core_busy),
        .core_done(core_done)
    );

endmodule
