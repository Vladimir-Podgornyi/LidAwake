<p align="center">
  <img src="docs/images/icon.png" width="128" alt="LidAwake app icon: a closed laptop with amber rays on a dark blue background">
</p>

<h1 align="center">LidAwake</h1>

<p align="center">A macOS menu bar app that keeps your Mac awake, even with the lid closed.</p>

<p align="center">macOS 13+ · Apple silicon · MIT</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/window-dark.png">
    <img src="docs/images/window-light.png" width="335" alt="The LidAwake window with Run with Lid Closed selected and the settings collapsed">
  </picture>
</p>

## What it does

LidAwake keeps a Mac from sleeping in two situations: when you step away from the desk, and when the laptop is closed and travels with you. It lives in the menu bar, has no Dock icon, and offers one switch with three positions, so only one mode can be on at a time.

| | Off | Keep Screen On | Run with Lid Closed |
|---|---|---|---|
| For | normal use | stepping away from the desk | the road |
| Screen | as usual | stays on | may turn off and lock |
| Closing the lid | the Mac sleeps | the Mac sleeps | the Mac keeps running |
| Helper | not used | not used | required |
| Protections | none | timer only | all four |

<p align="center">
  <img src="docs/images/keep-screen-on.png" width="335" alt="The LidAwake window with Keep Screen On selected and a two-hour timer">
</p>

## Protections

Each protection is turned on separately in Settings.

| Protection | What it does | Default |
|---|---|---|
| Stop when the Mac gets hot | Ends the mode when macOS reports the thermal state as serious or critical | on |
| Stop on low battery | Ends the mode when the Mac runs on battery and the charge is at or below the limit (10 to 50 %) | on, 20 % |
| Only while charging | Pauses the mode on battery power and resumes it when power is connected | off |
| Turn off after | Ends the mode after the chosen time (30 min to 8 hours), counted from the moment it was switched on | off, 2 hours |

The timer applies to both modes; the other three protections apply only to Run with Lid Closed.

In Run with Lid Closed, the protections and the timer run in the privileged helper, not in the app, so they keep working if the app crashes or stops responding. If the battery level, the power source or the thermal state cannot be read while the matching protection is on, the mode turns off.

When a protection ends or pauses the mode, LidAwake shows a notification and the reason in its window. If the app was not running when the mode ended, it shows the reason the next time it starts.

Lock screen when the lid closes (on by default) locks the screen as soon as the lid is closed in Run with Lid Closed. It uses a private macOS function; if a macOS version does not have it, the window says so.

<p align="center">
  <img src="docs/images/settings-blue.png" width="335" alt="The LidAwake window with the settings expanded and the Blue accent">
  <img src="docs/images/settings-amber.png" width="335" alt="The LidAwake window with the settings expanded and the Amber accent">
</p>

A closed laptop in a bag cools poorly. The protections reduce the risk; they do not remove it. The thermal protection reacts only to what macOS itself reports as overheating: in tests on a MacBook Air (M1) under full CPU load, the system reported a nominal thermal state throughout, so this protection has never been seen to trip.

## Install

1. Download the DMG from the [latest release](https://github.com/Vladimir-Podgornyi/LidAwake/releases/latest).
2. Drag LidAwake to Applications.
3. Open LidAwake from Applications. Its icon appears in the menu bar.

Launch at login is on by default and is set up on the first launch from Applications. After login the app starts in Off and does not turn a mode on by itself.

The first time you choose Run with Lid Closed, LidAwake registers its helper and asks you to allow it once in System Settings > General > Login Items & Extensions. No password is asked. The window has a button that opens that section. If you allow LidAwake within five minutes, the mode turns on by itself; otherwise choose Run with Lid Closed again. The helper is installed only when the app is in the Applications folder.

Requirements:

- macOS 13 or later.
- A Mac with Apple silicon. The app does not run on Intel Macs.

LidAwake is developed and tested on a MacBook Air (M1) with macOS 26. Older versions of macOS have not been tested. The Glass appearance is available only on macOS 26 and later.

## Updates

Once a day LidAwake sends one request to `api.github.com` for the number of the latest release. The request carries no data about you or your Mac; its User-Agent contains only the app version. Only the version number is read from the reply. If a newer version exists, the window shows Update available with a Download button that opens the releases page. A failed check is silent.

The check is turned off with the Check for updates toggle in Settings; when it is off, no requests are made. Updates are installed by hand: download the new DMG and drag LidAwake over the old copy in Applications.

LidAwake makes no other network requests and contains no analytics. The helper does not use the network.

## How it works

Run with Lid Closed sets the system flag `SleepDisabled` (`pmset -a disablesleep 1`). A privileged helper, a launchd daemon that runs as root, sets and clears it.

- **Lease.** The helper keeps the flag only while the app keeps renewing the session: the app renews every 30 seconds, and the lease lasts two minutes of awake time. If the renewals stop, the helper clears the flag and normal sleep returns. Quitting LidAwake turns the mode off first.
- **Leftovers.** The system starts the helper at boot and after a crash. On start it clears a flag that it set earlier and, if that fails, retries every 30 seconds. With nothing to do it exits after two minutes. When the app starts, it also ends a session left over from its previous run.
- **Signature check.** The helper accepts connections only from LidAwake signed with the developer's Developer ID, and the app talks only to a helper signed the same way. Another program cannot change the flag through the helper.
- **Someone else's flag.** If `SleepDisabled` was set by another program, LidAwake does not clear it. The helper records the flags it sets in `/Library/Application Support/com.vladimirpodgornyi.LidAwake`. If the other program clears its flag during a LidAwake session, the helper sets the flag again and treats it as its own.

Keep Screen On does not use the helper. It holds a power assertion that prevents idle display sleep, as `caffeinate -d` does.

## If the Mac does not sleep

Check the flag:

```sh
pmset -g | grep SleepDisabled
```

`SleepDisabled 1` means sleep is disabled. `SleepDisabled 0` or no such line means it is not.

To clear the flag by hand, first set LidAwake to Off or quit it, otherwise the helper sets the flag again on the next renewal. Then run:

```sh
sudo pmset -a disablesleep 0
```

This also clears a flag that another program has set.

## Uninstall

The helper's launchd job is registered from inside the app bundle, so remove it before deleting the app.

1. In the LidAwake window, choose Off, open Settings and turn off Launch at login.
2. Choose Quit LidAwake.
3. Unregister the helper:

   ```sh
   /Applications/LidAwake.app/Contents/MacOS/LidAwake --uninstall-helper
   ```

   The command prints the helper state and exits.
4. Move LidAwake from Applications to the Trash.
5. Optionally, remove the settings and the helper's folder:

   ```sh
   defaults delete com.vladimirpodgornyi.LidAwake
   sudo rm -r "/Library/Application Support/com.vladimirpodgornyi.LidAwake"
   ```

## Build from source

You need macOS and Xcode; the scripts call `swift build`, `xcrun actool` and `codesign`. The project is a Swift package without an Xcode project file.

```sh
scripts/build-app.sh                # builds build/LidAwake.app
scripts/install-app.sh              # quits a running LidAwake and copies the app to /Applications
scripts/check-localizations.sh      # checks that every interface string exists in all three languages
```

`build-app.sh` signs with a Developer ID Application certificate of team `ZW984867UC` from the keychain, or with the identity in `SIGN_IDENTITY`. Without such a certificate it signs ad hoc and prints a warning that the privileged helper will not work in this build. The app and the helper accept each other only with a Developer ID signature of that team. Run with Lid Closed has not been tested in a build signed any other way.

`scripts/release.sh` builds, notarizes and packs the DMG for a release. It needs the Developer ID certificate of that team and a `notarytool` keychain profile.

## Languages

The interface is in English, German and Russian. The language follows the system settings.

## License

[MIT](LICENSE)
