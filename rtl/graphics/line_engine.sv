module line_engine #(
    parameter WIDTH  = 64,
    parameter HEIGHT = 64
)(
    input  logic clk,
    input  logic rst,
    input  logic start,

    input  logic [$clog2(WIDTH)-1:0]  x0,
    input  logic [$clog2(HEIGHT)-1:0] y0,
    input  logic [$clog2(WIDTH)-1:0]  x1,
    input  logic [$clog2(HEIGHT)-1:0] y1,

    input  logic [7:0] pixel_value,

    output logic [$clog2(WIDTH)-1:0]  pixel_x,
    output logic [$clog2(HEIGHT)-1:0] pixel_y,
    output logic [7:0] pixel_value_out,

    output logic pixel_valid,
    output logic busy,
    output logic done
);

localparam X_W    = $clog2(WIDTH);
localparam Y_W    = $clog2(HEIGHT);
localparam CALC_W = ((X_W > Y_W) ? X_W : Y_W) + 2;

logic [X_W-1:0] x, x_end;
logic [Y_W-1:0] y, y_end;

logic [CALC_W-1:0] dx;
logic [CALC_W-1:0] dy;
logic signed [CALC_W-1:0] sx;
logic signed [CALC_W-1:0] sy;
logic signed [CALC_W-1:0] error;
logic signed [CALC_W-1:0] e2;

typedef enum logic {
    IDLE,
    DRAW
} state_t;

state_t state;

assign e2 = 2 * error;

always_ff @(posedge clk) begin
    if (rst) begin
        state       <= IDLE;
        busy        <= 0;
        done        <= 0;
        pixel_valid <= 0;
    end
    else begin
        case (state)

            IDLE: begin
                busy        <= 0;
                done        <= 0;
                pixel_valid <= 0;

                if (start) begin
                    x <= x0;
                    y <= y0;
                    x_end <= x1;
                    y_end <= y1;

                    dx <= (x1 >= x0) ? (x1 - x0) : (x0 - x1);
                    dy <= (y1 >= y0) ? (y1 - y0) : (y0 - y1);
                    sx <= (x0 < x1) ? 1 : -1;
                    sy <= (y0 < y1) ? 1 : -1;

                    error <= ((x1 >= x0) ? (x1 - x0) : (x0 - x1))
                           - ((y1 >= y0) ? (y1 - y0) : (y0 - y1));

                    busy  <= 1;
                    state <= DRAW;
                end
            end

            DRAW: begin
                pixel_x         <= x;
                pixel_y         <= y;
                pixel_value_out <= pixel_value;
                pixel_valid     <= 1;

                if (x == x_end && y == y_end) begin
                    done  <= 1;
                    busy  <= 0;
                    state <= IDLE;
                end
                else begin
                    if ((e2 > -$signed(dy)) &&
                        (e2 < $signed(dx))) begin

                        x     <= x + sx;
                        y     <= y + sy;
                        error <= error - dy + dx;

                    end
                    else if (e2 > -$signed(dy)) begin

                        x     <= x + sx;
                        error <= error - dy;

                    end
                    else begin

                        y     <= y + sy;
                        error <= error + dx;

                    end
                end
            end

            default: begin
                state <= IDLE;
            end

        endcase
    end
end

endmodule