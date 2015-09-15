module clk_gen(clk);
  output clk;
  bit clk;
  
  always
    begin
      #5 clk = !clk;
    end
    
endmodule
