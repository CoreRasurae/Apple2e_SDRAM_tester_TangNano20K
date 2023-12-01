//Copyright (C)2014-2023 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//GOWIN Version: V1.9.9 Beta-6
//Created Time: 2023-12-01 16:02:58
create_clock -name clk -period 37 -waveform {0 18} [get_ports {clk}]
create_clock -name clk112M -period 8.929 -waveform {0 4} [get_pins {myrPLL/rpll_inst/CLKOUT}]
create_generated_clock -name clk8M -source [get_pins {myrPLL/rpll_inst/CLKOUT}] -master_clock clk112M -divide_by 14 [get_pins {myrPLL/rpll_inst/CLKOUTD}]
set_false_path -from [get_clocks {clk}] -to [get_clocks {clk8M}] 
set_false_path -from [get_clocks {clk8M}] -to [get_clocks {clk}] 
