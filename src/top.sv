// SPDX-License-Identifier: BSD-3-Clause
/*
 * Top module for the Apple2E SDRAM controller tester
 *
 * Copyright (C) 2023 Luís Mendes <luis.p.mendes@gmail.com>
 */
module top(clk, uart_rx_i, uart_tx_o, leds, rst, 
           O_sdram_clk, O_sdram_cke, O_sdram_cas_n, O_sdram_ras_n, O_sdram_cs_n, O_sdram_wen_n,
           O_sdram_ba, O_sdram_addr, IO_sdram_dq, O_sdram_dqm);
  input  clk;
  input  uart_rx_i;
  output uart_tx_o;
  input  rst;

  //Leds
  output [4:0] leds;

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
  logic rx_active;
  logic tx_dataValid;
  logic tx_active;
  logic tx_done;
  logic [7:0] tx_dataByte;
  logic  valid = 1'b0;

  logic [3:0] decodedNibble;
  logic decodeError;

  logic locked;
  logic clk140M;
  logic clk28M;
  logic clk14M;
  logic clk7M;
  logic clk2M;
  logic clk;

  assign IO_sdram_dq[31:16] = 16'bZZZZZZZZZZZZZZZZ;

  Gowin_rPLL1 myrPLL (
     .clkout(clk140M), //output clkout
     .lock(locked), //output lock
     .clkin(clk) //input clkin
  );

  Gowin_CLKDIV_5 div5 (
     .clkout(clk28M),
     .hclkin(clk140M), 
     .resetn(locked)
  );

  Gowin_CLKDIV_2 div2_14M (
     .clkout(clk14M), //output clkout
     .hclkin(clk28M), //input hclkin
     .resetn(locked) //input resetn
  );

  Gowin_CLKDIV_2 div2_7M (
     .clkout(clk7M), //output clkout
     .hclkin(clk14M), //input hclkin
     .resetn(locked) //input resetn
  );

  Gowin_CLKDIV_3_5 div3_5 (
     .clkout(clk2M), //output clkout
     .hclkin(clk7M), //input hclkin
     .resetn(locked) //input resetn
  );

  logic        init_n;
  logic [7:0]  din = 8'h00;
  logic [15:0] dout;
  logic [20:0] addr = 21'h000000;
  logic        aux = 1'b0;
  logic        we = 1'b0;
 
  assign O_sdram_cke = 1'b1;
  assign O_sdram_clk = clk28M;
  sdram apple2eSDRAMController (
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
	.clk(clk28M),               // sdram is accessed at up to 128MHz
	.clkref(clk2M),             // reference clock to sync to
	
	.din(din),		             // data input from chipset/cpu
	.dout(dout),		         // data output to chipset/cpu
	.aux(aux),
	.addr(addr),                 // 21 bit byte address
	.we(we)                      // cpu/chipset requests write
  );

  logic rst2M;
  AsyncMetaReset meatastableRst(
     .clk(clk2M),
     .rstIn(rst),
     .rstOut(rst2M)
  );

  logic ready = 1'b0;
  startupDelayUnit #(.CLK(2000000.0)) startupUnit (
     .start(locked && rst2M),
     .clk(clk2M),
     .sdram_init_n(init_n),
     .sdram_ready(ready)
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
     .o_Rx_Active(rx_active),
     .o_Rx_Byte(rx_byte)
  );

  uart_tx #(.CLKS_PER_BIT(c_CLKS_PER_BIT)) UART_TX_INST (
     .i_Clock(clk),
     .i_Tx_DV(tx_dataValid),
     .i_Tx_Byte(tx_dataByte),
     .o_Tx_Active(tx_active),
     .o_Tx_Serial(uart_tx_o),
     .o_Tx_Done(tx_done)
  );

  logic  [7:0] din27M;
  logic [15:0] dout27M;
  logic [20:0] addr27M;
  logic        aux27M;
  logic cmdWriteSDRAM27M;
  logic cmdWriteSDRAM;
  logic cmdWriteFull;
  logic cmdWriteStrobe;  
  logic cmdReadStrobe;
  logic cmdNoWordAvailable;
  logic serialError;

  SerialProtocol serialProtoINST (
     .clk(clk), 
     .dataValidRxStrobe(rx_dataValid), 
     .dataRx(rx_byte), 
     .dataToTx(tx_dataByte), 
     .dataTxStart(tx_dataValid),
     .dataTxActive(tx_active),
     .dataTxDone(tx_done),
     .decodedNibble(decodedNibble), 
     .nibbleError(decodeError),
     .sdramReady(ready), 
     .sdramNibbleSel(aux27M), 
     .cmdDatabyteOut(din27M),
     .cmdNoWordAvailable(cmdNoWordAvailable),
     .cmdWordIn(dout27M),
     .cmdReadStrobe(cmdReadStrobe), 
     .cmdAddress(addr27M), 
     .cmdWriteStrobe(cmdWriteStrobe),
     .cmdWriteSDRAM(cmdWriteSDRAM27M),
     .serialError(serialError)
  );

  logic fifoReadStrobe;
  logic fifoWriteStrobe;
  logic fifoDataEmpty;
  logic fifoDataFull;
  logic writeSDRAM;
  FIFO_HS_SerialOut FifoSerialOut (
     .Data({addr27M, din27M, aux27M, cmdWriteSDRAM27M}), //input [29:0] Data
     .WrClk(clk), //input WrClk
     .RdClk(clk2M), //input RdClk
     .WrEn(cmdWriteStrobe), //input WrEn
     .RdEn(fifoReadStrobe), //input RdEn
     .Q({addr, din, aux, writeSDRAM}), //output [30:0] Q
     .Empty(fifoDataEmpty), //output Empty
     .Full(cmdWriteFull) //output Full
  );

  FIFO_HS_SerialIn FifoSerialIn (
     .Data(dout), //input [15:0] Data
     .WrClk(clk2M), //input WrClk
     .RdClk(clk), //input RdClk
     .WrEn(fifoWriteStrobe), //input WrEn
     .RdEn(cmdReadStrobe),   //input RdEn
     .Q(dout27M), //output [15:0] Q
     .Empty(cmdNoWordAvailable), //output Empty
     .Full(fifoDataFull) //output Full
  );

  logic simpleArbiterError;
  SimpleArbiterFifoToSDRAM simpleArbiter (
     .clk2M(clk2M),
     .fifoDataEmpty(fifoDataEmpty), 
     .fifoDataFull(fifoDataFull), 
     .fifoReadStrobe(fifoReadStrobe), 
     .fifoWriteStrobe(fifoWriteStrobe),
     .writeSDRAM(writeSDRAM),
     .sdramReady(ready),
     .sdramWE(we),
     .simpleArbiterError(simpleArbiterError)
  );

  assign leds = {!ready, !simpleArbiterError, !serialError, !tx_active, !rx_active};
endmodule