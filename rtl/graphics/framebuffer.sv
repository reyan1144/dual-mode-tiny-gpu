module framebuffer#(parameter WIDTH = 64 ,parameter HEIGHT = 64)(
input logic clk,
input logic rst,
input logic write_en,
input logic read_en,
input logic [$clog2(WIDTH)-1:0] x,
input logic [$clog2(HEIGHT)-1:0] y,
input logic [7:0] pixel_in,
output logic [7:0] pixel_out

    );
    logic [7:0] fb_mem [0:WIDTH*HEIGHT-1];
    logic [$clog2(WIDTH*HEIGHT)-1:0] addr;
    assign addr = y * WIDTH + x;
    integer i;

    initial begin
        for (i = 0; i < WIDTH*HEIGHT; i = i + 1)
            fb_mem[i] = 8'h00;
    end
    always_ff @(posedge clk)begin
        if (rst) begin
            pixel_out <= 8'h00;
        end
        else if(write_en)
            fb_mem[addr] <= pixel_in;
        else if(read_en)
            pixel_out <= fb_mem[addr];
    end
    
endmodule
