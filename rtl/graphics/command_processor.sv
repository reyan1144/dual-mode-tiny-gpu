module command_processor #(
    parameter CMD_WIDTH    = 128,
    parameter OPCODE_WIDTH = 8,
    parameter XY_WIDTH     = 6,
    parameter COLOR_WIDTH  = 8,
    parameter Z_WIDTH      = 16,
    parameter FIFO_DEPTH   = 8
)(
    input  logic                  clk,
    input  logic                  rst,

    // CPU Command Interface
    input  logic                  cmd_write_en,
    input  logic [CMD_WIDTH-1:0]  cmd_write_data,
    output logic                  cmd_fifo_full,

    // Line Engine Interface
    output logic                  line_start,
    input  logic                  line_done,

    // Triangle Rasterizer Interface
    output logic                  triangle_start,
    input  logic                  triangle_done,

    // Geometry Outputs
    output logic [XY_WIDTH-1:0]   x0,
    output logic [XY_WIDTH-1:0]   y0,
    output logic [XY_WIDTH-1:0]   x1,
    output logic [XY_WIDTH-1:0]   y1,
    output logic [XY_WIDTH-1:0]   x2,
    output logic [XY_WIDTH-1:0]   y2,

    output logic [COLOR_WIDTH-1:0] color,

    output logic [Z_WIDTH-1:0]    z0,
    output logic [Z_WIDTH-1:0]    z1,
    output logic [Z_WIDTH-1:0]    z2
);

    // Internal FIFO signals
    logic                            fifo_read_en;
    logic [CMD_WIDTH-1:0]            fifo_read_data;
    logic                            fifo_empty;
    logic                            fifo_full;
    logic                            fifo_overflow_error;
    logic                            fifo_underflow_error;
    logic [$clog2(FIFO_DEPTH+1)-1:0] fifo_count;

    // Internal Decoder signals
    logic [OPCODE_WIDTH-1:0]         opcode;
    logic                            nop_cmd;
    logic                            line_cmd;
    logic                            triangle_cmd;
    logic                            clear_cmd;

    // Command FIFO Instance
    command_fifo #(
        .DATA_WIDTH (CMD_WIDTH),
        .DEPTH      (FIFO_DEPTH)
    ) fifo_inst (
        .clk              (clk),
        .rst              (rst),
        .write_en         (cmd_write_en),
        .write_data       (cmd_write_data),
        .read_en          (fifo_read_en),
        .read_data        (fifo_read_data),
        .full             (fifo_full),
        .empty            (fifo_empty),
        .overflow_error   (fifo_overflow_error),
        .underflow_error  (fifo_underflow_error),
        .count            (fifo_count)
    );

    // Command Decoder Instance
    command_decoder #(
        .CMD_WIDTH    (CMD_WIDTH),
        .OPCODE_WIDTH (OPCODE_WIDTH),
        .XY_WIDTH     (XY_WIDTH),
        .COLOR_WIDTH  (COLOR_WIDTH),
        .Z_WIDTH      (Z_WIDTH)
    ) decoder_inst (
        .cmd_packet    (fifo_read_data),
        .opcode        (opcode),
        .nop_cmd       (nop_cmd),
        .line_cmd      (line_cmd),
        .triangle_cmd  (triangle_cmd),
        .clear_cmd     (clear_cmd),
        .x0            (x0),
        .y0            (y0),
        .x1            (x1),
        .y1            (y1),
        .x2            (x2),
        .y2            (y2),
        .color         (color),
        .z0            (z0),
        .z1            (z1),
        .z2            (z2)
    );

    assign cmd_fifo_full = fifo_full;

    // FSM States
    typedef enum logic [2:0] {
        IDLE,
        FETCH,
        EXECUTE,
        WAIT_LINE,
        WAIT_TRIANGLE
    } state_t;

    state_t current_state, next_state;

    // State Register
    always_ff @(posedge clk) begin
        if (rst)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    // Next State Logic
    always_comb begin
        next_state = current_state;

        case (current_state)
            IDLE: begin
                if (!fifo_empty)
                    next_state = FETCH;
            end

            FETCH: begin
                // Synchronous FIFO read completes at the next clock edge
                next_state = EXECUTE;
            end

            EXECUTE: begin
                if (line_cmd)
                    next_state = WAIT_LINE;
                else if (triangle_cmd)
                    next_state = WAIT_TRIANGLE;
                else
                    next_state = IDLE; // NOP, CLEAR, or unhandled opcodes
            end

            WAIT_LINE: begin
                if (line_done)
                    next_state = IDLE;
            end

            WAIT_TRIANGLE: begin
                if (triangle_done)
                    next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // Output Control Logic
    always_comb begin
        fifo_read_en   = 1'b0;
        line_start     = 1'b0;
        triangle_start = 1'b0;

        case (current_state)
            FETCH: begin
                fifo_read_en = 1'b1;
            end

            EXECUTE: begin
                if (line_cmd)
                    line_start = 1'b1;
                else if (triangle_cmd)
                    triangle_start = 1'b1;
            end

            default: begin
            end
        endcase
    end

endmodule