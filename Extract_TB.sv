`timescale 1ns/1ps


module Extract_TB();

    localparam CLOCK_PERIOD = 10.0;
    localparam IN_WIDTH = 64;
    localparam IN_EMPTY_WIDTH = $clog2(IN_WIDTH / 8);
    localparam OUT_WIDTH = 256;
    localparam OUT_MASK_WIDTH = OUT_WIDTH / 8;
    localparam BYTE_WIDTH = 8; 
    localparam IN_BYTES = IN_WIDTH / BYTE_WIDTH;
    localparam OUT_BYTES = OUT_WIDTH / BYTE_WIDTH;
    localparam MAX_PACKET_BURSTS = 1500 / IN_BYTES + 1;

    logic clk;
    logic reset_n;

    logic in_valid;
    logic in_startofpacket;
    logic in_endofpacket;
    logic [IN_WIDTH-1:0] in_data;
    logic [IN_EMPTY_WIDTH-1:0] in_empty;
    logic in_ready;

    logic out_valid;
    logic [OUT_WIDTH-1:0] out_data;
    logic [OUT_MASK_WIDTH-1:0] out_bytemask;

    //DUT instantiation
    Extract # (
        .IN_WIDTH(IN_WIDTH),
        .OUT_WIDTH(OUT_WIDTH)
    ) u_test (
        .clk(clk),
        .reset_n(reset_n),
        .in_error(1'b0),
        .in_valid(in_valid),
        .in_startofpacket(in_startofpacket),
        .in_endofpacket(in_endofpacket),
        .in_data(in_data),
        .in_empty(in_empty),
        .in_ready(in_ready),

        .out_valid(out_valid),
        .out_data(out_data),
        .out_bytemask(out_bytemask)
    );


    initial begin
      clk = 0;
      forever #(CLOCK_PERIOD/2) clk <= ~clk;
    end

    //Reset
    task automatic reset();
        reset_n = 0;
        in_valid = 0;
        in_startofpacket = 0;
        in_endofpacket = 0;
        in_data = 0;
        in_empty = 0;
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        reset_n = 1;
    endtask

    logic [IN_WIDTH-1:0] in_data_arr [MAX_PACKET_BURSTS-1:0];
    int num_bursts;
    logic [IN_EMPTY_WIDTH-1:0] in_data_arr_empty; //empty signal for last burst
    logic [BYTE_WIDTH-1:0] in_byte;
    task automatic read_input_file();
        int fid, ret, i, j;
        fid = $fopen("C:/Users/Ming/Documents/messageExtract/input.txt", "r");
        if (!fid) begin
            $error($time, " [**ERROR] Input file not found");
            $finish(1);
        end

        i = IN_BYTES-1;
        j = 0;
        while (!$feof(fid)) begin
            ret = $fscanf(fid, "%h", in_byte);
            $display("read byte=%h, ret=%d", in_byte, ret);
            //Fill from MSB to LSB
            in_data_arr[j][i*BYTE_WIDTH +: BYTE_WIDTH] = in_byte;
            if (i==0) begin
                i = IN_BYTES-1;
                j++;
            end
            else begin
                i--;
            end
        end
        in_data_arr_empty = i+1;
        num_bursts = (in_data_arr_empty==IN_BYTES) ? j : j+1;

        $fclose(fid);
    endtask

    task automatic send_stream();
        int i = 0;
        //Note: DUT is always ready
        for (i = 0; i < num_bursts; i++) begin
            @(posedge clk);
            in_valid = 1;
            in_startofpacket = (i==0);
            in_endofpacket = (i==num_bursts-1);
            in_data = in_data_arr[i];
            in_empty = (i==num_bursts-1) ? in_data_arr_empty : 0;
            $display($time, " sent burst=%h", in_data);
        end

        @(posedge clk);
        #1 //FIXME: should use clocking block??
        in_valid = 0;
        in_startofpacket = 0;
        in_endofpacket = 0;
        in_data = 0;
        in_empty = 0;
    endtask

    //TODO: add check

    

    //Run TB
    initial begin
        reset();
        read_input_file();
        send_stream();
    end



endmodule



