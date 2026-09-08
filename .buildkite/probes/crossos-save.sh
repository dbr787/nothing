#!/bin/bash
# Saves the platform-agnostic `crossos` cache from Linux so the Windows job can
# try to restore it. Linux-side half of the cross-platform key collision test.
set -uo pipefail

echo "--- Saving crossos from $(uname -s)/$(uname -m)"
mkdir -p bk-crossos/nested
echo "linux $(uname -s) $(uname -m) build ${BUILDKITE_BUILD_NUMBER}" > bk-crossos/origin.txt
printf 'posix mode bits and a symlink follow\n' > bk-crossos/nested/payload.txt
chmod 0500 bk-crossos/nested/payload.txt
ln -sf payload.txt bk-crossos/nested/link.txt
ls -la bk-crossos bk-crossos/nested

buildkite-agent cache save --name crossos
code=$?
echo "RESULT: crossos.linux.save | $([ $code -eq 0 ] && echo PASS || echo FAIL) | exit $code"
exit 0
