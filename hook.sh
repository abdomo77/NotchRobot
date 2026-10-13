#!/bin/sh
# NotchRobot ← Claude Code hook
# بيحط الـ event في inbox والتطبيق يقراه. ممنوع يطبع أي حاجة على stdout (غير رد الإذن)، ولازم exit 0.
pgrep -qx NotchRobot 2>/dev/null || exit 0
d="$HOME/.notchrobot/inbox"
r="$HOME/.notchrobot/replies"
mkdir -p "$d" "$r" 2>/dev/null
pid=$PPID
case "$(ps -o comm= -p "$pid" 2>/dev/null)" in
  *sh) pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ') ;;
esac
id="$(date +%s)-$$"
f="$d/$id"
# الهيدر: pid بتاع claude، التيرمنال، pid بتاع الـ hook ده
{ printf '%s %s %s\n' "${pid:-0}" "${__CFBundleIdentifier:--}" "$$"; cat; } > "$f.tmp" 2>/dev/null || exit 0
mv "$f.tmp" "$f.json" 2>/dev/null || exit 0

# طلب إذن: نستنى ردك من النوتش لحد 5 دقايق.
# الرد بيكتبه التطبيق بس لما تدوس زرار. رد فاضي أو مفيش رد = السؤال العادي في التيرمنال.
if grep -q '"hook_event_name" *: *"PermissionRequest"' "$f.json" 2>/dev/null; then
  i=0
  while [ $i -lt 1200 ]; do
    if [ -f "$r/$id.json" ]; then
      cat "$r/$id.json"
      rm -f "$r/$id.json"
      exit 0
    fi
    pgrep -qx NotchRobot 2>/dev/null || exit 0
    sleep 0.25
    i=$((i + 1))
  done
fi
exit 0
