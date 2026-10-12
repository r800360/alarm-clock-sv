#!/bin/bash
# synth.sh - Yosys synthesis of each configuration to a generic gate library (synth -flatten; abc -g gates):
# flip-flops, two-input gates and inverters. Full statistics in build/synth/<config>.txt.
cd "$(dirname "$0")/.."
B=build/synth; mkdir -p $B
printf '%-14s %6s %6s %6s %6s\n' configuration FFs gates inv total | tee $B/summary.txt
one() {  # name chparam
  yosys -q -p "read_verilog -sv rtl/alarm_clock.sv; chparam $2 alarm_clock; synth -top alarm_clock -flatten; \
    abc -g gates; opt_clean; tee -q -o $B/$1.txt stat; write_verilog -noattr $B/$1.v" > $B/$1.log 2>&1 < /dev/null || { echo "$1: yosys failed"; return; }
  awk -v n="$1" '/^ +\$_/ { c=$1; v=$2; if (c ~ /DFF/) ff+=v; else if (c=="$_NOT_") inv+=v; else g+=v }
    END { printf "%-14s %6d %6d %6d %6d\n", n, ff, g, inv, ff+g+inv }' $B/$1.txt | tee -a $B/summary.txt
}
one conventional "-set DECIMAL 0 -set CALENDAR 0"
one decimal      "-set DECIMAL 1 -set CALENDAR 0"
one calendar     "-set DECIMAL 1 -set CALENDAR 1"
