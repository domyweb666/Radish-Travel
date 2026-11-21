#!/usr/bin/env bash
# 把 App Store Connect API 金鑰從環境變數 ASC_KEY_P8_BASE64 還原成檔案，並先驗格式。
# 用法：bash ios/ci/restore_asc_key.sh <輸出路徑>
# 兩種放法都吃：base64 編過的一串，或 .p8 檔的原文（-----BEGIN PRIVATE KEY----- 開頭）。
# 2026-11-15 踩到：secret 放的是原文，舊流程照 base64 解出一坨亂碼，
# 到 archive 才回看不懂的 keyPathInvalid。所以在這裡驗，只印形狀，不印內容。
set -euo pipefail

OUT="${1:?要給輸出路徑}"

case "${ASC_KEY_P8_BASE64:-}" in
  "")
    echo "::error::沒有 ASC_KEY_P8_BASE64 這個 secret。請照 ios/ci/README.md 第八段放。"
    exit 1
    ;;
  -----BEGIN*)
    FORM="原文"
    # 2026-11-22 踩到：貼進 GitHub 時換行不見了（或變成空白），整把金鑰擠成一行，openssl 不認。
    # 所以不管原本有沒有換行，都把頭尾標記拿掉、空白全去掉，再照每行 64 個字重排。
    BODY="$(printf '%s' "$ASC_KEY_P8_BASE64" \
      | sed -e 's/-----BEGIN PRIVATE KEY-----//' -e 's/-----END PRIVATE KEY-----//' \
      | tr -d ' \r\n\t')"
    {
      echo "-----BEGIN PRIVATE KEY-----"
      printf '%s\n' "$BODY" | fold -w 64
      echo "-----END PRIVATE KEY-----"
    } > "$OUT"
    ;;
  *)
    FORM="base64"
    printf '%s' "$ASC_KEY_P8_BASE64" | base64 --decode > "$OUT" || true
    ;;
esac
chmod 600 "$OUT"

BYTES="$(wc -c < "$OUT" | tr -d ' ')"
if ! openssl pkey -in "$OUT" -noout 2> /dev/null; then
  HEADER=no
  if LC_ALL=C head -c 27 "$OUT" | LC_ALL=C grep -q -- "-----BEGIN PRIVATE KEY-----"; then HEADER=yes; fi
  echo "::error::ASC_KEY_P8_BASE64 還原出來不是有效的 .p8 金鑰。放法：${FORM}；大小 ${BYTES} bytes（正常約 257）；開頭是金鑰標頭：${HEADER}。請照 ios/ci/README.md 第八段重放這個 secret。"
  rm -f "$OUT"
  exit 1
fi
echo "API 金鑰格式正確（放法：${FORM}，${BYTES} bytes）"
