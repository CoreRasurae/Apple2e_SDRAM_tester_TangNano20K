//Copyright (C)2014-2023 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//GOWIN Version: V1.9.9 Beta-6
//Created Time: 2023-12-01 16:24:50
create_clock -name clk28M -period 35 -waveform {0 17} [get_pins {div5/clkdiv_inst/CLKOUT}]
create_clock -name clk -period 37 -waveform {0 18} [get_ports {clk}]
create_clock -name clk140M -period 7 -waveform {0 3} [get_pins {myrPLL/rpll_inst/CLKOUT}]
create_generated_clock -name clk2M -source [get_pins {div2_14M/clkdiv_inst/CLKOUT}] -master_clock clk14M -divide_by 7 -duty_cycle 14 [get_nets {clk2M}]
create_generated_clock -name clk14M -source [get_pins {div5/clkdiv_inst/CLKOUT}] -master_clock clk28M -divide_by 2 -duty_cycle 50 [get_pins {div2_14M/clkdiv_inst/CLKOUT}]
set_false_path -from [get_clocks {clk}] -to [get_clocks {clk2M}] 
set_false_path -from [get_clocks {clk2M}] -to [get_clocks {clk}] 
