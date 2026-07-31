--------------------------------------------------------------------------------
--                                  out_ieee
--                    (OutputIEEE_8_23_to_8_23_comb_uid2)
-- VHDL generated for DummyFPGA @ 0MHz
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: F. Ferrandi  (2009-2012)
--------------------------------------------------------------------------------
-- combinatorial
-- Clock period (ns): inf
-- Target frequency (MHz): 0
-- Input signals: X
-- Output signals: R
--  approx. input signal timings: X: 0.000000ns
--  approx. output signal timings: R: 0.100000ns

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity out_ieee is
    port (X : in  std_logic_vector(8+23+2 downto 0);
          R : out  std_logic_vector(31 downto 0)   );
end entity;

architecture arch of out_ieee is
signal fracX :  std_logic_vector(22 downto 0);
   -- timing of fracX: 0.000000ns
signal exnX :  std_logic_vector(1 downto 0);
   -- timing of exnX: 0.000000ns
signal expX :  std_logic_vector(7 downto 0);
   -- timing of expX: 0.000000ns
signal sX :  std_logic;
   -- timing of sX: 0.050000ns
signal expZero :  std_logic;
   -- timing of expZero: 0.050000ns
signal fracR :  std_logic_vector(22 downto 0);
   -- timing of fracR: 0.100000ns
signal expR :  std_logic_vector(7 downto 0);
   -- timing of expR: 0.050000ns
begin
   fracX  <= X(22 downto 0);
   exnX  <= X(33 downto 32);
   expX  <= X(30 downto 23);
   sX  <= X(31) when (exnX = "01" or exnX = "10" or exnX = "00") else '0';
   expZero  <= '1' when expX = (7 downto 0 => '0') else '0';
   -- since we have one more exponent value than IEEE (field 0...0, value emin-1),
   -- we can represent subnormal numbers whose mantissa field begins with a 1
   fracR <= 
      "00000000000000000000000" when (exnX = "00") else
      '1' & fracX(22 downto 1) & "" when (expZero = '1' and exnX = "01") else
      fracX  & "" when (exnX = "01") else
      "0000000000000000000000" & exnX(0);
   expR <=  
      (7 downto 0 => '0') when (exnX = "00") else
      expX when (exnX = "01") else 
      (7 downto 0 => '1');
   R <= sX & expR & fracR; 
end architecture;

