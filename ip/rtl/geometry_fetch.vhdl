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

    type beat_array_t is array (0 to 2) of std_logic_vector(63 downto 0);
    signal beats        : beat_array_t;
    signal beat_idx     : integer range 0 to 3;
    signal index        : std_logic_vector(31 downto 0); -- current index value for vertex buffer address calculation

    signal desc         : draw_descriptor_t;
    signal vertex_data  : std_logic_vector(255 downto 0);
    signal vertex_valid : std_logic;
    signal vertex_last  : std_logic;

    signal ar_capt      : std_logic;
    
    signal clk          : std_logic;
begin

    process(clk_in, rst_n)
    begin
        if rst_n = '0' then
            busy <= '0';
        elsif rising_edge(clk_in) then
            if start = '1' then
                busy <= '1';
            elsif vertex_last = '1' then
                busy <= '0';
            end if;
        end if;
    end process;

    cg_inst : entity work.cg
        port map (
            clk     => clk_in,
            en      => busy,
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
            vertex_last  <= '0';
        elsif rising_edge(clk) then
            if tvalid = '1' and tready = '1' then
                vertex_valid <= '0';
            end if;
            rdata_int <= (others => '0');
            if rresp /= RESP_OKAY then
                rdata_err <= '1';
            elsif rvalid = '1' and rready = '1' then
                vertex_last <= '0';
                case data_state is
                    when DESCR =>
                        beat_idx <= beat_idx + 1;
                        if rlast = '1' then
                            desc     <= unpack_descriptor(beats(0), beats(1), beats(2), rdata);
                            beat_idx <= 0;
                        else
                            beats(beat_idx) <= rdata;
                        end if;
                    when IDX =>
                        index <= rdata(31 downto 0);
                    when VERTEX =>
                        beat_idx <= beat_idx + 1;
                        if rlast = '1' then
                            vertex_data  <= rdata & beats(2) & beats(1) & beats(0);
                            vertex_valid <= '1';
                            beat_idx     <= 0;
                            vertex_last  <= '1' when idx_cntr = desc.index_count-1;
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
            ar_capt    <= '0';
            data_state <= IDLE;
            rready     <= '0';
            idx_cntr   <= (others => '0');
        elsif rising_edge(clk) then
            data_state <= arstate;
            case arstate is
                when DESCR =>
                    araddr  <= std_logic_vector(CMD_BASE); -- Base address for descriptor
                    if ar_capt = '0' then
                        arvalid <= '1';
                        ar_capt <= '1';
                    end if;
                    arsize  <= AXSIZE_8B; -- 64-bit beat size
                    arburst <= AXBURST_INCR; -- Incrementing burst
                    arlen   <= std_logic_vector(to_unsigned(DESC_BEATS - 1, 8)); -- Number of beats for descriptor
                    if arready = '1' then -- Next address once the current one is accepted
                        arvalid <= '0';
                    end if;
                    if rlast = '1' then -- Move to next address after the data has been recieved for the next address
                        arstate <= IDX;
                        ar_capt <= '0';
                    end if;
                when IDX =>
                    araddr <= std_logic_vector(resize(desc.ib_base + idx_cntr * 4, C_AXI_ADDR_W));
                    arlen    <= (others => '0'); -- Single beat for index buffer
                    arsize   <= AXSIZE_4B; -- 32-bit beat size
                    arburst  <= AXBURST_INCR; -- Incrementing burst
                    if ar_capt = '0' then
                        arvalid <= '1';
                        ar_capt <= '1';
                    end if;
                    if arready = '1' then -- Next address once the current one is accepted
                        arvalid <= '0';
                    end if;
                    if rlast = '1' then -- Move to next address after the data has been recieved for the next address
                        arstate <= VERTEX;
                        ar_capt <= '0';
                    end if;
                when VERTEX =>
                    araddr <= std_logic_vector(resize(desc.vb_base + unsigned(index) * desc.vertex_stride, C_AXI_ADDR_W));
                    arlen  <= std_logic_vector(to_unsigned(VERTEX_BEATS - 1, 8)); -- Number of beats for vertex buffer
                    arsize <= AXSIZE_8B; -- 64-bit beat size
                    arburst <= AXBURST_INCR; -- Incrementing burst
                    if ar_capt = '0' then
                        arvalid <= '1';
                        ar_capt <= '1';
                    end if;
                    if arready = '1' then -- Next address once the current one is accepted
                        arvalid <= '0';
                    end if;
                    if rlast = '1' and (idx_cntr = desc.index_count - 1) then
                        arstate  <= IDLE;
                        idx_cntr <= (others => '0');
                        arvalid <= '0';
                        ar_capt <= '0';
                    elsif rlast = '1' then
                        arstate <= IDX;
                        idx_cntr <= idx_cntr + 1;
                        arvalid <= '0';
                        ar_capt <= '0';
                    end if;
                when others => -- IDLE
                    rready <= '0';
                    if busy = '1' then
                        arstate <= DESCR;
                        rready  <= '1';
                    end if;
            end case;      
        end if;
    end process sequencer;

    ---------------------------------------
    -- send vertex data for the next module
    axi_stream : process(clk, rst_n)
    begin
        if rst_n = '0' then
            tdata  <= (others => '0');
            tvalid <= '0';
            tlast  <= '0';
        elsif rising_edge(clk) then
            if vertex_valid = '1' then
                tdata  <= vertex_data;
                tvalid <= '1';
                tlast  <= vertex_last;
            else 
                tvalid <= '0';
            end if;
            if tvalid = '1' and tready = '1' then
                tvalid <= '0';
            end if;
        end if;
    end process axi_stream;

end RTL;