# Alarm clock with decimal time and calendar, in SystemVerilog

A fully synchronous alarm clock in one parameterized module:
* conventional (60 s / 60 min / 24 h) or **decimal** (100 s / 100 min / 10 h) time;
* an optional **decimal calendar**: 10-day weeks, 3-week months, 12 months, then 5 complementary days (6 in leap
  years) and a year counter;
* an alarm, and a two-digit seven-segment display for every field.

It is verified against two independent references, and its safety invariants are proven unbounded with PDR.

## Interface

```systemverilog
module alarm_clock #(DECIMAL = 0, CALENDAR = 0, SYNC = 2) (
  input  clk, rst,                                  // one clock; synchronous reset
  input  tick,                                      // one-cycle pulse per second (from a divider)
  input  setup_time, setup_alarm, alarm_on,         // switches (asynchronous)
  input  btn_min, btn_hr, btn_day, btn_week, btn_month,   // push-buttons (asynchronous)
  output sec, min, hr, day, week, month, year,      // the time
  output alarm_min, alarm_hr, alarm_day, alarm_week, alarm_month,
  output buzz,
  output seg_sec, seg_min, seg_hr, seg_day, seg_week, seg_month, seg_year);   // 2 x 7 segments each
```

| Switches (time, alarm) | Mode | Behavior |
|---|---|---|
| 0 0 or 1 1 | run | the time advances on `tick`; buttons are ignored |
| 1 0 | set time | the time is frozen; each button press advances its field by one, wrapping without carrying into the next field (the year is not settable) |
| 0 1 | set alarm | the time is frozen; buttons advance the alarm's fields; the display shows the alarm (seconds and year as 00) |

`buzz` is on in run mode when `alarm_on` is set and every alarm field equals the time's: minute and hour, plus day,
week and month with the calendar.

## Design

* **One clock, enables instead of derived clocks.** `tick` is an enable, and every field updates on the same edge.
  All carries are computed combinationally from terminal counts, so `9:99:99 → 0:00:00` (or a full year rollover)
  happens in a single step.
* **Clean inputs.** Each switch and button passes through a `SYNC`-stage synchronizer. Each button then goes
  through a rising-edge detector, so a press held for any number of cycles counts exactly once.
* **The calendar.** The day's terminal count depends on the month and the year: 9 in a normal week, 4 in the
  complementary days, 5 in a year with year mod 4 = 3. The complementary days follow month 11 (as "month 12") and end
  the year. Terminal counts use `>=`, so a day set above its month's last day, which setting the day before the month
  allows, wraps cleanly at the end of that day.
* **Display.** Each value 0–99 becomes two digits, each decoded to seven segments (gfedcba, active high).

Synthesized with Yosys to a generic gate library (`make synth`):

| Configuration | Flip-flops | Two-input gates | Inverters | Total |
|---|--:|--:|--:|--:|
| conventional | 41 | 393 | 6 | 440 |
| decimal | 41 | 404 | 5 | 450 |
| decimal + calendar | 74 | 628 | 12 | 714 |

## Verification

### Simulation: `tb/tb_alarm_clock.sv` (Icarus and Verilator, all three configurations)

Two references:
* **A field model.** The time, the alarm and the mode, stepped by the specification's rules. Every output (all
  fields, buzz, all seven displays) is compared with it after every tick and every button press.
* **An arithmetic decomposition.** After N ticks from reset, the fields must equal N split into seconds, minutes,
  hours and days. The days are then split into years (360 + 5 or 6 days), months and weeks. This catches carry
  errors independently of the field model.

Inputs are driven the way a person would drive them: buttons are held for several cycles, and switches settle
through the synchronizers before anything is checked.

| Check | Result |
|---|---|
| Reset state and displays | pass |
| One minute and one full day, every tick against both references (100 000 ticks in decimal time) | pass |
| Both switches on is normal operation; the time is frozen in both setting modes | pass |
| Setting the time: every field wraps without carrying; buttons are ignored in run mode | pass |
| Setting the alarm: fields wrap, the time is untouched, the display shows the alarm | pass |
| Buzz lasts exactly the alarm minute, only with `alarm_on`, silent while setting; the calendar alarm also needs the day | pass |
| The seven-segment pattern of every value 00–99 | pass |
| Month 11 → complementary days → next year; 5 or 6 complementary days for years 0–15; year 15 wraps to 0 | pass |
| A day set above the last complementary day wraps at the end of that day | pass |
| Reset mid-minute; a button held across a mode change counts once | pass |
| `make long`: **1461 days (146 100 000 ticks)** from reset, equal to the decomposition (Verilator, ~2 min) | pass |

### Formal: `make formal` (Yosys + ABC PDR)

For every input sequence after reset (any tick, switch and button pattern, resets at any time), and for all three
configurations, these invariants are **proven unbounded**:

| | Invariant |
|---|---|
| P1 | every field stays in range (seconds and minutes ≤ 59 or 99, hours ≤ 23 or 9, day ≤ 9, week ≤ 2, month ≤ 12, likewise for the alarm); without the calendar those fields stay 0 |
| P2 | while the alarm is being set the time does not change; outside run mode the seconds and the year never change; outside alarm-setting mode the alarm does not change |
| P3 | `buzz` only in run mode, with `alarm_on` and every alarm field equal to the time's |
| P4 | in run mode, a tick advances the seconds by exactly one (modulo a minute), and without a tick nothing changes |

Three broken designs each produce a counterexample: a button that also moves the seconds in run mode, a month
counter that wraps at 13, and an alarm that follows the buttons in any mode.

## Repository layout

```
rtl/alarm_clock.sv            the design
tb/tb_alarm_clock.sv          self-checking testbench (+ tb_common.svh); CFG = 1 / 2 / 3, LONG for the 4-year run
formal/alarm_clock_formal.sv  invariants; pdr.sh, run_formal.sh (proofs and negative controls)
scripts/                      run_sim.sh, synth.sh
```

## Running

```bash
make                 # lint, Icarus and Verilator simulation of the three configurations
make long            # four calendar years from reset (Verilator)
make formal          # PDR proofs and negative controls
make synth           # gate counts
```

Requirements: Verilator 5, Icarus Verilog 12, Yosys ≥ 0.30 with yosys-abc. Tested with Verilator 5.032, Icarus 12.0
and Yosys 0.52.

## Background

This design started as a university digital-design lab assignment, a schematic alarm clock built around provided
counter components whose carries were derived clocks. This repository is a from-scratch, single-clock
re-implementation in SystemVerilog, extended with the calendar and verified by simulation against two references and
by formal proofs.
