module vertex_processor #(
    parameter XY_WIDTH = 16,
    parameter Z_WIDTH  = 16
)(
    input  logic clk,
    input  logic rst,

    input  logic start,

    input  logic signed [XY_WIDTH-1:0] x0,
    input  logic signed [XY_WIDTH-1:0] y0,
    input  logic signed [XY_WIDTH-1:0] x1,
    input  logic signed [XY_WIDTH-1:0] y1,
    input  logic signed [XY_WIDTH-1:0] x2,
    input  logic signed [XY_WIDTH-1:0] y2,

    input  logic signed [XY_WIDTH-1:0] tx,
    input  logic signed [XY_WIDTH-1:0] ty,
    input logic signed [XY_WIDTH-1:0] sx,
    input logic signed [XY_WIDTH-1:0] sy,

    input logic [6:0] angle,


    input  logic [7:0] color,

    input  logic [Z_WIDTH-1:0] z0,
    input  logic [Z_WIDTH-1:0] z1,
    input  logic [Z_WIDTH-1:0] z2,

    output logic busy,
    output logic done,

    output logic signed [XY_WIDTH-1:0] out_x0,
    output logic signed [XY_WIDTH-1:0] out_y0,
    output logic signed [XY_WIDTH-1:0] out_x1,
    output logic signed [XY_WIDTH-1:0] out_y1,
    output logic signed [XY_WIDTH-1:0] out_x2,
    output logic signed [XY_WIDTH-1:0] out_y2,

    output logic [7:0] out_color,

    output logic [Z_WIDTH-1:0] out_z0,
    output logic [Z_WIDTH-1:0] out_z1,
    output logic [Z_WIDTH-1:0] out_z2
);




logic signed [XY_WIDTH-1:0] scaled_x0;
logic signed [XY_WIDTH-1:0] scaled_y0;

logic signed [XY_WIDTH-1:0] scaled_x1;
logic signed [XY_WIDTH-1:0] scaled_y1;

logic signed [XY_WIDTH-1:0] scaled_x2;
logic signed [XY_WIDTH-1:0] scaled_y2;

assign scaled_x0 = x0 * sx;
assign scaled_y0 = y0 * sy;

assign scaled_x1 = x1 * sx;
assign scaled_y1 = y1 * sy;

assign scaled_x2 = x2 * sx;
assign scaled_y2 = y2 * sy;

logic signed [31:0] x0_cos;
logic signed [31:0] y0_sin;
logic signed [31:0] x0_sin;
logic signed [31:0] y0_cos;
logic signed [31:0] x1_cos;
logic signed [31:0] y1_sin;
logic signed [31:0] x1_sin;
logic signed [31:0] y1_cos;
logic signed [31:0] x2_cos;
logic signed [31:0] y2_sin;
logic signed [31:0] x2_sin;
logic signed [31:0] y2_cos;


logic signed [XY_WIDTH-1:0] rotated_x0;
logic signed [XY_WIDTH-1:0] rotated_y0;
logic signed [XY_WIDTH-1:0] rotated_x1;
logic signed [XY_WIDTH-1:0] rotated_y1;
logic signed [XY_WIDTH-1:0] rotated_x2;
logic signed [XY_WIDTH-1:0] rotated_y2;

logic signed [15:0] sin_theta;
logic signed [15:0] cos_theta;

trig_lut trig_lut_inst (
    .angle(angle),
    .sin_theta(sin_theta),
    .cos_theta(cos_theta)
);

assign x0_cos = scaled_x0 * cos_theta;
assign y0_sin = scaled_y0 * sin_theta;
assign x0_sin = scaled_x0 * sin_theta;
assign y0_cos = scaled_y0 * cos_theta;
assign x1_cos = scaled_x1 * cos_theta;
assign y1_sin = scaled_y1 * sin_theta;
assign x1_sin = scaled_x1 * sin_theta;
assign y1_cos = scaled_y1 * cos_theta;
assign x2_cos = scaled_x2 * cos_theta;
assign y2_sin = scaled_y2 * sin_theta;
assign x2_sin = scaled_x2 * sin_theta;
assign y2_cos = scaled_y2 * cos_theta;


assign rotated_x0 = (x0_cos >>> 8) - (y0_sin >>> 8);
assign rotated_y0 = (x0_sin >>> 8) + (y0_cos >>> 8);
assign rotated_x1 = (x1_cos >>> 8) - (y1_sin >>> 8);
assign rotated_y1 = (x1_sin >>> 8) + (y1_cos >>> 8);
assign rotated_x2 = (x2_cos >>> 8) - (y2_sin >>> 8);
assign rotated_y2 = (x2_sin >>> 8) + (y2_cos >>> 8);





always_ff @(posedge clk) begin
      if (rst) begin
       

        busy <= 1'b0;
        done <= 1'b0;

        out_x0 <= '0;
        out_y0 <= '0;
        out_x1 <= '0;
        out_y1 <= '0;
        out_x2 <= '0;
        out_y2 <= '0;

        out_color <= '0;

        out_z0 <= '0;
        out_z1 <= '0;
        out_z2 <= '0;
    end
    else begin
        // Default outputs
        done <= 1'b0;
        busy <= 1'b0;

        // This is a single-cycle transform: start and done land on the
        // same registered edge, so busy pulses alongside done rather than
        // spanning multiple cycles. It was previously hardcoded to 0 here
        // and never actually asserted - fixed so gpu_top's busy-OR has a
        // real (if brief) signal to see.
        if (start) begin
            busy <= 1'b1;

            out_x0 <= rotated_x0 + tx;
            out_y0 <= rotated_y0 + ty;

            out_x1 <= rotated_x1 + tx;
            out_y1 <= rotated_y1 + ty;

            out_x2 <= rotated_x2 + tx;
            out_y2 <= rotated_y2 + ty;

            out_color <= color;

            // Depth is unaffected by the 2D screen-space transform;
            // pass it straight through.
            out_z0 <= z0;
            out_z1 <= z1;
            out_z2 <= z2;

            done <= 1'b1;
        end

       
    end
end
endmodule