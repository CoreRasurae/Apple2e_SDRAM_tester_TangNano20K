// SPDX-License-Identifier: BSD-3-Clause
/*
 * Startup-delay for the SDRAM Power-Up time
 *
 * Copyright (C) 2023 Luís Mendes <luis.p.mendes@gmail.com>
 */
module startupDelayUnit #(parameter CLK = 111857000.0)
(start, clk112M, sdram_init_n, sdram_ready);

input start;
input clk112M;
output sdram_init_n;
output sdram_ready;

logic init_n = 1'b1;
logic ready = 1'b0;

localparam integer unsigned CYCLES_200MS = $ceil(0.201 * CLK);
localparam integer unsigned CYCLES_25MS = $ceil(0.025 * CLK);
localparam BITS_200MS = $clog2(CYCLES_200MS);
localparam COUNTER_ZERO_200MS  = {BITS_200MS{1'b0}};

logic [BITS_200MS-1:0] counter = COUNTER_ZERO_200MS;

always @(posedge clk112M)
begin
if (start) begin
   if (init_n == 1'b1)
      if (counter < CYCLES_200MS)
         counter = counter + 1'b1;
      else
      begin
         init_n = 1'b0;
         counter = COUNTER_ZERO_200MS;
      end
   else
      if (counter < CYCLES_25MS)
         counter = counter + 1'b1;
      else
         ready = 1'b1;
end else begin
   ready = 1'b0;
   init_n = 1'b1;
end
end

assign sdram_init_n = init_n;
assign sdram_ready = ready;
endmodule