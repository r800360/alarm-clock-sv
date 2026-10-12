# Verification

`make ci` runs on every push; `make full` adds the four-year run. Logs and reports go to `build/`, and
`build/SUMMARY.md` collects them.

## Simulation (`tb/tb_alarm_clock.sv`; `CFG` = 1 conventional, 2 decimal, 3 decimal + calendar)

There are two independent references:
* **A field model.** The time, the alarm and the mode, stepped by the specification's rules. Every output (all
  fields, buzz and all seven displays) is compared with it after every tick and every button press.
* **An arithmetic decomposition.** After N ticks from reset, the fields must equal N split into seconds, minutes,
  hours and days. The days are then split into years (360 + 5 or 6 days), months and weeks with integer arithmetic.
  This catches carry errors independently of the field model.

Inputs are driven the way a person would drive them: buttons are held for several cycles, and switches settle
through the synchronizers before anything is checked.

| Check | Result |
|---|---|
| Reset state and displays | pass |
| One minute and one full day, every tick against both references (100 000 ticks in decimal time) | pass |
| Both switches on means normal operation; the time is frozen in both setting modes | pass |
| Setting the time: every field wraps without carrying; buttons are ignored in run mode | pass |
| Setting the alarm: fields wrap, the time is untouched, the display shows the alarm | pass |
| Buzz lasts exactly the alarm minute, only with `alarm_on`, and is silent while setting; the calendar alarm also needs the day | pass |
| The seven-segment pattern of every value 00–99 | pass |
| Month 11 → complementary days → next year; 5 or 6 complementary days for years 0–15; year 15 wraps to 0 | pass |
| A day set above the last complementary day wraps at the end of that day | pass |
| Reset mid-minute; a button held across a mode change counts once | pass |
| `make long`: **1461 days (146 100 000 ticks)** from reset equal the decomposition (Verilator, about 2 minutes) | pass |

## Formal (`make formal`)

For every input sequence after reset (any tick, switch or button pattern, and resets at any time), and in all three
configurations, these invariants are proven unbounded with ABC's PDR:

| | Invariant |
|---|---|
| P1 | every field stays in range (seconds and minutes ≤ 59 or 99, hours ≤ 23 or 9, day ≤ 9, week ≤ 2, month ≤ 12, and the same for the alarm). Without the calendar, those fields stay 0 |
| P2 | while the alarm is being set the time does not change; outside run mode the seconds and the year never change; outside alarm-setting mode the alarm does not change |
| P3 | `buzz` only in run mode, with `alarm_on` and every alarm field equal to the time's |
| P4 | in run mode a tick advances the seconds by exactly one (modulo a minute), and without a tick nothing changes |

Three broken designs must each produce a counterexample, and they do:
* a button that also moves the seconds in run mode;
* a month counter that wraps at 13;
* an alarm that follows the buttons in any mode.

The harness tracks the mode through its own copy of the two synchronizer stages. It also compares against explicitly
registered previous values, since clocked assertions are sampled a cycle late in this flow.

## Tools and how they are run

| Tool (version) | Used for | Command |
|---|---|---|
| Icarus Verilog 12.0 | simulation | `iverilog -g2012 -I tb -DCFG=<n> -o build/<t>.vvp tb/tb_alarm_clock.sv rtl/alarm_clock.sv`, then `vvp -n` |
| Verilator 5.032 | lint, simulation, four-year run | `verilator --lint-only -Wall -GDECIMAL=... -GCALENDAR=...`; `verilator --binary --timing -O2 -Itb -DCFG=3 -DLONG ...` |
| Yosys 0.52 + ABC | proofs, synthesis | `formal/pdr.sh`: Yosys writes an AIGER model, then `yosys-abc -c "read_aiger m.aig; fold; strash; pdr"`; `scripts/synth.sh` |

The proof model is built with `read_verilog -sv -formal; chparam; prep; flatten; async2sync; chformal -lower; chformal
-assume -early; …; write_aiger -I -B -zinit`. `chformal -lower` is essential: Yosys 0.52 turns `assert` into `$check`
cells, which would otherwise leave the model with no properties. `pdr.sh` refuses a model with none.

## CI

| Workflow | Trigger | Runs |
|---|---|---|
| CI (`.github/workflows/ci.yml`) | every push to `main`, pull requests | `lint`, `sim`, `formal`, `synth` |
| Full verification (`full.yml`) | manual, or a `v*` tag | the CI steps plus `long`; a tag also publishes a release |

Both use the pinned `ubuntu:26.04` image and `scripts/install-tools.sh`, the same script as the `Dockerfile`, and
upload `build/` as an artifact.
