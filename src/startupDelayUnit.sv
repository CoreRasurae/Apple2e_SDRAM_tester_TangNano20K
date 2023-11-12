// SPDX-License-Identifier: BSD-3-Clause
/*
 * Startup-delay for the SDRAM Power-Up time
 *
 * Copyright (C) 2023 Luís Mendes <luis.p.mendes@gmail.com>
 */
module startupDelayUnit #(parameter CLK = 111857000.0)
(start, clk14M, sdram_init_n, sdram_ready);

input start;
input clk14M;
output sdram_init_n;
output sdram_ready;

logic init_n = 1'b1;
logic ready = 1'b0;
logic started = 1'b1;

localparam integer unsigned CYCLES_200MS = $ceil(0.201 * CLK);
localparam integer unsigned CYCLES_25MS = $ceil(0.025 * CLK);
localparam integer unsigned CYCLES_DELAY = 10'h03F;
localparam BITS_200MS = $clog2(CYCLES_200MS);
localparam COUNTER_ZERO_200MS  = {BITS_200MS{1'b0}};

logic [BITS_200MS-1:0] counter = COUNTER_ZERO_200MS;

always @(posedge clk14M)
begin
if (start) begin
   if (started) begin
      init_n = 1'b0;      
      if (counter < CYCLES_200MS)
         counter = counter + 1'b1;
      else
      begin 
         init_n = 1'b1;        
         started = 1'b0;  
         counter = COUNTER_ZERO_200MS;
      end
   end
   else begin      
      if (counter < CYCLES_DELAY)
         counter = counter + 1'b1;
      else begin
         counter = CYCLES_DELAY;
         ready = 1'b1;
      end
   end
end else begin
   started = 1'b1;
   ready = 1'b0;
   init_n = 1'b1;
end
end

assign sdram_init_n = init_n;
assign sdram_ready = ready;
endmodule