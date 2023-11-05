// SPDX-License-Identifier: BSD-3-Clause
/*
 * Dumb Write-Reader controller to test the Apple2E SDRAM
 *
 * Copyright (C) 2023 Luís Mendes  <luis.p.mendes@gmail.com>
 */
module dumbWriteReader(clk14M, ready14M, sdram_aux, sdram_din, sdram_dout, sdram_addr, sdram_we, mach_reading, mach_error);
input clk14M;
input ready14M;
output sdram_aux;
output [7:0] sdram_din;
input [15:0] sdram_dout;
output [20:0] sdram_addr;
output sdram_we;
output mach_reading;
output mach_error;

localparam s_WAIT_READY = 4'b0000;
localparam s_WRITE_AT_00000_0 = 4'b0001;
localparam s_WRITE_AT_00000_1 = 4'b0010;
localparam s_READ_AT_00000 = 4'b0011;
localparam s_READ_AT_00001 = 4'b0100;

logic [20:0] addr;
logic [7:0] din;
logic aux = 1'b0;
logic we = 1'b0;
logic reading = 1'b0;
logic error = 1'b0;
 
logic [3:0] state = s_WAIT_READY;

always @(posedge clk14M)
begin
    case (state)
    s_WAIT_READY :
    begin
      if (ready14M)
      begin
         addr = 21'h000000;
         aux = 1'b0;
         din = 8'hfe;
         we = 1'b1;

         state = s_WRITE_AT_00000_0; 
      end
    end

    s_WRITE_AT_00000_0:
    begin
         addr = 21'h000000;
         aux = 1'b1;
         din = 8'he0;
         we = 1'b1;

         state = s_WRITE_AT_00000_1; 
    end

    s_WRITE_AT_00000_1:
    begin
         addr = 21'h000000;
         aux = 1'b0;
         din = 8'h00;
         we = 1'b0;
         reading = 1'b1;

         state = s_READ_AT_00000;
    end

    s_READ_AT_00000:
    begin
         addr = 21'h000001;
         aux = 1'b0;
         din = 8'h00;
         we = 1'b0;
         reading = 1'b1;

         state = s_READ_AT_00001;
    end

    s_READ_AT_00001:
    begin
    end

    default:
       error = 1'b1;
    endcase;
end;

assign sdram_we = we;
assign sdram_addr = addr;
assign sdram_din = din;
assign sdram_aux = aux;
assign mach_reading = reading;
assign mach_error = error;

endmodule