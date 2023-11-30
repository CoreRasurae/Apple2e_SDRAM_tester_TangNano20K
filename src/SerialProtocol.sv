// SPDX-License-Identifier: BSD-3-Clause
/*
 * Serial protocol state-machine for the SDRAM tester
 *
 * Copyright (C) 2023 Luís Mendes <luis.p.mendes@gmail.com>
 */
module SerialProtocol #(parameter CLK = 27000000.0, parameter CommsTimeout = 1, parameter ErrorDelay = 2000) //Timeout and delay in ms
(clk, dataValidRxStrobe, dataRx, dataToTx, dataTxStart, dataTxActive, dataTxDone, decodedNibble, nibbleError,
      sdramReady, sdramNibbleSel, 
      cmdDatabyteOut, cmdNoWordAvailable, cmdWordIn, cmdReadStrobe, cmdAddress, cmdWriteStrobe, cmdWriteSDRAM,
      serialError);

input  logic        clk;
input  logic        dataValidRxStrobe;
input  logic  [7:0] dataRx;
output logic  [7:0] dataToTx;
output logic        dataTxStart = 1'b0;
input  logic        dataTxActive;
input  logic        dataTxDone;
input  logic  [3:0] decodedNibble;
input  logic        nibbleError;
input  logic        sdramReady;
output logic        sdramNibbleSel;
output logic  [7:0] cmdDatabyteOut;
input  logic        cmdNoWordAvailable;
input  logic [15:0] cmdWordIn;
output logic        cmdReadStrobe = 1'b0;
output logic [20:0] cmdAddress;
output logic        cmdWriteStrobe = 1'b0;
output logic        cmdWriteSDRAM;
output logic        serialError = 1'b0;

localparam integer unsigned CYCLES_CommsTimeout = $ceil(CommsTimeout/1000.0 * CLK);
localparam integer unsigned CYCLES_ErrorDelay =  $ceil(ErrorDelay/1000.0 * CLK);
localparam integer unsigned BITS_CommsTimeout = $clog2(CYCLES_CommsTimeout);
localparam integer unsigned BITS_ErrorDelay = $clog2(CYCLES_ErrorDelay);
localparam integer unsigned ZERO_CommsTimeout = {BITS_CommsTimeout{1'b0}};
localparam integer unsigned ONE_CommsTimeout = {{(BITS_CommsTimeout-1){1'b0}}, 1'b1};
localparam integer unsigned ZERO_ErrorDelay = {BITS_ErrorDelay{1'b0}};
localparam integer unsigned ONE_ErrorDelay =  {{(BITS_ErrorDelay-1){1'b0}}, 1'b1};

localparam s_CMD_WAIT      = 3'b000;
localparam s_CMD_READ      = 3'b001;
localparam s_CMD_WRITE     = 3'b010;
localparam s_CMD_NIBBLE    = 3'b011;
localparam s_CMD_READY     = 3'b100;
localparam s_CMD_OK        = 3'b101;
localparam s_CMD_UNKNOWN   = 3'b110;
localparam s_CMD_ERROR     = 3'b111;

localparam s_INNER_00 = 4'b0000;
localparam s_INNER_01 = 4'b0001;
localparam s_INNER_02 = 4'b0010;
localparam s_INNER_03 = 4'b0011;
localparam s_INNER_04 = 4'b0100;
localparam s_INNER_05 = 4'b0101;
localparam s_INNER_06 = 4'b0110;
localparam s_INNER_07 = 4'b0111;
localparam s_INNER_08 = 4'b1000;
localparam s_INNER_09 = 4'b1001;
localparam s_INNER_10 = 4'b1010;
localparam s_INNER_11 = 4'b1011;
localparam s_INNER_12 = 4'b1100;
localparam s_INNER_13 = 4'b1101;
localparam s_INNER_14 = 4'b1110;
localparam s_INNER_15 = 4'b1111;

localparam CR = 8'h0d;
localparam LF = 8'h0a;

logic [2:0]  statesCMD     = 3'b000;
logic [3:0]  statesINNER   = 4'b0000;
logic [4:0]  attemptsIndex = 5'b00000;
logic [1:0]  nibbleIndex   = 2'b00;
logic [7:0]  nibbleChar;
logic [7:0]  cmdReceived   = "Z";
logic [7:0]  cmdBytesCount = 8'h00;
logic [3:0]  nibbleToEncode;

assign nibbleToEncode = nibbleIndex[1] ? (nibbleIndex[0] ? cmdWordIn[3:0] : cmdWordIn[7:4]) : (nibbleIndex[0] ? cmdWordIn[11:8] : cmdWordIn[15:12]);

hexEncoderUnit myHexEncoder(
   .nibble(nibbleToEncode),
   .nibbleChar(nibbleChar)
) /* synthesis syn_noprune = 1 */ ;

logic errorDelayReset = 1'b1;
logic [BITS_ErrorDelay-1:0] errorDelayCounter = ZERO_ErrorDelay;
logic errorDelayFlag = 1'b0;
//
logic commsTimeoutReset = 1'b1;
logic [BITS_CommsTimeout-1:0] commsTimeoutCounter = ZERO_CommsTimeout;
logic commsTimeoutFlag = 1'b0;

always @(posedge clk)
begin
   if (commsTimeoutReset)
   begin
      commsTimeoutCounter <= ZERO_CommsTimeout;
      commsTimeoutFlag = 1'b0;
   end
   else
   begin
      if (commsTimeoutCounter < CYCLES_CommsTimeout)
      begin
         commsTimeoutCounter <= commsTimeoutCounter + ONE_CommsTimeout;
      end
      else
      begin
         commsTimeoutFlag = 1'b1;
      end
  end
end

always @(posedge clk)
begin
   if (errorDelayReset)
   begin
      errorDelayCounter = ZERO_ErrorDelay;
      errorDelayFlag = 1'b0;
   end
   else
   begin
      if (errorDelayCounter < CYCLES_ErrorDelay)
      begin
         errorDelayCounter <= errorDelayCounter + ONE_ErrorDelay;
      end
      else
      begin
         errorDelayFlag = 1'b1;
      end
  end
end

always @(posedge clk)
begin
   cmdWriteStrobe = 1'b0;
   cmdReadStrobe = 1'b0;
   cmdWriteSDRAM = 1'b0;

   if (dataTxActive)
   begin
      dataTxStart = 1'b0;
   end

   unique case (statesCMD)
   s_CMD_WAIT:
   begin
      commsTimeoutReset = 1'b1;
      errorDelayReset = 1'b1;
      if (dataValidRxStrobe)          
      begin
         cmdReceived = dataRx;
         statesINNER = 3'b000;
         unique case (dataRx)             
            "W": 
            begin
               statesCMD = s_CMD_WRITE;;
            end

            "R": 
            begin
               statesCMD = s_CMD_READ;
            end

            "S": 
            begin
               statesCMD = s_CMD_NIBBLE;
            end

            "Y": 
            begin
               statesCMD = s_CMD_READY;
            end

            default:
            begin
               statesCMD = s_CMD_ERROR;
            end
         endcase
      end
   end
      
   s_CMD_WRITE:    
   begin
      commsTimeoutReset = 1'b0;
      if (commsTimeoutFlag)
      begin
         statesINNER = s_INNER_00;       
         statesCMD = s_CMD_ERROR;
      end
      else
      begin
         //Handle write commmand
         unique case (statesINNER)
         s_INNER_00:
         begin
            //Receive high nibble of databytes count to write
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               if (nibbleError)
               begin
                  statesINNER = s_INNER_00;
                  statesCMD = s_CMD_ERROR;
               end
               else
               begin
                  cmdBytesCount[7:4] = decodedNibble;
                  statesINNER = s_INNER_01;
               end          
            end
         end

         s_INNER_01:
         begin
            //Receive low nibble of databyes count to write
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (nibbleError)
               begin
                  statesINNER = s_INNER_00;
                  statesCMD = s_CMD_ERROR;
               end
               else
               begin
                  cmdBytesCount[3:0] = decodedNibble;
                  statesINNER = s_INNER_02;
               end          
            end
         end

         s_INNER_02:
         begin
            //Receive comma
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (dataRx == ",")
                  statesINNER = s_INNER_03;
               else
               begin
                  statesCMD = s_CMD_ERROR;
                  statesINNER = s_INNER_00;
               end
           end
         end

         s_INNER_03:
         begin
            //Receive high bit 20
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (dataRx == "1")
               begin
                  cmdAddress[20:20] = 1'b1;
                  statesINNER = s_INNER_04;
               end
               else if (dataRx == "0")
               begin
                  cmdAddress[20:20] = 1'b0;
                  statesINNER = s_INNER_04;
               end
               else
               begin
                  statesCMD = s_CMD_ERROR;
                  statesINNER = s_INNER_00;
               end
            end
         end

         s_INNER_04:
         begin
            //Receive bits 19:16
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (nibbleError)
               begin
                  statesINNER = s_INNER_00;
                  statesCMD = s_CMD_ERROR;
               end
               else
               begin
                  cmdAddress[19:16] = decodedNibble;
                  statesINNER = s_INNER_05;
               end          
            end           
         end

         s_INNER_05:
         begin
            //Receive bits 15:12
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (nibbleError)
               begin
                  statesINNER = s_INNER_00;
                  statesCMD = s_CMD_ERROR;
               end
               else
               begin
                  cmdAddress[15:12] = decodedNibble;
                  statesINNER = s_INNER_06;
               end          
            end           
         end

         s_INNER_06:
         begin
            //Receive bits 11:8
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (nibbleError)
               begin
                  statesINNER = s_INNER_00;
                  statesCMD = s_CMD_ERROR;
               end
               else
               begin
                  cmdAddress[11:8] = decodedNibble;
                  statesINNER = s_INNER_07;
               end          
            end           
         end

         s_INNER_07:
         begin
            //Receive bits 7:4
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (nibbleError)
               begin
                  statesINNER = s_INNER_00;
                  statesCMD = s_CMD_ERROR;
               end
               else
               begin
                  cmdAddress[7:4] = decodedNibble;
                  statesINNER = s_INNER_08;
               end          
            end           
         end

         s_INNER_08:
         begin
            //Receive bits 3:0
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (nibbleError)
               begin
                  statesCMD = s_CMD_ERROR;
                  statesINNER = s_INNER_00;
               end
               else
               begin
                  cmdAddress[3:0] = decodedNibble;
                  statesINNER = s_INNER_09;
               end          
            end           
         end

         s_INNER_09:
         begin
            //Receive comma
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (dataRx == ",")
                  statesINNER = s_INNER_10;
               else
               begin
                  statesINNER = s_INNER_00;
                  statesCMD = s_CMD_ERROR;
               end
            end
         end

         s_INNER_10:
         begin
            //Receive first data byte high nibble
            //Receive bits 7:4
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (nibbleError)
               begin
                  statesINNER = s_INNER_00;
                  statesCMD = s_CMD_ERROR;
               end
               else
               begin
                  cmdDatabyteOut[7:4] = decodedNibble;
                  statesINNER = s_INNER_11;
               end          
            end
         end

         s_INNER_11:
         begin
            //Receive first data byte low nibble
            //Receive bits 3:0
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (nibbleError)
               begin
                  statesINNER = s_INNER_00;
                  statesCMD = s_CMD_ERROR;
               end
               else
               begin                  
                  cmdDatabyteOut[3:0] = decodedNibble;
                  cmdWriteStrobe = 1'b1;
                  cmdWriteSDRAM = 1'b1;
                  statesINNER = s_INNER_12;
               end          
            end
         end

         s_INNER_12:
         begin
            cmdWriteStrobe = 1'b0;
            //Receive subsequente data bytes high nibble
            if (cmdBytesCount == 8'h00)
               statesINNER = s_INNER_14;
            else
            begin
               //Receive bits 7:4
               if (dataValidRxStrobe)
               begin
                  commsTimeoutReset = 1'b1; 
                  unique if (nibbleError)
                  begin
                     statesINNER = s_INNER_00;
                     statesCMD = s_CMD_ERROR;
                  end
                  else
                  begin
                     cmdDatabyteOut[7:4] = decodedNibble;
                     statesINNER = s_INNER_13;
                  end          
               end
            end
         end

         s_INNER_13:
         begin
            //Receive first data byte low nibble
            //Receive bits 3:0
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (nibbleError)
               begin
                  statesINNER = s_INNER_00;
                  statesCMD = s_CMD_ERROR;
               end
               else
               begin
                  cmdDatabyteOut[3:0] = decodedNibble;
                  statesINNER = s_INNER_12;
                  cmdBytesCount = cmdBytesCount - 8'h01;
                  cmdAddress = cmdAddress + 21'h000001;
                  cmdWriteStrobe = 1'b1;
                  cmdWriteSDRAM = 1'b1;
               end          
            end
         end

         s_INNER_14:
         begin
            //Receive End of Line
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (dataRx == CR || dataRx == LF)
                  statesINNER = s_INNER_15;
               else
               begin
                  statesINNER = s_INNER_00;
                  statesCMD = s_CMD_ERROR;
               end
            end
         end

         s_INNER_15:    
            //Receive End of Line
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (dataRx == CR || dataRx == LF)
               begin
                  statesINNER = s_INNER_00;
                  statesCMD = s_CMD_OK;
               end
               else
               begin
                  statesINNER = s_INNER_00;
                  statesCMD = s_CMD_ERROR;
               end
            end

         default:
         begin
            statesINNER = s_INNER_00;
            statesCMD = s_CMD_ERROR;
         end
         endcase
      end
   end

   s_CMD_READ:
   begin
      cmdReadStrobe = 1'b0;
      cmdWriteStrobe = 1'b0;

      commsTimeoutReset = 1'b0;
      if (commsTimeoutFlag)
      begin
         statesINNER <= s_INNER_00;
         statesCMD <= s_CMD_ERROR;
      end
      else
      begin
         //Handle write commmand
         unique case (statesINNER)
         s_INNER_00:
         begin
            //Receive high nibble of databytes count to write
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               if (nibbleError)
               begin
                  statesINNER <= s_INNER_00;
                  statesCMD <= s_CMD_ERROR;
               end
               else
               begin
                  cmdBytesCount[7:4] <= decodedNibble;
                  statesINNER <= s_INNER_01;
               end          
            end
         end

         s_INNER_01:
         begin
            //Receive low nibble of databyes count to write
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (nibbleError)
               begin
                  statesINNER <= s_INNER_00;
                  statesCMD <= s_CMD_ERROR;
               end
               else
               begin
                  cmdBytesCount[3:0] <= decodedNibble;
                  statesINNER <= s_INNER_02;
               end          
            end
         end

         s_INNER_02:
         begin
            //Receive comma
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (dataRx == ",")
                  statesINNER <= s_INNER_03;
               else
               begin
                  statesCMD <= s_CMD_ERROR;
                  statesINNER <= s_INNER_00;
               end
            end
         end

         s_INNER_03:
         begin
            //Receive high bit 20
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (dataRx == "1")
               begin
                  cmdAddress[20:20] <= 1'b1;
                  statesINNER = s_INNER_04;
               end
               else if (dataRx == "0")
               begin
                  cmdAddress[20:20] <= 1'b0;
                  statesINNER <= s_INNER_04;
               end
               else
               begin
                  statesCMD <= s_CMD_ERROR;
                  statesINNER <= s_INNER_00;
               end
            end
         end

         s_INNER_04:
         begin
            //Receive bits 19:16
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (nibbleError)
               begin
                  statesINNER <= s_INNER_00;
                  statesCMD <= s_CMD_ERROR;
               end
               else
               begin
                  cmdAddress[19:16] <= decodedNibble;
                  statesINNER <= s_INNER_05;
               end          
            end           
         end

         s_INNER_05:
         begin
            //Receive bits 15:12
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (nibbleError)
               begin
                  statesINNER <= s_INNER_00;
                  statesCMD <= s_CMD_ERROR;
               end
               else
               begin
                  cmdAddress[15:12] <= decodedNibble;
                  statesINNER <= s_INNER_06;
               end          
            end           
         end

         s_INNER_06:
         begin
            //Receive bits 11:8
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (nibbleError)
               begin
                  statesINNER <= s_INNER_00;
                  statesCMD <= s_CMD_ERROR;
               end
               else
               begin
                  cmdAddress[11:8] <= decodedNibble;
                  statesINNER <= s_INNER_07;
               end          
            end           
         end

         s_INNER_07:
         begin
            //Receive bits 7:4
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (nibbleError)
               begin
                  statesINNER <= s_INNER_00;
                  statesCMD <= s_CMD_ERROR;
               end
               else
               begin
                  cmdAddress[7:4] <= decodedNibble;
                  statesINNER <= s_INNER_08;
               end          
            end           
         end

         s_INNER_08:
         begin
            //Receive bits 3:0
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (nibbleError)
               begin
                  statesCMD <= s_CMD_ERROR;
                  statesINNER <= s_INNER_00;
               end
               else
               begin
                  cmdAddress[3:0] <= decodedNibble;
                  statesINNER <= s_INNER_09;
               end          
            end           
         end

         s_INNER_09:
         begin
            //Receive End of Line
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (dataRx == CR || dataRx == LF)
                  statesINNER <= s_INNER_10;
               else
               begin
                  statesINNER <= s_INNER_00;
                  statesCMD <= s_CMD_ERROR;
               end
            end
         end

         s_INNER_10:
         begin
            //Receive End of Line
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (dataRx == CR || dataRx == LF)
               begin
                  cmdWriteStrobe = 1'b1; //Issue the first SDRAM read
                  attemptsIndex <= 5'b00001;
                  statesINNER <= s_INNER_11;
               end
               else
               begin
                  statesINNER <= s_INNER_00;
                  statesCMD <= s_CMD_ERROR;
               end
            end
         end

         s_INNER_11:
         begin
            commsTimeoutReset = 1'b1;
            //Start sending the bytes. We always have to send one word at least.
            unique if (!cmdNoWordAvailable)
            begin
               //Give an extra cycle between the read strobe and the actual data read
               cmdReadStrobe <= 1'b1;
               attemptsIndex = 5'b00000;
            end
            else if (attemptsIndex == 5'b00000)
            begin
               nibbleIndex <= 2'b00;
               statesINNER <= s_INNER_12;
            end
            else
            begin
               if (attemptsIndex < 5'b11111)
                  attemptsIndex = attemptsIndex + 5'b00001;
               else
               begin
                  statesINNER <= s_INNER_00;
                  statesCMD <= s_CMD_ERROR;
               end
            end
         end

         s_INNER_12:
         begin
            commsTimeoutReset = 1'b1;
            //Send first nibble of the word
            if (nibbleIndex == 2'b00)
            begin
               if (!dataTxActive && !dataTxStart)
               begin
                  dataToTx <= nibbleChar;
                  dataTxStart <= 1'b1;
                  nibbleIndex <= 2'b01;
               end
            end
            else
            begin
               //Send the other nibbles
               if (!dataTxActive && !dataTxStart)
               begin
                  dataToTx <= nibbleChar;
                  dataTxStart <= 1'b1;
                  if (nibbleIndex == 2'b11)
                  begin
                     //Last nibble of the first word is about to be sent...
                     if (cmdBytesCount != 8'h00)
                     begin
                        //If there are more words to send, increment the address and send the SDRAM read request
                        cmdAddress <= cmdAddress + 21'h0000001;
                        cmdWriteStrobe <= 1'b1;
                     end
                     statesINNER <= s_INNER_13;
                  end
                  nibbleIndex <= nibbleIndex + 2'b01;
               end
            end
         end

         s_INNER_13:
         begin
            commsTimeoutReset = 1'b1;            
            if (cmdBytesCount == 0)
            begin
               statesINNER <= s_INNER_15;
            end
            else
            begin
               //Send the comma separator char
               if (!dataTxActive && !dataTxStart)
               begin
                  if (!cmdNoWordAvailable)
                  begin
                     cmdReadStrobe <= 1'b1;
                     dataToTx <= ",";
                     dataTxStart <= 1'b1;
                     statesINNER <= s_INNER_14;
                     cmdBytesCount <= cmdBytesCount - 8'h01;
                     nibbleIndex <= 2'b00;
                  end
                  else
                  begin
                     statesINNER <= s_INNER_00;
                     statesCMD <= s_CMD_ERROR;
                  end
               end
            end
         end

         s_INNER_14:
         begin
            commsTimeoutReset = 1'b1;
            //Send first nibble of the word
            if (nibbleIndex == 2'b00)
            begin
               if (!dataTxActive && !dataTxStart)
               begin
                  dataToTx <= nibbleChar;
                  dataTxStart <= 1'b1;
                  nibbleIndex <= 2'b01;
               end
            end
            else
            begin
               //Send the other nibbles
               if (!dataTxActive && !dataTxStart)
               begin
                  dataToTx <= nibbleChar;
                  dataTxStart <= 1'b1;
                  if (nibbleIndex == 2'b11)
                  begin
                     //Last nibble of the current word is being sent, so lets move to the next word
                     statesINNER = s_INNER_13;
                     if (cmdBytesCount != 8'h00)
                     begin
                        //If there are more words to send, increment the address and send the SDRAM read request
                        cmdAddress <= cmdAddress + 21'h0000001;
                        cmdWriteStrobe <= 1'b1;
                     end
                  end
                  nibbleIndex <= nibbleIndex + 2'b01;
               end
            end
         end

         s_INNER_15:
         begin
            commsTimeoutReset = 1'b1;
            //All data is sent, so lets send the End of line and finish the Read Op.
            unique if (nibbleIndex == 2'b00)
            begin
               if (!dataTxActive && !dataTxStart)
               begin
                  dataToTx <= CR;
                  dataTxStart <= 1'b1;
                  nibbleIndex <= 2'b01;
               end
            end
            else if (nibbleIndex == 2'b01)
            begin
               if (!dataTxActive && !dataTxStart)
               begin
                  dataToTx = LF;
                  dataTxStart <= 1'b1;
                  nibbleIndex <= 2'b00;
                  statesINNER <= s_INNER_00;
                  statesCMD <= s_CMD_OK;
               end
            end
            else
            begin
               statesINNER <= s_INNER_00;
               statesCMD <= s_CMD_ERROR;
            end
         end

         default:
         begin
            statesINNER <= s_INNER_00;
            statesCMD <= s_CMD_ERROR;
         end

         endcase
      end
   end

   s_CMD_NIBBLE:
   begin
      commsTimeoutReset = 1'b0;
      if (commsTimeoutFlag)
      begin
         statesINNER = s_INNER_00;
         statesCMD = s_CMD_ERROR;
      end
      else
      begin
         unique case (statesINNER)
         s_INNER_00:
         begin
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (dataRx == "1")
               begin
                  sdramNibbleSel = 1'b1;
                  statesINNER = s_INNER_01;
               end
               else if (dataRx == "0")
               begin
                  sdramNibbleSel = 1'b0;
                  statesINNER = s_INNER_01;
               end
               else
               begin
                  statesINNER = s_INNER_00;
                  statesCMD = s_CMD_ERROR;
               end
            end
         end

         s_INNER_01:
         begin
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (dataRx == CR || dataRx == LF)
               begin
                  statesINNER = s_INNER_02;
               end
               else
               begin
                  statesINNER = s_INNER_00;
                  statesCMD = s_CMD_ERROR;
               end
            end
         end

         s_INNER_02:
         begin
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (dataRx == CR || dataRx == LF)
               begin
                  statesINNER = s_INNER_00;
                  statesCMD = s_CMD_OK;
               end
               else
               begin
                  statesINNER = s_INNER_00;
                  statesCMD = s_CMD_ERROR;
               end
            end
         end

         default:
         begin
            statesINNER = s_INNER_00;
            statesCMD = s_CMD_ERROR;
         end

         endcase
      end
   end

   s_CMD_READY:
   begin
      commsTimeoutReset = 1'b0;
      if (commsTimeoutFlag)
      begin
         statesINNER = s_INNER_00;
         statesCMD = s_CMD_ERROR;
      end
      else
      begin
         unique case (statesINNER)
         s_INNER_00:
         begin
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (dataRx == CR || dataRx == LF)
               begin
                  statesINNER = s_INNER_01;
               end
               else
               begin
                  statesINNER = s_INNER_00;
                  statesCMD = s_CMD_ERROR;
               end
            end
         end

         s_INNER_01:
         begin
            if (dataValidRxStrobe)
            begin
               commsTimeoutReset = 1'b1;
               unique if (dataRx == CR || dataRx == LF)
               begin
                  statesINNER = s_INNER_02;
               end
               else
               begin
                  statesINNER = s_INNER_00;
                  statesCMD = s_CMD_ERROR;
               end
            end
         end

         s_INNER_02:
         begin
            commsTimeoutReset = 1'b1;
            if (sdramReady)
            begin
               if (!dataTxActive && !dataTxStart)
               begin
                  dataToTx = "Y";
                  dataTxStart = 1'b1;
                  statesINNER = s_INNER_03;
               end 
            end
            else
            begin
               if (!dataTxActive && !dataTxStart)
               begin
                  dataToTx = "N";
                  dataTxStart = 1'b1;
                  statesINNER = s_INNER_03;
               end
            end
         end

         s_INNER_03:
         begin
            commsTimeoutReset = 1'b1;
            if (!dataTxActive && !dataTxStart)
            begin
               dataToTx = CR;
               dataTxStart = 1'b1;
               statesINNER = s_INNER_04;
            end
         end

         s_INNER_04:
         begin
            commsTimeoutReset = 1'b1;
            if (!dataTxActive && !dataTxStart)
            begin
               dataToTx = LF;
               dataTxStart = 1'b1;
               statesINNER = s_INNER_05;
            end
         end

         s_INNER_05:
         begin
            commsTimeoutReset = 1'b1;
            statesCMD = s_CMD_WAIT;
            statesINNER = s_INNER_00;
         end

         default:
         begin
            statesCMD = s_CMD_ERROR;
            statesINNER = s_INNER_00;
         end
         endcase
      end
   end

   s_CMD_OK:
   begin
      //Send ACK\r\n
      commsTimeoutReset = 1'b1;
      errorDelayReset = 1'b1;

      unique case (statesINNER)
      s_INNER_00:
      begin      
         if (!dataTxActive && !dataTxStart)
         begin
            dataToTx = "A";
            dataTxStart = 1'b1;
            statesINNER = s_INNER_01;
         end         
      end

      s_INNER_01:
      begin
         if (!dataTxActive && !dataTxStart)
         begin
            dataToTx = "C";
            dataTxStart = 1'b1;
            statesINNER = s_INNER_02;
         end         
      end

      s_INNER_02:
      begin
         if (!dataTxActive && !dataTxStart)
         begin
            dataToTx = "K";
            dataTxStart = 1'b1;
            statesINNER = s_INNER_03;
         end
      end

      s_INNER_03:
      begin
         if (!dataTxActive && !dataTxStart)
         begin
            dataToTx = CR;
            dataTxStart = 1'b1;
            statesINNER = s_INNER_04;
         end
      end

      s_INNER_04:
      begin
         if (!dataTxActive && !dataTxStart)
         begin
            dataToTx = LF;
            dataTxStart = 1'b1;
            statesINNER = s_INNER_05;
         end
      end

      s_INNER_05:
      begin
         statesINNER = s_INNER_00;
         statesCMD = s_CMD_WAIT;
      end

      default:
      begin
         statesINNER = s_INNER_00;
         statesCMD = s_CMD_ERROR;
      end
      endcase
   end

   s_CMD_ERROR:
   begin
      //Send NAK\r\n
      commsTimeoutReset = 1'b1;
      errorDelayReset = 1'b0;

      unique case (statesINNER)
      s_INNER_00:
      begin      
         if (!dataTxActive && !dataTxStart)
         begin
            dataToTx = "N";
            dataTxStart = 1'b1;
            statesINNER = s_INNER_01;
         end         
      end

      s_INNER_01:
      begin
         if (!dataTxActive && !dataTxStart)
         begin
            dataToTx = "A";
            dataTxStart = 1'b1;
            statesINNER = s_INNER_02;
         end         
      end

      s_INNER_02:
      begin
         if (!dataTxActive && !dataTxStart)
         begin
            dataToTx = "K";
            dataTxStart = 1'b1;
            statesINNER = s_INNER_03;
         end
      end

      s_INNER_03:
      begin
         if (!dataTxActive && !dataTxStart)
         begin
            dataToTx = CR;
            dataTxStart = 1'b1;
            statesINNER = s_INNER_04;
         end
      end

      s_INNER_04:
      begin
         if (!dataTxActive && !dataTxStart)
         begin
            dataToTx = LF;
            dataTxStart = 1'b1;
            statesINNER = s_INNER_05;
         end
      end

      s_INNER_05:
      begin
         serialError = 1'b1;
         statesINNER = s_INNER_06;
         errorDelayReset = 1'b0;
      end

      s_INNER_06:
      begin
         if (errorDelayFlag)
         begin
            serialError = 1'b0;
            statesCMD = s_CMD_WAIT;
            statesINNER = s_INNER_00;
         end
      end

      default:
      begin
         serialError = 1'b1;
         statesINNER = s_INNER_15;
      end
      endcase
   end

   default:
   begin
      statesCMD = s_CMD_ERROR;
      statesINNER = s_INNER_00;
   end

   endcase
end;

endmodule