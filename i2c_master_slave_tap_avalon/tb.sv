module tb;
  
  reg [7:0] avs_write_data;
  reg [7:0] avs_read_data;
  reg [3:0] avs_address;
  bit       avs_write;
  bit       clk;
  int fsm = 0;
  
  clk_gen clk_g(clk);
  i2c_avalon i2c_master(.avs_clock(clk), .avs_reset(1'b0), .avs_write(avs_write),
   .avs_read(1'b0), .avs_write_data(avs_write_data), .avs_read_data(avs_read_data),
    .avs_address(avs_address), .scl_in(scl_in), .scl_out(scl_out), .sda_in(sda_in), .sda_out(sda_out));
  
  i2c_avalon  #(.i2cSlaveAddress(7'b1001001), .i2cSlaveEnable(8)) i2c_slave(.avs_clock(clk), .scl_in(scl_out), .scl_out(scl_in), .sda_in(sda_out), .sda_out(sda_in));
  
  always @(posedge clk)
    begin
      case  (fsm)
        0   : begin
                avs_address = 2;
                avs_write = 1;
                avs_write_data  = 8'h02;
                fsm++;
              end
        1   : begin
                avs_address = 4;
                avs_write = 1;
                avs_write_data  = 8'b10010010;
                fsm++;
              end
        2   : begin
                avs_address = 4;
                avs_write = 1;
                avs_write_data  = 8'h55;
                fsm++;
              end
        3   : begin
                avs_address = 4;
                avs_write = 1;
                avs_write_data  = 8'h77;
                fsm++;
              end
        4   : begin
                avs_address = 0;
                avs_write = 1;
                avs_write_data  = 8'h03;
                fsm++;
              end 
        5   : begin
                avs_address = 0;
                avs_write = 0;
                avs_write_data  = 0;
                fsm++;
              end
        6   : begin
                avs_address = 0;
                avs_write = 0;
                avs_write_data  = 0;
                fsm++;
              end
        7   : begin
                avs_address = 0;
                avs_write = 0;
                avs_write_data  = 0;
                fsm++;
              end
      endcase
    end
endmodule