# Release notes

Newest first. Each release needs a `## <version>` section matching its git tag (v1.3 → `## 1.3`);
build.sh refuses to build without it.

## 2.0

Redpaper is now **Easy Backgrounds**. Reddit closed its public feeds in November 2026, which broke fetching (the misleading "r/… doesn't exist" error), and it no longer gives API access to apps like this one. Wallpapers now come from Wallhaven, which needs no account or key.

- **Topics replace subreddits.** You start with landscape, nature and space. Add more from a menu of 50 popular topics, or type your own.
- **Newest or top of the month, year or all time.** "Top today" and "Top this week" are gone: on Wallhaven those lists are nearly empty once filtered by topic and screen size.
- **Safe for work only, no anime or people categories.** The NSFW setting is gone.
- **Never repeats, for real.** The app used to forget wallpapers after 1,000; now it remembers every one it has shown.
- Each wallpaper links to its page on Wallhaven.

**Updating from Redpaper.** Easy Backgrounds is a new app next to the old one, and your settings, history and kept wallpapers don't carry over. Do this once:

1. In Redpaper, right-click any wallpaper you want to keep under **History → Kept** and choose **Save to Pictures**.
2. In Redpaper, turn off **Settings → Launch at login**, then choose **Quit Redpaper**.
3. In your Redpaper folder, run `git pull && ./deploy.sh`. This installs and starts Easy Backgrounds.
4. Delete `/Applications/Redpaper.app`.
5. In Easy Backgrounds, choose your topics and turn on **Settings → Launch at login** again.
6. Optional: delete Redpaper's old images and settings with `rm -rf ~/Library/Application\ Support/Redpaper && defaults delete local.Redpaper`.

## 1.4

- Don't like the new wallpaper? Each update now downloads the best few images, and "This time's top 3" on the Now tab lets you switch between them right away, without waiting for Reddit. Switching doesn't change the schedule.
- Set how many images each update downloads (1–5) in Settings. At 1, it works as before.

## 1.3

- Release notes: see what changed in Settings, and after updating.
- With the same wallpaper on all screens, a display that connects after an update (e.g. on wake) now gets the new wallpaper too.

## 1.2

- Pick from the top posts of the day, week, month, year or all time, besides the newest.
- Right-click a wallpaper in History to save it to Pictures.
- "Check Now" button for updates in Settings.

## 1.1

- Tells you when a new version is released.
