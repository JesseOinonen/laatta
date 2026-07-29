--------------------------------------
-- Laatta GPU
-- Geometry Fetch IP
-- Author: Jesse Oinonen
--------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library work;
use work.laatta_pkg.all;

entity geometry_fetch is
    port ( clk_in           : in  std_logic;
           rst_n            : in  std_logic;
           -- AXI4 READ ADDRESS CHANNEL
           araddr           : out std_logic_vector(C_AXI_ADDR_W-1 downto 0);
           arvalid          : out std_logic;
           arready          : in  std_logic;
           arsize           : out std_logic_vector(2 downto 0);
           arburst          : out std_logic_vector(1 downto 0);
           arlen            : out std_logic_vector(7 downto 0);
           -- AXI4 READ DATA CHANNEL
           rdata            : in  std_logic_vector(C_AXI_DATA_W-1 downto 0);
           rvalid           : in  std_logic;
           rready           : out std_logic;
           rlast            : in  std_logic;
           rresp            : in  std_logic_vector(1 downto 0);
           -- AXI stream signals
           tdata            : out std_logic_vector(C_AXIS_DATA_W-1 downto 0);
           tvalid           : out std_logic;
           tready           : in  std_logic;
           tlast            : out std_logic;
           -- Control signals
           start            : in  std_logic  -- Start pulse to begin fetching a draw descriptor, index buffer and vertex buffer.
        );
end geometry_fetch;

architecture RTL of geometry_fetch is
    type ar_state_t is (
        IDLE,
        DESCR,
        IDX,
        VERTEX
    );
    signal arstate      : ar_state_t;
    signal data_state   : ar_state_t;

    signal rdata_int    : std_logic_vector(C_AXI_DATA_W-1 downto 0); -- internal read data
    signal rdata_err    : std_logic; -- internal error flag for read data channe
    signal busy         : std_logic; -- internal busy flag
    signal idx_cntr     : unsigned(31 downto 0); -- index counter

    type beat_array_t is array (0 to 3) of std_logic_vector(63 downto 0);
    signal beats        : beat_array_t;
    signal beat_idx     : integer range 0 to 3;
    signal index        : std_logic_vector(31 downto 0); -- current index value for vertex buffer address calculation

    signal desc         : draw_descriptor_t;
    signal vertex_data  : std_logic_vector(255 downto 0);
    signal vertex_valid : std_logic;
    
    signal clk          : std_logic;
    signal ce           : std_logic;
begin

    ce <= start or busy;

    cg_inst : entity work.cg
        port map (
            clk     => clk_in,
            en      => ce,
            clk_out => clk
        );

    r_channel : process(clk, rst_n)
    begin
        if rst_n = '0' then
            rdata_int    <= (others => '0');
            rdata_err    <= '0';
            beat_idx     <= 0;
            index        <= (others => '0');
            vertex_data  <= (others => '0');
            vertex_valid <= '0';
        elsif rising_edge(clk) then
            rdata_int <= (others => '0');
            if rresp /= RESP_OKAY then
                rdata_err <= '1';
            elsif rvalid = '1' and rready = '1' then
                vertex_valid <= '0';
                case data_state is
                    when DESCR =>
                        beat_idx <= beat_idx + 1;
                        if rlast = '1' then
                            desc     <= unpack_descriptor(beats(0), beats(1), beats(2), beats(3));
                            beat_idx <= 0;
                        else
                            beats(beat_idx) <= rdata;
                        end if;
                    when IDX =>
                        index <= rdata(31 downto 0);
                    when VERTEX =>
                        beat_idx <= beat_idx + 1;
                        if rlast = '1' then
                            vertex_data  <= beats(3) & beats(2) & beats(1) & beats(0);
                            vertex_valid <= '1';
                            beat_idx     <= 0;
                        else
                            beats(beat_idx) <= rdata;
                        end if;
                    when others =>
                        -- TBD NOT IMPLEMENTED
                end case;
            end if;
        end if;
    end process r_channel;

    ---------------------------------------
    -- sequencer for read address generation
    sequencer : process(clk, rst_n)
    begin
        if rst_n = '0' then
            araddr     <= (others => '0');
            arvalid    <= '0';
            arsize     <= (others => '0');
            arburst    <= (others => '0');
            arlen      <= (others => '0');
            arstate    <= IDLE;
            data_state <= IDLE;
            rready     <= '0';
            idx_cntr   <= (others => '0');
        elsif rising_edge(clk) then
            data_state <= arstate;
            case arstate is
                when DESCR =>
                    araddr  <= std_logic_vector(CMD_BASE); -- Base address for descriptor
                    arvalid <= '1';
                    arsize  <= AXSIZE_8B; -- 64-bit beat size
                    arburst <= AXBURST_INCR; -- Incrementing burst
                    arlen   <= std_logic_vector(to_unsigned(DESC_BEATS - 1, 8)); -- Number of beats for descriptor
                    if arready = '1' then -- Next address once the current one is accepted
                        arstate <= IDX;
                        arvalid <= '0';
                    end if;
                when IDX =>
                    araddr   <= std_logic_vector(desc.ib_base + idx_cntr * 4);
                    arlen    <= (others => '0'); -- Single beat for index buffer
                    arsize   <= AXSIZE_4B; -- 32-bit beat size
                    arburst  <= AXBURST_INCR; -- Incrementing burst
                    arvalid  <= '1';
                    idx_cntr <= idx_cntr + 1;
                    if arready = '1' then -- Next address once the current one is accepted
                        arstate <= VERTEX;
                        arvalid <= '0';
                    end if;
                when VERTEX =>
                    araddr <= std_logic_vector(resize(desc.vb_base + unsigned(index) * desc.vertex_stride, C_AXI_ADDR_W));
                    arlen  <= std_logic_vector(to_unsigned(VERTEX_BEATS - 1, 8)); -- Number of beats for vertex buffer
                    arsize <= AXSIZE_8B; -- 64-bit beat size
                    arburst <= AXBURST_INCR; -- Incrementing burst
                    arvalid <= '1';
                    if arready = '1' then -- Next address once the current one is accepted
                        if rlast = '1' and (idx_cntr = desc.index_count - 1) then
                            arvalid <= '0';
                            arstate <= IDLE;
                        else
                            arvalid <= '0';
                            arstate <= IDX;
                        end if;
                    end if;
                when others => -- IDLE
                    rready <= '0';
                    busy   <= '0';
                    if start = '1' then
                        arstate <= DESCR;
                        busy    <= '1';
                        rready  <= '1';
                    end if;
            end case;      
        end if;
    end process sequencer;

    axi_stream : process(clk, rst_n)
    begin
        if rst_n = '0' then
            tdata  <= (others => '0');
            tvalid <= '0';
            tlast  <= '0';
        elsif rising_edge(clk) then
            tvalid <= '0';
            if vertex_valid = '1' then
                tdata  <= vertex_data;
                tvalid <= '1';
                tlast  <= '0';
                if idx_cntr = desc.index_count - 1 then
                    tlast  <= '1';
                end if;
            end if;
        end if;
    end process axi_stream;

end RTL;