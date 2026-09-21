module warp_scheduler #(
    parameter int WARP_COUNT = 4
) (
    input  logic                         clk,
    input  logic                         reset,

    input  logic                         start,

    input  logic [1:0]                   warp_state [0:WARP_COUNT-1],

    input  logic                         shader_busy,
    input  logic                         shader_done,

    output logic [$clog2(WARP_COUNT)-1:0] selected_warp,
    output logic                         warp_select_valid,

    output logic                         shader_start,

    output logic                         state_write,
    output logic [$clog2(WARP_COUNT)-1:0] state_write_warp,
    output logic [1:0]                    state_write_data,

    output logic                         busy,
    output logic                         done
);

localparam int WARP_ID_WIDTH = $clog2(WARP_COUNT);

typedef enum logic [1:0] {
    IDLE,
    SELECT,
    ISSUE,
    RUN
} scheduler_state_t;

scheduler_state_t current_state;

logic [WARP_ID_WIDTH-1:0] rr_pointer;
logic [WARP_ID_WIDTH-1:0] current_warp;

logic found_warp;
logic [WARP_ID_WIDTH-1:0] next_warp;

integer i;
integer idx;

always_comb begin
    found_warp = 1'b0;
    next_warp  = '0;

    for (i = 0; i < WARP_COUNT; i = i + 1) begin
        idx = (rr_pointer + i) % WARP_COUNT;

        if (!found_warp && (warp_state[idx] == 2'b01)) begin
            found_warp = 1'b1;
            next_warp  = idx[WARP_ID_WIDTH-1:0];
        end
    end
end

always_ff @(posedge clk) begin
    if (reset) begin
        current_state <= IDLE;
        rr_pointer    <= '0;
        current_warp  <= '0;
    end
    else begin
        case (current_state)

            IDLE: begin
                if (start)
                    current_state <= SELECT;
            end

            SELECT: begin
                if (found_warp) begin
                    current_warp  <= next_warp;
                    rr_pointer    <= next_warp + 1'b1;
                    current_state <= ISSUE;
                end
                else begin
                    // No warp is READY -> nothing left to dispatch.
                    // (Revisit this once STALLED warps exist: "not READY"
                    // will no longer imply "finished".)
                    current_state <= IDLE;
                end
            end


            ISSUE: begin
                current_state <= RUN;
            end

            RUN: begin
                if (shader_done)
                    current_state <= SELECT;
            end

            default: begin
                current_state <= IDLE;
            end

        endcase
    end
end

always_comb begin
    selected_warp     = current_warp;
    warp_select_valid = 1'b0;
    shader_start      = 1'b0;

    state_write       = 1'b0;
    state_write_warp  = '0;
    state_write_data  = 2'b00;

    busy              = 1'b0;
    done              = 1'b0;

    case (current_state)

        IDLE: begin
            busy = 1'b0;
        end

        SELECT: begin
            busy = 1'b1;

            if (found_warp) begin
                selected_warp     = next_warp;
                warp_select_valid = 1'b1;
            end
            else begin
                // No READY warp left -> the whole batch is finished.
                busy = 1'b0;
                done = 1'b1;
            end
        end

        ISSUE: begin
            busy         = 1'b1;
            shader_start = 1'b1;

            state_write      = 1'b1;
            state_write_warp = current_warp;
            state_write_data = 2'b10;   // RUNNING
        end

        RUN: begin
            busy = 1'b1;

            if (shader_done) begin
                state_write      = 1'b1;
                state_write_warp = current_warp;
                state_write_data = 2'b00;   // IDLE
            end
        end

        default: begin
            busy = 1'b0;
        end

    endcase
end
endmodule