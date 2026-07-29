--------------------------------------
-- Common IP
-- AXI4 Read FSM
-- Author: Jesse Oinonen
--------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library work;
use work.laatta_pkg.all;

entity axi4_read is
    generic ( C_AXI_ADDR_W : integer := 32;
              C_AXI_DATA_W : integer := 64 );
    port ( clk_in           : in  std_logic;
           rst_n            : in  std_logic;
           ce               : in  std_logic;
           -- AXI4 READ ADDRESS CHANNEL
           araddr           : out std_logic_vector(C_AXI_ADDR_W-1 downto 0);
           arvalid          : out std_logic;
           arready          : in  std_logic;
           arsize           : out std_logic_vector(2 downto 0);
           arburst          : out std_logic_vector(1 downto 0);
           arlen            : out std_logic_vector(7 downto 0);
           arid             : out std_logic_vector(3 downto 0);  -- TBD NOT IMPLEMENTED
           -- AXI4 READ DATA CHANNEL
           rdata            : in  std_logic_vector(C_AXI_DATA_W-1 downto 0);
           rvalid           : in  std_logic;
           rready           : out std_logic;
           rlast            : in  std_logic;
           rresp            : in  std_logic_vector(1 downto 0);
           rid              : in  std_logic_vector(3 downto 0);  -- TBD NOT IMPLEMENTED
           -- Internal output signals
           araddr_int       : in  std_logic_vector(C_AXI_ADDR_W-1 downto 0); -- internal read address
           arvalid_int      : in  std_logic; -- internal read valid
           arsize_int       : in  std_logic_vector(2 downto 0); -- internal read size
           arburst_int      : in  std_logic_vector(1 downto 0); -- internal read burst type
           arlen_int        : in  std_logic_vector(7 downto 0); -- internal read burst length
           rdata_int        : out std_logic_vector(C_AXI_DATA_W-1 downto 0); -- internal read data
           rdata_err        : out std_logic; -- internal error flag for read data channe
           rdone            : out std_logic; -- internal flag for read data channel done
           axi4_state       : out axi4_state_t
        );
end axi4_read;

architecture RTL of axi4_read is
    signal clk : std_logic;
begin

    ---------------------------------------
    -- Clock gate for AXI4 read FSM
    cg_inst : entity work.cg
        port map (
            clk         => clk_in,
            en          => ce,
            clk_out     => clk
        );
    
    ---------------------------------------
    -- AXI4 read FSM
    axi4_read_fsm : process(clk, rst_n)
    begin
        if rst_n = '0' then
            axi4_state <= IDLE;
            araddr     <= (others => '0');
            arvalid    <= '0';
            rready     <= '0';
            rdata_err  <= '0';
            rdone      <= '0';
            arsize     <= (others => '0');
            arburst    <= (others => '0');
            arlen      <= (others => '0');
        elsif rising_edge(clk) then
            rdone      <= '0'; -- rdone pulse for sequencer so the signals change only after the read is done
            case axi4_state is 
                when SEND_AR =>
                    if arready = '1' and arvalid = '1' then
                        axi4_state <= READ_DATA;
                        arvalid    <= '0';
                        rready     <= '1';
                    end if;
                when READ_DATA =>
                    if rvalid = '1' and rready = '1' then
                        if rlast = '1' then
                            axi4_state <= IDLE;
                            rready     <= '0';
                            rdone      <= '1';
                        else
                            axi4_state <= READ_DATA;
                        end if;
                    end if;
                    if rresp /= RESP_OKAY then
                        -- Handle error response (not implemented in this snippet)
                        rdata_err <= '1';
                        axi4_state <= IDLE;
                        rready     <= '0';
                        rdone      <= '1';
                    end if;
                when others => -- IDLE state
                    arvalid <= '0';
                    rready  <= '0';
                    if arvalid_int = '1' then
                        axi4_state <= SEND_AR;
                        araddr     <= araddr_int;
                        arsize     <= arsize_int;
                        arburst    <= arburst_int;
                        arlen      <= arlen_int;
                    end if;
            end case;
        end if;
    end process axi4_read_fsm;

end RTL;