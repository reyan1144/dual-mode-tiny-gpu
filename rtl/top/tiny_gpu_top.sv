`timescale 1ns/1ps

// =============================================================================
// tiny_gpu_top
//
// Mode-selecting integration wrapper for the Tiny GPU graphics and compute
// engines.
//
//   mode = 1'b0 : graphics engine (gpu_top)
//   mode = 1'b1 : compute engine  (multicore_compute_gpu)
//
// Mode-change protocol:
//   1. Stop issuing work to the currently selected engine.
//   2. Wait for gpu_busy to deassert.
//   3. Change mode.
//   4. Wait until mode_active == mode (mode_switch_pending == 0).
//   5. Issue work to the newly selected engine.
//
// The wrapper never gates the clock. Instead, it gates all side-effecting
// request signals. Both engines receive the same active-high synchronous reset.
// Readback ports remain connected in either mode because reads do not start work.
// =============================================================================

module tiny_gpu_top #(
    // Graphics parameters
    parameter int GFX_CMD_WIDTH     = 128,
    parameter int GFX_OPCODE_WIDTH  = 8,
    parameter int GFX_XY_WIDTH      = 6,
    parameter int GFX_VP_XY_WIDTH   = 16,
    parameter int GFX_COLOR_WIDTH   = 8,
    parameter int GFX_Z_WIDTH       = 16,
    parameter int GFX_FIFO_DEPTH    = 8,
    parameter int GFX_WIDTH         = 64,
    parameter int GFX_HEIGHT        = 64,

    // Compute parameters
    parameter int NUM_CORES         = 4,
    parameter int WARP_COUNT        = 4,
    parameter int LANES             = 4,
    parameter int REG_COUNT         = 8,
    parameter int REG_WIDTH         = 16
)(
    // -------------------------------------------------------------------------
    // Common control
    // -------------------------------------------------------------------------
    input  logic clk,
    input  logic reset,
    input  logic mode,

    output logic mode_active,
    output logic mode_switch_pending,
    output logic gpu_busy,
    output logic gpu_done,
    output logic graphics_busy,
    output logic compute_busy,
    output logic compute_done,

    // -------------------------------------------------------------------------
    // Graphics command interface (used when mode_active == 0)
    // -------------------------------------------------------------------------
    input  logic                         gfx_cmd_write_en,
    input  logic [GFX_CMD_WIDTH-1:0]     gfx_cmd_write_data,
    output logic                         gfx_cmd_fifo_full,

    // Uniform transform applied to graphics triangles
    input  logic signed [GFX_VP_XY_WIDTH-1:0] gfx_xform_tx,
    input  logic signed [GFX_VP_XY_WIDTH-1:0] gfx_xform_ty,
    input  logic signed [GFX_VP_XY_WIDTH-1:0] gfx_xform_sx,
    input  logic signed [GFX_VP_XY_WIDTH-1:0] gfx_xform_sy,
    input  logic [6:0]                        gfx_xform_angle,

    // Graphics framebuffer readback
    input  logic                           gfx_fb_read_en,
    input  logic [GFX_XY_WIDTH-1:0]        gfx_fb_read_x,
    input  logic [GFX_XY_WIDTH-1:0]        gfx_fb_read_y,
    output logic [GFX_COLOR_WIDTH-1:0]     gfx_fb_read_data,

    // -------------------------------------------------------------------------
    // Compute control/program interface (used when mode_active == 1)
    // -------------------------------------------------------------------------
    input  logic                         compute_start,
    input  logic [4:0]                   compute_program_length,

    input  logic                         compute_program_write_enable,
    input  logic [3:0]                   compute_program_write_addr,
    input  logic [15:0]                  compute_program_write_data,

    // Compute register initialization
    input  logic [$clog2(NUM_CORES)-1:0]  compute_input_core_select,
    input  logic                         compute_input_load_enable,
    input  logic [$clog2(WARP_COUNT)-1:0] compute_input_load_warp,
    input  logic [$clog2(LANES)-1:0]      compute_input_load_lane,
    input  logic [$clog2(REG_COUNT)-1:0]  compute_input_load_addr,
    input  logic signed [REG_WIDTH-1:0]   compute_input_load_data,

    // Compute register readback
    input  logic [$clog2(NUM_CORES)-1:0]  compute_read_core_select,
    input  logic [$clog2(WARP_COUNT)-1:0] compute_read_register_warp,
    input  logic [$clog2(LANES)-1:0]      compute_read_register_lane,
    input  logic [$clog2(REG_COUNT)-1:0]  compute_read_register_addr,
    output logic signed [REG_WIDTH-1:0]   compute_read_register_data
);

    // -------------------------------------------------------------------------
    // Internal mode and request gating
    // -------------------------------------------------------------------------
    logic gfx_cmd_fifo_full_int;
    logic gfx_cmd_write_en_gated;
    logic compute_start_gated;
    logic compute_program_write_enable_gated;
    logic compute_input_load_enable_gated;

    // A mode request is accepted only while both engines are idle. Reset always
    // returns the device to graphics mode.
    always_ff @(posedge clk) begin
        if (reset)
            mode_active <= 1'b0;
        else if (!graphics_busy && !compute_busy)
            mode_active <= mode;
    end

    assign mode_switch_pending = (mode != mode_active);

    // Stop accepting old-mode work as soon as a mode change is requested. This
    // allows the active engine to drain before mode_active changes.
    assign gfx_cmd_write_en_gated = gfx_cmd_write_en &&
                                    (mode_active == 1'b0) &&
                                    !mode_switch_pending;

    assign compute_start_gated = compute_start &&
                                 (mode_active == 1'b1) &&
                                 !mode_switch_pending;

    assign compute_program_write_enable_gated = compute_program_write_enable &&
                                                (mode_active == 1'b1) &&
                                                !mode_switch_pending;

    assign compute_input_load_enable_gated = compute_input_load_enable &&
                                             (mode_active == 1'b1) &&
                                             !mode_switch_pending;

    // Present a full/not-ready indication whenever graphics mode cannot accept
    // commands. This prevents a command source from assuming an inactive-mode
    // write was accepted.
    assign gfx_cmd_fifo_full = ((mode_active == 1'b0) && !mode_switch_pending)
                             ? gfx_cmd_fifo_full_int
                             : 1'b1;

    // Since the engines are mutually exclusive, OR-ing their busy signals gives
    // a mode-independent indication and avoids hiding an operation during a
    // pending mode transition. Graphics currently has no top-level done pulse,
    // so gpu_done mirrors the compute completion pulse.
    assign gpu_busy = graphics_busy | compute_busy;
    assign gpu_done = compute_done;

    // -------------------------------------------------------------------------
    // Graphics engine
    // -------------------------------------------------------------------------
    gpu_top #(
        .CMD_WIDTH    (GFX_CMD_WIDTH),
        .OPCODE_WIDTH (GFX_OPCODE_WIDTH),
        .XY_WIDTH     (GFX_XY_WIDTH),
        .VP_XY_WIDTH  (GFX_VP_XY_WIDTH),
        .COLOR_WIDTH  (GFX_COLOR_WIDTH),
        .Z_WIDTH      (GFX_Z_WIDTH),
        .FIFO_DEPTH   (GFX_FIFO_DEPTH),
        .WIDTH        (GFX_WIDTH),
        .HEIGHT       (GFX_HEIGHT)
    ) u_graphics_gpu (
        .clk           (clk),
        .rst           (reset),
        .cmd_write_en  (gfx_cmd_write_en_gated),
        .cmd_write_data(gfx_cmd_write_data),
        .cmd_fifo_full (gfx_cmd_fifo_full_int),
        .xform_tx      (gfx_xform_tx),
        .xform_ty      (gfx_xform_ty),
        .xform_sx      (gfx_xform_sx),
        .xform_sy      (gfx_xform_sy),
        .xform_angle   (gfx_xform_angle),
        .fb_read_en    (gfx_fb_read_en),
        .fb_read_x     (gfx_fb_read_x),
        .fb_read_y     (gfx_fb_read_y),
        .fb_read_data  (gfx_fb_read_data),
        .pipeline_busy (graphics_busy)
    );

    // -------------------------------------------------------------------------
    // Compute engine
    // -------------------------------------------------------------------------
    multicore_compute_gpu #(
        .NUM_CORES (NUM_CORES),
        .WARP_COUNT(WARP_COUNT),
        .LANES     (LANES),
        .REG_COUNT (REG_COUNT),
        .REG_WIDTH (REG_WIDTH)
    ) u_compute_gpu (
        .clk                 (clk),
        .reset               (reset),
        .start               (compute_start_gated),
        .program_length      (compute_program_length),
        .program_write_enable(compute_program_write_enable_gated),
        .program_write_addr  (compute_program_write_addr),
        .program_write_data  (compute_program_write_data),
        .input_core_select   (compute_input_core_select),
        .input_load_enable   (compute_input_load_enable_gated),
        .input_load_warp     (compute_input_load_warp),
        .input_load_lane     (compute_input_load_lane),
        .input_load_addr     (compute_input_load_addr),
        .input_load_data     (compute_input_load_data),
        .read_core_select    (compute_read_core_select),
        .read_register_warp  (compute_read_register_warp),
        .read_register_lane  (compute_read_register_lane),
        .read_register_addr  (compute_read_register_addr),
        .read_register_data  (compute_read_register_data),
        .busy                (compute_busy),
        .done                (compute_done)
    );

endmodule

