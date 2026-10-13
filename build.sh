#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=NotchRobot.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources

swiftc -O -swift-version 5 Sources/*.swift -o $APP/Contents/MacOS/NotchRobot \
  -framework SwiftUI -framework IOKit -framework ServiceManagement
cp icon/AppIcon.icns $APP/Contents/Resources/AppIcon.icns
clang -dynamiclib -fobjc-arc -O2 -framework Foundation mr/nowplaying.m -o $APP/Contents/Resources/libnowplaying.dylib

cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>NotchRobot</string>
  <key>CFBundleIdentifier</key><string>com.gendy.notchrobot</string>
  <key>CFBundleExecutable</key><string>NotchRobot</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleDisplayName</key><string>NotchRobot</string>
  <key>CFBundleShortVersionString</key><string>2.2</string>
  <key>CFBundleVersion</key><string>$(date +%Y%m%d%H%M)</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>روبو محتاج يشوف تاب يوتيوب الشغال عشان يجيب صورة الأغنية</string>
</dict></plist>
PLIST
codesign --force -s - $APP/Contents/Resources/libnowplaying.dylib
codesign --force -s - $APP

# hook بتاع Claude Code في مكان ثابت
mkdir -p ~/.notchrobot
cp hook.sh statusline.sh ~/.notchrobot/
chmod +x ~/.notchrobot/hook.sh ~/.notchrobot/statusline.sh
echo "✅ Built $APP"

# ./build.sh install → يتسطّب في /Applications ويشتغل من هناك
if [[ "$1" == "install" ]]; then
  pkill -x NotchRobot 2>/dev/null && sleep 1 || true
  rm -rf /Applications/$APP
  ditto $APP /Applications/$APP
  # النسخة اللي في فولدر المشروع متبانش في Spotlight/Launchpad جنب المتسطّبة
  rm -rf $APP
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/$APP
  open /Applications/$APP
  echo "✅ Installed /Applications/$APP"
fi
