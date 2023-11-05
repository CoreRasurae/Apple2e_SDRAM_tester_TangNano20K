// SPDX-License-Identifier: BSD-3-Clause
/*
 * Top module for the Apple2E SDRAM controller tester
 *
 * Copyright (C) 2023 Luís Mendes <luis.p.mendes@gmail.com>
 */
module top(clk, uart_rx_i, uart_tx_o, blueLed, greenLed, redLed, rst, 
           O_sdram_clk, O_sdram_cke, O_sdram_cas_n, O_sdram_ras_n, O_sdram_cs_n, O_sdram_wen_n,
           O_sdram_ba, O_sdram_addr, IO_sdram_dq, O_sdram_dqm);
  input  clk;
  input  uart_rx_i;
  output uart_tx_o;
  input  rst;

  //Leds
  output blueLed, greenLed, redLed;

  //SDRAM
  output O_sdram_clk;
  output O_sdram_cke;
  output O_sdram_cas_n;           // columns address select
  output O_sdram_ras_n;           // row address select
  output O_sdram_cs_n;            // chip select
  output O_sdram_wen_n;           // write enable
  output [1:0] O_sdram_ba;        // four banks
  output [10:0] O_sdram_addr;     // 11 bit multiplexed address bus
  inout  [31:0] IO_sdram_dq;      // 32 bit bidirectional data bus
  output [3:0] O_sdram_dqm;       // 32/4

  parameter c_CLKS_PER_BIT    = 18; //1.5MBaud at 27MHz clock

  logic [7:0] rx_byte;
  logic rx_dataValid; 
  logic tx_dataValid;
  logic tx_active;
  logic tx_done;
  logic  [7:0] dataByte;
  logic  valid = 1'b0;
  logic redLedState = 1'b0;

  logic [3:0] decodedNibble;
  logic decodeError;

  logic locked;
  logic clk112M;
  logic clk;

  assign IO_sdram_dq[31:16] = 16'bZZZZZZZZZZZZZZZZ;

  Gowin_rPLL1 myrPLL (
     .clkout(clk112M), //output clkout
     .lock(locked), //output lock
     .clkoutd(clk14M), //output clkoutd
     .clkin(clk) //input clkin
  );

  logic        init_n;
  logic [7:0]  din = 8'h00;
  logic [15:0] dout;
  logic [20:0] addr = 21'h000000;
  logic        aux = 1'b0;
  logic        we = 1'b0;
 
  assign O_sdram_cke = 1'b1;
  assign O_sdram_clk = clk112M;
  sdram mySDRAM (
	.sd_data(IO_sdram_dq[15:0]), // 16 bit bidirectional data bus
	.sd_addr(O_sdram_addr),      // 11 bit multiplexed address bus
	.sd_dqm(O_sdram_dqm),        // two byte masks
	.sd_ba(O_sdram_ba),          // two banks
	.sd_cs(O_sdram_cs_n),        // a single chip select
	.sd_we(O_sdram_wen_n),       // write enable
	.sd_ras(O_sdram_ras_n),      // row address select
	.sd_cas(O_sdram_cas_n),      // columns address select

	// cpu/chipset interface
	.init_n(init_n),	         // init signal after FPGA config to initialize RAM
	.clk(clk112M),               // sdram is accessed at up to 128MHz
	.clkref(clk14M),             // reference clock to sync to
	
	.din(din),		             // data input from chipset/cpu
	.dout(dout),		         // data output to chipset/cpu
	.aux(aux),
	.addr(addr),                 // 21 bit byte address
	.we(we)                      // cpu/chipset requests write
  );

  logic rst112M;
  AsyncMetaReset meatastableRst(
     .clk(clk112M),
     .rstIn(rst),
     .rstOut(rst112M)
  );

  logic ready;
  startupDelayUnit startupUnit (
     .start(locked && rst112M),
     .clk112M(clk112M),
     .sdram_init_n(init_n),
     .sdram_ready(ready)
  );

  logic ready14M;
  MetaSignal meatastableReady(
     .clk(clk14M),
     .signalIn(ready),
     .signalOut(ready14M)
  );

  logic db_reading;
  logic db_error;
  dumbWriteReader dumbWRUnit(
     .clk14M(clk14M),
     .ready14M(ready14M),
     .sdram_aux(aux),
     .sdram_din(din),
     .sdram_dout(dout),
     .sdram_addr(addr),
     .sdram_we(we),
     .mach_reading(db_reading),
     .mach_error(db_error)
  );

  hexDecoderUnit nibbleDec (
    .clk(clk),
    .nibbleChar(rx_byte), 
    .nibble(decodedNibble), 
    .error(decodeError)
  );

  uart_rx #(.CLKS_PER_BIT(c_CLKS_PER_BIT)) UART_RX_INST (
     .i_Clock(clk),
     .i_Rx_Serial(uart_rx_i),
     .o_Rx_DV(rx_dataValid),
     .o_Rx_Byte(rx_byte)
  );

  uart_tx #(.CLKS_PER_BIT(c_CLKS_PER_BIT)) UART_TX_INST (
     .i_Clock(clk),
     .i_Tx_DV(tx_dataValid),
     .i_Tx_Byte(dataByte),
     .o_Tx_Active(tx_active),
     .o_Tx_Serial(uart_tx_o),
     .o_Tx_Done(tx_done)
  );

    always @(posedge clk)
    begin
       tx_dataValid = 1'b0;
       if (rx_dataValid && !valid)
       begin
          dataByte = rx_byte + 8'b01;
          valid = 1'b1;
          redLedState = ~redLedState;
       end

       if (valid && !tx_active && !tx_done)
       begin
          tx_dataValid = 1'b1;
       end

       if (tx_done)
       begin
         valid = 1'b0;
       end
    end

    assign redLed = redLedState;
endmodule