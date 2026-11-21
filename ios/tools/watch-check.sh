#!/usr/bin/env bash
# 等 HEAD 那次 push 的「iOS check」跑完，印各關結果；紅燈就印錯誤行；把 UI 測試的截圖抓回來。
# 要先 gh auth login。用法：bash ios/tools/watch-check.sh [輸出資料夾]
# 會等到跑完（十幾分鐘），建議丟背景。
cd "$(dirname "$0")/../.." || exit 1
SCRATCH="${1:-${TMPDIR:-/tmp}/radish-ci}"
SHA=$(git rev-parse HEAD)
RUN=""
for i in $(seq 1 30); do
  RUN=$(gh run list --workflow=ios-check.yml --limit 8 --json databaseId,headSha --jq ".[] | select(.headSha==\"$SHA\") | .databaseId" | head -1)
  [ -n "$RUN" ] && break
  sleep 6
done
[ -z "$RUN" ] && { echo "找不到這次 push 的執行"; exit 1; }
echo "run $RUN  sha ${SHA:0:7}"
for i in $(seq 1 200); do
  ST=$(gh run view "$RUN" --json status --jq .status)
  [ "$ST" = "completed" ] && break
  sleep 12
done
gh run view "$RUN" --json jobs --jq '.jobs[] | .name + " = " + (.conclusion // .status)'
gh run view "$RUN" --json jobs --jq '.jobs[] | .steps[] | select(.conclusion=="failure") | "  失敗的步驟：" + .name'
OUT="$SCRATCH/${SHA:0:7}"
rm -rf "$OUT"; mkdir -p "$OUT"
gh run download "$RUN" --dir "$OUT" >/dev/null 2>&1
CORE="$OUT/radish-core-log/core-test.log"
if [ -f "$CORE" ]; then
  echo "--- 規則引擎測試（錯誤與結果行）"
  grep -E "error:|warning: unre|failed|XCTAssert|Executed [0-9]+ tests|Compiling|Build complete" "$CORE" | grep -v "^\[" | sed 's#/__w/Radish-Travel/Radish-Travel/##' | sort -u | cut -c1-400 | head -120
fi
LOG="$OUT/radish-ui-log/build-uitest.log"
if [ -f "$LOG" ]; then
  echo "--- 編譯與 UI 測試（錯誤與結果行）"
  grep -E "error:|Test Case .*(failed)|XCTAssert|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)|BUILD (SUCCEEDED|FAILED)|Testing failed|\*\* " "$LOG" | sed 's#/Users/runner/work/Radish-Travel/Radish-Travel/##' | sort -u | cut -c1-420 | head -120
else
  J=$(gh run view "$RUN" --json jobs --jq '.jobs[] | select(.name|startswith("編譯")) | .databaseId')
  echo "--- 沒有編譯紀錄，印 macOS 那一關失敗的步驟"
  gh run view --job "$J" --log-failed 2>/dev/null | sed 's/^.*Z //' | grep -vE "^\s*$" | tail -40 | cut -c1-300
fi
echo "--- 截圖"
ls "$OUT/radish-ui-screenshots" 2>/dev/null | head -100
echo "下載到：$OUT"
