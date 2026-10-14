#!/bin/sh
# بيعرض مميزات NotchRobot واحدة ورا التانية عشان تصوّر فيديو.
# كل البيانات تجريبية (جلسة demo-…)، ومش بيلمس جلسات كلود الحقيقية. بيرجّع كل حاجة زي ما كانت في الآخر.
# الاستخدام: ابدأ تسجيل الشاشة، شغّل أغنية، وبعدين ./scripts/demo.sh
set -u
nr="$HOME/.notchrobot"
inbox="$nr/inbox"
dylib="/Applications/NotchRobot.app/Contents/Resources/libnowplaying.dylib"
sid="demo-$$"
js="$(mktemp -t nrdemo).js"

cat > "$js" <<'JS'
ObjC.import('Foundation');
function run(argv) {
  $.NSDistributedNotificationCenter.defaultCenter
    .postNotificationNameObjectUserInfoDeliverImmediately('com.gendy.notchrobot.demo', argv[0], $.NSDictionary.dictionary, true);
}
JS

# أمر للتطبيق
nr() { osascript -l JavaScript "$js" "$1" >/dev/null 2>&1; }
# حدث كأنه جاي من Claude Code. الـ pid التالت لازم يفضل عايش عشان كروت الإذن متختفيش
fake_hook=""
ev() {
  f="$inbox/demo-$(date +%s)-$RANDOM"
  { printf '0 - %s\n' "${fake_hook:-0}"; printf '%s' "$1"; } > "$f.tmp" && mv "$f.tmp" "$f.json"
}
music() { NOTCHROBOT_MR="$1" /usr/bin/perl -e 'use DynaLoader; DynaLoader::dl_load_file($ARGV[0], 0) or exit 1;' "$dylib" 2>/dev/null; }
usage() { # usage <5h%> <ثواني لحد ما يرجع>
  now=$(date +%s)
  printf '{"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":41,"resets_at":%s}}}' \
    "$1" $((now + $2)) $((now + 300000)) > "$nr/usage.json.tmp" && mv -f "$nr/usage.json.tmp" "$nr/usage.json"
  nr poll
}
task_new() { ev '{"hook_event_name":"PostToolUse","session_id":"'$sid'","tool_name":"TaskCreate","tool_input":{"subject":"'"$2"'"},"tool_response":{"task":{"id":"'$1'"}}}'; }
task_set() { ev '{"hook_event_name":"PostToolUse","session_id":"'$sid'","tool_name":"TaskUpdate","tool_input":{"taskId":"'$1'","status":"'$2'"}}'; }
tool() { ev '{"hook_event_name":"PreToolUse","session_id":"'$sid'","tool_name":"'$1'","tool_input":'"$2"'}'; }

cleanup() {
  ev '{"hook_event_name":"SessionEnd","session_id":"'$sid'"}'
  [ -n "$fake_hook" ] && kill "$fake_hook" 2>/dev/null
  [ -f "$nr/usage.json.demo-backup" ] && mv -f "$nr/usage.json.demo-backup" "$nr/usage.json"
  defaults delete com.gendy.notchrobot usageAlert.five_hour >/dev/null 2>&1
  rm -f "$nr"/replies/demo-* "$js"
  nr poll
  nr release
}
trap cleanup EXIT INT TERM

[ -f "$nr/usage.json" ] && cp "$nr/usage.json" "$nr/usage.json.demo-backup"
sleep 600 & fake_hook=$!

echo "▶︎ النوتش المقفول والأغنية شغالة"
nr hold; nr collapse
sleep 3

echo "▶︎ النوتش بيفتح"
nr tab:home; nr expand
sleep 3

echo "▶︎ جلسة كلود + المهام + الاستهلاك"
ev '{"hook_event_name":"SessionStart","session_id":"'$sid'","cwd":"/Users/demo/NotchRobot","source":"startup"}'
ev '{"hook_event_name":"UserPromptSubmit","session_id":"'$sid'","prompt":"ضيف تنبيهات الاستهلاك للنوتش"}'
task_new 1 "أقرا الكود"; task_new 2 "أضيف التنبيهات"; task_new 3 "أجرّب البيلد"; task_new 4 "أحدّث الـ README"
task_set 1 in_progress
tool Read '{"file_path":"/Users/demo/NotchRobot/Sources/ClaudeStore.swift"}'
usage 63 7200
nr tab:claude
sleep 2.5
task_set 1 completed; task_set 2 in_progress; tool Edit '{"file_path":"/Users/demo/NotchRobot/Sources/NotchModel.swift"}'
sleep 2
task_set 2 completed; task_set 3 in_progress; tool Bash '{"command":"./build.sh"}'
sleep 2.5

echo "▶︎ الموسيقى + تقديم الأغنية"
nr tab:music
sleep 2.5
music seek:75
sleep 3

echo "▶︎ تقليب التبويبات"
for t in clipboard shelf timer settings home; do nr tab:$t; sleep 1.3; done
nr collapse
sleep 1.5

echo "▶︎ كارت الإذن"
ev '{"hook_event_name":"PermissionRequest","session_id":"'$sid'","cwd":"/Users/demo/NotchRobot","tool_name":"Bash","tool_input":{"command":"swift build -c release"}}'
sleep 4
nr allow
ev '{"hook_event_name":"PostToolUse","session_id":"'$sid'","tool_name":"Bash","tool_input":{"command":"swift build -c release"}}'
sleep 2

echo "▶︎ كارت السؤال"
ev '{"hook_event_name":"PermissionRequest","session_id":"'$sid'","cwd":"/Users/demo/NotchRobot","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"أضيف أنهي تنبيهات؟","header":"التنبيهات","multiSelect":true,"options":[{"label":"لما الليمت يوصل 90%","description":"تنبيه برتقالي على النوتش"},{"label":"كل ساعة","description":"ملخص الاستهلاك"},{"label":"لما الليمت يرجع","description":"تنبيه أخضر مرة واحدة"}]}]}}'
sleep 2.5
nr pick:0; sleep 1.2
nr pick:2; sleep 1.5
nr send
task_set 3 completed; task_set 4 in_progress
sleep 2

echo "▶︎ تنبيه الاستهلاك 92%"
usage 92 9
sleep 10
echo "▶︎ الليمت رجع"
nr poll
sleep 6

echo "▶︎ كلود خلص"
task_set 4 completed
ev '{"hook_event_name":"Stop","session_id":"'$sid'","last_assistant_message":"ضفت تنبيه لما الليمت يوصل 90%، وتنبيه مرة واحدة لما يرجع."}'
sleep 5

echo "✅ خلص"
