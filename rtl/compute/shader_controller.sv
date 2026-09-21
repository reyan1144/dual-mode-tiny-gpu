module shader_controller (
    input  logic       clk,
    input  logic       reset,
    input  logic       start,
    input  logic       final_instruction,

    output logic       busy,
    output logic       done,
    output logic       pc_clear,
    output logic       pc_increment,
    output logic       ir_load,
    output logic       reg_write_enable,
    output logic [2:0] state
);

    typedef enum logic [2:0] {
        IDLE      = 3'd0,
        FETCH     = 3'd1,
        DECODE    = 3'd2,
        EXECUTE   = 3'd3,
        WRITEBACK = 3'd4,
        DONE      = 3'd5
    } state_t;

    state_t current_state;
    state_t next_state;

    // State register
    always_ff @(posedge clk) begin
        if (reset)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    // Next-state logic
    always_comb begin
        next_state = current_state;

        unique case (current_state)
            IDLE: begin
                if (start)
                    next_state = FETCH;
            end

            FETCH:     next_state = DECODE;
            DECODE:    next_state = EXECUTE;
            EXECUTE:   next_state = WRITEBACK;

            WRITEBACK: begin
                if (final_instruction)
                    next_state = DONE;
                else
                    next_state = FETCH;
            end

            DONE:      next_state = IDLE;
            default:   next_state = IDLE;
        endcase
    end

    // Control-output logic
    always_comb begin
        busy             = 1'b0;
        done             = 1'b0;
        pc_clear         = 1'b0;
        pc_increment     = 1'b0;
        ir_load          = 1'b0;
        reg_write_enable = 1'b0;

        unique case (current_state)
            IDLE: begin
                if (start)
                    pc_clear = 1'b1;
            end

            FETCH: begin
                busy    = 1'b1;
                ir_load = 1'b1;
            end

            DECODE: begin
                busy = 1'b1;
            end

            EXECUTE: begin
                busy = 1'b1;
            end

            WRITEBACK: begin
                busy             = 1'b1;
                reg_write_enable = 1'b1;
                pc_increment     = !final_instruction;
            end

            DONE: begin
                done = 1'b1;
            end

            default: begin
            end
        endcase
    end

    assign state = current_state;

endmodule