# Build Mac Awaker

You'll need macOS 13 or later and Xcode or Apple's Command Line Tools.
There are no third-party build dependencies.

```sh
./scripts/build.sh
open "build/Mac Awaker.app"
```

The default build targets the Mac you're using. For a build that supports
Apple silicon and Intel, run `./scripts/build.sh --universal`. The script
builds and signs the app locally; it doesn't notarise it.

To verify the keep-awake requests, expiry and cleanup:

```sh
./scripts/test.sh
```

The tests compare the Mac's power settings before and after. You can also
inspect the active request with `pmset -g assertions`; look for
**Mac Awaker: reading reference material** while a session is on.

## How it behaves

The app uses Apple's temporary display-sleep request. It does not change
system power, screen saver or lock settings. Stopping a session or quitting
releases the request, as does the process exiting. Timed sessions also have
a macOS timeout, so they can end even if the app stops responding.

The app starts switched off. It remembers only the reminder size and whether
the reminder is visible. Manual locking, closing the lid and forced sleep
still work. Managed devices may enforce their own lock settings.

Artwork lives in `Resources/AppIcon.png`. The build makes the macOS icon
from this source; README images live in `docs/images/`.
