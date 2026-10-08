# Intel source-build verification

A contributor tested a native Intel source build on 2026-10-08. The app ran with the lid physically closed, and its helper continued responding. This is evidence for the configuration below, rather than a change to the architectures shipped in the published release.

## Environment

| Item | Tested configuration |
| --- | --- |
| Mac | MacBook Pro, MacBookPro16,1 |
| Processor | Intel Core i7-9750H, 2.6 GHz, six cores |
| macOS | 14.8.7, build 23J520 |
| Swift | Apple Swift 6.0.3, Command Line Tools |
| Executables | Native x86_64 app and helper; deployment target macOS 13.0 |

## Results

| Check | Observation |
| --- | --- |
| Release compilation | Both executables compiled successfully for x86_64 |
| Localization coverage | The compiler found 86 strings, all present in the four language tables |
| Simplified Chinese UI | Nine native window snapshots rendered; light/dark settings and update/logout banners were visually checked |
| System language selection | An installed build selected Simplified Chinese from the system preference `zh-Hans-CN`, without a language override |
| Keep Screen On assertion | The app's real IOKit assertion appeared in the process assertion list and disappeared after release |
| Power and thermal readings | Battery, AC power and thermal state were readable through the project's implementations |
| Helper registration and XPC | Registration was enabled/current and protocol version 7 responded using the temporary signing setup below |
| Unauthorized caller | A caller without the local signing certificate was rejected |
| Session lifecycle | Starting a helper session set SleepDisabled to 1; ending it restored 0 |
| Physical closed lid | Three checks over 30 seconds reported a closed lid, SleepDisabled=1, an active owned session and a responsive app/helper |

The physical closed-lid checks ran at 12:31:16, 12:31:31 and 12:31:46 (UTC+8), while connected to AC power at 100% battery. Each reported:

```text
AppleClamshellState = Yes
SleepDisabled = Yes
enabled protocol=7 sleep-disabled=1 session=ours paused=no timer=off battery=100 power=ac thermal=fair registration=current
```

## Temporary signing setup

The unmodified source requires the original developer's Developer ID certificate for both sides of the XPC connection. An ad-hoc build cannot satisfy those requirements.

To exercise the helper locally, a separate, temporary source copy used a self-signed code-signing certificate. Both XPC requirements pinned the corresponding bundle identifier and the same certificate fingerprint. Signature verification remained enabled in both directions. No system certificate trust rules were added. The upstream source and release-signing requirements were not changed.

Consequently, the helper and closed-lid results above apply to that locally signed test build. They do not show that an ad-hoc build, the published Apple silicon download, or an unmodified build signed by a different developer will work on Intel.

## Limits

- Full XCTest execution was blocked because this machine has Command Line Tools without XCTest (`no such module 'XCTest'`).
- The standard app-packaging script reached successful Release compilation, then failed because `actool` was unavailable. The test app was assembled locally with localization resources and an icon generated using `sips` and `iconutil`.
- Other apps held idle-sleep/display-sleep assertions during the closed-lid observation. SleepDisabled and session ownership were checked directly, but this was not an isolated comparison with all other power-management apps disabled.
- Battery-only operation, long sessions, thermal shutdown, real screen locking and normal sleep after physically closing the lid with the mode off were not tested.
- These checks cover one Intel model and one macOS version. They do not establish general Intel support or a universal release package.
