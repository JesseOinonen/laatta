# Phase 0 golden model. Plain C++17, no external dependencies.
#
#   make            # build everything
#   make render     # render the test scene, compare TBDR against immediate mode
#   make sweep      # tile size design-space sweep -> output/sweep.csv
#   make plots      # sweep + matplotlib charts (needs python3-matplotlib)

CXX      := g++
CXXFLAGS := -std=c++17 -Wall -Wextra -O2 -g
SRC_DIR   := src
BUILD_DIR := build
OUT_DIR   := output

COMMON_SRCS := $(SRC_DIR)/memory/dram_model.cpp \
               $(SRC_DIR)/render/vertex_cache.cpp \
               $(SRC_DIR)/tools/obj_loader.cpp \
               $(SRC_DIR)/render/framebuffer.cpp \
               $(SRC_DIR)/render/transform.cpp \
               $(SRC_DIR)/render/binner.cpp \
               $(SRC_DIR)/render/raster.cpp \
               $(SRC_DIR)/render/renderer.cpp

LAATTA_SRCS := $(COMMON_SRCS) $(SRC_DIR)/main.cpp
SWEEP_SRCS  := $(COMMON_SRCS) $(SRC_DIR)/tools/sweep_main.cpp

LAATTA_OBJS := $(LAATTA_SRCS:$(SRC_DIR)/%.cpp=$(BUILD_DIR)/%.o)
SWEEP_OBJS  := $(SWEEP_SRCS:$(SRC_DIR)/%.cpp=$(BUILD_DIR)/%.o)

SCENE ?= testdata/nokia_mouse.obj

.PHONY: all render sweep plots clean

all: $(OUT_DIR)/laatta $(OUT_DIR)/sweep

render: $(OUT_DIR)/laatta
	./$(OUT_DIR)/laatta $(SCENE)

sweep: $(OUT_DIR)/sweep
	./$(OUT_DIR)/sweep $(SCENE)

plots: sweep
	python3 tools/plot_sweep.py

$(OUT_DIR)/laatta: $(LAATTA_OBJS) | $(OUT_DIR)
	$(CXX) $^ -o $@

$(OUT_DIR)/sweep: $(SWEEP_OBJS) | $(OUT_DIR)
	$(CXX) $^ -o $@

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -MMD -MP -c $< -o $@

$(OUT_DIR):
	@mkdir -p $(OUT_DIR)

-include $(shell find $(BUILD_DIR) -name '*.d' 2>/dev/null)

clean:
	rm -rf $(BUILD_DIR) $(OUT_DIR)
