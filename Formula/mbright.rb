class Mbright < Formula
  desc "Brightness control for macOS displays that ignore DDC/CI"
  homepage "https://github.com/axklim/mbright"
  url "https://github.com/axklim/mbright/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "PLACEHOLDER_FILLED_IN_AFTER_THE_TAG_IS_PUSHED"
  license "MIT"
  head "https://github.com/axklim/mbright.git", branch: "main"

  depends_on macos: :sonoma

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release", "--product", "mbright"
    bin.install ".build/release/mbright"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/mbright --version")

    # Exercises real argument handling without needing a display attached:
    # `get` rejects --all as a usage error (exit 64).
    output = shell_output("#{bin}/mbright get --all 2>&1", 64)
    assert_match "get does not support --all", output
  end
end
