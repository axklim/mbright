# Releasing

1. Bump `Version.current` in `Sources/MBrightCore/Version.swift` and commit.
2. Tag and push:

   ```bash
   git tag -a v0.2.0 -m "mbright 0.2.0" && git push origin v0.2.0
   ```

Never move a published tag.

There is no package or formula; users build from the tag with
`make install`.
