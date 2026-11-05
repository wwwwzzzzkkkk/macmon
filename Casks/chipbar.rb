cask "chipbar" do
  version "3.1.1"
  sha256 "824d4d44d550b293984ee8f555db2254e5e0da2a05b8651dadd5054f0cbf3970"

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
