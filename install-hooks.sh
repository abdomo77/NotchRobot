#!/bin/sh
# بيوصّل NotchRobot بـ Claude Code:
# بيحط hook.sh في ~/.notchrobot وبيضيف الـ hooks في ~/.claude/settings.json (بياخد نسخة احتياطي الأول)
set -e
cd "$(dirname "$0")"

mkdir -p "$HOME/.notchrobot" "$HOME/.claude"
cp hook.sh "$HOME/.notchrobot/hook.sh"
chmod +x "$HOME/.notchrobot/hook.sh"

settings="$HOME/.claude/settings.json"
[ -f "$settings" ] && cp "$settings" "$settings.bak-notchrobot"

# JXA موجود في كل ماك، فمش محتاجين python أو jq
osascript -l JavaScript - "$settings" "$HOME/.notchrobot/hook.sh" >/dev/null <<'JS'
function run(argv) {
  const path = argv[0], cmd = argv[1];
  const fm = $.NSFileManager.defaultManager;
  let s = {};
  if (fm.fileExistsAtPath(path)) {
    const text = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null).js;
    if (text && text.trim()) s = JSON.parse(text);
  }
  s.hooks = s.hooks || {};
  // الأحداث اللي ليها أدوات بتاخد matcher
  const events = {
    SessionStart: null, SessionEnd: null, UserPromptSubmit: null, Notification: null,
    Stop: null, StopFailure: null,
    PreToolUse: "*", PostToolUse: "*", PostToolUseFailure: "*", PermissionRequest: "*",
  };
  for (const name in events) {
    const list = s.hooks[name] = s.hooks[name] || [];
    if (JSON.stringify(list).includes(".notchrobot/hook.sh")) continue;
    // طلب الإذن بيستنى ردك من النوتش لحد 5 دقايق
    const entry = { hooks: [{ type: "command", command: cmd, timeout: name === "PermissionRequest" ? 310 : 5 }] };
    if (events[name]) entry.matcher = events[name];
    list.push(entry);
  }
  $.NSString.alloc.initWithUTF8String(JSON.stringify(s, null, 2) + "\n")
    .writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
  return "ok";
}
JS

echo "✅ NotchRobot hooks installed in $settings"
echo "   Restart any running claude sessions to pick them up."
