# RTL for the vertex_shader block simulation, in compile order.
# Paths are relative to ip/. VHDL (.vhdl) -> xvhdl, (System)Verilog -> xvlog.
rtl/laatta_pkg.vhdl
rtl/common/cg.vhdl

# FloPoCo cores, then the wrappers that present the in-house fp interface.
# recip/rsqrt are not instantiated yet; they are the lighting tail (normalise,
# Lambert), and analysing them here keeps them from rotting.
rtl/common/fp/gen/in_ieee.vhdl
rtl/common/fp/gen/out_ieee.vhdl
rtl/common/fp/gen/fp_mul_core.vhdl
rtl/common/fp/gen/fp_add_core.vhdl
rtl/common/fp/gen/fp_div_core.vhdl
rtl/common/fp/gen/fp_sqrt_core.vhdl
rtl/common/fp/fp_mul.vhdl
rtl/common/fp/fp_add.vhdl
rtl/common/fp/fp_recip.vhdl
rtl/common/fp/fp_rsqrt.vhdl

rtl/common/dot_product.vhdl
rtl/vertex_shader.vhdl
