# report-timeout

Says plainly that a step timed out. A step that hits its `timeout-minutes` is only
shown as failed, and a job that hits its own limit is shown as cancelled with no
step able to run afterwards, so neither says why.

Record `date +%s` before and after the step (the second with `if: always()`),
then call this with `if: failure() && steps.<id>.outcome == 'failure'`. If the step ran
for about its limit it emits `::error title=Timed out::<name> ran N min (limit M min); ...`
and writes the same line to the job summary. An ordinary failure gets nothing.

| input | notes |
| --- | --- |
| `name` | what to call the step in the message |
| `started`, `ended` | epoch seconds |
| `limit` | the step's `timeout-minutes` |

Used by the `R-CMD-check` workflow.
