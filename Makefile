# Alarm clock (conventional or decimal time, optional decimal calendar): lint, simulation, formal proofs, synthesis.
# Tools: Verilator >= 5, Icarus Verilog >= 12, Yosys >= 0.30 (with yosys-abc).

RTL := rtl/alarm_clock.sv
TB  := tb/tb_alarm_clock.sv
RUN := bash scripts/run_sim.sh

.PHONY: all lint sim sim-icarus sim-verilator long formal synth clean

all: lint sim

lint:
	verilator --lint-only -Wall --top-module alarm_clock $(RTL)
	verilator --lint-only -Wall --top-module alarm_clock -GDECIMAL="1'b1" $(RTL)
	verilator --lint-only -Wall --top-module alarm_clock -GDECIMAL="1'b1" -GCALENDAR="1'b1" $(RTL)

define TESTS
	$(RUN) $(1) conventional $(TB) "CFG=1" $(RTL)
	$(RUN) $(1) decimal      $(TB) "CFG=2" $(RTL)
	$(RUN) $(1) calendar     $(TB) "CFG=3" $(RTL)
endef

sim: sim-icarus sim-verilator

sim-icarus:
	$(call TESTS,icarus)

sim-verilator:
	$(call TESTS,verilator)

# four calendar years (1461 days, 1.46e8 ticks) from reset, compared with the arithmetic decomposition
long:
	$(RUN) verilator calendar_long $(TB) "CFG=3 LONG" $(RTL)

formal:
	bash formal/run_formal.sh

synth:
	bash scripts/synth.sh

clean:
	rm -rf build obj_dir
