module triangle_rasterizer #(
    parameter int WIDTH    = 64,
    parameter int HEIGHT   = 64,
    parameter int Z_WIDTH  = 16
)(
    input  logic clk, rst, start,

    input logic [$clog2(WIDTH)-1:0]  x0, x1, x2,
    input logic [$clog2(HEIGHT)-1:0] y0, y1, y2,
    input logic [7:0] pixel_value,

    // Per-vertex depth, latched at start alongside vertex xy
    input logic [Z_WIDTH-1:0] z0, z1, z2,

    output logic [$clog2(WIDTH)-1:0]  pixel_x,
    output logic [$clog2(HEIGHT)-1:0] pixel_y,
    output logic [7:0] pixel_value_out,
    output logic [Z_WIDTH-1:0] pixel_depth,
    output logic pixel_valid,

    output logic busy, done
);

    localparam int X_W    = $clog2(WIDTH);
    localparam int Y_W    = $clog2(HEIGHT);
    localparam int COORD_W = (X_W > Y_W) ? X_W : Y_W;
    localparam int DIFF_W  = COORD_W + 1;
    localparam int MULT_W  = 2 * DIFF_W;
    localparam int EDGE_W  = MULT_W + 1;

    logic [X_W-1:0] vx0, vx1, vx2;
    logic [Y_W-1:0] vy0, vy1, vy2;
    logic [Z_WIDTH-1:0] vz0, vz1, vz2;
    logic [X_W-1:0] min_x, max_x, current_x;
    logic [Y_W-1:0] min_y, max_y, current_y;

    typedef enum logic [1:0] { IDLE, BBOX, INIT, RASTER } state_t;
    state_t state;

    function automatic logic signed [EDGE_W-1:0] edge_fn (
        input logic [X_W-1:0] px,
        input logic [Y_W-1:0] py,
        input logic [X_W-1:0] ax,
        input logic [Y_W-1:0] ay,
        input logic [X_W-1:0] bx,
        input logic [Y_W-1:0] by
    );
        edge_fn =
            ($signed({1'b0, px}) - $signed({1'b0, ax})) *
            ($signed({1'b0, by}) - $signed({1'b0, ay}))
          - ($signed({1'b0, py}) - $signed({1'b0, ay})) *
            ($signed({1'b0, bx}) - $signed({1'b0, ax}));
    endfunction

    logic signed [EDGE_W-1:0] e0, e1, e2;
    logic inside_tri;
    logic lane_active;

    assign lane_active =
        (state == RASTER) &&
        (current_y <= max_y) &&
        (current_x <= max_x);

    assign e0 = edge_fn(current_x, current_y, vx0, vy0, vx1, vy1);
    assign e1 = edge_fn(current_x, current_y, vx1, vy1, vx2, vy2);
    assign e2 = edge_fn(current_x, current_y, vx2, vy2, vx0, vy0);

    assign inside_tri =
        ((e0 >= 0) && (e1 >= 0) && (e2 >= 0)) ||
        ((e0 <= 0) && (e1 <= 0) && (e2 <= 0));

    assign pixel_x         = current_x;
    assign pixel_y         = current_y;
    assign pixel_value_out = pixel_value;
    assign pixel_valid     = lane_active && inside_tri;

    // Barycentric depth interpolation.
    // e1 is the weight opposite v0, e2 opposite v1, e0 opposite v2.
    // Sized generously (48b) for the 64x64 / Z_WIDTH=16 case; re-check
    // widths if WIDTH/HEIGHT/Z_WIDTH grow significantly.
    logic signed [47:0] depth_num;
    logic signed [47:0] area_ext;
    logic signed [47:0] depth_div;

    assign area_ext = $signed(e0) + $signed(e1) + $signed(e2);
    assign depth_num =
        ($signed(e1) * $signed({1'b0, vz0})) +
        ($signed(e2) * $signed({1'b0, vz1})) +
        ($signed(e0) * $signed({1'b0, vz2}));

    assign depth_div = (area_ext != 0) ? (depth_num / area_ext) : '0;

    assign pixel_depth = (depth_div < 0) ? '0 : depth_div[Z_WIDTH-1:0];

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            busy  <= 1'b0;
            done  <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                IDLE: begin
                    busy <= 1'b0;

                    if (start) begin
                        vx0 <= x0;  vy0 <= y0;
                        vx1 <= x1;  vy1 <= y1;
                        vx2 <= x2;  vy2 <= y2;

                        vz0 <= z0;  vz1 <= z1;  vz2 <= z2;

                        busy  <= 1'b1;
                        state <= BBOX;
                    end
                end

                BBOX: begin
                    min_x <= (vx0 < vx1) ? ((vx0 < vx2) ? vx0 : vx2)
                                         : ((vx1 < vx2) ? vx1 : vx2);

                    max_x <= (vx0 > vx1) ? ((vx0 > vx2) ? vx0 : vx2)
                                         : ((vx1 > vx2) ? vx1 : vx2);

                    min_y <= (vy0 < vy1) ? ((vy0 < vy2) ? vy0 : vy2)
                                         : ((vy1 < vy2) ? vy1 : vy2);

                    max_y <= (vy0 > vy1) ? ((vy0 > vy2) ? vy0 : vy2)
                                         : ((vy1 > vy2) ? vy1 : vy2);

                    state <= INIT;
                end

                INIT: begin
                    current_x <= min_x;
                    current_y <= min_y;
                    state     <= RASTER;
                end

                RASTER: begin
                    // Advance by 1 pixel each clock - one candidate/cycle,
                    // matching z_buffer's single-pixel-per-cycle port
                    // directly. No stall/serializer needed downstream.
                    if (current_x == max_x) begin
                        if (current_y == max_y) begin
                            busy  <= 1'b0;
                            done  <= 1'b1;
                            state <= IDLE;
                        end else begin
                            current_x <= min_x;
                            current_y <= current_y + 1'b1;
                        end
                    end else begin
                        current_x <= current_x + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule