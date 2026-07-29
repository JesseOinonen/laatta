--------------------------------------
-- Laatta GPU
-- Common package: memory map, buffer formats, shared types.
--
-- This is the RTL counterpart of model/src/memory/memory_map.h and must be
-- kept in step with it. Constants here are the single source of truth for the
-- address map, so no block hardcodes an address of its own.
--
-- Author: Jesse Oinonen
--------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package laatta_pkg is

    ----------------------------------------------------------------------------
    -- Bus widths
    ----------------------------------------------------------------------------
    constant C_AXI_ADDR_W  : integer := 32;   -- DRAM address width
    constant C_AXI_DATA_W  : integer := 64;   -- DRAM data bus (one burst beat)
    constant C_AXIS_DATA_W : integer := 256;  -- vertex stream: one 32 B vertex

    ----------------------------------------------------------------------------
    -- DRAM address map -- mirrors mmap:: in memory_map.h
    ----------------------------------------------------------------------------
    constant DRAM_SIZE  : unsigned(C_AXI_ADDR_W-1 downto 0) := x"04000000"; -- 64 MiB

    constant CMD_BASE   : unsigned(C_AXI_ADDR_W-1 downto 0) := x"00000000"; -- draw descriptor
    constant VB_BASE    : unsigned(C_AXI_ADDR_W-1 downto 0) := x"00100000"; -- vertex buffer
    constant IB_BASE    : unsigned(C_AXI_ADDR_W-1 downto 0) := x"00800000"; -- index buffer
    constant TEX_BASE   : unsigned(C_AXI_ADDR_W-1 downto 0) := x"01000000"; -- textures (phase 2)
    constant PARAM_BASE : unsigned(C_AXI_ADDR_W-1 downto 0) := x"02000000"; -- binner tile lists
    constant FB_BASE    : unsigned(C_AXI_ADDR_W-1 downto 0) := x"03000000"; -- framebuffer

    ----------------------------------------------------------------------------
    -- Buffer formats
    ----------------------------------------------------------------------------
    constant VERTEX_BYTES : integer := 32;   -- one Vertex record
    constant INDEX_BYTES  : integer := 4;    -- one 32-bit index
    constant DESC_BYTES   : integer := 32;   -- one DrawDescriptor

    -- Beats of the DRAM bus that make up each record.
    constant VERTEX_BEATS : integer := VERTEX_BYTES * 8 / C_AXI_DATA_W;  -- 4
    constant DESC_BEATS   : integer := DESC_BYTES   * 8 / C_AXI_DATA_W;  -- 4

    -- Draw descriptor validation word ("LAAT").
    constant DRAW_MAGIC : std_logic_vector(31 downto 0) := x"4C414154";

    ----------------------------------------------------------------------------
    -- Draw descriptor, unpacked. Filled by geometry_fetch from the four beats
    -- read at CMD_BASE; see the beat-packing table in the architecture spec.
    ----------------------------------------------------------------------------
    type draw_descriptor_t is record
        magic         : std_logic_vector(31 downto 0);
        vertex_count  : unsigned(31 downto 0);
        index_count   : unsigned(31 downto 0);
        vb_base       : unsigned(31 downto 0);
        ib_base       : unsigned(31 downto 0);
        vertex_stride : unsigned(31 downto 0);
        tex_base      : unsigned(31 downto 0);
        flags         : std_logic_vector(31 downto 0);
    end record;

    -- Unpacks the four 64-bit read beats (beat 0 first) into a descriptor.
    -- On each beat the lower-offset field is on bits [31:0], the next on
    -- [63:32].
    function unpack_descriptor(
        beat0, beat1, beat2, beat3 : std_logic_vector(C_AXI_DATA_W-1 downto 0)
    ) return draw_descriptor_t;

    type axi4_state_t is (
        IDLE,
        SEND_AR,
        READ_DATA
    );

    ----------------------------------------------------------------------------
    -- AXI4 burst encodings, for readability at the port level.
    ----------------------------------------------------------------------------
    constant AXBURST_FIXED : std_logic_vector(1 downto 0) := "00";
    constant AXBURST_INCR  : std_logic_vector(1 downto 0) := "01";
    constant AXBURST_WRAP  : std_logic_vector(1 downto 0) := "10";

    constant AXSIZE_4B  : std_logic_vector(2 downto 0) := "010";  -- one 32-bit word
    constant AXSIZE_8B  : std_logic_vector(2 downto 0) := "011";  -- one 64-bit beat

    constant RESP_OKAY  : std_logic_vector(1 downto 0) := "00";

end package laatta_pkg;


package body laatta_pkg is

    function unpack_descriptor(
        beat0, beat1, beat2, beat3 : std_logic_vector(C_AXI_DATA_W-1 downto 0)
    ) return draw_descriptor_t is
        variable d : draw_descriptor_t;
    begin
        d.magic         := beat0(31 downto 0);
        d.vertex_count  := unsigned(beat0(63 downto 32));
        d.index_count   := unsigned(beat1(31 downto 0));
        d.vb_base       := unsigned(beat1(63 downto 32));
        d.ib_base       := unsigned(beat2(31 downto 0));
        d.vertex_stride := unsigned(beat2(63 downto 32));
        d.tex_base      := unsigned(beat3(31 downto 0));
        d.flags         := beat3(63 downto 32);
        return d;
    end function;

end package body laatta_pkg;
