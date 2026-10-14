# Changelog

All notable changes to NotchRobot. [العربي](#بالعربي)

## v2.5

### New
- **Smart clipboard.** Copied text is recognized as a link, email, color (`#FF6B35`), JSON, or file path, and each gets a one-click action: open the link, write an email, copy the color as `rgb()`, pretty-print the JSON, or show the file in Finder.
- **Pinned clipboard items.** Right-click → **Pin** to keep up to 5 things you paste often at the top. Pinned items survive **Clear all** and restarts.
- **Screenshots to the shelf.** Press **⌃⌥S** (or the button in the shelf tab), select part of the screen, and the image lands on the shelf and on your clipboard. Files are saved in `~/Pictures/NotchRobot`.
- **Live Activities.** When a new song starts or Claude moves on to its next task, the island stretches for a few seconds to show it. The timer and Claude's task list now show a small progress ring next to the notch.
- **Themes.** A new style tab (🖌) with four notch looks (Dark, Glass, Neon, Minimal) and six accent colors.
- **Characters.** Pick a Robot, Cat, Ghost, or Pixel buddy. Each one reacts to everything the robot did: thinking, listening, sleeping, dancing to music.
- **Battery.** Plugging in shows a battery that fills up in front of you. You get a warning at 20% and 10%, a red battery next to the notch below 10%, and a note when it's fully charged. The notch now hears about the charger from macOS right away, instead of checking every 30 seconds.
- **Welcome tour.** A short four-page tour the first time you open NotchRobot: what it does, picking a look, and the permissions it may ask for. Replay it from the style tab.
- **Automatic updates.** NotchRobot downloads the new release from GitHub, checks it's a newer, correctly signed NotchRobot, replaces itself, and reopens. It waits if a Claude card is open. Turn it off in Settings with **Update automatically**, or update by hand with the **Update to vX** button.

### Notes
- Pinned clipboard items are saved in the app's preferences. The rest of the clipboard history is still kept in memory only.
- Screenshots need the **Screen Recording** permission. macOS asks the first time.
- NotchRobot isn't notarized, so macOS may forget granted permissions (Screen Recording, Automation) after an update. Grant them again if screenshots or terminal focus stop working.

## v2.4

### New
- **Swipe between tabs** with two fingers on the trackpad while the notch is open.
- **Usage alerts.** A warning when your 5-hour or weekly limit reaches 90%, and a note once when it resets.
- **Seek.** Drag the song progress bar to jump through the track.

### Changed
- Calmer tab switch animation.
- Softer artwork glow around the notch.

## v2.3

### New look
- **Dynamic Island style:** a pill that springs open into a rounded island, with blur transitions.
- **Apple design:** SF Pro, iOS dark colors, a segmented tab bar, and iPhone-style switches.
- **Permission card:** round Allow / Deny / Terminal buttons, like an incoming call.
- **Question card:** iOS-style list with blue checkmarks.

### Fixed
- The permission card no longer disappears while Claude runs other tools or subagents in the same session.

## v2.2

### New
- **Account usage:** your plan's 5-hour and weekly usage, with reset times (Pro and Max plans).
- **Task progress:** sessions show `2/4`, a progress bar, and the task Claude is on now.
- **English UI:** follows your Mac's language; switch in Settings.
- **Update check:** NotchRobot tells you when a new version is out.

### Changed
- The status line shows the model name even without usage data.
- `install-hooks.sh` backs up your settings only the first time.

## v2.1

First public release.

- Claude Code sessions in the notch (working, waiting, done), with click-to-focus for Terminal and iTerm2.
- Allow or deny tool permissions from the notch.
- Answer Claude's questions from the notch: single choice, multi-select, and multiple questions.
- Now playing, clipboard history, file shelf, and timer.

---

## بالعربي

### v2.5
- **كليب بورد ذكي:** بيعرف اللينك والإيميل واللون والـ JSON ومسار الملف، وجنب كل واحد زرار: يفتح اللينك، يكتب إيميل، ينسخ اللون `rgb()`، يرتّب الـ JSON، أو يوريك الملف في Finder.
- **تثبيت في الكليب بورد:** كليك يمين ← ثبّت، لحد 5 حاجات بتفضل فوق حتى لو مسحت الكل أو قفلت التطبيق.
- **سكرين شوت على الرف:** دوس **⌃⌥S** وحدد حتة من الشاشة، الصورة هتتحط على الرف وتتنسخ. بتتحفظ في `~/Pictures/NotchRobot`.
- **Live Activities:** لما أغنية جديدة تشتغل أو كلود يبدأ المهمة اللي بعدها، الجزيرة بتتمد ثواني وتعرضها. والتايمر ومهام كلود بقى ليهم دايرة تقدم جنب النوتش.
- **ثيمات:** تبويب جديد للشكل (🖌) فيه غامق وزجاج ونيون وهادي، و6 ألوان.
- **شخصيات:** روبوت أو قطة أو شبح أو بكسل، وكلهم بيتفاعلوا زي الروبوت بالظبط.
- **البطارية:** أنيميشن شحن أول ما توصّل الشاحن، وتنبيه عند 20% و10%، وبطارية حمرا جنب النوتش تحت 10%.
- **ترحيب:** أربع صفحات أول مرة تفتح التطبيق، وتقدر تشوفها تاني من تبويب الشكل.
- **تحديث تلقائي:** بينزّل الإصدار الجديد من GitHub ويتأكد منه ويركّبه ويفتح تاني. تقدر تقفله من الإعدادات.

التفاصيل الكاملة للإصدارات القديمة فوق بالإنجليزي.
