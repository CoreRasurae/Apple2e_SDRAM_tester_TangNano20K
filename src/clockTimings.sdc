//Copyright (C)2014-2023 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//GOWIN Version: V1.9.9 Beta-6
//Created Time: 2023-11-29 17:38:39
create_clock -name clk -period 37 -waveform {0 18} [get_ports {clk}]
create_clock -name clk112M -period 8.94 -waveform {0 4.47} [get_pins {myrPLL/rpll_inst/CLKOUT}]
create_clock -name clk8M -period 125.156 -waveform {0 62.578} [get_pins {myrPLL/rpll_inst/CLKOUTD}]
set_false_path -from [get_clocks {clk}] -to [get_clocks {clk8M}] 
set_false_path -from [get_clocks {clk8M}] -to [get_clocks {clk}] 
