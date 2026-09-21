module trig_lut #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 7
)(
    input  logic [ADDR_WIDTH-1:0] angle,

    output logic signed [DATA_WIDTH-1:0] sin_theta,
    output logic signed [DATA_WIDTH-1:0] cos_theta
);

logic signed [DATA_WIDTH-1:0] sin_rom [0:90];
logic signed [DATA_WIDTH-1:0] cos_rom [0:90];

// ROM only covers 0-90 degrees. angle is 7 bits (0-127), so anything
// above 90 must be clamped or it reads uninitialized memory.
// NOTE: this only supports a 0-90 degree quadrant. Full 0-359 degree
// rotation needs quadrant-selection logic (mirroring/negation based on
// angle range) added in vertex_processor - out of scope for this pass.
logic [ADDR_WIDTH-1:0] angle_clamped;
assign angle_clamped = (angle > 7'd90) ? 7'd90 : angle;

assign sin_theta = sin_rom[angle_clamped];
assign cos_theta = cos_rom[angle_clamped];

initial begin
    $readmemh("sin_lut.mem", sin_rom);
    $readmemh("cos_lut.mem", cos_rom);
end

endmodule
