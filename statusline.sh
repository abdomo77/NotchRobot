#!/bin/sh
# NotchRobot ← status line بتاع Claude Code
# بيحفظ الـ JSON عشان النوتش يعرض استهلاك الحساب (5 ساعات وأسبوع)، وبيطبع نفس الأرقام في سطر صغير.
# rate_limits بتيجي بس لمشتركين Pro و Max، وبعد أول رد في الجلسة. لازم يبقى سريع ويخرج بـ 0.
d="$HOME/.notchrobot"
mkdir -p "$d" 2>/dev/null
tmp="$d/usage.json.$$"
cat > "$tmp" 2>/dev/null || exit 0
if ! grep -q '"rate_limits"' "$tmp" 2>/dev/null; then
  rm -f "$tmp"
  exit 0
fi
mv -f "$tmp" "$d/usage.json" 2>/dev/null || exit 0

# من غير jq: نلم الـ JSON في سطر واحد ونطلع الرقم من جوه النافذة
json=$(tr -d '\n' < "$d/usage.json")
pct() {
  printf '%s' "$json" | sed -n "s/.*\"$1\" *: *{[^}]*\"used_percentage\" *: *\([0-9]*\).*/\1/p"
}
h=$(pct five_hour)
w=$(pct seven_day)
out=""
[ -n "$h" ] && out="5h $h%"
[ -n "$w" ] && out="${out:+$out · }7d $w%"
printf '%s\n' "$out"
exit 0
