# Apple2e_SDRAM_tester_TangNano20K
Apple2E SDRAM controller tester for the Tang Nano 20K. The intent is to validate the SDRAM controller from the Apple 2E core against the SDRAM in the Tang Nano 20K.

- It currently writes two bytes E0FE in two nibbles (one nibble at each two CPU cycles with CLK14M) of SDRAM at address 0.
- After writing it reads back the bytes written at address 0
- Finally it reads the word composed by two bytes at address 1
