#!/usr/bin/env bash
set -euo pipefail

: "${THEOS:?Set THEOS first, e.g. export THEOS=$HOME/theos}"

make clean
make stage

APP="$(find .theos/_ -type d -path '*/Applications/AWSLivenessPractice.app' 2>/dev/null | head -n 1 || true)"
if [[ -z "$APP" ]]; then
  echo "Could not find staged AWSLivenessPractice.app"
  exit 1
fi

rm -rf build/Payload
mkdir -p build/Payload
cp -R "$APP" build/Payload/AWSLivenessPractice.app

(
  cd build
  rm -f "AWSLivenessPractice-2.0.tipa"
  zip -qry "AWSLivenessPractice-2.0.tipa" Payload
)

echo "Built: build/AWSLivenessPractice-2.0.tipa"
