// gpu_top

module gpu_top #(
    parameter int CMD_WIDTH    = 128,
    parameter int OPCODE_WIDTH = 8,
    parameter int XY_WIDTH     = 6,     // screen-space coord width (64x64)
    parameter int VP_XY_WIDTH  = 16,    // vertex_processor's signed coord width
    parameter int COLOR_WIDTH  = 8,
    parameter int Z_WIDTH      = 16,
    parameter int FIFO_DEPTH   = 8,
    parameter int WIDTH        = 64,
    parameter int HEIGHT       = 64
)(
    input  logic clk,
    input  logic rst,

    // CPU command write interface
    input  logic                  cmd_write_en,
    input  logic [CMD_WIDTH-1:0]  cmd_write_data,
    output logic                  cmd_fifo_full,

    // Uniform transform applied to every triangle (see decision #2 above)
    input  logic signed [VP_XY_WIDTH-1:0] xform_tx,
    input  logic signed [VP_XY_WIDTH-1:0] xform_ty,
    input  logic signed [VP_XY_WIDTH-1:0] xform_sx,
    input  logic signed [VP_XY_WIDTH-1:0] xform_sy,
    input  logic [6:0]                    xform_angle,

    // External framebuffer readback (e.g. display controller / CPU peek)
    input  logic                    fb_read_en,
    input  logic [XY_WIDTH-1:0]     fb_read_x,
    input  logic [XY_WIDTH-1:0]     fb_read_y,
    output logic [COLOR_WIDTH-1:0]  fb_read_data,

    output logic pipeline_busy
);

    // -------------------------------------------------------------------
    // command_processor
    // -------------------------------------------------------------------
    logic line_start, line_done;
    logic triangle_start, triangle_done;

    logic [XY_WIDTH-1:0]    cp_x0, cp_y0, cp_x1, cp_y1, cp_x2, cp_y2;
    logic [COLOR_WIDTH-1:0] cp_color;
    logic [Z_WIDTH-1:0]     cp_z0, cp_z1, cp_z2;

    command_processor #(
        .CMD_WIDTH    (CMD_WIDTH),
        .OPCODE_WIDTH (OPCODE_WIDTH),
        .XY_WIDTH     (XY_WIDTH),
        .COLOR_WIDTH  (COLOR_WIDTH),
        .Z_WIDTH      (Z_WIDTH),
        .FIFO_DEPTH   (FIFO_DEPTH)
    ) cmd_proc_inst (
        .clk             (clk),
        .rst             (rst),
        .cmd_write_en    (cmd_write_en),
        .cmd_write_data  (cmd_write_data),
        .cmd_fifo_full   (cmd_fifo_full),
        .line_start      (line_start),
        .line_done       (line_done),
        .triangle_start  (triangle_start),
        .triangle_done   (triangle_done),
        .x0 (cp_x0), .y0 (cp_y0),
        .x1 (cp_x1), .y1 (cp_y1),
        .x2 (cp_x2), .y2 (cp_y2),
        .color (cp_color),
        .z0 (cp_z0), .z1 (cp_z1), .z2 (cp_z2)
    );

    // NOTE: clear_cmd is decoded internally by command_processor's decoder
    // but has no dedicated output/state - it's a no-op today (decision #4).

    // -------------------------------------------------------------------
    // Line path: command_processor -> line_engine -> framebuffer
    // -------------------------------------------------------------------
    logic [XY_WIDTH-1:0] line_px, line_py;
    logic [COLOR_WIDTH-1:0] line_pval;
    logic line_pixel_valid, line_busy;

    line_engine #(
        .WIDTH  (WIDTH),
        .HEIGHT (HEIGHT)
    ) line_engine_inst (
        .clk (clk), .rst (rst), .start (line_start),
        .x0 (cp_x0), .y0 (cp_y0),
        .x1 (cp_x1), .y1 (cp_y1),
        .pixel_value (cp_color),
        .pixel_x (line_px), .pixel_y (line_py),
        .pixel_value_out (line_pval),
        .pixel_valid (line_pixel_valid),
        .busy (line_busy),
        .done (line_done)
    );

    // -------------------------------------------------------------------
    // Triangle path, stage 1: vertex_processor
    //
    // command_processor's XY_WIDTH=6 unsigned outputs are zero-extended
    // into vertex_processor's signed 16-bit inputs (always non-negative
    // coming out of the decoder, so zero-extension is safe here).
    // -------------------------------------------------------------------
    logic vp_start, vp_busy, vp_done;
    logic signed [VP_XY_WIDTH-1:0] vp_out_x0, vp_out_y0, vp_out_x1, vp_out_y1, vp_out_x2, vp_out_y2;
    logic [COLOR_WIDTH-1:0] vp_out_color;
    logic [Z_WIDTH-1:0] vp_out_z0, vp_out_z1, vp_out_z2;

    assign vp_start = triangle_start;

    vertex_processor #(
        .XY_WIDTH (VP_XY_WIDTH),
        .Z_WIDTH  (Z_WIDTH)
    ) vertex_processor_inst (
        .clk (clk), .rst (rst), .start (vp_start),
        .x0 ({{(VP_XY_WIDTH-XY_WIDTH){1'b0}}, cp_x0}),
        .y0 ({{(VP_XY_WIDTH-XY_WIDTH){1'b0}}, cp_y0}),
        .x1 ({{(VP_XY_WIDTH-XY_WIDTH){1'b0}}, cp_x1}),
        .y1 ({{(VP_XY_WIDTH-XY_WIDTH){1'b0}}, cp_y1}),
        .x2 ({{(VP_XY_WIDTH-XY_WIDTH){1'b0}}, cp_x2}),
        .y2 ({{(VP_XY_WIDTH-XY_WIDTH){1'b0}}, cp_y2}),
        .tx (xform_tx), .ty (xform_ty),
        .sx (xform_sx), .sy (xform_sy),
        .angle (xform_angle),
        .color (cp_color),
        .z0 (cp_z0), .z1 (cp_z1), .z2 (cp_z2),
        .busy (vp_busy), .done (vp_done),
        .out_x0 (vp_out_x0), .out_y0 (vp_out_y0),
        .out_x1 (vp_out_x1), .out_y1 (vp_out_y1),
        .out_x2 (vp_out_x2), .out_y2 (vp_out_y2),
        .out_color (vp_out_color),
        .out_z0 (vp_out_z0), .out_z1 (vp_out_z1), .out_z2 (vp_out_z2)
    );

    // Clamp signed transformed coords into unsigned [0, WIDTH/HEIGHT-1] screen
    // space (decision #6). Saturates rather than wraps.
    function automatic logic [XY_WIDTH-1:0] clamp_coord(
        input logic signed [VP_XY_WIDTH-1:0] v,
        input int max_val
    );
        if (v < 0)
            clamp_coord = '0;
        else if (v > max_val)
            clamp_coord = max_val[XY_WIDTH-1:0];
        else
            clamp_coord = v[XY_WIDTH-1:0];
    endfunction

    logic [XY_WIDTH-1:0] rast_x0, rast_y0, rast_x1, rast_y1, rast_x2, rast_y2;
    logic [COLOR_WIDTH-1:0] rast_color_in;
    logic [Z_WIDTH-1:0] rast_z0, rast_z1, rast_z2;
    logic rast_start;

    // Latch vertex_processor's output for one cycle to feed the rasterizer's
    // start pulse (vertex_processor's done is already a single-cycle pulse).
    always_ff @(posedge clk) begin
        if (rst) begin
            rast_x0 <= '0; rast_y0 <= '0;
            rast_x1 <= '0; rast_y1 <= '0;
            rast_x2 <= '0; rast_y2 <= '0;
            rast_color_in <= '0;
            rast_z0 <= '0; rast_z1 <= '0; rast_z2 <= '0;
            rast_start <= 1'b0;
        end else begin
            rast_start <= vp_done;
            if (vp_done) begin
                rast_x0 <= clamp_coord(vp_out_x0, WIDTH-1);
                rast_y0 <= clamp_coord(vp_out_y0, HEIGHT-1);
                rast_x1 <= clamp_coord(vp_out_x1, WIDTH-1);
                rast_y1 <= clamp_coord(vp_out_y1, HEIGHT-1);
                rast_x2 <= clamp_coord(vp_out_x2, WIDTH-1);
                rast_y2 <= clamp_coord(vp_out_y2, HEIGHT-1);
                rast_color_in <= vp_out_color;
                rast_z0 <= vp_out_z0;
                rast_z1 <= vp_out_z1;
                rast_z2 <= vp_out_z2;
            end
        end
    end

    // -------------------------------------------------------------------
    // Triangle path, stage 2: rasterizer (1 pixel/cycle) -> z_buffer
    // (single-lane, so the rasterizer's output ports connect straight
    // into z_buffer's single-pixel port - no serializer required)
    // -------------------------------------------------------------------
    logic rast_busy, rast_done;
    logic [XY_WIDTH-1:0] rp_x, rp_y;
    logic [COLOR_WIDTH-1:0] rp_color;
    logic [Z_WIDTH-1:0] rp_depth;
    logic rp_valid;

    triangle_rasterizer #(
        .WIDTH   (WIDTH),
        .HEIGHT  (HEIGHT),
        .Z_WIDTH (Z_WIDTH)
    ) rasterizer_inst (
        .clk (clk), .rst (rst), .start (rast_start),
        .x0 (rast_x0), .x1 (rast_x1), .x2 (rast_x2),
        .y0 (rast_y0), .y1 (rast_y1), .y2 (rast_y2),
        .pixel_value (rast_color_in),
        .z0 (rast_z0), .z1 (rast_z1), .z2 (rast_z2),
        .pixel_x (rp_x), .pixel_y (rp_y),
        .pixel_value_out (rp_color),
        .pixel_depth (rp_depth),
        .pixel_valid (rp_valid),
        .busy (rast_busy), .done (rast_done)
    );

    // -------------------------------------------------------------------
    // Triangle path, stage 3: z_buffer
    // -------------------------------------------------------------------
    logic zbuf_fb_write_en;
    logic [XY_WIDTH-1:0] zbuf_fb_x, zbuf_fb_y;
    logic [COLOR_WIDTH-1:0] zbuf_fb_color;

    z_buffer #(
        .WIDTH       (WIDTH),
        .HEIGHT      (HEIGHT),
        .COLOR_WIDTH (COLOR_WIDTH),
        .DEPTH_WIDTH (Z_WIDTH)
    ) z_buffer_inst (
        .clk (clk), .rst (rst),
        .pixel_valid (rp_valid),
        .pixel_x     (rp_x),
        .pixel_y     (rp_y),
        .pixel_depth (rp_depth),
        .pixel_color (rp_color),
        .fb_write_en (zbuf_fb_write_en),
        .fb_x        (zbuf_fb_x),
        .fb_y        (zbuf_fb_y),
        .fb_color    (zbuf_fb_color)
    );

    assign triangle_done = rast_done;

    // -------------------------------------------------------------------
    // Framebuffer arbitration: line_engine and z_buffer never write in the
    // same cycle because command_processor's FSM only runs one of
    // WAIT_LINE / WAIT_TRIANGLE at a time. Simple priority-free OR-mux.
    // External readback is gated off whenever an internal write is active.
    // -------------------------------------------------------------------
    logic fb_write_en_int;
    logic [XY_WIDTH-1:0] fb_x_int, fb_y_int;
    logic [COLOR_WIDTH-1:0] fb_pixel_in_int;

    assign fb_write_en_int = line_pixel_valid || zbuf_fb_write_en;
    assign fb_x_int        = line_pixel_valid ? line_px       : zbuf_fb_x;
    assign fb_y_int         = line_pixel_valid ? line_py       : zbuf_fb_y;
    assign fb_pixel_in_int = line_pixel_valid ? line_pval      : zbuf_fb_color;

    logic fb_read_en_gated;
    assign fb_read_en_gated = fb_read_en && !fb_write_en_int;

    logic [XY_WIDTH-1:0] fb_addr_x, fb_addr_y;
    assign fb_addr_x = fb_write_en_int ? fb_x_int : fb_read_x;
    assign fb_addr_y = fb_write_en_int ? fb_y_int : fb_read_y;

    framebuffer #(
        .WIDTH  (WIDTH),
        .HEIGHT (HEIGHT)
    ) framebuffer_inst (
        .clk (clk), .rst (rst),
        .write_en  (fb_write_en_int),
        .read_en   (fb_read_en_gated),
        .x (fb_addr_x), .y (fb_addr_y),
        .pixel_in  (fb_pixel_in_int),
        .pixel_out (fb_read_data)
    );

    // -------------------------------------------------------------------
    // Busy tracking: line_busy/vp_busy/rast_busy alone have a blind spot -
    // there's real latency between triangle_start firing and rast_busy
    // actually going high (through vertex_processor + one registered
    // handoff stage), during which none of the downstream busy signals
    // are asserted yet even though a command is genuinely in flight.
    // Latch busy the instant start fires; only clear it on the matching
    // done, so there's no gap for an external waiter to sample through.
    // -------------------------------------------------------------------
    logic waiting_for_line, waiting_for_triangle;

    always_ff @(posedge clk) begin
        if (rst) begin
            waiting_for_line     <= 1'b0;
            waiting_for_triangle <= 1'b0;
        end else begin
            if (line_start)
                waiting_for_line <= 1'b1;
            else if (line_done)
                waiting_for_line <= 1'b0;

            if (triangle_start)
                waiting_for_triangle <= 1'b1;
            else if (triangle_done)
                waiting_for_triangle <= 1'b0;
        end
    end

    assign pipeline_busy = waiting_for_line || waiting_for_triangle ||
                            line_busy || vp_busy || rast_busy;

endmodule
