// alarm_clock_formal.sv - invariants of rtl/alarm_clock.sv for every input sequence after the first reset (any tick,
// switch and button pattern, resets at any time). Checked for each configuration by formal/run_formal.sh.
//   P1  every field stays in range: seconds and minutes <= 59 (99 decimal), hours <= 23 (9), day <= 9, week <= 2,
//       month <= 12, and the same for the alarm; without the calendar those fields stay 0
//   P2  while the alarm is being set the time does not change; outside run mode the seconds and the year never
//       change (only the buttons move the other fields); outside alarm-setting mode the alarm does not change
//   P3  buzz only in run mode with alarm_on and every alarm field equal to the time's
//   P4  in run mode a tick advances the seconds by exactly one (modulo a minute); without a tick nothing changes
module alarm_clock_formal #(
  parameter bit DECIMAL  = 1'b1,
  parameter bit CALENDAR = 1'b1
) (
  input logic clk,
  input logic rst,
  input logic tick,
  input logic setup_time,
  input logic setup_alarm,
  input logic alarm_on,
  input logic btn_min,
  input logic btn_hr,
  input logic btn_day,
  input logic btn_week,
  input logic btn_month
);
  logic [6:0]  sec, min, alarm_min;
  logic [4:0]  hr, alarm_hr;
  logic [3:0]  day, month, year, alarm_day, alarm_month;
  logic [1:0]  week, alarm_week;
  logic        buzz;
  logic [13:0] seg_sec, seg_min, seg_hr, seg_day, seg_week, seg_month, seg_year;
  alarm_clock #(.DECIMAL(DECIMAL), .CALENDAR(CALENDAR), .SYNC(2)) dut (.*);

  localparam logic [6:0] SL = DECIMAL ? 7'd99 : 7'd59;
  localparam logic [4:0] HL = DECIMAL ? 5'd9 : 5'd23;

  // the mode the design acts on is the synchronised one: follow the switches through the same two stages
  logic [1:0] m0, m1;
  logic       run, set_a;
  always_ff @(posedge clk) begin m0 <= {setup_time, setup_alarm}; m1 <= m0; end
  assign run   = (m1[1] == m1[0]);
  assign set_a = m1[0] & ~m1[1];

  logic first = 1'b1, second = 1'b1, prst;
  logic [32:0] t_prev;   // {sec, min, hr, day, week, month, year}
  logic [21:0] a_prev;   // {alarm_min, alarm_hr, alarm_day, alarm_week, alarm_month}
  logic        run_prev, set_a_prev, tick_prev;
  logic [6:0]  sec_prev;
  logic [3:0]  year_prev;
  always_ff @(posedge clk) begin
    first <= 1'b0; second <= first; prst <= rst;
    t_prev <= {sec, min, hr, day, week, month, year};
    a_prev <= {alarm_min, alarm_hr, alarm_day, alarm_week, alarm_month};
    run_prev <= run; set_a_prev <= set_a; tick_prev <= tick; sec_prev <= sec; year_prev <= year;
  end
  always_comb if (first || second) assume (rst);     // reset long enough to flush the synchronisers

  always_comb begin
    if (!first && !second) begin
      assert (sec <= SL && min <= SL && hr <= HL && alarm_min <= SL && alarm_hr <= HL);
      if (CALENDAR) begin
        assert (day <= 4'd9 && week <= 2'd2 && month <= 4'd12);
        assert (alarm_day <= 4'd9 && alarm_week <= 2'd2 && alarm_month <= 4'd12);
      end else begin
        assert (day == '0 && week == '0 && month == '0 && year == '0);
        assert (alarm_day == '0 && alarm_week == '0 && alarm_month == '0);
      end
      if (buzz) assert (run && alarm_on && min == alarm_min && hr == alarm_hr &&
                        (!CALENDAR || (day == alarm_day && week == alarm_week && month == alarm_month)));
      if (!prst) begin
        if (set_a_prev) assert ({sec, min, hr, day, week, month, year} == t_prev);
        if (!run_prev) assert (sec == sec_prev && year == year_prev);
        if (!set_a_prev) assert ({alarm_min, alarm_hr, alarm_day, alarm_week, alarm_month} == a_prev);
        if (run_prev && !tick_prev) assert ({sec, min, hr, day, week, month, year} == t_prev);
        if (run_prev && tick_prev) assert (sec == ((sec_prev == SL) ? 7'd0 : sec_prev + 7'd1));
      end
    end
  end
endmodule
