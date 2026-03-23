#----------------------------------------------------------------------
# Quartus
#----------------------------------------------------------------------
# Open existing project 
q_open:
	./build.sh --open 

# Build full project
q_build:
	./build.sh --clean

# Build full project and program the board
q_program:
	./build.sh --clean --program

# Program only the board
q_program_only:
	./build.sh --prog

# Clean the Quartus files
q_clean:
	./build.sh --clean-only 

#----------------------------------------------------------------------
# Connect PC and FPGA
#----------------------------------------------------------------------
connect:
	python3 jtag_uart_raw.py

connect_image:
	python3 jtag_uart_image.py --input images/logo.png --output images/logo_received.png --timeout 60

connect_conv:
	python3 jtag_uart_image.py --input images/pfe.png --output images/pfe_received.png --timeout 60 --kernel-size 3
#----------------------------------------------------------------------
# Verilator simulations
#----------------------------------------------------------------------
VERILATOR ?= verilator

# Default verbosity (0 = quiet, 1 = verbose)
VERBOSE ?= 1

VERILATOR_FLAGS = -Wall --trace --binary -O2 --timescale 1ns/1ps \
                  -Wno-PROCASSINIT -Wno-UNUSEDSIGNAL -Wno-SYNCASYNCNET -Wno-BLKSEQ \
                  -DTB_VERBOSE=$(VERBOSE)

RTL_DIR = rtl
DV_DIR  = dv
BUILD_DIR = build


RTL_FIFO      = $(RTL_DIR)/fifo.v 
RTL_DESER     = $(RTL_DIR)/byte_deserializer.sv 
RTL_SER       = $(RTL_DIR)/byte_serializer.sv
RTL_JTAG_CTRL = $(RTL_DIR)/jtag_uart_controller.v
RTL_ACC       = $(RTL_DIR)/accumulator.sv
RTL_PFE       = $(RTL_DIR)/pfe.sv

TB_FIFO       = $(DV_DIR)/tb_fifo.v
TB_DESER      = $(DV_DIR)/tb_byte_deserializer.v
TB_SER        = $(DV_DIR)/tb_byte_serializer.v
TB_JTAG       = $(DV_DIR)/tb_jtag_uart_controller.v
MODEL_JTAG    = $(DV_DIR)/jtag_uart_model.v
TB_ACC        = $(DV_DIR)/tb_accumulator.sv
TB_PFE        = $(DV_DIR)/tb_pfe.sv

# Simulate fifo
sim_fifo:
	@mkdir -p $(BUILD_DIR)/fifo
	@echo "== Building tb_fifo =="
	$(VERILATOR) $(VERILATOR_FLAGS) \
		--top-module tb_fifo \
		-Mdir $(BUILD_DIR)/fifo \
		$(RTL_FIFO) $(TB_FIFO)
	@echo "== Running tb_fifo =="
	./$(BUILD_DIR)/fifo/Vtb_fifo

# Simulate deserializer
sim_deser:
	@mkdir -p $(BUILD_DIR)/deser
	@echo "== Building tb_byte_deserializer =="
	$(VERILATOR) $(VERILATOR_FLAGS) \
		--top-module tb_byte_deserializer \
		-Mdir $(BUILD_DIR)/deser \
		$(RTL_DESER) $(TB_DESER)
	@echo "== Running tb_byte_deserializer =="
	./$(BUILD_DIR)/deser/Vtb_byte_deserializer

# Simulate serializer
sim_ser:
	@mkdir -p $(BUILD_DIR)/ser
	@echo "== Building tb_byte_serializer =="
	$(VERILATOR) $(VERILATOR_FLAGS) \
		--top-module tb_byte_serializer \
		-Mdir $(BUILD_DIR)/ser \
		$(RTL_SER) $(TB_SER)
	@echo "== Running tb_byte_serializer =="
	./$(BUILD_DIR)/ser/Vtb_byte_serializer

# Simulate JTAG controller
sim_jtag:
	@mkdir -p $(BUILD_DIR)/jtag
	@echo "== Building tb_jtag_uart_controller =="
	$(VERILATOR) $(VERILATOR_FLAGS) \
		--top-module tb_jtag_uart_controller \
		-Mdir $(BUILD_DIR)/jtag \
		$(RTL_JTAG_CTRL) $(MODEL_JTAG) $(TB_JTAG)
	@echo "== Running tb_jtag_uart_controller =="
	./$(BUILD_DIR)/jtag/Vtb_jtag_uart_controller

# Simulate accumulator
sim_acc:
	@mkdir -p $(BUILD_DIR)/acc
	@echo "== Building tb_accumulator =="
	$(VERILATOR) $(VERILATOR_FLAGS) \
		--top-module tb_accumulator \
		-Mdir $(BUILD_DIR)/acc \
		$(RTL_ACC) $(TB_ACC)
	@echo "== Running tb_accumulator =="
	./$(BUILD_DIR)/acc/Vtb_accumulator

# Simulate pfe
sim_pfe:
	@mkdir -p $(BUILD_DIR)/pfe
	@echo "== Building tb_pfe =="
	$(VERILATOR) $(VERILATOR_FLAGS) \
		--top-module tb_pfe \
		-Mdir $(BUILD_DIR)/pfe \
		$(RTL_PFE) $(RTL_ACC) $(RTL_SER) $(TB_PFE)
	@echo "== Running tb_pfe =="
	./$(BUILD_DIR)/pfe/Vtb_pfe

# Simulate all
sim_all:
	make sim_fifo
	make sim_deser
	make sim_ser
	make sim_jtag
	make sim_acc
	make sim_pfe

#----------------------------------------------------------------------
# Clean
#----------------------------------------------------------------------
clean:
	rm -rf $(BUILD_DIR) *.vcd
	make q_clean
