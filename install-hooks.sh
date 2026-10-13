#!/bin/sh
# بيوصّل NotchRobot بـ Claude Code:
# بيحط hook.sh و statusline.sh في ~/.notchrobot، وبيضيف الـ hooks والـ status line في ~/.claude/settings.json
# (بياخد نسخة احتياطي الأول، ومش بيلمس status line موجودة)
set -e
cd "$(dirname "$0")"

mkdir -p "$HOME/.notchrobot" "$HOME/.claude"
cp hook.sh statusline.sh "$HOME/.notchrobot/"
chmod +x "$HOME/.notchrobot/hook.sh" "$HOME/.notchrobot/statusline.sh"

settings="$HOME/.claude/settings.json"
# النسخة الاحتياطي بتتاخد أول مرة بس، عشان تفضل الإعدادات اللي قبل NotchRobot
[ -f "$settings" ] && [ ! -f "$settings.bak-notchrobot" ] && cp "$settings" "$settings.bak-notchrobot"

# JXA موجود في كل ماك، فمش محتاجين python أو jq
result=$(osascript -l JavaScript - "$settings" "$HOME/.notchrobot/hook.sh" "$HOME/.notchrobot/statusline.sh" <<'JS'
function run(argv) {
  const path = argv[0], cmd = argv[1], line = argv[2];
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
  // استهلاك الحساب بيوصل بس للـ status line
  let status = "ok";
  if (!s.statusLine) s.statusLine = { type: "command", command: line };
  else if (!JSON.stringify(s.statusLine).includes(".notchrobot/statusline.sh")) status = "statusline-taken";
  $.NSString.alloc.initWithUTF8String(JSON.stringify(s, null, 2) + "\n")
    .writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
  return status;
}
JS
)

echo "✅ NotchRobot hooks installed in $settings"
echo "   Restart any running claude sessions to pick them up."
if [ "$result" = "statusline-taken" ]; then
  echo
  echo "ℹ️  You already have a statusLine, so it was left alone. To see your account usage in the notch,"
  echo "   pipe its input through NotchRobot first, e.g. in your status line script:"
  echo "     input=\$(cat); printf '%s' \"\$input\" | ~/.notchrobot/statusline.sh >/dev/null"
fi
