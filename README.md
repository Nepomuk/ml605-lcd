ML605 LCD control module
========================

With this simple module you should be able to display your stuff on the LCD screen which comes with the Xilinx ML605 development board. The ML605 has a Displaytech S162D LCD soldiered and uses a Virtex 6 FPGA

Installation
------------

Just import the .xise file as a project in the Xilinx ISE. At least with version 13.4 under Linux it is compiling.

If not you can always look at the .vhd files to see what should happen and import the modules into your project.

Usage
-----

For future versions there will be a mode selector, that chooses what to display. Until now you can only display, that the firmware is loaded and the the uptime.

The process `what_to_display` shows you, how you display something. The characters are basically stored in two arrays for the two lines. Each character is encoded via the specifics given by the [S162D documentation](http://www.displaytech-us.com/16x2-character-lcd-displays-d), but generally you can just use the ASCII encoding in the range of 0x20 to 0x7d.

There is a function `to_bcd` which converts an std_logic_vector with 10 bits into a std_logic_vector, where the decimal numbers are put into 4 bit blocks.

Known Bugs
----------

* When you boot the firmware the first time, the display doesn't work. You have to reload the firmware via button (not by turning it off and on again).
