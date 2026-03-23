RTL_PATH = ${ROOT_DIR}/rtl
DV_PATH = ${ROOT_DIR}/dv

# Default target: build and run simulation
all: ${PATTERN:=.vcd}

$(PATTERN).vvp: clean
	iverilog -g2012 -Wall -Wno-timescale ${IVERILOG_FLAGS} \
	$(wildcard $(RTL_PATH)/*.sv) ${DV_PATH}/${PATTERN}_tb.sv -o $@

# Run simulation to produce mux.vcd
$(PATTERN).vcd: $(PATTERN).vvp
	vvp $<

lint_tb:
	verilator --lint-only -Wall --timing -Wno-TIMESCALEMOD -I${RTL_PATH} -sv $(wildcard $(RTL_PATH)/*.sv) ${DV_PATH}/${PATTERN}_tb.sv

lint_dut:
	verilator --lint-only -Wall --timing -I${RTL_PATH} -sv $(wildcard $(RTL_PATH)/*.sv)

clean:
	rm -rf *.vvp *.vcd