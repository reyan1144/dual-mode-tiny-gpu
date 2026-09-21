module command_fifo #(
    parameter DATA_WIDTH  = 128,
    parameter DEPTH       = 8,
    parameter ADDR_WIDTH  = $clog2(DEPTH),
    parameter COUNT_WIDTH = $clog2(DEPTH+1)
)(
    // Global Signals
    input  logic                    clk,
    input  logic                    rst,

    // Write Interface
    input  logic                    write_en,
    input  logic [DATA_WIDTH-1:0]   write_data,

    // Read Interface
    input  logic                    read_en,
    output logic [DATA_WIDTH-1:0]   read_data,

    // Status Signals
    output logic                    full,
    output logic                    empty,
    output logic                    overflow_error,
    output logic                    underflow_error,
    output logic [COUNT_WIDTH-1:0]  count
);

logic [DATA_WIDTH-1:0] fifo_mem [0:DEPTH-1];

logic [ADDR_WIDTH-1:0] wr_ptr;
logic [ADDR_WIDTH-1:0] rd_ptr;

assign full  = (count == COUNT_WIDTH'(DEPTH));
assign empty = (count == '0);

always_ff @(posedge clk) begin
    if (rst) begin
        wr_ptr <= '0;
        rd_ptr <= '0;
        count  <= '0;

        read_data <= '0;

        overflow_error  <= 1'b0;
        underflow_error <= 1'b0;
    end
    else begin
        overflow_error  <= 1'b0;
        underflow_error <= 1'b0;

        case ({write_en, read_en})

            2'b00: begin
            end

            2'b01: begin
                if (!empty) begin
                    read_data <= fifo_mem[rd_ptr];

                    if (rd_ptr == DEPTH-1)
                        rd_ptr <= '0;
                    else
                        rd_ptr <= rd_ptr + 1;

                    count <= count - 1;
                end
                else begin
                    underflow_error <= 1'b1;
                end
            end

            2'b10: begin
                if (!full) begin
                    fifo_mem[wr_ptr] <= write_data;

                    if (wr_ptr == DEPTH-1)
                        wr_ptr <= '0;
                    else
                        wr_ptr <= wr_ptr + 1;

                    count <= count + 1;
                end
                else begin
                    overflow_error <= 1'b1;
                end
            end

            2'b11: begin
                if (empty) begin
                    fifo_mem[wr_ptr] <= write_data;

                    if (wr_ptr == DEPTH-1)
                        wr_ptr <= '0;
                    else
                        wr_ptr <= wr_ptr + 1;

                    count <= count + 1;

                    underflow_error <= 1'b1;
                end
                else begin
                    read_data <= fifo_mem[rd_ptr];

                    if (rd_ptr == DEPTH-1)
                        rd_ptr <= '0;
                    else
                        rd_ptr <= rd_ptr + 1;

                    fifo_mem[wr_ptr] <= write_data;

                    if (wr_ptr == DEPTH-1)
                        wr_ptr <= '0;
                    else
                        wr_ptr <= wr_ptr + 1;
                end
            end

            default: begin
            end

        endcase
    end
end
endmodule
