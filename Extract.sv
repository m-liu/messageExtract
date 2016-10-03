`timescale 1ns/1ps


typedef enum {
    IDLE,
    MSG_PROC,
    MSG_END,
    MSG_LEN
} ExtractState;

module Extract #(
    parameter IN_WIDTH = 64,
    parameter IN_EMPTY_WIDTH = $clog2(IN_WIDTH / 8),
    parameter OUT_WIDTH = 256,
    parameter OUT_MASK_WIDTH = OUT_WIDTH / 8
)
(

    input clk,
    input reset_n,

    //IN interface (INPUT)
    input in_error, //Always 0 
    input in_valid,
    input in_startofpacket,
    input in_endofpacket,
    input [IN_WIDTH-1:0] in_data,
    input [IN_EMPTY_WIDTH-1:0] in_empty,
    output logic in_ready,

    //Message output interface
    output logic out_valid,
    output logic [OUT_WIDTH-1:0] out_data,
    output logic [OUT_MASK_WIDTH-1:0] out_bytemask


);

    localparam BYTE_WIDTH = 8; 
    localparam IN_BYTES = IN_WIDTH / BYTE_WIDTH;
    localparam OUT_BYTES = OUT_WIDTH / BYTE_WIDTH;


    ExtractState state;
    ExtractState next_state;
    logic [BYTE_WIDTH-1:0] in_data_bytes [IN_BYTES-1:0];
    //Two sets of data buffers: current and next message
    logic [BYTE_WIDTH-1:0] outDataReg [1:0][OUT_BYTES-1:0]; 

    logic [BYTE_WIDTH-1:0] msg_cnt;
    logic [BYTE_WIDTH-1:0] next_msg_cnt;
    logic [$clog2(OUT_BYTES):0] msg_shift;
    logic [$clog2(OUT_BYTES):0] next_msg_shift;
    logic [BYTE_WIDTH-1:0] msg_rem; 
    logic [BYTE_WIDTH-1:0] next_msg_rem; 
    logic out_reg_sel; 
    logic next_out_reg_sel; 
    logic write_both_regs;
    logic [$clog2(OUT_BYTES):0] shift[1:0];
    logic next_out_valid; 
    logic test;


    //convert input to bytes
    genvar i;
    generate
        for (i = 0; i < IN_BYTES; i++) begin: MakeOutWords
            assign in_data_bytes[i] = in_data[BYTE_WIDTH*i +: BYTE_WIDTH];
        end
    endgenerate
        

    integer j;
    always @ (posedge clk) begin
        if (in_valid) begin
            test <= 1;
        end 
        else begin
            test <= 0;
        end
        if (in_valid) begin

            if (out_reg_sel==0 || write_both_regs) begin
                //TODO: this is kind of ugly
                if (out_reg_sel == 1 && write_both_regs) begin
                    shift[0] = 8;
                end
                else begin
                    shift[0] = msg_shift;
                end

                for (j=0; j<OUT_BYTES; j++) begin
                    if (j < shift[0]) begin
                        outDataReg[0][j] <= in_data_bytes[IN_BYTES - shift[0] + j];
                    end
                    else begin
                        outDataReg[0][j] <= outDataReg[0][j-shift[0]];
                    end
                end
            end

            if (out_reg_sel==1 || write_both_regs) begin
                //TODO: this is kind of ugly
                if (out_reg_sel == 0 && write_both_regs) begin
                    shift[1] = 8;
                end
                else begin
                    shift[1] = msg_shift;
                end

                for (j=0; j<OUT_BYTES; j++) begin
                    if (j < shift[1]) begin
                        outDataReg[1][j] <= in_data_bytes[IN_BYTES - shift[1] + j];
                    end
                    else begin
                        outDataReg[1][j] <= outDataReg[1][j-shift[1]];
                    end
                end
            end

        end
    end

            //EXAMPLE: shift=4
            //outDataReg[3:0] <= in_data_bytes[7 : 7-3]
            //outDataReg[31:4] <= outDataReg[31-3:0] 
            //if (state == IDLE) begin 
            //outDataReg[0][msg_offset-1 -: msg_burst_len] <= 



    
    
    //Mealy next state
    always @ (*) begin
        //default values
        next_state = state;
        next_msg_cnt = msg_cnt;
        next_msg_rem = msg_rem;
        next_msg_shift = msg_shift;
        next_out_reg_sel = out_reg_sel; 
        write_both_regs = 0;
        next_out_valid = 0;
        
        case (state)
            IDLE: begin
                if (in_valid && in_startofpacket) begin
                    //Top 2 bytes are message count, always < 256, we can just use the lower byte
                    next_msg_cnt = in_data_bytes[6] - 1; //msg count - current msg
                    next_msg_rem = in_data_bytes[4] - 4; //length - 4 bytes we took

                    if (next_msg_rem > 8) begin
                        next_msg_shift = 8;
                        next_state = MSG_PROC;
                    end
                    else begin
                        next_msg_shift = next_msg_rem;
                        next_state = MSG_END;
                    end
                end
            end

            MSG_PROC: begin
                if (in_valid) begin
                    next_msg_rem = msg_rem - 8;
                    if (next_msg_rem > 8) begin
                        next_msg_shift = 8;
                        next_state = MSG_PROC;
                    end
                    else begin
                        next_msg_shift = next_msg_rem;
                        next_state = MSG_END;
                    end
                end
            end

            MSG_END: begin
                if (in_valid) begin
                    next_msg_cnt = msg_cnt - 1;
                    next_out_reg_sel = ~ out_reg_sel; //switch output reg 
                    next_out_valid = 1;
                    if (msg_cnt == 0) begin //finished packet
                        next_state = IDLE;
                        next_msg_shift = 8; //TODO FIXME
                        next_msg_rem = 0;
                    end
                    //special case for msg_rem == 8 and msg_rem==7
                    else if (msg_rem == 8 || msg_rem == 7) begin
                        //more packets, but don't have next length, go to MSG_LEN
                        //keep msg_rem as the same value to indicate where we should offset
                        next_state = MSG_LEN;
                    end
                    else begin
                        next_msg_rem = in_data_bytes[6 - msg_rem];
                        if (msg_rem < 5) begin
                            write_both_regs = 1;
                            //we took some bytes for the next msg
                            next_msg_rem = next_msg_rem - (8 - 2 - msg_rem);
                        end

                        if (next_msg_rem > 8) begin
                            next_msg_shift = 8;
                            next_state = MSG_PROC;
                        end
                        else begin
                            next_msg_shift = next_msg_rem;
                            next_state = MSG_END;
                        end
                    end
                end
            end

            MSG_LEN: begin
                if (in_valid) begin
                    if (msg_rem==7) begin
                        next_msg_rem = in_data_bytes[7];
                        next_msg_rem = next_msg_rem - 7; //take the rest of the 7 bytes
                    end
                    else begin
                        next_msg_rem = in_data_bytes[6];
                        next_msg_rem = next_msg_rem - 6; //take the rest of the 6 bytes
                    end

                    if (next_msg_rem > 8) begin
                        next_msg_shift = 8;
                        next_state = MSG_PROC;
                    end
                    else begin
                        next_msg_shift = next_msg_rem;
                        next_state = MSG_END;
                    end
                end
            end
        endcase

    end

    always @ (posedge clk) begin
        if (!reset_n) begin
            state <= IDLE;
            msg_cnt <= 0;
            msg_rem <= 0;
            msg_shift <= 8; //TODO FIXME: use a new state?
            out_reg_sel <= 0;
            out_valid <= 0;
        end
        else begin
            state <= next_state;
            msg_cnt <= next_msg_cnt;
            msg_rem <= next_msg_rem; //how many bytes are remaining in the message
            msg_shift <= next_msg_shift;
            out_reg_sel <= next_out_reg_sel;
            out_valid <= next_out_valid;
        end
    end

    generate
        for (i = 0; i < OUT_BYTES; i++) begin: MakeWords
            assign out_data[BYTE_WIDTH*i +: BYTE_WIDTH] = out_reg_sel ? outDataReg[0][i] : outDataReg[1][i];
        end
    endgenerate
    //assign out_data = out_reg_sel ? outDataReg[0] : outDataReg[1];
    
    //This module is always ready
    assign in_ready = 1'b1;

endmodule
    



    /*

    always @ (posedge clk) begin
        if (!reset_n) begin
        end
        else begin
            if (in_valid) begin
                if (in_startofpacket && state == IDLE) begin
                    msg_cnt_remaining <= in_data[IN_DATA_WIDTH-1 -: 16] - 1; //Take top 2 bytes 
                    msg_next_offset <= in_data[IN_DATA_WIDTH-1-16 -: 16 ] - 4; //Take next 2 bytes, subtract by 4 for the 4 input bytes we have in this payload
                    outDataReg[ in_data[3:0] -: 4*8 ][reg_sel] <= in_data[IN_DATA_WIDTH-1-32 : 0]; //take next 4 bytes as output. Careful of offset in outDataReg
                    state <= MSG_BEGIN;
                end
                else if (state==MSG_BEGIN) begin
                    if (msg_next_offset < 8 ) begin //last IN payload
                        outDataReg[][] <= in_data[]; 
                        //set the next offset if we can
                        if (msg_next_offset > ?) begin
                            
                        end
                        //set the next message output reg if we can

                    end
                    else begin
                        outDataReg[][] <= in_data[]; 
                        msg_next_offset <= msg_next_offset - 8;
                    end
                end

            end
        end
    end





    function [BYTE_WIDTH-1][OUT_BYTES-1:0] shiftAndLoad(
        input [BYTE_WIDTH-1:0] dataReg [OUT_BYTES-1:0],
        input [BYTE_WIDTH-1:0] in_bytes [IN_BYTES-1:0],
        input [$clog2(OUT_BYTES)-1:0] shift 
    );

        if (shift > 0) begin
            dataReg[shift-1:0] = in_bytes[IN_BYTES-1 -: shift];
            dataReg[OUT_BYTES-1:shift] = dataReg[

    endfunction



                //    outDataReg[0][msg_shift-1:0] <= in_data_bytes[IN_BYTES-1 -: msg_shift];
                //    outDataReg[0][OUT_BYTES-1:msg_shift] <= dataReg[0 +: OUT_BYTES-msg_shift];
                //end
                //else begin
                //end
            case (msg_shift)
                1: begin
                    outDataReg[0][0:0] <= in_data_bytes[IN_BYTES-1 -: 1];
                    outDataReg[0][OUT_BYTES-1 : 1] <= outDataReg[0 +: OUT_BYTES-1];
                end
                default begin
                    outDataReg[0] <= outDataReg[0];
                end

            if (msg_shift > 0) begin

                outDataReg[0][msg_shift-1:0] <= in_data_bytes[IN_BYTES-1 -: msg_shift];
                outDataReg[0][OUT_BYTES-1:msg_shift] <= dataReg[0 +: OUT_BYTES-msg_shift];
            end
                
            endcase



    */
