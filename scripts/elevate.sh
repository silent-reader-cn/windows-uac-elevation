#!/bin/bash
# Run one command elevated via UAC, then print its output.
#
# The wrapper's exit code reflects Start-Process ONLY, not the inner command.
# Always judge by the captured log.
#
# Usage: bash elevate.sh "<command with NATIVE Windows paths>" [logfile]
# Paths inside the command MUST be native (C:/...), never MSYS (/c/...).
set -u

CMD="${1:?usage: elevate.sh \"<command with native Windows paths>\" [logfile]}"
LOG="${2:-C:/tmp/uac-elevation.log}"

rm -f "${LOG}"
powershell -NoProfile -Command \
  "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c','${CMD} > ${LOG} 2>&1' -Verb RunAs -Wait"
rc=$?

echo "--- wrapper exit: ${rc} (does NOT reflect the inner command) ---"
if [ -f "${LOG}" ]; then
  cat "${LOG}"
else
  echo "no log written - check that the command used native C:/ paths, not /c/" >&2
  exit 2
fi
