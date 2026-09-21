module z_buffer #(
    parameter WIDTH       = 64,
    parameter HEIGHT      = 64,
    parameter COLOR_WIDTH = 8,
    parameter DEPTH_WIDTH = 16
)(
    input  logic clk,
    input  logic rst,

    // Pixel from Triangle Rasterizer
    input  logic                    pixel_valid,
    input  logic [$clog2(WIDTH)-1:0]  pixel_x,
    input  logic [$clog2(HEIGHT)-1:0] pixel_y,
    input  logic [DEPTH_WIDTH-1:0]  pixel_depth,
    input  logic [COLOR_WIDTH-1:0]  pixel_color,

    // Pixel to Framebuffer
    output logic                    fb_write_en,
    output logic [$clog2(WIDTH)-1:0]  fb_x,
    output logic [$clog2(HEIGHT)-1:0] fb_y,
    output logic [COLOR_WIDTH-1:0]  fb_color
);

localparam X_W = $clog2(WIDTH);
localparam Y_W = $clog2(HEIGHT);
localparam ADDR_W = $clog2(WIDTH * HEIGHT);
logic [ADDR_W-1:0] addr;
logic [DEPTH_WIDTH-1:0] z_mem [0:WIDTH*HEIGHT-1];
logic depth_pass;

assign addr = pixel_y * WIDTH + pixel_x;

integer i;

initial begin
    for(i = 0; i < WIDTH*HEIGHT; i++)
        z_mem[i] = {DEPTH_WIDTH{1'b1}};
end

assign depth_pass = pixel_valid &&(pixel_depth < z_mem[addr]);

always_ff @(posedge clk) begin
    if (rst) begin
        fb_write_en <= 1'b0;
        fb_x        <= '0;
        fb_y        <= '0;
        fb_color    <= '0;

    end
    else begin

        
        fb_write_en <= 1'b0;

        
        if (depth_pass) begin
            z_mem[addr] <= pixel_depth;

            fb_write_en <= 1'b1;
            fb_x        <= pixel_x;
            fb_y        <= pixel_y;
            fb_color    <= pixel_color;
        end

    end
end


endmodule