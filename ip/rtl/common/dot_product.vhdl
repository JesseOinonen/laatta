--------------------------------------
-- Laatta GPU
-- Dot product module
-- Author: Jesse Oinonen
--------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library work;
use work.laatta_pkg.all;

entity dot_product is
    generic (
        VEC_LEN : positive := 4;   -- dot-product length (MVP=4, normal/light=3)
        MUL_LAT : natural  := 1;   -- fp_mul pipeline depth
        ADD_LAT : natural  := 3    -- fp_add pipeline depth
    );
    port (
        clk        : in  std_logic;
        rst_n      : in  std_logic;
        a          : in  slv_array(0 to VEC_LEN-1);
        b          : in  slv_array(0 to VEC_LEN-1);
        valid_in   : in  std_logic;
        result     : out std_logic_vector(31 downto 0);
        valid_out  : out std_logic
    );
end entity;

architecture RTL of dot_product is
    constant LEVELS : natural := clog2(VEC_LEN);
    signal prod     : slv_array(0 to VEC_LEN-1);
    -- tree nodes: node(0)=products, node(LEVELS)(0)=final result
    type node_t is array (0 to LEVELS) of slv_array(0 to VEC_LEN-1);
    signal node     : node_t;
    signal vshift   : std_logic_vector(MUL_LAT + LEVELS*ADD_LAT - 1 downto 0);
begin

    -----------------------
    -- VEC_LEN multipliers 
    gen_mul: for i in 0 to VEC_LEN-1 generate
        mul_i : entity work.fp_mul_wrapper
            port map ( 
                       clk        => clk, 
                       rst_n      => rst_n,
                       a_in       => a(i),
                       b_in       => b(i),
                       valid_in   => valid_in,
                       result_out => prod(i),
                       valid_out  => open     -- valid tracked centrally below
            );
    end generate;

    node(0) <= prod;

    -------------------------------------------------------------
    -- adder tree: level lvl -> lvl+1, VEC_LEN/2^(lvl+1) adders 
    gen_lvl: for lvl in 0 to LEVELS-1 generate
        gen_add: for i in 0 to (VEC_LEN/(2**(lvl+1)))-1 generate
            add_i : entity work.fp_add_wrapper
                port map ( 
                           clk        => clk, 
                           rst_n      => rst_n,
                           a_in       => node(lvl)(2*i),
                           b_in       => node(lvl)(2*i+1),
                           valid_in   => '0',
                           result_out => node(lvl+1)(i),
                           valid_out  => open
                );
        end generate;
    end generate;

    result <= node(LEVELS)(0);

    -------------------------------------------------------------------
    -- valid: one shift over the whole latency (mul + tree levels*add)
    process(clk, rst_n) begin
        if rst_n = '0' then 
            vshift <= (others => '0');
        elsif rising_edge(clk) then 
            vshift <= vshift(vshift'high-1 downto 0) & valid_in;
        end if;
    end process;

    valid_out <= vshift(vshift'high);

end architecture;
