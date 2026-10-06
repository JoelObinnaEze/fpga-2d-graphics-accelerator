package command_pkg;
    typedef enum logic [7:0] {
        OP_CLEAR       = 8'h01,
        OP_DRAW_RECT   = 8'h02,
        OP_DRAW_SPRITE = 8'h03,
        OP_PRESENT     = 8'h04
    } opcode_t;

    typedef struct packed {
        opcode_t opcode;
        logic [7:0] sequence_id;
        logic [15:0] arg0;
        logic [15:0] arg1;
        logic [15:0] arg2;
        logic [15:0] arg3;
        logic [15:0] arg4;
    } command_t;
endpackage
