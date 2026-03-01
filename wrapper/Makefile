VERILATOR ?= verilator

# Default verbosity (0 = quiet, 1 = verbose)
VERBOSE ?= 1

VERILATOR_FLAGS = -Wall --trace --binary -O2 --timescale 1ns/1ps \
                  -Wno-PROCASSINIT -Wno-UNUSEDSIGNAL -Wno-SYNCASYNCNET -Wno-BLKSEQ \
                  -DTB_VERBOSE=$(VERBOSE)

RTL_DIR = rtl
DV_DIR  = dv
BUILD_DIR = build


RTL_DESER     = $(RTL_DIR)/byte_deserializer.v 
RTL_SER       = $(RTL_DIR)/byte_serializer.v
RTL_JTAG_CTRL = $(RTL_DIR)/jtag_uart_controller.v

TB_DESER      = $(DV_DIR)/tb_byte_deserializer.v
TB_SER        = $(DV_DIR)/tb_byte_serializer.v
TB_JTAG       = $(DV_DIR)/tb_jtag_uart_controller.v
MODEL_JTAG    = $(DV_DIR)/jtag_uart_model.v

all: deser ser jtag

deser:
	@mkdir -p $(BUILD_DIR)/deser
	@echo "== Building tb_byte_deserializer =="
	$(VERILATOR) $(VERILATOR_FLAGS) \
		--top-module tb_byte_deserializer \
		-Mdir $(BUILD_DIR)/deser \
		$(RTL_DESER) $(TB_DESER)
	@echo "== Running tb_byte_deserializer =="
	./$(BUILD_DIR)/deser/Vtb_byte_deserializer

ser:
	@mkdir -p $(BUILD_DIR)/ser
	@echo "== Building tb_byte_serializer =="
	$(VERILATOR) $(VERILATOR_FLAGS) \
		--top-module tb_byte_serializer \
		-Mdir $(BUILD_DIR)/ser \
		$(RTL_SER) $(TB_SER)
	@echo "== Running tb_byte_serializer =="
	./$(BUILD_DIR)/ser/Vtb_byte_serializer

jtag:
	@mkdir -p $(BUILD_DIR)/jtag
	@echo "== Building tb_jtag_uart_controller =="
	$(VERILATOR) $(VERILATOR_FLAGS) \
		--top-module tb_jtag_uart_controller \
		-Mdir $(BUILD_DIR)/jtag \
		$(RTL_JTAG_CTRL) $(MODEL_JTAG) $(TB_JTAG)
	@echo "== Running tb_jtag_uart_controller =="
	./$(BUILD_DIR)/jtag/Vtb_jtag_uart_controller

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all deser ser jtag clean