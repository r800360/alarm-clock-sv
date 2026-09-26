#!/bin/bash
# run_formal.sh - unbounded proofs (ABC PDR) of formal/alarm_clock_formal.sv for all three configurations, then
# negative controls that must fail. Summary: build/formal/summary.txt
cd "$(dirname "$0")/.."
OUTD=build/formal; mkdir -p $OUTD/mutants
OUT=$OUTD/summary.txt; : > $OUT
bad=0
check() {  # expected tag rtl-file params
  local r; r=$(bash formal/pdr.sh "$2" alarm_clock_formal "$3 formal/alarm_clock_formal.sv" "$4")
  local got=${r#*: }; got=${got%% *}
  if [ "$got" = "$1" ]; then echo "  ok        $r" | tee -a $OUT
  else echo "  UNEXPECTED (expected $1) $r" | tee -a $OUT; bad=1; fi
}
mutant() {  # name sed-expression
  sed "$2" rtl/alarm_clock.sv > $OUTD/mutants/$1.sv
  if cmp -s rtl/alarm_clock.sv $OUTD/mutants/$1.sv; then echo "  mutation $1 did not apply" | tee -a $OUT; bad=1; return 1; fi
}
R=rtl/alarm_clock.sv
echo "== range, mode and buzz invariants" | tee -a $OUT
check PROVED conventional $R "-set DECIMAL 0 -set CALENDAR 0"
check PROVED decimal      $R "-set DECIMAL 1 -set CALENDAR 0"
check PROVED calendar     $R "-set DECIMAL 1 -set CALENDAR 1"
echo "== negative controls: each must FAIL" | tee -a $OUT
mutant button_in_run "s/      if (tick) sec <= wrap7(sec, SEC_LAST);/      if (tick || p_min) sec <= wrap7(sec, SEC_LAST);/" \
  && check FAILED mut_button_in_run $OUTD/mutants/button_in_run.sv "-set DECIMAL 1 -set CALENDAR 1"
mutant month_wrap13 "s/if (p_month) month <= wrap4(month, 4'd12);/if (p_month) month <= wrap4(month, 4'd13);/" \
  && check FAILED mut_month_wrap13 $OUTD/mutants/month_wrap13.sv "-set DECIMAL 1 -set CALENDAR 1"
mutant alarm_runs "s/    end else if (set_a) begin/    end else begin/" \
  && check FAILED mut_alarm_runs $OUTD/mutants/alarm_runs.sv "-set DECIMAL 0 -set CALENDAR 0"
if [ $bad -eq 0 ]; then echo "ALL OUTCOMES AS EXPECTED" | tee -a $OUT; else echo "SOME OUTCOMES UNEXPECTED" | tee -a $OUT; fi
exit $bad
