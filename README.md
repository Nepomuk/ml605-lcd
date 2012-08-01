ML605 LCD control module
========================

With this simple module you should be able to display your stuff on the LCD screen which comes with the Xilinx ML605 development board. The ML605 has a Displaytech S162D LCD soldiered.

Installation
------------

Just import the .xise file as a project in the Xilinx ISE.

Usage
-----

For future versions there will be a mode selector, that chooses what to display. Until now you can only display, that the firmware is loaded and the the uptime.

The process `what_to_display` shows you, how you display something. The characters are basically stored in two arrays for the two lines. Each character is encoded via the specifics given by the [S162D documentation](http://www.displaytech-us.com/16x2-character-lcd-displays-d), but generally you can just use the ASCII encoding in the range of 0x20 to 0x7d.

Known Bugs
----------

* When you boot the firmware the first time, the display doesn't work. You have to reload the firmware via button (not by turning it off and on again).
* Also there is a bug, that sometimes after a reset there is still rubbish on the screen. Both is presumably due to some timing issues.
* Over the time some of the _fixed_ LCD fields will switch in the fourth most significant bit (for instance difference between 0x61 (=a) and 0x71 (=q)
