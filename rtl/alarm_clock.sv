// alarm_clock.sv - alarm clock with conventional or decimal time and an optional decimal calendar.
//
// One clock domain. `tick` is a one-cycle pulse per second (from a divider). The mode switches and the push-buttons
// are asynchronous: each goes through a SYNC-stage synchroniser, and each button press is turned into a single
// one-cycle pulse by a rising-edge detector, so holding a button advances a field exactly once.
//
//   time        DECIMAL = 0: 60 s / 60 min / 24 h      DECIMAL = 1: 100 s / 100 min / 10 h
//   calendar    CALENDAR = 1: 10-day weeks, 3 weeks per month, months 0..11, then a period of complementary days
//               (month 12: 5 days, 6 in every year with year mod 4 = 3), and a 4-bit year counter
//
//   modes       setup_time == setup_alarm  run: the time advances on tick, buttons are ignored
//               setup_time only            set time: the time is frozen; a button press advances its field by one
//                                          (wrapping, without carry into the next field; the year is not settable)
//               setup_alarm only           set alarm: the time is frozen; buttons advance the alarm's fields
//   buzz        run mode, alarm_on, and every alarm field (minute, hour; day, week, month) equals the time's
//   display     two seven-segment digits per field (segments gfedcba, active high); while the alarm is being set the
//               alarm is shown, with seconds and year as 00
//
// All carries are synchronous: every field that wraps does so on the same clock edge (9:99:99 -> 0:00:00 in one
// step). A day counter above its month's last day (possible after setting the month) wraps at the end of that day.
module alarm_clock #(
  parameter bit DECIMAL  = 1'b0,
  parameter bit CALENDAR = 1'b0,
  parameter int SYNC     = 2
) (
  input  logic        clk,
  input  logic        rst,          // synchronous: time 0:00:00 (day 0, week 0, month 0, year 0), alarm 0:00
  input  logic        tick,         // one-cycle pulse per second
  input  logic        setup_time,
  input  logic        setup_alarm,
  input  logic        alarm_on,
  input  logic        btn_min,
  input  logic        btn_hr,
  input  logic        btn_day,      // the calendar buttons are ignored when CALENDAR = 0
  input  logic        btn_week,
  input  logic        btn_month,
  output logic [6:0]  sec,
  output logic [6:0]  min,
  output logic [4:0]  hr,
  output logic [3:0]  day,
  output logic [1:0]  week,
  output logic [3:0]  month,
  output logic [3:0]  year,
  output logic [6:0]  alarm_min,
  output logic [4:0]  alarm_hr,
  output logic [3:0]  alarm_day,
  output logic [1:0]  alarm_week,
  output logic [3:0]  alarm_month,
  output logic        buzz,
  output logic [13:0] seg_sec,      // {tens, ones}, 7 segments each
  output logic [13:0] seg_min,
  output logic [13:0] seg_hr,
  output logic [13:0] seg_day,
  output logic [13:0] seg_week,
  output logic [13:0] seg_month,
  output logic [13:0] seg_year
);
  localparam logic [6:0] SEC_LAST = DECIMAL ? 7'd99 : 7'd59;
  localparam logic [6:0] MIN_LAST = DECIMAL ? 7'd99 : 7'd59;
  localparam logic [4:0] HR_LAST  = DECIMAL ? 5'd9  : 5'd23;

  // ---------------------------------------------------------------- input synchronisers and button edges
  logic [6:0] raw, s, s_q;                  // {setup_time, setup_alarm, min, hr, day, week, month}
  /* verilator lint_off UNUSEDSIGNAL */
  logic [6:0] press;                        // rising edges; only the five button bits are used
  /* verilator lint_on UNUSEDSIGNAL */
  assign raw = {setup_time, setup_alarm, btn_min, btn_hr, btn_day, btn_week, btn_month};
  if (SYNC == 0) begin : g_nosync
    assign s = raw;
  end else begin : g_sync
    logic [6:0] stage [SYNC];
    always_ff @(posedge clk) begin
      stage[0] <= raw;
      for (int i = 1; i < SYNC; i++) stage[i] <= stage[i-1];
    end
    assign s = stage[SYNC-1];
  end
  always_ff @(posedge clk) s_q <= s;
  assign press = s & ~s_q;

  logic run, set_t, set_a;
  assign run   = (s[6] == s[5]);
  assign set_t = s[6] & ~s[5];
  assign set_a = s[5] & ~s[6];
  logic p_min, p_hr, p_day, p_week, p_month;
  assign {p_min, p_hr, p_day, p_week, p_month} = press[4:0];

  // ---------------------------------------------------------------- terminal counts and carries (run mode)
  logic comp, leap, day_last, week_last;
  assign comp      = CALENDAR && (month == 4'd12);                 // complementary days
  assign leap      = (year[1:0] == 2'b11);
  assign day_last  = comp ? (day >= (leap ? 4'd5 : 4'd4)) : (day >= 4'd9);
  assign week_last = (week >= 2'd2);

  logic c_s, c_m, c_h, c_d, c_w, c_y;
  assign c_s = run && tick && (sec == SEC_LAST);                   // a minute ends
  assign c_m = c_s && (min == MIN_LAST);                           // an hour ends
  assign c_h = c_m && (hr == HR_LAST);                             // a day ends
  assign c_d = CALENDAR && c_h && day_last;                        // a week (or the complementary period) ends
  assign c_w = c_d && !comp && week_last;                          // a month ends
  assign c_y = c_d && comp;                                        // a year ends

  function automatic logic [6:0] wrap7(input logic [6:0] v, input logic [6:0] last);
    wrap7 = (v >= last) ? 7'd0 : v + 7'd1;
  endfunction
  function automatic logic [4:0] wrap5(input logic [4:0] v, input logic [4:0] last);
    wrap5 = (v >= last) ? 5'd0 : v + 5'd1;
  endfunction
  function automatic logic [3:0] wrap4(input logic [3:0] v, input logic [3:0] last);
    wrap4 = (v >= last) ? 4'd0 : v + 4'd1;
  endfunction

  // ---------------------------------------------------------------- time
  always_ff @(posedge clk) begin
    if (rst) begin
      sec <= '0; min <= '0; hr <= '0; day <= '0; week <= '0; month <= '0; year <= '0;
    end else if (run) begin
      if (tick) sec <= wrap7(sec, SEC_LAST);
      if (c_s)  min <= wrap7(min, MIN_LAST);
      if (c_m)  hr  <= wrap5(hr, HR_LAST);
      if (CALENDAR) begin
        if (c_h)         day   <= day_last ? 4'd0 : day + 4'd1;
        if (c_d && !comp) week <= week_last ? 2'd0 : week + 2'd1;
        if (c_w)         month <= month + 4'd1;                     // 11 -> 12: the complementary days
        if (c_y) begin month <= 4'd0; year <= year + 4'd1; end
      end
    end else if (set_t) begin
      if (p_min) min <= wrap7(min, MIN_LAST);
      if (p_hr)  hr  <= wrap5(hr, HR_LAST);
      if (CALENDAR) begin
        if (p_day)   day   <= day_last ? 4'd0 : day + 4'd1;
        if (p_week)  week  <= week_last ? 2'd0 : week + 2'd1;
        if (p_month) month <= wrap4(month, 4'd12);
      end
    end
  end

  // ---------------------------------------------------------------- alarm (changes only while it is being set)
  always_ff @(posedge clk) begin
    if (rst) begin
      alarm_min <= '0; alarm_hr <= '0; alarm_day <= '0; alarm_week <= '0; alarm_month <= '0;
    end else if (set_a) begin
      if (p_min) alarm_min <= wrap7(alarm_min, MIN_LAST);
      if (p_hr)  alarm_hr  <= wrap5(alarm_hr, HR_LAST);
      if (CALENDAR) begin
        if (p_day)   alarm_day   <= wrap4(alarm_day, 4'd9);
        if (p_week)  alarm_week  <= (alarm_week >= 2'd2) ? 2'd0 : alarm_week + 2'd1;
        if (p_month) alarm_month <= wrap4(alarm_month, 4'd12);
      end
    end
  end

  assign buzz = run && alarm_on && (min == alarm_min) && (hr == alarm_hr) &&
                (!CALENDAR || (day == alarm_day && week == alarm_week && month == alarm_month));

  // ---------------------------------------------------------------- seven-segment display
  function automatic logic [6:0] seg7(input logic [3:0] d);        // gfedcba
    case (d)
      4'd0: seg7 = 7'h3F; 4'd1: seg7 = 7'h06; 4'd2: seg7 = 7'h5B; 4'd3: seg7 = 7'h4F; 4'd4: seg7 = 7'h66;
      4'd5: seg7 = 7'h6D; 4'd6: seg7 = 7'h7D; 4'd7: seg7 = 7'h07; 4'd8: seg7 = 7'h7F; 4'd9: seg7 = 7'h6F;
      default: seg7 = 7'h40;                                        // "-"
    endcase
  endfunction
  function automatic logic [13:0] two_digits(input logic [6:0] v); // v = 0..99
    logic [6:0] tens;
    tens = v / 7'd10;
    two_digits = {seg7(4'(tens)), seg7(4'(v - tens * 7'd10))};
  endfunction
  assign seg_sec   = two_digits(set_a ? 7'd0 : sec);
  assign seg_min   = two_digits(set_a ? alarm_min : min);
  assign seg_hr    = two_digits(7'(set_a ? alarm_hr : hr));
  assign seg_day   = two_digits(7'(set_a ? alarm_day : day));
  assign seg_week  = two_digits(7'(set_a ? alarm_week : week));
  assign seg_month = two_digits(7'(set_a ? alarm_month : month));
  assign seg_year  = two_digits(7'(set_a ? 4'd0 : year));
endmodule
