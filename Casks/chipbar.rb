cask "chipbar" do
  version "1.3.12"
  sha256 "29e9c9d883301bb3f81ad7b8316ee63f3556b7db6c4aa27d777cad1df676bc6c"

  url "https://github.com/wwwwzzzzkkkk/macmon/releases/download/chipbar-v#{version}/ChipBar-macOS-arm64.zip"
  name "ChipBar"
  desc "Native menu bar client for macmon power and temperature monitoring"
  homepage "https://github.com/wwwwzzzzkkkk/macmon"

  depends_on arch: :arm64
  depends_on macos: :ventura
  depends_on formula: "macmon"

  app "ChipBar.app"

  uninstall quit: "local.chipbar.monitor"

  caveats <<~EOS
    ChipBar is locally signed and not notarized. If macOS blocks opening it,
    allow ChipBar in System Settings > Privacy & Security.
    Sensor availability depends on the installed macmon and your hardware.
  EOS
end
