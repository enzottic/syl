fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Capture fresh iPhone, iPhone Duo, iPad, and Apple Watch screenshots, then compose the App Store pages

### ios capture_duo_open

```sh
[bundle exec] fastlane ios capture_duo_open
```

Capture the unfolded iPhone Duo's Stats screen (unfold the Duo in Device Hub first)

### ios capture_watch

```sh
[bundle exec] fastlane ios capture_watch
```

Capture Apple Watch screenshots from the Debug watch app's preview fixture

### ios frame

```sh
[bundle exec] fastlane ios frame
```

Re-compose existing captures after editing screenshot_template.json or a style

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Upload all screenshots to App Store Connect, replacing the existing ones (metadata and binary untouched)

Signs in with the App Store Connect API key from fastlane/.env when set, otherwise asks for your Apple ID

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
