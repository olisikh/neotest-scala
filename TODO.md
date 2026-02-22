## Bloop

ZIO-test:
- stdout parsing is non-deterministic, zio runs tests in parallel producing different output
to troubleshoot: run test multiple times, see how diagnostics jump in the buffer

MUnit:
- exception line is not determined correctly for exceptions with stacktrace
- exceptions without stacktrace can't be shown at correct line number. No line number information in stdout.

Scalatest:
- stacktrace parsing is non-determninistic, same issue like in ZIO
- FreeSpec: nested tests always shown failing

uTest:
- looks like bloop is not supported (investigate)

Specs2:
- exceptions are not matched correctly

## Next steps
- FlatSpec: is not supported, but is quite challenging to support
