`timescale 1ns/1ps

// =============================================================================
// Self-checking testbench for tiny_gpu_top
//
// Coverage:
//   1. Reset and default graphics-mode selection.
//   2. Blocking compute requests while graphics mode is active.
//   3. Graphics line command execution and framebuffer contents.
//   4. Deferring a graphics-to-compute mode change until graphics is idle.
//   5. Blocking graphics requests while compute mode is active.
//   6. Shader program loading, SIMD input loading, execution, and readback.
//   7. Deferring a compute-to-graphics mode change until compute is idle.
//
// Run the simulation from the directory containing sin_lut.mem/cos_lut.mem.
// =============================================================================

module tb_tiny_gpu_top;

    localparam time CLK_PERIOD = 10ns;

    localparam int GFX_CMD_WIDTH    = 128;
    localparam int GFX_XY_WIDTH     = 6;
    localparam int GFX_VP_XY_WIDTH  = 16;
    localparam int GFX_COLOR_WIDTH  = 8;

    localparam int NUM_CORES = 4;
    localparam int WARP_COUNT = 4;
    localparam int LANES = 4;
    localparam int REG_COUNT = 8;
    localparam int REG_WIDTH = 16;

    localparam int CORE_W = $clog2(NUM_CORES);
    localparam int WARP_W = $clog2(WARP_COUNT);
    localparam int LANE_W = $clog2(LANES);
    localparam int REG_W  = $clog2(REG_COUNT);

    logic clk;
    logic reset;
    logic mode;

    logic mode_active;
    logic mode_switch_pending;
    logic gpu_busy;
    logic gpu_done;
    logic graphics_busy;
    logic compute_busy;
    logic compute_done;

    logic                         gfx_cmd_write_en;
    logic [GFX_CMD_WIDTH-1:0]     gfx_cmd_write_data;
    logic                         gfx_cmd_fifo_full;

    logic signed [GFX_VP_XY_WIDTH-1:0] gfx_xform_tx;
    logic signed [GFX_VP_XY_WIDTH-1:0] gfx_xform_ty;
    logic signed [GFX_VP_XY_WIDTH-1:0] gfx_xform_sx;
    logic signed [GFX_VP_XY_WIDTH-1:0] gfx_xform_sy;
    logic [6:0]                        gfx_xform_angle;

    logic                             gfx_fb_read_en;
    logic [GFX_XY_WIDTH-1:0]          gfx_fb_read_x;
    logic [GFX_XY_WIDTH-1:0]          gfx_fb_read_y;
    logic [GFX_COLOR_WIDTH-1:0]       gfx_fb_read_data;

    logic                         compute_start;
    logic [4:0]                   compute_program_length;
    logic                         compute_program_write_enable;
    logic [3:0]                   compute_program_write_addr;
    logic [15:0]                  compute_program_write_data;

    logic [CORE_W-1:0]            compute_input_core_select;
    logic                         compute_input_load_enable;
    logic [WARP_W-1:0]            compute_input_load_warp;
    logic [LANE_W-1:0]            compute_input_load_lane;
    logic [REG_W-1:0]             compute_input_load_addr;
    logic signed [REG_WIDTH-1:0]  compute_input_load_data;

    logic [CORE_W-1:0]            compute_read_core_select;
    logic [WARP_W-1:0]            compute_read_register_warp;
    logic [LANE_W-1:0]            compute_read_register_lane;
    logic [REG_W-1:0]             compute_read_register_addr;
    logic signed [REG_WIDTH-1:0]  compute_read_register_data;

    int checks;
    int errors;

    tiny_gpu_top #(
        .GFX_CMD_WIDTH   (GFX_CMD_WIDTH),
        .GFX_XY_WIDTH    (GFX_XY_WIDTH),
        .GFX_VP_XY_WIDTH (GFX_VP_XY_WIDTH),
        .GFX_COLOR_WIDTH (GFX_COLOR_WIDTH),
        .NUM_CORES       (NUM_CORES),
        .WARP_COUNT      (WARP_COUNT),
        .LANES           (LANES),
        .REG_COUNT       (REG_COUNT),
        .REG_WIDTH       (REG_WIDTH)
    ) dut (
        .clk                            (clk),
        .reset                          (reset),
        .mode                           (mode),
        .mode_active                    (mode_active),
        .mode_switch_pending            (mode_switch_pending),
        .gpu_busy                       (gpu_busy),
        .gpu_done                       (gpu_done),
        .graphics_busy                  (graphics_busy),
        .compute_busy                   (compute_busy),
        .compute_done                   (compute_done),
        .gfx_cmd_write_en               (gfx_cmd_write_en),
        .gfx_cmd_write_data             (gfx_cmd_write_data),
        .gfx_cmd_fifo_full              (gfx_cmd_fifo_full),
        .gfx_xform_tx                   (gfx_xform_tx),
        .gfx_xform_ty                   (gfx_xform_ty),
        .gfx_xform_sx                   (gfx_xform_sx),
        .gfx_xform_sy                   (gfx_xform_sy),
        .gfx_xform_angle                (gfx_xform_angle),
        .gfx_fb_read_en                 (gfx_fb_read_en),
        .gfx_fb_read_x                  (gfx_fb_read_x),
        .gfx_fb_read_y                  (gfx_fb_read_y),
        .gfx_fb_read_data               (gfx_fb_read_data),
        .compute_start                  (compute_start),
        .compute_program_length         (compute_program_length),
        .compute_program_write_enable   (compute_program_write_enable),
        .compute_program_write_addr     (compute_program_write_addr),
        .compute_program_write_data     (compute_program_write_data),
        .compute_input_core_select      (compute_input_core_select),
        .compute_input_load_enable      (compute_input_load_enable),
        .compute_input_load_warp        (compute_input_load_warp),
        .compute_input_load_lane        (compute_input_load_lane),
        .compute_input_load_addr        (compute_input_load_addr),
        .compute_input_load_data        (compute_input_load_data),
        .compute_read_core_select       (compute_read_core_select),
        .compute_read_register_warp     (compute_read_register_warp),
        .compute_read_register_lane     (compute_read_register_lane),
        .compute_read_register_addr     (compute_read_register_addr),
        .compute_read_register_data     (compute_read_register_data)
    );

    // -------------------------------------------------------------------------
    // Clock and watchdog
    // -------------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        #200us;
        $fatal(1, "[TB] Global timeout");
    end

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    task automatic check(input logic condition, input string message);
        checks++;
        if (condition !== 1'b1) begin
            errors++;
            $error("[TB][FAIL] %s", message);
        end
        else begin
            $display("[TB][PASS] %s", message);
        end
    endtask

    function automatic logic [127:0] make_line_command(
        input logic [5:0] x0,
        input logic [5:0] y0,
        input logic [5:0] x1,
        input logic [5:0] y1,
        input logic [7:0] color
    );
        logic [127:0] command;
        begin
            command = '0;
            command[127:120] = 8'h01; // DRAW_LINE
            command[119:114] = x0;
            command[113:108] = y0;
            command[107:102] = x1;
            command[101:96]  = y1;
            command[83:76]   = color;
            return command;
        end
    endfunction

    function automatic logic [15:0] make_shader_instruction(
        input logic [1:0] opcode,
        input logic [2:0] rd,
        input logic [2:0] rs1,
        input logic [2:0] rs2
    );
        return {opcode, rd, rs1, rs2, 5'b0};
    endfunction

    task automatic pulse_graphics_command(input logic [127:0] command);
        begin
            while (gfx_cmd_fifo_full)
                @(negedge clk);
            @(negedge clk);
            gfx_cmd_write_data = command;
            gfx_cmd_write_en   = 1'b1;
            @(negedge clk);
            gfx_cmd_write_en   = 1'b0;
            gfx_cmd_write_data = '0;
        end
    endtask

    task automatic expect_framebuffer_pixel(
        input logic [5:0] x,
        input logic [5:0] y,
        input logic [7:0] expected
    );
        begin
            @(negedge clk);
            gfx_fb_read_x  = x;
            gfx_fb_read_y  = y;
            gfx_fb_read_en = 1'b1;
            @(posedge clk);
            #1;
            check(gfx_fb_read_data === expected,
                  $sformatf("Framebuffer (%0d,%0d) = 0x%02h", x, y, expected));
            @(negedge clk);
            gfx_fb_read_en = 1'b0;
        end
    endtask

    task automatic write_program_word(
        input logic [3:0] address,
        input logic [15:0] instruction
    );
        begin
            @(negedge clk);
            compute_program_write_addr   = address;
            compute_program_write_data   = instruction;
            compute_program_write_enable = 1'b1;
            @(negedge clk);
            compute_program_write_enable = 1'b0;
        end
    endtask

    task automatic load_compute_register(
        input logic [CORE_W-1:0] core_id,
        input logic [WARP_W-1:0] warp_id,
        input logic [LANE_W-1:0] lane_id,
        input logic [REG_W-1:0]  reg_id,
        input logic signed [REG_WIDTH-1:0] value
    );
        begin
            @(negedge clk);
            compute_input_core_select = core_id;
            compute_input_load_warp   = warp_id;
            compute_input_load_lane   = lane_id;
            compute_input_load_addr   = reg_id;
            compute_input_load_data   = value;
            compute_input_load_enable = 1'b1;
            @(negedge clk);
            compute_input_load_enable = 1'b0;
        end
    endtask

    task automatic expect_compute_register(
        input logic [CORE_W-1:0] core_id,
        input logic [WARP_W-1:0] warp_id,
        input logic [LANE_W-1:0] lane_id,
        input logic [REG_W-1:0]  reg_id,
        input logic signed [REG_WIDTH-1:0] expected
    );
        begin
            @(negedge clk);
            compute_read_core_select   = core_id;
            compute_read_register_warp = warp_id;
            compute_read_register_lane = lane_id;
            compute_read_register_addr = reg_id;
            #1;
            check(compute_read_register_data === expected,
                  $sformatf("Core %0d warp %0d lane %0d r%0d = %0d",
                            core_id, warp_id, lane_id, reg_id, expected));
        end
    endtask

    task automatic wait_for_graphics_busy(input int max_cycles);
        int count;
        begin
            count = 0;
            while (!graphics_busy && count < max_cycles) begin
                @(posedge clk);
                #1;
                count++;
            end
            check(graphics_busy, "Graphics engine asserted busy");
        end
    endtask

    task automatic wait_for_graphics_idle(input int max_cycles);
        int count;
        begin
            count = 0;
            while (graphics_busy && count < max_cycles) begin
                @(posedge clk);
                #1;
                count++;
            end
            check(!graphics_busy, "Graphics engine returned idle");
        end
    endtask

    task automatic wait_for_compute_busy(input int max_cycles);
        int count;
        begin
            count = 0;
            while (!compute_busy && count < max_cycles) begin
                @(posedge clk);
                #1;
                count++;
            end
            check(compute_busy, "Compute engine asserted busy");
        end
    endtask

    task automatic wait_for_compute_done(input int max_cycles);
        int count;
        bit observed;
        begin
            count    = 0;
            observed = 1'b0;
            while (!observed && count < max_cycles) begin
                @(posedge clk);
                #1;
                if (compute_done && gpu_done)
                    observed = 1'b1;
                count++;
            end
            check(observed, "Compute and GPU done pulses were observed");
        end
    endtask

    task automatic wait_for_mode(input logic expected_mode, input int max_cycles);
        int count;
        begin
            count = 0;
            while (((mode_active !== expected_mode) || mode_switch_pending) &&
                   count < max_cycles) begin
                @(posedge clk);
                #1;
                count++;
            end
            check((mode_active === expected_mode) && !mode_switch_pending,
                  $sformatf("Mode %0d became active", expected_mode));
        end
    endtask

    // -------------------------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------------------------
    initial begin
        logic [15:0] add_instruction;
        logic [15:0] multiply_instruction;

        checks = 0;
        errors = 0;

        reset = 1'b1;
        mode  = 1'b0;

        gfx_cmd_write_en   = 1'b0;
        gfx_cmd_write_data = '0;
        gfx_xform_tx       = '0;
        gfx_xform_ty       = '0;
        gfx_xform_sx       = 16'sd256; // 1.0 in Q8.8 for future triangle tests
        gfx_xform_sy       = 16'sd256;
        gfx_xform_angle    = '0;
        gfx_fb_read_en     = 1'b0;
        gfx_fb_read_x      = '0;
        gfx_fb_read_y      = '0;

        compute_start                = 1'b0;
        compute_program_length       = '0;
        compute_program_write_enable = 1'b0;
        compute_program_write_addr   = '0;
        compute_program_write_data   = '0;
        compute_input_core_select    = '0;
        compute_input_load_enable    = 1'b0;
        compute_input_load_warp      = '0;
        compute_input_load_lane      = '0;
        compute_input_load_addr      = '0;
        compute_input_load_data      = '0;
        compute_read_core_select     = '0;
        compute_read_register_warp   = '0;
        compute_read_register_lane   = '0;
        compute_read_register_addr   = '0;

        $dumpfile("tb_tiny_gpu_top.vcd");
        $dumpvars(0, tb_tiny_gpu_top);

        repeat (4) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);
        #1;

        $display("\n[TB] Test 1: reset/default mode");
        check(mode_active === 1'b0, "Reset selected graphics mode");
        check(mode_switch_pending === 1'b0, "No mode switch pending after reset");
        check(gpu_busy === 1'b0, "GPU is idle after reset");

        $display("\n[TB] Test 2: compute request blocked in graphics mode");
        @(negedge clk);
        compute_start = 1'b1;
        #1;
        check(dut.compute_start_gated === 1'b0,
              "Compute start is gated off in graphics mode");
        @(negedge clk);
        compute_start = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        check(compute_busy === 1'b0, "Blocked compute request did not start a core");

        $display("\n[TB] Test 3: graphics line and deferred switch to compute mode");
        pulse_graphics_command(make_line_command(6'd2, 6'd3, 6'd9, 6'd3, 8'hA5));
        wait_for_graphics_busy(40);

        // Request compute mode while the line is still being generated.
        @(negedge clk);
        mode = 1'b1;
        #1;
        check(mode_switch_pending === 1'b1, "Mode change marked pending");
        check(mode_active === 1'b0, "Graphics mode retained while graphics is busy");

        repeat (2) begin
            @(posedge clk);
            #1;
            if (graphics_busy)
                check(mode_active === 1'b0,
                      "Mode stayed graphics during in-flight line");
        end

        wait_for_graphics_idle(100);
        wait_for_mode(1'b1, 10);
        check(gfx_cmd_fifo_full === 1'b1,
              "Graphics interface reports not-ready in compute mode");

        // Allow the final framebuffer write to settle, then verify the line.
        repeat (2) @(posedge clk);
        expect_framebuffer_pixel(6'd2, 6'd3, 8'hA5);
        expect_framebuffer_pixel(6'd5, 6'd3, 8'hA5);
        expect_framebuffer_pixel(6'd9, 6'd3, 8'hA5);
        expect_framebuffer_pixel(6'd2, 6'd4, 8'h00);

        $display("\n[TB] Test 4: graphics request blocked in compute mode");
        @(negedge clk);
        gfx_cmd_write_data = make_line_command(6'd1, 6'd1, 6'd2, 6'd1, 8'hFF);
        gfx_cmd_write_en   = 1'b1;
        #1;
        check(dut.gfx_cmd_write_en_gated === 1'b0,
              "Graphics command write is gated off in compute mode");
        @(negedge clk);
        gfx_cmd_write_en   = 1'b0;
        gfx_cmd_write_data = '0;

        $display("\n[TB] Test 5: compute SIMD program and deferred return to graphics");
        add_instruction      = make_shader_instruction(2'b00, 3'd3, 3'd1, 3'd2);
        multiply_instruction = make_shader_instruction(2'b10, 3'd4, 3'd3, 3'd2);
        compute_program_length = 5'd2;

        // Program is broadcast to every compute core.
        write_program_word(4'd0, add_instruction);       // r3 = r1 + r2
        write_program_word(4'd1, multiply_instruction);  // r4 = r3 * r2

        // Prepare core 0, warp 0, two SIMD lanes.
        // lane 0: 7 + 5 = 12; 12 * 5 = 60
        load_compute_register(CORE_W'(0), WARP_W'(0), LANE_W'(0), REG_W'(1), 16'sd7);
        load_compute_register(CORE_W'(0), WARP_W'(0), LANE_W'(0), REG_W'(2), 16'sd5);

        // lane 1: -3 + 4 = 1; 1 * 4 = 4
        load_compute_register(CORE_W'(0), WARP_W'(0), LANE_W'(1), REG_W'(1), -16'sd3);
        load_compute_register(CORE_W'(0), WARP_W'(0), LANE_W'(1), REG_W'(2), 16'sd4);

        @(negedge clk);
        compute_start = 1'b1;
        @(negedge clk);
        compute_start = 1'b0;

        wait_for_compute_busy(40);
        check(gpu_busy === 1'b1, "Combined GPU busy reflects compute activity");

        // Request graphics mode while compute is running.
        @(negedge clk);
        mode = 1'b0;
        #1;
        check(mode_switch_pending === 1'b1,
              "Compute-to-graphics switch marked pending");
        check(mode_active === 1'b1,
              "Compute mode retained while compute is busy");

        wait_for_compute_done(500);

        // The multicore controller clears busy shortly after the done pulse.
        begin : wait_compute_idle_block
            int timeout;
            timeout = 0;
            while (compute_busy && timeout < 20) begin
                @(posedge clk);
                #1;
                timeout++;
            end
            check(!compute_busy, "Compute engine returned idle");
        end

        wait_for_mode(1'b0, 10);

        // Readback remains available even after returning to graphics mode.
        expect_compute_register(CORE_W'(0), WARP_W'(0), LANE_W'(0), REG_W'(3), 16'sd12);
        expect_compute_register(CORE_W'(0), WARP_W'(0), LANE_W'(0), REG_W'(4), 16'sd60);
        expect_compute_register(CORE_W'(0), WARP_W'(0), LANE_W'(1), REG_W'(3), 16'sd1);
        expect_compute_register(CORE_W'(0), WARP_W'(0), LANE_W'(1), REG_W'(4), 16'sd4);

        check(gpu_busy === 1'b0, "GPU idle at end of test");
        check(mode_active === 1'b0, "GPU returned to graphics mode");
        check(mode_switch_pending === 1'b0, "No mode switch pending at end");

        $display("\n============================================================");
        if (errors == 0) begin
            $display("[TB] ALL TESTS PASSED (%0d checks)", checks);
            $display("============================================================\n");
            $finish;
        end
        else begin
            $display("[TB] TEST FAILED: %0d of %0d checks failed", errors, checks);
            $display("============================================================\n");
            $fatal(1, "Self-checking testbench detected failures");
        end
    end

endmodule
