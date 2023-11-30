import serial
import sys
import numpy as np
from typing import List
from time import sleep
from random import seed
from random import randint
import argparse
from skimage.io import imread
import PIL
from PIL import Image

def imresize(im, res):
   return np.array(Image.fromarray(im).resize(res, PIL.Image.LANCZOS)) #PIL.Image.LANCZOS, PIL.Image.BICUBIC 

class SDRAMSerialClient():
   def __init__(self, serialPort='/dev/ttyUSB1', baudRate=1500000, timeout = 100e-3):
      self.ser = serial.Serial(serialPort, baudRate, timeout = timeout)
      self.pageSize = 256
      self.buffers = 4
      self.writeOutput = False

   def setDebugTransfers(self, writeOutput : bool):
      self.writeOutput = writeOutput

   def convertToHexWord(self, dataWord : int, size=6):
      wordStr = hex(dataWord)[2:]
      if len(wordStr) < size:
         wordStr = '0'*(size-len(wordStr)) + wordStr
      return wordStr

   def convertFromHexWord(self, hexWord : str):
      return int(hexWord, 16)

   def writeToSDRAM(self, bytesCount : int, targetAddress : int, data : np.array):
      if bytesCount < 1 or bytesCount > 256:
         raise Exception('Cannot write less than 1 byte, nor more than 256') 
      if bytesCount > len(data):
         raise Exception('Cannot write ' + str(bytesCount) + ', since only ' + str(len(data)) + 'bytes are available') 
      dataToSend = bytes('W' + self.convertToHexWord(bytesCount-1, 2) + ',' + self.convertToHexWord(targetAddress, 6) + ',', 'ascii');
      self.ser.write(dataToSend)
      if self.writeOutput:
         print(dataToSend, end='')
      for i in np.arange(bytesCount):
         dataToSend = bytes(self.convertToHexWord(data[i], 2), 'ascii')
         self.ser.write(dataToSend)
         if self.writeOutput:
            print(dataToSend, end='')
      self.ser.write(bytes('\r\n', 'ascii'))  
      line=self.ser.readline()
      if self.writeOutput:
         print(line)
      if line[0:3] != b'ACK':
         raise Exception('Failed to execute Write command')

   def readFromSDRAM(self, bytesCount : int, targetAddress : int) -> np.array:
      if bytesCount < 1 or bytesCount > 256:
         raise Exception('Cannot write less than 1 byte, nor more than 256') 
      dataToSend = bytes('R' + self.convertToHexWord(bytesCount-1, 2) + ',' + self.convertToHexWord(targetAddress, 6) + '\r\n', 'ascii');
      self.ser.write(dataToSend)
      if self.writeOutput:
         print(dataToSend, end='')
      lineData=self.ser.readline()
      if self.writeOutput:
         print(lineData, end='')
      line=self.ser.readline()
      if self.writeOutput:
         print(line)   
      if line[0:3] != b'ACK':
         raise Exception('Failed to execute Read command - ACK not received')
      data = np.zeros(bytesCount, dtype=np.uint16)
      dataWords = lineData.split(b',')
      if len(dataWords) != bytesCount:
         raise Exception('Failed to execute Read command - Expected ' + str(bytesCount) + ' words, but received ' + str(len(dataWords)))    
      index = 0
      for dataWord in dataWords:
         data[index] = self.convertFromHexWord(dataWord)
         index = index + 1
      return data     

   def isSDRAMReady(self):
      dataToSend = bytes('Y\r\n', 'ascii');
      self.ser.write(dataToSend)
      self.ser.flush()
      line=self.ser.readline()
      if self.writeOutput:
         print(dataToSend, end='')
      if self.writeOutput:
         print(line)
      if line == b'Y\r\n':
         return True
      elif line == b'N\r\n':
         return False
      else: 
         raise Exception('Unkown response received: ' + str(line));
   
   def setSDRAMNibble(self, highNibble: bool):
      dataToSend = bytes('S' + ('1' if highNibble else '0') + '\r\n', 'ascii')
      self.ser.write(dataToSend)
      self.ser.flush()      
      line=self.ser.readline()
      if self.writeOutput:
         print(dataToSend, end='')
      if self.writeOutput:
         print(line)
      if line[0:3] != b'ACK':
         raise Exception('Failed to execute SetSDRAMNibble command')

   def loadRange(self, lowAddress : int, highAddress : int, data : np.array):
      i = lowAddress
      while i <= highAddress: 
         count = 256
         if i + 255 > highAddress:
            count = highAddress - i + 1
         self.writeToSDRAM(count, i, data[i:i+count])
         if i % (100*1024) == 0:
            print('Wrote ' + str(i - lowAddress + count) + ' bytes')
         i = i + count

   def readRange(self, lowAddress : int, highAddress : int) -> np.array:
      dataRead = np.zeros(highAddress-lowAddress + 1, dtype = np.uint16)
      i = lowAddress
      while i <= highAddress: 
         count = 256
         if i + 255 > highAddress:
            count = highAddress - i + 1
         dataRead[i:i+count] = self.readFromSDRAM(count, i)
         if i % (100*1024) == 0:
            print('Read ' + str(i - lowAddress + count) + ' bytes')
         i = i + count;
      return dataRead

   def checkRange(self, lowAddress : int, highAddress : int, highDataRef : np.array, lowDataRef : np.array, dataTest : np.array):
      i = lowAddress
      while i <= highAddress:
         if highDataRef[i] << 8 | lowDataRef[i] != dataTest[i]:
            raise Exception('Error veryfing read data at address: ' + self.convertToHexWord(i) + ', expected: ' + self.convertToHexWord(highDataRef[i] << 8 | lowDataRef[i], 4) + ', read: ' + self.convertToHexWord(dataTest[i], 4))
         if i % (100*1024) == 0:
            print('Verified ' + str(i - lowAddress + 1) + ' bytes')
         i = i + 1


def simpleTest():
   client = SDRAMSerialClient(serialPort='/dev/ttyUSB1')
   client.setDebugTransfers(True)
   if not client.isSDRAMReady():
      print('Cannot proceed with the test, since SDRAM controller responded as not being Ready for use')
      return;
   client.setSDRAMNibble(True)
   data = np.zeros(256,dtype=np.uint8)
   for i in np.arange(len(data)):
      data[i] = i;
   client.writeToSDRAM(256,0,data)
   client.setSDRAMNibble(False)
   for i in np.arange(len(data)):
      data[i] = len(data) - i - 1;
   client.writeToSDRAM(256,0,data)
   dataOut = client.readFromSDRAM(256, 0)
   print('Test passed!')

def mediumTest():
   twoMegaWords = np.int32(2*1024*1024) #64Mb / 8 = 8MB / 4 bytes words = 2Mega words of 32bits
   eightBits = np.int32(2**8 - 1) #Max. value to be randomized
   rng=np.random.default_rng()
   allMemHigh = np.random.randint(0, eightBits, twoMegaWords)
   allMemLow = np.random.randint(0, eightBits, twoMegaWords)
     
   client = SDRAMSerialClient(serialPort='/dev/ttyUSB1')
   client.setDebugTransfers(False)
   if not client.isSDRAMReady():
      print('Cannot proceed with the test, since SDRAM controller responded as not being Ready for use')
      return;
   client.setSDRAMNibble(True)
   print('Writing high nibble')
   client.loadRange(0, np.int(0.5*1024*1024-1), allMemHigh)
   print('Writing low nibble')
   client.setSDRAMNibble(False)
   client.loadRange(0, np.int(0.5*1024*1024-1), allMemLow)
   dataRead = client.readRange(0, np.int(0.5*1024*1024-1))
   client.checkRange(0, np.int(0.5*1024*1024-1), allMemHigh, allMemLow, dataRead)
   print('Test passed!')

def fullTest():
   twoMegaWords = np.int32(2*1024*1024) #64Mb / 8 = 8MB / 4 bytes words = 2Mega words of 32bits
   eightBits = np.int32(2**8 - 1) #Max. value to be randomized
   rng=np.random.default_rng()
   allMemHigh = np.random.randint(0, eightBits, twoMegaWords)
   allMemLow = np.random.randint(0, eightBits, twoMegaWords)
     
   client = SDRAMSerialClient(serialPort='/dev/ttyUSB1')
   client.setDebugTransfers(False)
   if not client.isSDRAMReady():
      print('Cannot proceed with the test, since SDRAM controller responded as not being Ready for use')
      return;
   client.setSDRAMNibble(True)
   print('Writing high nibble')
   client.loadRange(0, 2*1024*1024-1, allMemHigh)
   print('Writing low nibble')
   client.setSDRAMNibble(False)
   client.loadRange(0, 2*1024*1024-1, allMemLow)
   dataRead = client.readRange(0, 2*1024*1024-1)
   client.checkRange(0, 2*1024*1024-1, allMemHigh, allMemLow, dataRead)
   print('Test passed!')
   
if __name__ == "__main__":
   parser = argparse.ArgumentParser()
   t_arg = parser.add_argument('--test', dest='test', help='Select the type of test to run: simple, medium, full')
   #p_arg = parser.add_argument('--exec', dest='exec', help='Select an operation to be executed: loadAndValidateImage, loadImage, validateImage')

   args = parser.parse_args()
   if args.test == 'simple':
      simpleTest()
   if args.test == 'medium':
      mediumTest() 
   if args.test == 'full':
      fullTest()

