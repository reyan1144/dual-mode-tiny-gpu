module multicore_controller #(
    parameter int NUM_CORES = 4
)(
    input  logic                 clk,
    input  logic                 reset,

    input  logic                 start,

    input  logic [NUM_CORES-1:0] core_busy,
    input  logic [NUM_CORES-1:0] core_done,

    output logic [NUM_CORES-1:0] core_start,

    output logic                 busy,
    output logic                 done
);

    logic [NUM_CORES-1:0] core_active;

    logic [$clog2(NUM_CORES)-1:0] next_core;

    integer offset;
    integer candidate;

    always_ff @(posedge clk or posedge reset) begin

        if (reset) begin

            core_active <= '0;
            core_start  <= '0;
            next_core   <= '0;
            done        <= 1'b0;

        end
        else begin

            // Default pulse signals
            core_start <= '0;
            done       <= 1'b0;

            // Release completed cores
            for (int i = 0; i < NUM_CORES; i++) begin

                if (core_done[i]) begin
                    core_active[i] <= 1'b0;
                end

            end

            // Completion pulse
            if (|core_done) begin
                done <= 1'b1;
            end

            // Allocate new work
            if (start) begin

                for (offset = 0; offset < NUM_CORES; offset++) begin

                    candidate = next_core + offset;

                    if (candidate >= NUM_CORES) begin
                        candidate = candidate - NUM_CORES;
                    end

                    if (!core_active[candidate] &&
                        !core_busy[candidate]) begin

                        core_start[candidate]  <= 1'b1;
                        core_active[candidate] <= 1'b1;

                        if (candidate == NUM_CORES-1) begin
                            next_core <= '0;
                        end
                        else begin
                            next_core <= candidate + 1;
                        end

                        break;

                    end

                end

            end

        end

    end

    // Busy whenever at least one core is active
    always_comb begin
        busy = |core_active;
    end

endmodule