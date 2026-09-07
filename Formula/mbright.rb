class Mbright < Formula
  desc "Brightness control for macOS displays that ignore DDC/CI"
  homepage "https://github.com/axklim/mbright"
  url "https://github.com/axklim/mbright/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "5886f257a79592194ac47f03ce28c446f300682a293e6de0ce6fb19cb474ba29"
  license "MIT"
  head "https://github.com/axklim/mbright.git", branch: "main"

  depends_on macos: :sonoma

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    # The CLI and menu bar app look for mbrightd next to their own binary,
    # so all three must land in the same directory.
    bin.install ".build/release/mbright", ".build/release/mbrightd", ".build/release/mbright-menubar"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/mbright --version")

    # Exercises real argument handling without needing a display attached:
    # `get` rejects --all as a usage error (exit 64).
    output = shell_output("#{bin}/mbright get --all 2>&1", 64)
    assert_match "get does not support --all", output

    assert_match version.to_s, shell_output("#{bin}/mbrightd --version")
  end
end
