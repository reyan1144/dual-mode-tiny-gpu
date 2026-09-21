module command_decoder #(
    parameter CMD_WIDTH    = 128,
    parameter OPCODE_WIDTH = 8,
    parameter XY_WIDTH     = 6,
    parameter COLOR_WIDTH  = 8,
    parameter Z_WIDTH      = 16
)(
    input  logic [CMD_WIDTH-1:0]    cmd_packet,

    output logic [OPCODE_WIDTH-1:0] opcode,

    output logic                    nop_cmd,
    output logic                    line_cmd,
    output logic                    triangle_cmd,
    output logic                    clear_cmd,

    output logic [XY_WIDTH-1:0]     x0,
    output logic [XY_WIDTH-1:0]     y0,
    output logic [XY_WIDTH-1:0]     x1,
    output logic [XY_WIDTH-1:0]     y1,
    output logic [XY_WIDTH-1:0]     x2,
    output logic [XY_WIDTH-1:0]     y2,

    output logic [COLOR_WIDTH-1:0]  color,

    // Depth outputs
    output logic [Z_WIDTH-1:0]      z0,
    output logic [Z_WIDTH-1:0]      z1,
    output logic [Z_WIDTH-1:0]      z2
);

    localparam logic [OPCODE_WIDTH-1:0] NOP               = 8'h00;
    localparam logic [OPCODE_WIDTH-1:0] DRAW_LINE         = 8'h01;
    localparam logic [OPCODE_WIDTH-1:0] DRAW_TRIANGLE     = 8'h02;
    localparam logic [OPCODE_WIDTH-1:0] CLEAR_FRAMEBUFFER = 8'h03;

    always_comb begin
        nop_cmd        = 1'b0;
        line_cmd       = 1'b0;
        triangle_cmd   = 1'b0;
        clear_cmd      = 1'b0;

        opcode = cmd_packet[127:120];

        x0 = cmd_packet[119:114];
        y0 = cmd_packet[113:108];

        x1 = cmd_packet[107:102];
        y1 = cmd_packet[101:96];

        x2 = cmd_packet[95:90];
        y2 = cmd_packet[89:84];

        color = cmd_packet[83:76];

        // Bits [27:0] are reserved for future use
        z0 = cmd_packet[75:60];
        z1 = cmd_packet[59:44];
        z2 = cmd_packet[43:28];

        case (opcode)
            NOP:               nop_cmd      = 1'b1;
            DRAW_LINE:         line_cmd     = 1'b1;
            DRAW_TRIANGLE:     triangle_cmd = 1'b1;
            CLEAR_FRAMEBUFFER: clear_cmd    = 1'b1;
            default: ;
        endcase
    end

endmodule