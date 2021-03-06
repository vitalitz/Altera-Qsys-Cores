library ieee ;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.all;

entity i2c_avalon is
  generic (
            clockRateValue          : integer                       :=  100000000;
            i2cClock                : integer                       :=  400000;
            bufSize                 : integer    range 0 to 255     :=  4;
            i2cSlaveEnable          : std_logic_vector (3 downto 0)                     :=  x"0";
            i2cSlaveAddress         : std_logic_vector (6 downto 0) :=  (others =>  '0')
            );
  port  (
          avs_clock       :   in    std_logic                     :=  '0';
          avs_reset       :   in    std_logic                     :=  '0';
          avs_write       :   in    std_logic                     :=  '0';
          avs_read        :   in    std_logic                     :=  '0';
          avs_write_data  :   in    std_logic_vector (7 downto 0) :=  (others =>  '0');
          avs_read_data   :   out   std_logic_vector (7 downto 0) :=  (others =>  '0');
          avs_address     :   in    std_logic_vector (3 downto 0) :=  (others =>  '0');
		  
          scl_en          :   out std_logic       	               :=  '0';
          scl_in          :   in std_logic       	                :=  'Z';
      		  scl_out         :   out std_logic        	              :=  'Z';
	     	  sda_en          :   out std_logic                	      :=  '0'; 
          sda_in          :   in std_logic         		             :=  'Z';    
	     	  sda_out         :   out std_logic             	         :=  'Z'
        );
end i2c_avalon;

architecture behv of i2c_avalon is
 
 signal scl1, scl2    :  std_logic                       :=  '0';
 signal sda1, sda2    :  std_logic                       :=  '0';
 signal i2c_clock     :  std_logic_vector  (7 downto 0)  :=   std_logic_vector(to_unsigned(clockRateValue / ( i2cClock * 4), 8));
 signal reg_control   :  std_logic_vector  (7 downto 0)  :=  x"01";
 signal reg_status    :  std_logic_vector  (7 downto 0)  :=  (others =>  '0');
 signal reg_slave     :  std_logic_vector  (7 downto 0)  :=  (others =>  '0');
 signal reg_wr_size   :  std_logic_vector  (7 downto 0)  :=  (others =>  '0');
 signal reg_rd_size   :  std_logic_vector  (7 downto 0)  :=  (others =>  '0');
 signal shift_reg     :  std_logic_vector  (7 downto 0)  :=  (others =>  '0');
 type   buffer_array  is  array (bufSize downto 0) of std_logic_vector  (7 downto 0);
 signal data_buffer   :  buffer_array;
 signal counter       :  integer  range 0 to  255        :=  0;
 signal fifo_index    :  integer  range 0 to  bufSize    :=  0;
 signal fifo_p        :  integer  range 0 to  bufSize    :=  0;
 signal bit_counter   :  integer  range 0 to  7          :=  0;
 
 type master_state_type is (op_idle, op_start0, op_start1, op_write0, op_write1, op_write2, op_check_ack0, op_check_ack1, op_check_ack2, op_check_ack3,
  op_write3, op_read0, op_read1, op_read2, op_read3, sl_start, sl_ack0, sl_ack1, sl_nack0, sl_nack1, sl_write, sl_read, sl_check_ack);
 signal i2c_op        :  master_state_type               := op_idle;
  
begin
main:  process (avs_clock)
    begin
      if  (rising_edge(avs_clock))  then
        scl2  <=  scl1;
        scl1  <=  scl_in;
        sda2  <=  sda1;
        sda1  <=  sda_in;
        
        if  (avs_reset = '1') then
          avs_read_data <=  (others =>  '0');
          i2c_op        <=  op_idle;
        else
          if  (avs_write = '1') then
            case  avs_address is
              when  x"0"    =>  reg_control    <=  avs_write_data;
              when  x"1"    =>  reg_status     <=  avs_write_data;
              when  x"2"    =>  reg_wr_size    <=  avs_write_data;
              when  x"3"    =>  reg_rd_size    <=  avs_write_data;
              when  x"4"    =>  data_buffer(fifo_p)  <=  avs_write_data;
                                fifo_p <=  fifo_p + 1;
              when  others  =>  reg_status    <=  reg_status;
            end case;
          elsif (avs_read = '1') then
            case  avs_address is
              when  x"0"    =>  avs_read_data <=  reg_control;
              when  x"1"    =>  avs_read_data <=  reg_status;
              when  x"2"    =>  avs_read_data <=  reg_wr_size;
              when  x"3"    =>  avs_read_data <=  reg_rd_size;
              when  x"4"    =>  avs_read_data <=  data_buffer(fifo_p);
                                if  (fifo_p = 0)  then
                                  fifo_p  <=  fifo_p;
                                else
                                  fifo_p  <=  fifo_p - 1;
                                end  if;
              when  others  =>  reg_status    <=  reg_status;
            end case;
          end if;
          if  (reg_control(0) = '1')  then
            if  (reg_control(1) = '1')  then
              if  (reg_wr_size = x"00" and reg_rd_size = x"00")  then
                reg_control(1)  <=  '0';
              else
                if  (i2c_op = op_idle and scl_in = '1' and sda_in = '1')  then
                  i2c_op  <=   op_start0;
               end if;
             end if;
            end if;
          end if;
        end if;
        
      if  (reg_control(0) = '1')  then
        case  i2c_op  is
          when  op_idle       =>
                                  if  (scl_in = '1' and sda_in = '0' and sda1 = '0' and sda2 = '1')  then
                                    i2c_op  <=  sl_start;
                                  end if;
          when  op_start0     =>
                                  if (counter = to_integer(unsigned(i2c_clock))) then
                                    i2c_op  <=  op_start1;
                                    fifo_index  <=  0;
                                    counter <=  0;
                                  else
                                    counter <=  counter + 1;
                                  end if;
          when  op_start1     =>
                                  if (counter = to_integer(unsigned(i2c_clock))) then
                                    counter <=  0;
                                    i2c_op  <=  op_write0;
                                    shift_reg  <=  data_buffer(fifo_index);
                                  else
                                    counter <=  counter + 1;
                                  end if;
          when  op_write0     =>
                                  if (counter = to_integer(unsigned(i2c_clock))) then
                                    counter <=  0;
                                    i2c_op  <=  op_write1;
                                  else
                                    counter <=  counter + 1;
                                  end if;     
          when  op_write1     =>
                                  if  (scl_in = '1')  then
                                    if (counter = to_integer(unsigned(i2c_clock))) then
                                      counter <=  0;
                                      i2c_op  <=  op_write2;
                                    else
                                      counter <=  counter + 1;
                                    end if;
                                  end if;
          when  op_write2     =>
                                  if (counter = to_integer(unsigned(i2c_clock))) then
                                    counter <=  0;
                                    i2c_op  <=  op_write3;
                                  else
                                    counter <=  counter + 1;
                                  end if;
          when  op_write3     =>
                                  if (counter = to_integer(unsigned(i2c_clock))) then
                                    counter <=  0;
                                    if  (bit_counter = 7) then
                                        i2c_op      <=  op_check_ack0;
                                        bit_counter <=  0;
                                    else
                                      shift_reg  <=  shift_reg(6  downto  0)  & '0';
                                      bit_counter <=  bit_counter + 1;
                                      i2c_op      <=  op_write0;
                                    end if;
                                  else
                                    counter <=  counter + 1;
                                  end if;
          when  op_check_ack0 =>
                                  if (counter = to_integer(unsigned(i2c_clock))) then
                                    counter <=  0;
                                    i2c_op  <=  op_check_ack1;
                                  else
                                    counter <=  counter + 1;
                                  end if;
          when  op_check_ack1 =>
                                  if (counter = to_integer(unsigned(i2c_clock))) then
                                    counter <=  0;
                                    i2c_op  <=  op_check_ack2;
                                    reg_control(3)  <=  not sda_in;
                                  else
                                    counter <=  counter + 1;
                                  end if;
          when  op_check_ack2 =>
                                  if (counter = to_integer(unsigned(i2c_clock))) then
                                    counter <=  0;
                                    i2c_op  <=  op_check_ack3;
                                  else
                                    counter <=  counter + 1;
                                  end if;
          when  op_check_ack3 =>
                                  if (counter = to_integer(unsigned(i2c_clock))) then
                                    counter <=  0;
                                    if  (reg_control(3) = '1')  then
                                      if  (fifo_index = to_integer(unsigned(reg_wr_size)))  then
                                        fifo_index          <=  0;
                                        bit_counter     <=  0;
                                        i2c_op          <= op_idle;
                                        reg_control(1)  <=  '0';
                                      else
                                        i2c_op  <=  op_write0;
                                        fifo_index  <=  fifo_index  + 1;
                                        shift_reg <=  data_buffer(fifo_index  + 1);
                                      end if;
                                    else
                                      i2c_op  <= op_start0;
                                    end if;
                                  else
                                    counter <=  counter + 1;
                                  end if;
          when  sl_start       =>
                                  if  (scl_in = '1' and scl1 = '1' and scl2 = '0')  then
                                    if  (bit_counter = 7) then
                                      shift_reg  <=  shift_reg(6  downto  0)  & sda_in;
                                      bit_counter <=  0;
                                      if  (shift_reg(6  downto  0) = i2cSlaveAddress)  then
                                        i2c_op <=  sl_ack0;
                                      else
                                        i2c_op <=  sl_nack0;
                                      end if;
                                    else
                                      shift_reg  <=  shift_reg(6  downto  0)  & sda_in;
                                      bit_counter <=  bit_counter + 1;
                                    end if;
                                  end if;
          when  sl_ack0        =>
                                  if (scl_in = '0' and scl1 = '0' and scl2 = '1')  then
                                    i2c_op  <=  sl_ack1;
                                    data_buffer(fifo_p) <=  shift_reg;
                                  end if;
          when  sl_ack1        =>
                                  if (scl_in = '0' and scl1 = '0' and scl2 = '1')  then
                                    fifo_p <=  fifo_p + 1;
                                    if  (data_buffer(0)(0) = '0') then
                                      i2c_op  <=  sl_read;
                                    else
                                      i2c_op  <=  sl_write;
                                    end if;
                                  end if;
          when  sl_nack0       =>
                                  if (scl_in = '0' and scl1 = '0' and scl2 = '1')  then
                                    i2c_op <= sl_nack1;
                                  end if;
          when  sl_read        =>
                                  if  (scl_in = '1' and scl1 = '1' and scl2 = '0')  then
                                    if  (bit_counter = 7) then
                                      shift_reg  <=  shift_reg(6  downto  0)  & sda_in;
                                      bit_counter <=  0;
                                      i2c_op <=  sl_ack0;
                                    else
                                      shift_reg  <=  shift_reg(6  downto  0)  & sda_in;
                                      bit_counter <=  bit_counter + 1;
                                    end if;
                                  end if;
          when  sl_write       =>
                                  if  (scl_in = '1' and scl1 = '1' and scl2 = '0')  then
                                    if  (bit_counter = 7) then
                                      shift_reg  <=  shift_reg(6  downto  0)  & '0';
                                      bit_counter <=  0;
                                      i2c_op <=  sl_check_ack;
                                    else
                                      shift_reg  <=  shift_reg(6  downto  0)  & '0';
                                      bit_counter <=  bit_counter + 1;
                                    end if;
                                  end if;
          when  sl_check_ack   =>
                                  if  (scl_in = '1' and scl1 = '1' and scl2 = '0')  then
                                    if  (sda_in = '0') then
                                      shift_reg  <=  shift_reg(6  downto  0)  & '0';
                                      bit_counter <=  0;
                                      i2c_op <=  sl_check_ack0;
                                    else
                                      shift_reg  <=  shift_reg(6  downto  0)  & '0';
                                      bit_counter <=  bit_counter + 1;
                                    end if;
                                  end if;
          when  others         => i2c_op  <=  op_idle;
        end case;        
        
        if  (i2c_op /= op_check_ack3 and scl_in = '1' and sda_in = '1' and sda1 = '1' and sda2 = '0')  then
          i2c_op  <=  op_idle;
        end if;

      end if;
    end if;
  end process;
    
    with  i2c_op  select  sda_out <=
										'0' when op_start0,
										'0' when op_start1,
										shift_reg(7)  when  op_write0,
										shift_reg(7)  when  op_write1,
										shift_reg(7)  when  op_write2,
										shift_reg(7)  when  op_write3,
										'1' when  op_check_ack3,
										'0' when  sl_ack1,
										'1' when  sl_nack1,
										'1' when others;
                                    
    with  i2c_op  select  scl_out <=
										'1' when op_start0,
										'0' when op_start1,
										'0' when op_write0,
										'1' when op_write1,
										'1' when op_write2,
										'0' when op_write3,
										'0' when  op_check_ack0,
										'1' when  op_check_ack1,
										'1' when  op_check_ack2,
										'0' when  op_check_ack3,
										'1' when others;
                                     
end behv;