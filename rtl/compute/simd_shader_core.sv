module simd_shader_core #(
    parameter int WARP_COUNT = 4,
    parameter int LANES      = 4,
    parameter int REG_COUNT  = 8,
    parameter int REG_WIDTH  = 16
) (
    input  logic               clk,
    input  logic               reset,
    input  logic               start,
    input  logic        [4:0]  program_length,

    // Shader-program loading interface. Use only while the core is idle.
    // One shared program for every warp/lane -- unchanged from V10.
    input  logic               program_write_enable,
    input  logic        [3:0]  program_write_addr,
    input  logic        [15:0] program_write_data,

    // Initial register loading interface. Use only while the core is idle.
    // Now addresses {warp, lane, reg} -- one lane's registers at a time.
    input  logic                           input_load_enable,
    input  logic [$clog2(WARP_COUNT)-1:0]  input_load_warp,
    input  logic [$clog2(LANES)-1:0]       input_load_lane,
    input  logic [$clog2(REG_COUNT)-1:0]   input_load_addr,
    input  logic signed [REG_WIDTH-1:0]    input_load_data,

    // Readback interface for a completed warp's registers, per lane.
    input  logic [$clog2(WARP_COUNT)-1:0]  read_register_warp,
    input  logic [$clog2(LANES)-1:0]       read_register_lane,
    input  logic [$clog2(REG_COUNT)-1:0]   read_register_addr,
    output logic signed [REG_WIDTH-1:0]    read_register_data,

    output logic               busy,
    output logic               done
);

    logic [3:0]  pc;
    logic [15:0] fetched_instruction;
    logic [15:0] instruction;

    logic [1:0]  opcode;
    logic [$clog2(REG_COUNT)-1:0]  rd;
    logic [$clog2(REG_COUNT)-1:0]  rs1;
    logic [$clog2(REG_COUNT)-1:0]  rs2;
    logic [1:0]  alu_op;
    logic        decoder_reg_write;

    // per-lane SIMD datapath outputs (was: single rs1_data/rs2_data/alu_result)
    logic signed [REG_WIDTH-1:0] lane_rs1    [0:LANES-1];
    logic signed [REG_WIDTH-1:0] lane_rs2    [0:LANES-1];
    logic signed [REG_WIDTH-1:0] lane_result [0:LANES-1];

    logic        controller_pc_clear;
    logic        controller_pc_increment;
    logic        controller_ir_load;
    logic        controller_reg_write_enable;
    logic [2:0]  controller_state;

    logic        final_instruction;
    logic        core_idle;
    logic        start_accepted;
    logic        imem_write_enable;

    logic [$clog2(REG_COUNT)-1:0] regfile_rs1_addr;
    logic [$clog2(REG_COUNT)-1:0] regfile_rs2_addr;

    logic [1:0] warp_state [0:WARP_COUNT-1];
    logic [$clog2(WARP_COUNT)-1:0] selected_warp;

    logic warp_select_valid;
    logic shader_start;

    logic scheduler_state_write;
    logic [$clog2(WARP_COUNT)-1:0] scheduler_state_write_warp;
    logic [1:0] scheduler_state_write_data;

    logic scheduler_busy;
    logic scheduler_done;

    logic shader_busy;
    logic shader_done;

    logic                          input_state_write;
    logic [$clog2(WARP_COUNT)-1:0] input_state_warp;
    logic [1:0]                    input_state_data;

    logic                          context_state_write;
    logic [$clog2(WARP_COUNT)-1:0] context_state_warp;
    logic [1:0]                    context_state_data;

    always_comb begin
        context_state_write = 1'b0;
        context_state_warp  = '0;
        context_state_data  = 2'b00;

        if (input_state_write) begin
            context_state_write = 1'b1;
            context_state_warp  = input_state_warp;
            context_state_data  = input_state_data;
        end
        else if (scheduler_state_write) begin
            context_state_write = 1'b1;
            context_state_warp  = scheduler_state_write_warp;
            context_state_data  = scheduler_state_write_data;
        end
    end

    assign input_state_write = input_load_enable && core_idle;
    assign input_state_warp  = input_load_warp;
    assign input_state_data  = 2'b01;   // READY

    // Which warp's register banks are selected this cycle, across all lanes.
    // - Executing (not core_idle): follow the scheduler's selected_warp.
    // - Idle + actively loading initial registers: use input_load_warp.
    // - Idle + not loading: use read_register_warp, for readback.
    logic [$clog2(WARP_COUNT)-1:0] regfile_current_warp;
    assign regfile_current_warp = core_idle
        ? (input_load_enable ? input_load_warp : read_register_warp)
        : selected_warp;

    assign core_idle = (controller_state == 3'd0);

    assign start_accepted = start && (program_length != 5'd0);

    assign busy = scheduler_busy;
    assign done = scheduler_done;

    assign final_instruction = (program_length != 5'd0) &&
        ({1'b0, pc} == (program_length - 5'd1));

    assign imem_write_enable = program_write_enable && core_idle;

    // shared register-slot address bus (same slot for every lane, every cycle)
    assign regfile_rs1_addr = core_idle ? read_register_addr : rs1;
    assign regfile_rs2_addr = core_idle ? '0 : rs2;

    // readback pulls from whichever lane the caller asked for
    assign read_register_data = lane_rs1[read_register_lane];

    // ---- writeback control: split into "loading one lane" vs "SIMD exec" ----
    // During core_idle + input_load_enable: only the addressed lane writes,
    // using input_load_data (see simd_lane_array's load_enable/load_lane).
    // During real execution: every lane writes its own ALU result together,
    // no per-lane gating yet (active mask deliberately deferred).
    logic lane_load_enable;
    logic [$clog2(LANES)-1:0] lane_load_lane;
    logic signed [REG_WIDTH-1:0] lane_load_data;
    logic [$clog2(REG_COUNT)-1:0] lane_rd_addr;
    logic lane_exec_write_enable;

    assign lane_load_enable      = core_idle && input_load_enable;
    assign lane_load_lane        = input_load_lane;
    assign lane_load_data        = input_load_data;
    assign lane_exec_write_enable = controller_reg_write_enable && decoder_reg_write;

    assign lane_rd_addr = (core_idle && input_load_enable) ? input_load_addr : rd;

    shader_controller u_controller (
        .clk              (clk),
        .reset            (reset),
        .start            (shader_start),
        .final_instruction(final_instruction),
        .busy             (shader_busy),
        .done             (shader_done),
        .pc_clear         (controller_pc_clear),
        .pc_increment     (controller_pc_increment),
        .ir_load          (controller_ir_load),
        .reg_write_enable (controller_reg_write_enable),
        .state            (controller_state)
    );

    shader_pc #(
        .WARP_COUNT(WARP_COUNT),
        .PC_WIDTH(4)
    ) u_pc (
        .clk         (clk),
        .reset       (reset),
        .pc_clear    (controller_pc_clear),
        .pc_increment(controller_pc_increment),
        .current_warp(selected_warp),
        .pc          (pc)
    );

    shader_imem u_imem (
        .clk                 (clk),
        .program_write_enable(imem_write_enable),
        .program_write_addr  (program_write_addr),
        .program_write_data  (program_write_data),
        .fetch_addr          (pc),
        .instruction         (fetched_instruction)
    );

    shader_ir u_ir (
        .clk            (clk),
        .reset          (reset),
        .ir_load        (controller_ir_load),
        .instruction_in (fetched_instruction),
        .instruction_out(instruction)
    );

    shader_decoder u_decoder (
        .instruction(instruction),
        .opcode     (opcode),
        .rd         (rd),
        .rs1        (rs1),
        .rs2        (rs2),
        .alu_op     (alu_op),
        .reg_write  (decoder_reg_write)
    );

    // ---- V11: replaces the single shader_regfile + shader_alu from V10 ----
    simd_lane_array #(
        .LANES     (LANES),
        .WARP_COUNT(WARP_COUNT),
        .REG_COUNT (REG_COUNT),
        .REG_WIDTH (REG_WIDTH)
    ) u_lanes (
        .clk               (clk),
        .reset             (reset),
        .current_warp      (regfile_current_warp),
        .rs1_addr          (regfile_rs1_addr),
        .rs2_addr          (regfile_rs2_addr),
        .rd_addr           (lane_rd_addr),
        .alu_op            (alu_op),
        .exec_write_enable (lane_exec_write_enable),
        .load_enable       (lane_load_enable),
        .load_lane         (lane_load_lane),
        .load_data         (lane_load_data),
        .lane_result       (lane_result),
        .lane_rs1          (lane_rs1),
        .lane_rs2          (lane_rs2)
    );

    warp_context #(
        .WARP_COUNT(WARP_COUNT)
    ) u_warp_context (
        .clk             (clk),
        .reset           (reset),
        .warp_select     (context_state_warp),
        .state_write     (context_state_write),
        .state_write_data(context_state_data),
        .warp_state      (warp_state)
    );

    warp_scheduler #(
        .WARP_COUNT(WARP_COUNT)
    ) u_warp_scheduler (
        .clk               (clk),
        .reset             (reset),
        .start             (start_accepted),

        .warp_state        (warp_state),

        .shader_busy       (shader_busy),
        .shader_done       (shader_done),

        .selected_warp     (selected_warp),
        .warp_select_valid (warp_select_valid),

        .shader_start      (shader_start),

        .state_write       (scheduler_state_write),
        .state_write_warp  (scheduler_state_write_warp),
        .state_write_data  (scheduler_state_write_data),

        .busy              (scheduler_busy),
        .done              (scheduler_done)
    );

endmodule