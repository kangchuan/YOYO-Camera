#!/bin/bash
#
# 手动上传 dSYM 到 Firebase Crashlytics，让崩溃堆栈变成可读的函数名。
#
# 用法:
#   ./scripts/upload_dsyms.sh                 # 自动从 DerivedData 里找最新的 Yoyo.app.dSYM
#   ./scripts/upload_dsyms.sh <dSYM 路径>     # 手动指定
#
# 背景:
#   本工程的 Xcode 构建阶段里没有挂 Crashlytics 的 run 脚本，
#   所以 dSYM 不会自动上传，在线控制台里看到的崩溃堆栈会是裸地址。
#   需要符号化时手动跑一次本脚本即可。
#
#   字段来源: GoogleService-Info.plist（上传目标项目由它决定，
#   所以换过 plist 之后本脚本也会自动指向新项目）。
#
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_DIR="$(dirname "$SCRIPT_DIR")"
PLIST="$CLIENT_DIR/Yoyo/GoogleService-Info.plist"

if [ ! -f "$PLIST" ]; then
  echo "错误: 找不到 $PLIST"
  exit 1
fi

read_plist() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || echo "(未设置)"
}

FORCE=0
DSYM=""
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h | --help)
      echo "用法: $0 [--force] [dSYM 路径]"
      exit 0
      ;;
    *) DSYM="$arg" ;;
  esac
done

PROJECT_ID="$(read_plist PROJECT_ID)"
BUNDLE_ID="$(read_plist BUNDLE_ID)"
APP_ID="$(read_plist GOOGLE_APP_ID)"

echo "当前 GoogleService-Info.plist 指向的项目:"
echo "  PROJECT_ID    = $PROJECT_ID"
echo "  BUNDLE_ID     = $BUNDLE_ID"
echo "  GOOGLE_APP_ID = $APP_ID"
echo ""

if [ "$PROJECT_ID" = "yoyo-camera" ] && [ "$FORCE" -ne 1 ]; then
  echo "已中止: GoogleService-Info.plist 仍指向 Day1 Labs 的 Firebase 项目 (yoyo-camera)。"
  echo "        上传到那个项目的 dSYM 属于第三方工程，不是你的数据，本脚本拒绝执行。"
  echo ""
  echo "        请先在 Firebase 控制台创建自己的项目，把新下载的"
  echo "        GoogleService-Info.plist 覆盖到 Yoyo/GoogleService-Info.plist 后再运行。"
  echo ""
  echo "        如果你确实要往 yoyo-camera 上传(不建议)，用 --force："
  echo "          $0 --force"
  exit 1
fi

UPLOAD_SYMBOLS="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
  -path '*firebase-ios-sdk/Crashlytics/upload-symbols' -type f 2>/dev/null | head -1 || true)"

if [ -z "$UPLOAD_SYMBOLS" ]; then
  echo "错误: 找不到 upload-symbols。"
  echo "      请先在 Xcode 里成功构建一次，让 SwiftPM 把 firebase-ios-sdk 拉下来。"
  exit 1
fi

if [ -z "$DSYM" ]; then
  CANDIDATES="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -maxdepth 7 -type d -name 'Yoyo.app.dSYM' 2>/dev/null || true)"
  DSYM="$(printf '%s\n' "$CANDIDATES" | head -1)"
fi

if [ -z "$DSYM" ] || [ ! -d "$DSYM" ]; then
  echo "错误: 找不到 dSYM。请手动指定:"
  echo "  $0 /path/to/Yoyo.app.dSYM"
  echo ""
  echo "提示: 也可以从 Xcode 的 Organizer (Window > Organizer > Archives) 里"
  echo "      右键某个构建选 Show in Finder，在 .xcarchive 内部找 dSYMs 目录。"
  exit 1
fi

echo "upload-symbols = $UPLOAD_SYMBOLS"
echo "dSYM           = $DSYM"
echo ""
echo "开始上传…"

"$UPLOAD_SYMBOLS" -gsp "$PLIST" -p ios "$DSYM"

echo ""
echo "完成。稍等片刻后到 Firebase 控制台 Crashlytics 页面查看。"
