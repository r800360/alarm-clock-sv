// tb_alarm_clock.sv - self-checking testbench for rtl/alarm_clock.sv.
//
// +define+CFG=1 conventional time, 2 decimal time, 3 decimal time + calendar (default 3). +define+LONG adds a
// 4-year run from reset (use Verilator).
//
// Two references:
//   * a field model: the time, the alarm and the mode, stepped by the specification's rules. Every output (fields,
//     buzz, all seven displays) is compared with it at every tick and after every button press;
//   * an arithmetic decomposition: after N ticks from reset in run mode, the fields must equal N split into
//     seconds / minutes / hours / days, the days into years (360 + 5 or 6 complementary days), months, weeks.
// Buttons and switches are driven like a person would: held for several clock cycles, then released; the checks
// run once the synchronisers have settled.
`timescale 1ns/10ps
`include "tb_common.svh"
`ifndef CFG
`define CFG 3
`endif

module tb_alarm_clock;
  localparam int CFG = `CFG;
  localparam bit DEC = CFG >= 2, CAL = CFG == 3;
  localparam int SPM = DEC ? 100 : 60, MPH = DEC ? 100 : 60, HPD = DEC ? 10 : 24;   // per minute / hour / day
  localparam int SPD = SPM * MPH * HPD;                                              // seconds per day

  logic clk = 1'b0, rst = 1'b0, tick = 1'b0, setup_time = 1'b0, setup_alarm = 1'b0, alarm_on = 1'b0;
  logic btn_min = 1'b0, btn_hr = 1'b0, btn_day = 1'b0, btn_week = 1'b0, btn_month = 1'b0;
  logic [6:0] sec, min, alarm_min;
  logic [4:0] hr, alarm_hr;
  logic [3:0] day, month, year, alarm_day, alarm_month;
  logic [1:0] week, alarm_week;
  logic buzz;
  logic [13:0] seg_sec, seg_min, seg_hr, seg_day, seg_week, seg_month, seg_year;

  alarm_clock #(.DECIMAL(DEC), .CALENDAR(CAL), .SYNC(2)) dut (.*);

  // ---------------------------------------------------------------- field model
  int t_s, t_m, t_h, t_d, t_w, t_mo, t_y;            // time
  int a_m, a_h, a_d, a_w, a_mo;                      // alarm
  int mode;                                          // 0 run, 1 set time, 2 set alarm (after synchronisation)
  task automatic m_reset();
    t_s = 0; t_m = 0; t_h = 0; t_d = 0; t_w = 0; t_mo = 0; t_y = 0; a_m = 0; a_h = 0; a_d = 0; a_w = 0; a_mo = 0;
  endtask
  function automatic int days_in(input int mo, input int y);    // days of month mo (12 = complementary days)
    if (mo == 12) return (y % 4 == 3) ? 6 : 5;
    return 10;                                                  // days per *week*; a month is 3 weeks
  endfunction
  task automatic m_tick();
    if (mode == 0) begin
      t_s++;
      if (t_s == SPM) begin
        t_s = 0; t_m++;
        if (t_m == MPH) begin
          t_m = 0; t_h++;
          if (t_h == HPD) begin
            t_h = 0;
            if (CAL) begin
              t_d++;
              if (t_d >= days_in(t_mo, t_y)) begin
                t_d = 0;
                if (t_mo == 12) begin
                  t_mo = 0; t_y = (t_y + 1) % 16;
                end else begin
                  t_w++;
                  if (t_w == 3) begin t_w = 0; t_mo++; end
                end
              end
            end
          end
        end
      end
    end
  endtask

  // ---------------------------------------------------------------- arithmetic decomposition of N ticks from reset
  int x_s, x_m, x_h, x_d, x_w, x_mo, x_y;
  task automatic decompose(input longint n);
    longint d;
    int y;
    x_s = int'(n % SPM); x_m = int'((n / SPM) % MPH); x_h = int'((n / (SPM * MPH)) % HPD);
    d = n / SPD;
    x_d = 0; x_w = 0; x_mo = 0; x_y = 0;
    if (CAL) begin
      y = 0;
      while (d >= 360 + ((y % 4 == 3) ? 6 : 5)) begin d -= 360 + ((y % 4 == 3) ? 6 : 5); y++; end
      x_y = y % 16;
      if (d < 360) begin x_mo = int'(d / 30); x_w = int'((d % 30) / 10); x_d = int'(d % 10); end
      else begin x_mo = 12; x_w = 0; x_d = int'(d - 360); end
    end
  endtask

  // ---------------------------------------------------------------- display reference
  function automatic logic [6:0] seg(input int d);
    case (d)
      0: return 7'b0111111; 1: return 7'b0000110; 2: return 7'b1011011; 3: return 7'b1001111; 4: return 7'b1100110;
      5: return 7'b1101101; 6: return 7'b1111101; 7: return 7'b0000111; 8: return 7'b1111111; default: return 7'b1101111;
    endcase
  endfunction
  function automatic logic [13:0] disp(input int v); return {seg(v / 10), seg(v % 10)}; endfunction

  // ---------------------------------------------------------------- comparison
  int errs; string first;
  task automatic compare(input string what);
    bit sa, b;
    string m;
    sa = (mode == 2);
    b = (mode == 0) && alarm_on && t_m == a_m && t_h == a_h && (!CAL || (t_d == a_d && t_w == a_w && t_mo == a_mo));
    if (sec !== 7'(t_s) || min !== 7'(t_m) || hr !== 5'(t_h) || day !== 4'(t_d) || week !== 2'(t_w) ||
        month !== 4'(t_mo) || year !== 4'(t_y) || alarm_min !== 7'(a_m) || alarm_hr !== 5'(a_h) ||
        alarm_day !== 4'(a_d) || alarm_week !== 2'(a_w) || alarm_month !== 4'(a_mo) || buzz !== b ||
        seg_sec !== disp(sa ? 0 : t_s) || seg_min !== disp(sa ? a_m : t_m) || seg_hr !== disp(sa ? a_h : t_h) ||
        seg_day !== disp(sa ? a_d : t_d) || seg_week !== disp(sa ? a_w : t_w) ||
        seg_month !== disp(sa ? a_mo : t_mo) || seg_year !== disp(sa ? 0 : t_y)) begin
      errs++;
      if (errs == 1) begin
        m = $sformatf("%s: DUT %0d:%0d:%0d d%0d w%0d m%0d y%0d alarm %0d:%0d d%0d w%0d m%0d buzz %0b; ", what, hr, min,
                      sec, day, week, month, year, alarm_hr, alarm_min, alarm_day, alarm_week, alarm_month, buzz);
        first = {m, $sformatf("model %0d:%0d:%0d d%0d w%0d m%0d y%0d alarm %0d:%0d d%0d w%0d m%0d buzz %0b (or display)",
                              t_h, t_m, t_s, t_d, t_w, t_mo, t_y, a_h, a_m, a_d, a_w, a_mo, b)};
      end
    end
  endtask
  task automatic group(input string cat, input string name);
    `CHECK(cat, name, errs == 0, first)
    errs = 0; first = "";
  endtask

  // ---------------------------------------------------------------- stimulus
  task automatic cycle(input bit t);
    tick = t; #4 clk = 1'b1; #1 tick = 1'b0; #5 clk = 1'b0;
  endtask
  longint n_ticks;       // ticks applied in run mode since reset (for decompose)
  task automatic ticks(input longint n, input bit check_each = 1'b1, input bit check_decomp = 1'b0);
    for (longint i = 0; i < n; i++) begin
      cycle(1'b1);
      m_tick();
      if (mode == 0) n_ticks++;
      #1;
      if (check_each) compare($sformatf("tick %0d", n_ticks));
      if (check_decomp) begin
        decompose(n_ticks);
        if (sec !== 7'(x_s) || min !== 7'(x_m) || hr !== 5'(x_h) || day !== 4'(x_d) || week !== 2'(x_w) ||
            month !== 4'(x_mo) || year !== 4'(x_y)) begin
          errs++;
          if (errs == 1) first = $sformatf("after %0d ticks: DUT %0d:%0d:%0d d%0d w%0d m%0d y%0d, expected %0d:%0d:%0d d%0d w%0d m%0d y%0d",
                                           n_ticks, hr, min, sec, day, week, month, year, x_h, x_m, x_s, x_d, x_w, x_mo, x_y);
        end
      end
    end
  endtask
  task automatic idle(input int n); repeat (n) cycle(1'b0); endtask
  task automatic set_mode(input bit st, input bit sa);
    setup_time = st; setup_alarm = sa;
    idle(4);
    mode = (st == sa) ? 0 : st ? 1 : 2;
    #1 compare($sformatf("mode %0b%0b", st, sa));
  endtask
  // press a button: held 4 cycles, released 4 cycles; the model applies one increment
  task automatic press(input int b);
    case (b) 0: btn_min = 1'b1; 1: btn_hr = 1'b1; 2: btn_day = 1'b1; 3: btn_week = 1'b1; default: btn_month = 1'b1; endcase
    idle(4);
    {btn_min, btn_hr, btn_day, btn_week, btn_month} = '0;
    idle(4);
    if (mode == 1) begin
      case (b)
        0: t_m = (t_m + 1) % MPH;
        1: t_h = (t_h + 1) % HPD;
        2: if (CAL) t_d = (t_d + 1 >= days_in(t_mo, t_y)) ? 0 : t_d + 1;
        3: if (CAL) t_w = (t_w + 1) % 3;
        default: if (CAL) t_mo = (t_mo + 1) % 13;
      endcase
    end else if (mode == 2) begin
      case (b)
        0: a_m = (a_m + 1) % MPH;
        1: a_h = (a_h + 1) % HPD;
        2: if (CAL) a_d = (a_d + 1) % 10;
        3: if (CAL) a_w = (a_w + 1) % 3;
        default: if (CAL) a_mo = (a_mo + 1) % 13;
      endcase
    end
    #1 compare($sformatf("press %0d in mode %0d", b, mode));
  endtask
  task automatic presses(input int b, input int n); repeat (n) press(b); endtask
  task automatic do_reset(); rst = 1'b1; idle(2); rst = 1'b0; m_reset(); n_ticks = 0; #1 compare("reset"); endtask
  // set the time (in set-time mode) to the last second before the end of the current day: hh:mm = last:last
  task automatic to_day_end();
    set_mode(1'b1, 1'b0);
    presses(1, (HPD - 1 - t_h + HPD) % HPD);
    presses(0, (MPH - 1 - t_m + MPH) % MPH);
    set_mode(1'b0, 1'b0);
    ticks(SPM - 1 - t_s);
  endtask

  initial begin
    errs = 0; mode = 0; n_ticks = 0;
    $display("alarm_clock: %s time%s", DEC ? "decimal" : "conventional", CAL ? " + calendar" : "");
    do_reset();
    group("FUNC", "reset: 0:00:00, alarm 0:00, displays 00");

    ticks(SPM, 1'b1, 1'b1);
    group("FUNC", $sformatf("one minute: %0d ticks", SPM));
    ticks(SPD - SPM, 1'b1, 1'b1);
    group("FUNC", $sformatf("one full day (%0d ticks), every tick against the model and the decomposition", SPD));

    set_mode(1'b1, 1'b1);
    ticks(SPM + 3);
    group("FUNC", "both switches on is normal operation");
    set_mode(1'b1, 1'b0); ticks(50); set_mode(1'b0, 1'b1); ticks(50); set_mode(1'b0, 1'b0);
    group("FUNC", "the time is frozen while setting the time or the alarm");

    set_mode(1'b1, 1'b0);
    presses(0, MPH + 3); presses(1, HPD + 2);
    if (CAL) begin presses(2, 12); presses(3, 4); presses(4, 14); end
    set_mode(1'b0, 1'b0);
    group("FUNC", "setting the time: each field wraps without carrying into the next");
    for (int b = 0; b < 5; b++) press(b);
    group("FUNC", "buttons are ignored in run mode");

    set_mode(1'b0, 1'b1);
    presses(0, 7); presses(1, 3);
    if (CAL) begin presses(2, 11); presses(3, 5); presses(4, 13); end
    set_mode(1'b0, 1'b0);
    group("FUNC", "setting the alarm: fields wrap, the time is untouched, the display shows the alarm");

    // alarm one minute ahead of the time: buzz for exactly one minute, only when enabled and in run mode
    do_reset();
    set_mode(1'b0, 1'b1); press(0); set_mode(1'b0, 1'b0);
    alarm_on = 1'b1;
    ticks(3 * SPM);
    alarm_on = 1'b0; ticks(SPM);
    group("FUNC", "buzz sounds for exactly the alarm minute and only with alarm_on");
    do_reset();
    alarm_on = 1'b1;
    set_mode(1'b1, 1'b0); set_mode(1'b0, 1'b1); set_mode(1'b1, 1'b1);
    alarm_on = 1'b0;
    group("FUNC", "buzz is silent while setting, and sounds with both switches on");
    if (CAL) begin
      do_reset();
      set_mode(1'b0, 1'b1); press(2); set_mode(1'b0, 1'b0);
      alarm_on = 1'b1; ticks(SPM);
      to_day_end(); ticks(2);
      alarm_on = 1'b0;
      group("FUNC", "calendar alarm: buzz needs the day to match too");
    end

    // every display value
    do_reset();
    set_mode(1'b1, 1'b0);
    for (int v = 0; v < MPH; v++) press(0);
    set_mode(1'b0, 1'b0);
    group("FUNC", $sformatf("seven-segment display of every minute value 00..%0d", MPH - 1));

    if (CAL) begin
      // month 11, week 2, day 9, end of day -> complementary days; 5 of them in year 0, then year 1
      do_reset();
      set_mode(1'b1, 1'b0); presses(4, 11); presses(3, 2); presses(2, 9); set_mode(1'b0, 1'b0);
      to_day_end(); ticks(1);
      group("FUNC", "end of month 11 -> complementary days (month 12, day 0)");
      for (int k = 0; k < 5; k++) begin to_day_end(); ticks(1); end
      group("FUNC", "5 complementary days in year 0, then year 1, month 0, day 0");
      for (int y = 1; y < 16; y++) begin
        set_mode(1'b1, 1'b0); presses(4, 12); set_mode(1'b0, 1'b0);   // month 0 -> 12
        for (int k = 0; k < ((y % 4 == 3) ? 6 : 5); k++) begin to_day_end(); ticks(1); end
      end
      group("FUNC", "years 1..15: 6 complementary days when year mod 4 = 3, 5 otherwise; year 15 wraps to 0");
      set_mode(1'b1, 1'b0); presses(2, 8); presses(4, 12); set_mode(1'b0, 1'b0);   // day 8, then month 12
      to_day_end(); ticks(1);
      group("FUNC", "a day beyond the last complementary day wraps at the end of that day");
    end

`ifdef LONG
    do_reset();
    for (int d = 0; d < (CAL ? 1461 : 30); d++) ticks(SPD, 1'b0, 1'b0);
    decompose(n_ticks);
    if (sec !== 7'(x_s) || min !== 7'(x_m) || hr !== 5'(x_h) || day !== 4'(x_d) || week !== 2'(x_w) ||
        month !== 4'(x_mo) || year !== 4'(x_y)) begin errs++; first = "long run: wrong date"; end
    compare("long run");
    group("FUNC", $sformatf("%0d days from reset (%0d ticks): fields equal the decomposition", n_ticks / SPD, n_ticks));
`endif

    // robustness
    do_reset();
    ticks(SPM / 2);
    rst = 1'b1; idle(1); rst = 1'b0; m_reset(); n_ticks = 0; #1 compare("reset mid-run");
    ticks(SPM + 5, 1'b1, 1'b1);
    group("ROBUST", "reset in the middle of a minute, then counting restarts from 0");
    set_mode(1'b1, 1'b0);
    btn_min = 1'b1; idle(3); setup_time = 1'b0; idle(10); btn_min = 1'b0; idle(4);
    mode = 0; t_m = (t_m + 1) % MPH;                                  // the press was seen while still in set-time
    #1 compare("button held across a mode change");
    group("ROBUST", "a button held across a mode change counts once, when pressed");
    `REPORT
    $finish;
  end
endmodule
