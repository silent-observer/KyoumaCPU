## Generated SDC file "Top.sdc"

## Copyright (C) 2018  Intel Corporation. All rights reserved.
## Your use of Intel Corporation's design tools, logic functions 
## and other software and tools, and its AMPP partner logic 
## functions, and any output files from any of the foregoing 
## (including device programming or simulation files), and any 
## associated documentation or information are expressly subject 
## to the terms and conditions of the Intel Program License 
## Subscription Agreement, the Intel Quartus Prime License Agreement,
## the Intel FPGA IP License Agreement, or other applicable license
## agreement, including, without limitation, that your use is for
## the sole purpose of programming logic devices manufactured by
## Intel and sold by Intel or its authorized distributors.  Please
## refer to the applicable agreement for further details.


## VENDOR  "Altera"
## PROGRAM "Quartus Prime"
## VERSION "Version 18.1.0 Build 625 09/12/2018 SJ Lite Edition"

## DATE    "Sun Aug 11 15:59:46 2019"

##
## DEVICE  "EP4CE6E22C6"
##


#**************************************************************
# Time Information
#**************************************************************

set_time_format -unit ns -decimal_places 3



#**************************************************************
# Create Clock
#**************************************************************

create_clock -name {clock} -period 20.000 -waveform { 0.000 10.000 } [get_ports {clk}]


#**************************************************************
# Create Generated Clock
#**************************************************************



#**************************************************************
# Set Clock Latency
#**************************************************************



#**************************************************************
# Set Clock Uncertainty
#**************************************************************



#**************************************************************
# Set Input Delay
#**************************************************************



#**************************************************************
# Set Output Delay
#**************************************************************



#**************************************************************
# Set Clock Groups
#**************************************************************



#**************************************************************
# Set False Path
#**************************************************************

set_false_path -from [get_ports {rst}] 
set_false_path -to [get_ports {r1[0] r1[1] r1[2] r1[3] r1[4] r1[5] r1[6] r1[7] r1[8] r1[9] r1[10] r1[11] r1[12] r1[13] r1[14] r1[15] r1[16] r1[17] r1[18] r1[19] r1[20] r1[21] r1[22] r1[23] r1[24] r1[25] r1[26] r1[27] r1[28] r1[29] r1[30] r1[31]}]
set_false_path -to [get_ports {addr[0] addr[1] addr[2] addr[3] addr[4] addr[5] addr[6] addr[7] addr[8] addr[9] addr[10] addr[11] addr[12] addr[13] addr[14] addr[15] addr[16] addr[17] addr[18] addr[19] addr[20] addr[21] addr[22] addr[23] addr[24] addr[25] addr[26] addr[27] addr[28] addr[29] addr[30] addr[31]}]


#**************************************************************
# Set Multicycle Path
#**************************************************************


#**************************************************************
# Set Maximum Delay
#**************************************************************



#**************************************************************
# Set Minimum Delay
#**************************************************************



#**************************************************************
# Set Input Transition
#**************************************************************

