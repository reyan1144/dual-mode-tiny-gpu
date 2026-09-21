module shader_pc #(
    parameter int WARP_COUNT = 4,
    parameter int PC_WIDTH   = 4
) (
    input  logic                         clk,
    input  logic                         reset,
    input  logic                         pc_clear,
    input  logic                         pc_increment,
    input  logic [$clog2(WARP_COUNT)-1:0] current_warp,
    output logic [PC_WIDTH-1:0]          pc
);

    logic [PC_WIDTH-1:0] warp_pc [0:WARP_COUNT-1];

    assign pc = warp_pc[current_warp];

    always_ff @(posedge clk) begin
        if (reset) begin
            for (int i = 0; i < WARP_COUNT; i++) begin
                warp_pc[i] <= '0;
            end
        end
        else if (pc_clear) begin
            warp_pc[current_warp] <= '0;
        end
        else if (pc_increment) begin
            warp_pc[current_warp] <= warp_pc[current_warp] + 1'b1;
        end
    end

endmodule