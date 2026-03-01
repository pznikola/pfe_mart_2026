VERILATOR ?= verilator

# Default verbosity (0 = quiet, 1 = verbose)
VERBOSE ?= 1

VERILATOR_FLAGS = -Wall --trace --binary -O2 --timescale 1ns/1ps \
                  -Wno-PROCASSINIT -Wno-UNUSEDSIGNAL -Wno-SYNCASYNCNET -Wno-BLKSEQ \
                  -DTB_VERBOSE=$(VERBOSE)

RTL_DIR = rtl
DV_DIR  = dv
BUILD_DIR = build

RTL_SRCS = \
	$(RTL_DIR)/byte_deserializer.v \
	$(RTL_DIR)/byte_serializer.v

TB_DESER = $(DV_DIR)/tb_byte_deserializer.v
TB_SER   = $(DV_DIR)/tb_byte_serializer.v

all: deser ser

deser:
	@mkdir -p $(BUILD_DIR)/deser
	@echo "== Building tb_byte_deserializer =="
	$(VERILATOR) $(VERILATOR_FLAGS) \
		--top-module tb_byte_deserializer \
		-Mdir $(BUILD_DIR)/deser \
		$(RTL_SRCS) $(TB_DESER)
	@echo "== Running tb_byte_deserializer =="
	./$(BUILD_DIR)/deser/Vtb_byte_deserializer

ser:
	@mkdir -p $(BUILD_DIR)/ser
	@echo "== Building tb_byte_serializer =="
	$(VERILATOR) $(VERILATOR_FLAGS) \
		--top-module tb_byte_serializer \
		-Mdir $(BUILD_DIR)/ser \
		$(RTL_SRCS) $(TB_SER)
	@echo "== Running tb_byte_serializer =="
	./$(BUILD_DIR)/ser/Vtb_byte_serializer

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all deser ser clean