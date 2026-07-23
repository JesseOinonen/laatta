// Laatta GPU CSR map (AXI4-Lite), 32-bit word offsets.
//
// Mirrors the DRAM layout in model/src/memory/memory_map.h so the RTL address
// constants and the golden model cannot drift apart. Adjust to match the real
// register file once ip/rtl exists — these are the scaffolding defaults.

// --- Control / status ---
`define GPU_CTRL        8'h00   // [0] start_frame, [1] soft_reset, [2] irq_en
`define GPU_STATUS      8'h04   // [0] busy, [1] frame_done, [2] error
`define GPU_IRQ_CLEAR   8'h08   // W1C: clear frame_done / error

// --- Frame geometry (see documentation.md: 720p / 480p, variable tiling) ---
`define GPU_RES_X       8'h10   // frame width  in pixels
`define GPU_RES_Y       8'h14   // frame height in pixels
`define GPU_TILE_SIZE   8'h18   // tile edge in pixels (default 32, floor 16)

// --- DRAM base addresses (mirror of laatta::mmap::*) ---
`define GPU_CMD_BASE    8'h20   // draw descriptor            (mmap CMD_BASE)
`define GPU_VB_BASE     8'h24   // vertex buffer              (mmap VB_BASE)
`define GPU_IB_BASE     8'h28   // index buffer               (mmap IB_BASE)
`define GPU_TEX_BASE    8'h2C   // textures (phase 2)         (mmap TEX_BASE)
`define GPU_PARAM_BASE  8'h30   // binner tile lists          (mmap PARAM_BASE)
`define GPU_FB_BASE     8'h34   // framebuffer                (mmap FB_BASE)

// --- Draw descriptor shortcuts (also readable back from DRAM CMD_BASE) ---
`define GPU_VTX_COUNT   8'h38
`define GPU_IDX_COUNT   8'h3C   // multiple of 3

// Default values matching memory_map.h
`define MMAP_CMD_BASE   32'h0000_0000
`define MMAP_VB_BASE    32'h0010_0000
`define MMAP_IB_BASE    32'h0080_0000
`define MMAP_TEX_BASE   32'h0100_0000
`define MMAP_PARAM_BASE 32'h0200_0000
`define MMAP_FB_BASE    32'h0300_0000
`define DRAW_MAGIC      32'h4C41_4154   // "LAAT"
