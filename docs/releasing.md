# Releasing

Homebrew pins a release to a tag's tarball and its checksum, so a release
is a tag plus a formula bump, in this order:

1. Bump `Version.current` in `Sources/MBrightCore/Version.swift` and commit.
2. Tag and push:

   ```bash
   git tag -a v0.2.0 -m "mbright 0.2.0" && git push origin v0.2.0
   ```

3. Checksum the tarball GitHub generates for the tag:

   ```bash
   curl -sL https://github.com/axklim/mbright/archive/refs/tags/v0.2.0.tar.gz | shasum -a 256
   ```

4. Put the new `url` and `sha256` into `Formula/mbright.rb` and push to
   `main`. Users pick it up with `brew update && brew upgrade`.

Never move a published tag: Homebrew caches by checksum, and a moved tag
fails on every other machine.

The formula builds from source and installs all three binaries into the
same `bin`, which the daemon lookup depends on. It deliberately omits
`depends_on xcode:`; Homebrew's Xcode requirement is only satisfied by a
full Xcode.app, and this package builds with the Command Line Tools alone.
