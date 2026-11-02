# Menu Veil

<img src="Assets/MenuVeil.png" width="96" alt="Menu Veil icon">

I wanted to hide the Apple icon and all the File, Edit, View stuff on the left, but keep the icons on the right. Couldn't find a macOS setting for that. So here's a small app that does it with a cover.

Hover over the left side and the menus fade back in. Move away and they're hidden again. The width follows whichever app you're using, so there's nothing to adjust manually.

![Desktop demo with the left menus hidden](docs/demo.png)

This is an illustrated demo. Open `docs/demo.html` in a browser if you want to try the hover effect.

## Run it

You'll need Xcode's command line tools. From the project folder:

```sh
zsh build.sh
open "build/Menu Veil.app"
```

macOS will need you to allow Accessibility access for Menu Veil. Go to System Settings → Privacy & Security → Accessibility and turn it on there. The app reads the menu positions with that permission. It leaves the menus visible until access is allowed.

Once it's running, look for the little rectangle icon on the right. That's where you can pause it, pick a background, show the menus for ten seconds, or quit. It doesn't add itself to your login items.

## A few details

The app is written in Swift with AppKit. The cover is a window above the menu bar. Clicks go through it to the real menus underneath.

It measures the menu headings every 0.4 seconds and when you switch apps. That includes the Apple menu and greyed-out headings. The hover fade takes 0.2 seconds; hiding waits about half a second, then fades over 0.32 seconds. Opening a menu keeps it revealed. If you have Reduce Motion on, the fades are off.

For the cover background, it reads your wallpaper image. It doesn't record the screen or make network requests. There are no third-party dependencies.

## Things that still need work

I've only tried this on macOS 27.0.1 with one display. It works there, but I haven't checked older versions.

The menus are still underneath the cover, so you won't get extra room for status icons. And the background won't always match perfectly: animated wallpapers and the menu bar's tint can leave a seam. You can pick a solid background instead.

Multiple displays and full-screen apps need more testing. Right now it reuses the same measured width on other displays. Settings also reset when you restart it.

To stop it, quit from the rectangle icon. The cover disappears straight away. You can turn its Accessibility permission back off in System Settings too.
