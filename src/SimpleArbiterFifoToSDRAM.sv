module SimpleArbiterFifoToSDRAM(clk2M, fifoDataEmpty, fifoDataFull, fifoReadStrobe, fifoWriteStrobe, writeSDRAM, sdramReady, sdramWE, simpleArbiterError);
input  logic clk2M;
input  logic fifoDataEmpty;   //fifoDataEmpty   - Nothing to read from serial protocol
input  logic fifoDataFull;    //fifoDataFull    - Cannot send more data to the serial protocol
output logic fifoReadStrobe;  //fifoReadStrobe  - Toggle for 1 cycle to issue a FIFO read from the serial protocol
output logic fifoWriteStrobe; //fifoWriteStrobe - Toggle for 1 cycle to issue a FIFO write to the serial protocol
input  logic writeSDRAM;      //writeSDRAM      - Logic 1: Serial protcool wants to  issue a SDRAM write, Logic 0: Serial protocol wants to issue a read
input  logic sdramReady;      //sdramReady      - Logic 1: SDRAM is ready to receive commands, Logic 0: SDRAM is not initalized yet
output logic sdramWE;         //sdramWE         - Logic 1: Tell the SDRAM controller to issue a write, Logic 0: Tell the SDRAM controller to issue a read
output logic simpleArbiterError = 1'b0;

localparam s_ARB_WAIT_INIT   = 3'b000;
localparam s_ARB_REFRESH     = 3'b001;
localparam s_ARB_READ_FIFO_0 = 3'b011;
localparam s_ARB_READ_FIFO_1 = 3'b100;
localparam s_ARB_SDRAM_READ  = 3'b101;
localparam s_ARB_SDRAM_WRITE = 3'b110;

logic [2:0] state = s_ARB_WAIT_INIT;

always @(posedge clk2M)
begin
   fifoReadStrobe = 1'b0;
   fifoWriteStrobe = 1'b0;

   unique case (state)
      s_ARB_WAIT_INIT:
      begin
         sdramWE <= 1'b0;
         if (sdramReady)
         begin
            state <= s_ARB_REFRESH;
         end
      end

      s_ARB_REFRESH:
      begin
         //Two 14M cycles per each SDRAM operation
         sdramWE <= 1'b0; //Do a read to refresh the SDRAM - cycle 1
         if (!fifoDataEmpty)
         begin
            fifoReadStrobe <= 1'b1;
            state <= s_ARB_READ_FIFO_0;
         end
         else
            state <= s_ARB_REFRESH;
      end

      s_ARB_READ_FIFO_0:
      begin
         //Wait one cycle for the FIFO data
         state <= s_ARB_READ_FIFO_1;
      end

      s_ARB_READ_FIFO_1:
      begin
         //Perform the SDRAM operation
         sdramWE <= writeSDRAM;
         if (writeSDRAM)
            state <= s_ARB_SDRAM_WRITE;
         else
            state <= s_ARB_SDRAM_READ;
      end

      s_ARB_SDRAM_READ:
      begin
         sdramWE <= 1'b0;
         //Update the FIFO with the Data
         fifoWriteStrobe <= 1'b1;
         state <= s_ARB_REFRESH;
      end

      s_ARB_SDRAM_WRITE:
      begin
         sdramWE <= 1'b0; 
         state <= s_ARB_REFRESH;
      end

      default:
      begin
         simpleArbiterError <= 1'b1;
      end
   endcase
end

endmodule