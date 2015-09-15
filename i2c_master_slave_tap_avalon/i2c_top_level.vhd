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
          
          scl             :   inout std_logic                     :=  'Z';
          sda             :   inout std_logic                     :=  'Z'         
        );
end i2c_avalon;

architecture behv of i2c_avalon is
 
 signal scl1, scl2    :  std_logic                       :=  '0';
 signal sda1, sda2    :  std_logic                       :=  '0';
 signal i2c_clock     :  std_logic_vector  (7 downto 0)  :=   std_logic_vector(to_unsigned(clockRateValue / ( i2cClock * 4), 8));
 signal reg_control   :  std_logic_vector  (7 downto 0)  :=  (others =>  '0');
 signal reg_status    :  std_logic_vector  (7 downto 0)  :=  (others =>  '0');
 signal reg_slave     :  std_logic_vector  (7 downto 0)  :=  (others =>  '0');
 signal reg_wr_size   :  std_logic_vector  (7 downto 0)  :=  (others =>  '0');
 signal reg_rd_size   :  std_logic_vector  (7 downto 0)  :=  (others =>  '0');
 signal shift_reg     :  std_logic_vector  (7 downto 0)  :=  (others =>  '0');
 type   buffer_array  is  array (bufSize downto 0) of std_logic_vector  (7 downto 0);
 signal data_buffer   :  buffer_array;
 signal counter       :  integer                         :=  0;
 signal fifo_index    :  integer  range 0 to  bufSize    :=  0;
 signal fifo_p        :  integer  range 0 to  bufSize    :=  0;
 signal bit_counter   :  integer  range 0 to  7          :=  0;
 
 type master_state_type is (op_halt, op_halt_m, op_start0, op_start1, op_write0, op_write1, op_write2, op_check_ack0, op_check_ack1, op_check_ack2, op_check_ack3,
  op_write3, op_read0, op_read1, op_read2, op_read3, sl_start, sl_ack0, sl_ack1, sl_nack0, sl_nack1, sl_write, sl_read);
 signal i2c_op        :  master_state_type               := op_halt;
  
begin
  process (avs_clock)
    begin
      if  (rising_edge(avs_clock))  then
        if  (i2cSlaveEnable = x"0" and i2c_op = op_halt)  then
          i2c_op  <=  op_halt_m;
        end if;
        scl2  <=  scl1;
        scl1  <=  scl;
        sda2  <=  sda1;
        sda1  <=  sda;
        
--    Avalon bus operations
        if  (avs_reset = '1') then
          avs_read_data <=  (others =>  '0');
          i2c_op        <=  op_halt;
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
              if  ((i2c_op = op_halt or i2c_op = op_halt_m) and scl = '1' and sda = '1')  then
                i2c_op  <=   op_start0;
              end if;
            end if;
          end if;
        end if;
        
      if  (reg_control(0) = '1')  then
--      Master I2C operations
        if  (i2c_op = op_start0)  then
          if (counter = to_integer(unsigned(i2c_clock))) then
            i2c_op  <=  op_start1;
            counter <=  0;
          else
            counter <=  counter + 1;
          end if;
        end if;
        if  (i2c_op = op_start1)  then
          if (counter = to_integer(unsigned(i2c_clock))) then
            counter <=  0;
            i2c_op  <=  op_write0;
            shift_reg  <=  data_buffer(0);
          else
            counter <=  counter + 1;
          end if;
        end if;
        if  (i2c_op = op_write0)  then
          if (counter = to_integer(unsigned(i2c_clock))) then
            counter <=  0;
            i2c_op  <=  op_write1;
          else
            counter <=  counter + 1;
          end if;
        end if;
        if  (i2c_op = op_write1)  then
          if (counter = to_integer(unsigned(i2c_clock))) then
            counter <=  0;
            i2c_op  <=  op_write2;
          else
            counter <=  counter + 1;
          end if;
        end if;
        if  (i2c_op = op_write2)  then
          if (counter = to_integer(unsigned(i2c_clock))) then
            counter <=  0;
            i2c_op  <=  op_write3;
          else
            counter <=  counter + 1;
          end if;
        end if;
        if  (i2c_op = op_write3)  then
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
        end if;
        if  (i2c_op = op_check_ack0)  then
          if (counter = to_integer(unsigned(i2c_clock))) then
            counter <=  0;
            i2c_op  <=  op_check_ack1;
          else
            counter <=  counter + 1;
          end if;
        end if;
        if  (i2c_op = op_check_ack1)  then
          if (counter = to_integer(unsigned(i2c_clock))) then
            counter <=  0;
            i2c_op  <=  op_check_ack2;
            reg_control(3)  <=  not sda;
          else
            counter <=  counter + 1;
          end if;
        end if;
        if  (i2c_op = op_check_ack2)  then
          if (counter = to_integer(unsigned(i2c_clock))) then
            counter <=  0;
            i2c_op  <=  op_check_ack3;
          else
            counter <=  counter + 1;
          end if;
        end if;
        if  (i2c_op = op_check_ack3)  then
          if (counter = to_integer(unsigned(i2c_clock))) then
            counter <=  0;
            if  (reg_control(3) = '1')  then
              if  (fifo_p = fifo_size - 1)  then
                fifo_p          <=  0;
                fifo_size       <=  0;
                bit_counter     <=  0;
                i2c_op          <= op_halt;
                reg_control(1)  <=  '0';
              else
                i2c_op  <=  op_write0;
                fifo_index  <=  fifo_index  + 1;
              end if;
            else
              data_buffer(0)  <=  retry_buffer;
          else
            counter <=  counter + 1;
          end if;
        end if;
        
--  Slave I2C operations
        if  (i2cSlaveEnable = x"8" and scl = '1' and sda = '0' and sda1 = '0' and sda2 = '1')  then
          i2c_op  <=  sl_start;
        end if;
        
        if  (i2c_op = sl_start and scl = '1' and scl1 = '1' and scl2 = '0')  then
          if  (bit_counter = 7) then
            data_buffer(fifo_size)(7 - bit_counter)  <=  sda;
            bit_counter <=  0;
            if  (data_buffer(fifo_size)(7  downto  1) = i2cSlaveAddress)  then
              i2c_op <=  sl_ack0;
            else
              i2c_op <=  sl_nack0;
            end if;
          else
            data_buffer(fifo_size)(7 - bit_counter)  <=  sda;
            bit_counter <=  bit_counter + 1;
          end if;
        end if;
        
        if (scl = '0' and scl1 = '0' and scl2 = '1')  then
          if  (i2c_op = sl_ack0)  then
            i2c_op  <=  sl_ack1;
          elsif (i2c_op = sl_ack1)  then
            fifo_size <=  fifo_size + 1;
            if  (data_buffer(0)(0) = '0') then
              i2c_op  <=  sl_read;
            else
              i2c_op  <=  sl_write;
            end if;
          elsif (i2c_op = sl_nack0) then
            i2c_op <= sl_nack1;
          end if;
        end if;
        
        if  (i2c_op = sl_read and scl = '1' and scl1 = '1' and scl2 = '0')  then
          if  (bit_counter = 7) then
            data_buffer(fifo_size)(7 - bit_counter)  <=  sda;
            bit_counter <=  0;
            i2c_op <=  sl_ack0;
          else
            data_buffer(fifo_size)(7 - bit_counter)  <=  sda;
            bit_counter <=  bit_counter + 1;
          end if;
        end if;
      end if
    end if;
  end process;
    
    with  i2c_op  select  sda <=
                                    '1' when op_halt_m,
                                    '0' when op_start0,
                                    '0' when op_start1,
                                    shift_reg(7)  when  op_write0,
                                    shift_reg(7)  when  op_write1,
                                    shift_reg(7)  when  op_write2,
                                    shift_reg(7)  when  op_write3,
                                    '1' when  op_check_ack3,
                                    '0' when  sl_ack1,
                                    '1' when  sl_nack1,
                                    'Z' when others;
                                    
    with  i2c_op  select  scl <=
                                    '1' when op_halt_m,
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
                                    'Z' when others;
                                     
end behv;