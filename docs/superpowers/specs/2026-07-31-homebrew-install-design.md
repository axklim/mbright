# Homebrew install for mbright — design

Date: 2026-07-31

## Goal

Let people install mbright with Homebrew instead of cloning the repo and
copying a binary into `/usr/local/bin` by hand.

## Distribution shape

The formula lives in this repository at `Formula/mbright.rb`, not in a
separate `homebrew-tap` repo. Homebrew accepts any repository as a tap when
given its URL explicitly, so the install is two commands rather than one:

```bash
brew tap axklim/mbright https://github.com/axklim/mbright
brew install mbright
```

homebrew-core is not an option yet. It has a notability bar (established
usage, roughly 75+ stars) that a freshly published repository does not clear.

## The formula

```ruby
class Mbright < Formula
  desc "Brightness control for macOS displays that ignore DDC/CI"
  homepage "https://github.com/axklim/mbright"
  url "https://github.com/axklim/mbright/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "<sha256 of the published tarball>"
  license "MIT"
  head "https://github.com/axklim/mbright.git", branch: "main"

  depends_on macos: :sonoma

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release", "--product", "mbright"
    bin.install ".build/release/mbright"
  end

  test do
    assert_match "0.1.0", shell_output("#{bin}/mbright --version")
  end
end
```

Decisions worth recording:

- **Build from source, no prebuilt binary.** `brew install` compiles for
  roughly half a minute instead of unpacking instantly. In exchange there is
  no code signing, no notarization, and no release CI to maintain. Homebrew
  itself requires the Command Line Tools, which is all the build needs.
- **No `depends_on xcode`.** The conventional-looking `depends_on xcode:
  [..., :build]` line is deliberately omitted: Homebrew's Xcode requirement
  is satisfied only by a full Xcode.app install, and this package builds
  fine with the Command Line Tools alone. Requiring Xcode would cost users a
  ~10 GB install for nothing.
- **`depends_on macos: :sonoma`** mirrors `Package.swift`'s `.macOS(.v14)`.
- **`--disable-sandbox`** turns off SwiftPM's own sandbox, which otherwise
  blocks the package cache writes SwiftPM needs while resolving
  swift-argument-parser. Homebrew's separate build sandbox stays on.

Known rough edge, accepted rather than engineered around: a machine with
Command Line Tools older than Xcode 16 fails during `swift build` with a
message about `swift-tools-version 6.0` rather than a friendly explanation.
Version-sniffing inside the formula is not worth the complexity.

## Release mechanics

Homebrew resolves a versioned formula to a tarball URL plus its sha256, so a
published tag is a prerequisite:

1. Tag the released source `v0.1.0` and push it; create a GitHub release from
   the tag.
2. Compute the sha256 of
   `https://github.com/axklim/mbright/archive/refs/tags/v0.1.0.tar.gz`.
3. Fill `url` and `sha256` into the formula.

Future releases repeat those steps and push the bumped formula to `main`;
users pick it up with `brew update && brew upgrade mbright`. The tag must
never be moved after publication — Homebrew caches by sha256 and a moved tag
produces a checksum mismatch on other machines.

The README records this sequence so a later release is not guesswork.

## Documentation

`## Install` in the README leads with Homebrew and keeps the from-source
build below it as an alternative. A `Releasing` note under `## Development`
records the tag-and-bump sequence above.

## Verification

Homebrew is installed on the development machine, so the formula is tested
rather than assumed:

- `brew audit --strict --formula ./Formula/mbright.rb`
- `brew install --formula ./Formula/mbright.rb` (local file, before the
  formula reaches `main`)
- `brew test mbright`
- run the brew-installed `mbright list` binary
- after merge: the real `brew tap <url>` + `brew install mbright` path

## Out of scope

Bottles (prebuilt binaries), release automation via CI, and a homebrew-core
submission. Each becomes worth doing if the project picks up users; none is
needed to make `brew install` work today.
