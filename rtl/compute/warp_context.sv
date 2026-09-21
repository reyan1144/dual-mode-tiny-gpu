module warp_context #(
    parameter int WARP_COUNT = 4
    
) (
    input  logic                         clk,
    input  logic                         reset,

    input  logic [$clog2(WARP_COUNT)-1:0] warp_select,
    input  logic                         state_write,
    input  logic [1:0]                    state_write_data,
    output logic [1:0] warp_state [0:WARP_COUNT-1]
);

integer i;

always_ff @(posedge clk) begin
    if (reset) begin
        for (i = 0; i < WARP_COUNT; i++) begin
            warp_state[i] <= 2'b00;
        end
    end
    else begin
        if (state_write)
            warp_state[warp_select] <= state_write_data;
    end
end
endmodule