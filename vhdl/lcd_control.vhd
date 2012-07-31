----------------------------------------------------------------------------------
-- Company:		IKP-1, FZ Jlich
-- Engineer:	Andre Goerres
--
-- Create Date:    16:30:05 27-Feb-2012
-- Design Name:
-- Module Name:    LCD Control
-- Project Name:
-- Target Devices:
-- Tool versions:
-- Description: A module to print out stuff on the LCD. Modify to get your
-- 				 information on it. Currently it has two modes:
--                 0) [default]
--							....,....,....,.
--					 		Firmware loaded
--							online: ##:##:##
--
--                 1)
--							....,....,....,.
--                   [custom content]
-- 						[from software]
--							
--              This is based on a module I found somewhere. Unfortunately
--              I can't remember where I found it.
--
-- Dependencies:
--
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity lcd_control is 
   port ( 
       RST			: in std_logic;								-- Reset
       CLK			: in std_logic;								-- Clock, 200 MHz (was 66 MHz)
		 MODE			: in std_logic_vector (2 downto 0);		-- in which mode should the LCD operate? (see comments above)
       CONTROL		: out std_logic_vector (2 downto 0); 	-- (2): LCD_RS, (1): LCD_RW, (0): LCD_E
       SF_D			: out std_logic_vector (7 downto 4)		-- LCD data bus
	); 
end lcd_control; 



architecture lcd_control_arch of lcd_control is

	-- the state machine for displaying information on the LCD
	type state_type is ( waiting, init1,init2,init4,init5,init6,init7,init8, -- initialization
								lcd_idle,
								upper_line_pos, upper_line_char, lower_line_pos, lower_line_char,
								donestate);
	signal state,next_state		: state_type;
	signal state_flag				: std_logic := '0';
	signal exit_idle_flag		: std_logic := '1';
	
	-- We need two data vectors since the ML605-LCD has only
	-- four bits for the Data Bus.
	constant dual					: std_logic := '1';	-- set to 1 if want to do clock out dual nibbles on the lcd DB
	signal sf_d_temp				: std_logic_vector (7 downto 0) := "00000000";
	signal sf_d_short				: std_logic_vector (7 downto 4) := "0000";
	
	-- count minutes and seconds
	constant cycles_per_us     : integer := 200;
	signal count, count_temp	: integer := 0;
	signal second_counter		: integer range 0 to (cycles_per_us * 1000000) + 1 := 0;	-- 1s
	signal seconds_ones			: integer range 0 to 9 := 0;
	signal seconds_tens			: integer range 0 to 5 := 0;
	signal minutes_ones			: integer range 0 to 9 := 0;
	signal minutes_tens			: integer range 0 to 5 := 0;
	signal hours_ones				: integer range 0 to 9 := 0;
	signal hours_tens				: integer range 0 to 9 := 0;
	
	-- the basis for the control-signal
	signal control_base			: std_logic_vector (2 downto 0) := "000"; -- LCD_RS, LCD_RW, LCD_E

	-- different periods for waiting
	--   note: Sometimes it happenes, that the display is
	--         not initialized correctly and is displaying
	--         nothing. Don't know why...
	--         Waiting times matched to the 200 MHz clock
	--         and modified a bit accodring to what I
	--         understood from the manual.
	constant wait_dual_1                : integer := 10 * cycles_per_us;    -- was 10us (500 cycles);
	constant wait_dual_2                : integer := 20 * cycles_per_us;    -- was 20us (1000 cycles);
	constant wait_dual_3                : integer := 40 * cycles_per_us;    -- was 40us (2000 cycles);
	constant wait_dual_4                : integer := 60 * cycles_per_us;    -- was 60us (3000 cycles);
	constant wait_power_on              : integer := 15000 * cycles_per_us; -- was 15ms (750000 cycles);
	constant wait_data_exec             : integer := 200 * cycles_per_us;   -- was 200us (10000 cycles);
	constant wait_after_data_exec       : integer := 1000 * cycles_per_us;  -- was 4,2ms (210000 cycles);
	constant wait_after_data_exec_init  : integer := 6000 * cycles_per_us; -- was 8,4ms (420000 cycles);
	
	
	
------------------------ Character Definitions -----------------------------------
--
-- For the full list see S162D documentation.
--
-- Characters from 0x20 to 0x7d are according to the default ASCII codes with
-- one exception at 0x5c (the backslash is some japanese sign). To set a field,
-- use control_base = "100" and control = "101".
-- The positions are given by 0x80-0x8f for the first line and 0xc0-0xcf for
-- second line. Use control = "001" and control_base = "000" to set the position.
--	

	subtype lcd_char is std_logic_vector (7 downto 0);
	subtype lcd_pos  is std_logic_vector (7 downto 0);
	type lcd_line is array (15 downto 0) of lcd_char;
	
	signal upper_line       : lcd_line := (x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20");  -- 16x [blank];
	signal lower_line       : lcd_line := (x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20");  -- 16x [blank];
	signal line_pos         : integer range 0 to 15 := 0;
	signal line_pos_next    : integer range 0 to 15 := 0;
	signal line_pos_flag    : std_logic := '0';
	
	
begin 


	run : process (CLK, count, state, sf_d_temp, sf_d_short, control_base, mode,
						--chars_buffer,pos_buffer,--state_char_pos,
						line_pos, upper_line, lower_line, exit_idle_flag,
						seconds_ones,seconds_tens, minutes_ones,minutes_tens, hours_ones,hours_tens) is
		
	begin
		control_base <= "100";	-- default control is RS=1
		line_pos_flag <= '0';
		line_pos_next <= 0;

		
		case state is
		
------------------------ Initialization Starts -----------------------------------
			
			when waiting =>
				sf_d_temp <= "00000000";
				control <= "000"; 			-- clear
				if 	(count >= wait_power_on) then
						next_state <= init1;   state_flag <= '1';  
				else	next_state <= waiting; state_flag <= '0';
				end if;
				
			when init1 => 
				sf_d_temp <= "00110000";	--reset
				if 	(count = wait_after_data_exec_init) then
						next_state <= init2;	control <= "001"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec_init) then
						next_state <= init1; control <= "000"; state_flag <= '0';  
				else	next_state <= init1; control <= "001"; state_flag <= '0';
				end if;
				
			when init2 => 
				sf_d_temp <= "00110000";	--reset	
				if 	(count = wait_after_data_exec) then
						next_state <= init4;	control <= "001"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= init2; control <= "000"; state_flag <= '0';  
				else  next_state <= init2; control <= "001"; state_flag <= '0';
				end if;
			
			-- This init step was in the module I found but I can't find
			-- a reason in the documentation, why this should be in. It
			-- actually works without it.
--			when init3 =>
--				sf_d_temp <= "00110000";	 --reset
--				if 	(count = wait_after_data_exec_init) then
--						next_state <= init4;	control <= "001"; state_flag <= '1';
--				elsif (count > wait_data_exec AND count <= wait_after_data_exec_init) then
--						next_state <= init3; control <= "000"; state_flag <= '0';  
--				else	next_state <= init3; control <= "001"; state_flag <= '0';
--				end if;
				
			when init4 =>
				sf_d_temp <= "00101100";	-- set 4bit interface, 2 lines and 5*10 dots
				control_base <= "000";
				if 	(count = wait_after_data_exec) then
						next_state <= init5; control <= "001"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= init4; control <= "000"; state_flag <= '0';  
				else	next_state <= init4; control <= "001"; state_flag <= '0';
				end if;
				
			when init5 =>
				sf_d_temp <= "00001000"; 	-- display off
				control_base <= "000";
				if 	(count = wait_after_data_exec) then
						next_state <= init6; control <= "001"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= init5; control <= "000"; state_flag <= '0';  
				else	next_state <= init5; control <= "001"; state_flag <= '0';
				end if;
				
			when init6 =>
				sf_d_temp <= "00000001";	 -- clear display
				control_base <= "000";		
				if 	(count = wait_after_data_exec) then
						next_state <= init7; control <= "001"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= init6; control <= "000"; state_flag <= '0';  
				else	next_state <= init6; control <= "001"; state_flag <= '0';
				end if;
				
			when init7 =>
				sf_d_temp <= "00000110";	 -- entry mode set ID=1, S=0
				control_base <= "000";
				if 	(count = wait_after_data_exec) then
						next_state <= init8; control <= "001"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= init7; control <= "000"; state_flag <= '0';  
				else	next_state <= init7; control <= "001"; state_flag <= '0';
				end if;
				
			when init8 =>
				sf_d_temp <= "00001100";	 --Display: disp on, cursor off, blink off
				control_base <= "000";
				if 	(count = wait_after_data_exec) then
						next_state <= lcd_idle; control <= "001"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= init8; control <= "000"; state_flag <= '0';  
				else	next_state <= init8; control <= "001"; state_flag <= '0';
				end if;
				
------------------------- Initialization Ends ------------------------------------


----------------------- idle state for the LCD -----------------------------------
			when lcd_idle =>
				sf_d_temp <= "00000000";
				control_base <= "000";
				if 	(count = wait_after_data_exec) then
						if (exit_idle_flag = '1') then
							next_state <= upper_line_pos;
						else
							next_state <= lcd_idle;
						end if;
						control <= "001"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= lcd_idle; control <= "000"; state_flag <= '0';  
				else	next_state <= lcd_idle; control <= "001"; state_flag <= '0';
				end if;




----------------- Write out what is stored in the line arrays --------------------

			when upper_line_pos =>
				sf_d_temp <= x"80"; -- set address 
				control_base <= "000";
				if 	(count = wait_after_data_exec) then
						next_state <= upper_line_char;
						state_flag <= '1';
						line_pos_next <= 0;
						line_pos_flag <= '1';
						control <= "001";
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= upper_line_pos;
						state_flag <= '0';
						line_pos_next <= 0;
						line_pos_flag <= '0';
						control <= "000";
				else	next_state <= upper_line_pos;
						state_flag <= '0';
						line_pos_next <= 0;
						line_pos_flag <= '0';
						control <= "001";
				end if;

			when upper_line_char =>
				sf_d_temp <= upper_line(line_pos);
				if 	(count = wait_after_data_exec) then
						if ( line_pos = 15 ) then  -- reached the end
							next_state <= lower_line_pos;
							line_pos_next <= 0;
						else
							next_state <= upper_line_char;
							line_pos_next <= line_pos + 1;
						end if;
						line_pos_flag <= '1';
						control <= "101"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= upper_line_char;
						state_flag <= '0';
						line_pos_flag <= '0';
						line_pos_next <= line_pos;
						control <= "100";
				else	next_state <= upper_line_char;
						state_flag <= '0';
						line_pos_flag <= '0';
						line_pos_next <= line_pos;
						control <= "101";
				end if;
				
				
			when lower_line_pos =>
				sf_d_temp <= x"c0"; -- set address 
				control_base <= "000";
				if 	(count = wait_after_data_exec) then
						next_state <= lower_line_char;
						state_flag <= '1';
						line_pos_next <= 0;
						line_pos_flag <= '1';
						control <= "001";
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= lower_line_pos;
						state_flag <= '0'; 
						line_pos_next <= 0;
						line_pos_flag <= '0'; 
						control <= "000";
				else	next_state <= lower_line_pos;
						state_flag <= '0';
						line_pos_next <= 0;
						line_pos_flag <= '0';
						control <= "001";
				end if;

			when lower_line_char =>
				sf_d_temp <= lower_line(line_pos);
				if 	(count = wait_after_data_exec) then
						if ( line_pos = 15 ) then  -- reached the end
							next_state <= upper_line_pos;
							line_pos_next <= 0;
						else
							next_state <= lower_line_char;
							line_pos_next <= line_pos + 1;
						end if;
						line_pos_flag <= '1';
						control <= "101"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= lower_line_char;
						state_flag <= '0';
						line_pos_flag <= '0';
						line_pos_next <= line_pos;
						control <= "100";
				else	next_state <= lower_line_char;
						state_flag <= '0';
						line_pos_flag <= '0';
						line_pos_next <= line_pos;
						control <= "101";
				end if;


----------------------- finished state -------------------------------------------
			when donestate =>
				control <= "100";
				sf_d_temp <= "00000000";
				if 	(count = wait_after_data_exec) then
						next_state <= donestate; state_flag <= '1';
				else	next_state <= donestate; state_flag <= '0';
				end if;
				
				
		end case;
	
	
	
		-- if dual mode, then strobe out the high nibble before setting to low nibble, but if not dual, then just put out the high nibble
		
		if (dual = '1') then
			if (count <= wait_dual_1) then
				sf_d_short <= sf_d_temp(7 downto 4);
				control<= control_base or "001";
			elsif (count > wait_dual_1 and count <= wait_dual_2) then
				sf_d_short <= sf_d_temp(7 downto 4);
				control<= control_base;
			elsif (count > wait_dual_2 and count <= wait_dual_3) then
				sf_d_short <= sf_d_temp(7 downto 4);
				control<= control_base or "001";
			elsif (count > wait_dual_3 and count <= wait_dual_4) then
				sf_d_short <= sf_d_temp(7 downto 4); 
				control<= control_base or "001";
			else
				sf_d_short <= sf_d_temp(3 downto 0);
			end if;
		else
			sf_d_short <= sf_d_temp(7 downto 4);
		end if;
		
	end process run;
	
	
	what_to_display : process (RST, CLK, mode, hours_tens, hours_ones, minutes_tens, minutes_ones, seconds_tens, seconds_ones ) is
	begin
		if rising_edge(CLK) then
			if (RST = '1') then
				upper_line <= (x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20");  -- 16x [blank]
				lower_line <= (x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20");  -- 16x [blank]
			elsif mode = "000" then
				upper_line( 0) <= x"46"; -- F
				upper_line( 1) <= x"69"; -- i
				upper_line( 2) <= x"72"; -- r
				upper_line( 3) <= x"6d"; -- m
				upper_line( 4) <= x"77"; -- w
				upper_line( 5) <= x"61"; -- a
				upper_line( 6) <= x"72"; -- r
				upper_line( 7) <= x"65"; -- e
				upper_line( 8) <= x"20"; -- [blank]
				upper_line( 9) <= x"6c"; -- l
				upper_line(10) <= x"6f"; -- o
				upper_line(11) <= x"61"; -- a
				upper_line(12) <= x"64"; -- d
				upper_line(13) <= x"65"; -- e
				upper_line(14) <= x"64"; -- d
				upper_line(15) <= x"21"; -- !
				
				lower_line( 0) <= x"6f"; -- o
				lower_line( 1) <= x"6e"; -- n
				lower_line( 2) <= x"6c"; -- l
				lower_line( 3) <= x"69"; -- i
				lower_line( 4) <= x"6e"; -- n
				lower_line( 5) <= x"65"; -- e
				lower_line( 6) <= x"3a"; -- :
				lower_line( 7) <= x"20"; -- [blank]
				lower_line( 8) <= x"30" or std_logic_vector(to_unsigned(hours_tens, 4)); -- [0..9]
				lower_line( 9) <= x"30" or std_logic_vector(to_unsigned(hours_ones, 4)); -- [0..9]
				lower_line(10) <= x"3a"; -- :
				lower_line(11) <= x"30" or std_logic_vector(to_unsigned(minutes_tens, 4)); -- [0..5]
				lower_line(12) <= x"30" or std_logic_vector(to_unsigned(minutes_ones, 4)); -- [0..9]
				lower_line(13) <= x"3a"; -- :
				lower_line(14) <= x"30" or std_logic_vector(to_unsigned(seconds_tens, 4)); -- [0..5]
				lower_line(15) <= x"30" or std_logic_vector(to_unsigned(seconds_ones, 4)); -- [0..9]
			end if;
		end if;
	end process what_to_display;
	
	
	clock : process (RST, CLK) is
		variable tmp_seconds_ones : integer range 0 to 10;
		variable tmp_seconds_tens : integer range 0 to 6;
		variable tmp_minutes_ones : integer range 0 to 10;
		variable tmp_minutes_tens : integer range 0 to 6;
		variable tmp_hours_ones : integer range 0 to 10;
		variable tmp_hours_tens : integer range 0 to 10;
	begin
		if (rising_edge(CLK)) then
			if (RST = '1') then
				second_counter <= 0;
				seconds_ones <= 0;
				seconds_tens <= 0;
				minutes_ones <= 0;
				minutes_tens <= 0;
				hours_ones <= 0;
				hours_tens <= 0;
			elsif (second_counter = cycles_per_us * 1000000) then
				-- get the next number for each digit
				tmp_seconds_ones := seconds_ones + 1;
				if (tmp_seconds_ones = 10) then
					tmp_seconds_ones := 0;
					tmp_seconds_tens := seconds_tens + 1;
				end if;
				if (tmp_seconds_tens = 6) then
					tmp_seconds_tens := 0;
					tmp_minutes_ones := minutes_ones + 1;
				end if;
				if (tmp_minutes_ones = 10) then
					tmp_minutes_ones := 0;
					tmp_minutes_tens := minutes_tens + 1;
				end if;
				if (tmp_minutes_tens = 6) then
					tmp_minutes_tens := 0;
					tmp_hours_ones := hours_ones + 1;
				end if;
				if (tmp_hours_ones = 10) then
					tmp_hours_ones := 0;
					tmp_hours_tens := hours_tens + 1;
				end if;
				
				-- we have reached the end of our cycle, reset
				if (tmp_hours_tens = 10) then
					tmp_seconds_ones := 0;
					tmp_seconds_tens := 0;
					tmp_minutes_ones := 0;
					tmp_minutes_tens := 0;
					tmp_hours_ones := 0;
					tmp_hours_tens := 0;
				end if;
				
				-- set the signals
				second_counter <= 0;
				seconds_ones <= tmp_seconds_ones;
				seconds_tens <= tmp_seconds_tens;
				minutes_ones <= tmp_minutes_ones;
				minutes_tens <= tmp_minutes_tens;
				hours_ones <= tmp_hours_ones;
				hours_tens <= tmp_hours_tens;
			else
				second_counter <= second_counter + 1;
			end if;
		end if;
	end process clock;
	
	
	timing : process (RST, CLK) is
	begin
		if	(rising_edge(CLK)) then
			sf_d <= sf_d_short;
			count <= count_temp;
			if (RST = '1') then
				state <= waiting;
				count_temp <= 0;
			elsif (state_flag = '1') then
				state <= next_state;
				count_temp <= 0;
			else
				state <= next_state;
				count_temp <= count_temp + 1;
			end if;
			
			if ( RST = '1' ) then
				line_pos <= 0;
			elsif ( line_pos_flag = '1' ) then
				line_pos <= line_pos_next;
			else
				line_pos <= line_pos;
			end if;
		end if;
	end process timing;
	

end lcd_control_arch;  