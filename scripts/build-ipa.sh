#!/bin/bash
# SingFor10 本地一键构建未签名 IPA
# 使用：在 Mac 终端执行  bash scripts/build-ipa.sh
# 产物：./build/output/SingFor10-unsigned.ipa

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> [1/4] 检查 Xcode"
xcodebuild -version

echo "==> [2/4] 归档（不签名）"
mkdir -p build
xcodebuild \
  -project SingFor10.xcodeproj \
  -scheme SingFor10 \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ROOT/build/SingFor10.xcarchive" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  SKIP_INSTALL=NO \
  clean archive

echo "==> [3/4] 打包 IPA"
APP="$ROOT/build/SingFor10.xcarchive/Products/Applications/SingFor10.app"
OUT="$ROOT/build/output"
if [ ! -d "$APP" ]; then
  echo "ERROR: 未找到归档产物 $APP" >&2
  exit 1
fi
mkdir -p "$OUT/Payload"
rm -rf "$OUT/Payload/SingFor10.app"
cp -R "$APP" "$OUT/Payload/SingFor10.app"
cd "$OUT"
rm -f SingFor10-unsigned.ipa
zip -qry SingFor10-unsigned.ipa Payload
shasum -a 256 SingFor10-unsigned.ipa

echo "==> [4/4] 完成"
echo "IPA 路径: $OUT/SingFor10-unsigned.ipa"
ls -lh "$OUT/SingFor10-unsigned.ipa"
