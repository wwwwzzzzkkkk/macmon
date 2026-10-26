import Foundation
import Testing
@testable import ChipBar

struct ChipBarUpdaterTests {
    @Test func semanticVersionsAreComparedNumerically() {
        #expect(ChipBarVersion("2.1.9")! < ChipBarVersion("2.1.10")!)
        #expect(ChipBarVersion("2.9.0")! < ChipBarVersion("2.10.0")!)
        #expect(ChipBarVersion("3.0.0")! > ChipBarVersion("2.99.99")!)
        #expect(ChipBarVersion("2.1.0") == ChipBarVersion("2.1.0"))
        #expect(ChipBarVersion("v2.1.0") == nil)
        #expect(ChipBarVersion("2.1") == nil)
        #expect(ChipBarVersion("2.1.0-beta") == nil)
        #expect(ChipBarVersion("02.1.0") == nil)
    }

    @Test func releaseMustHaveMatchingTrustedAssets() throws {
        let data = """
        {
          "tag_name": "chipbar-v2.2.0",
          "draft": false,
          "prerelease": false,
          "assets": [
            {"name": "ChipBar-macOS-arm64.zip", "size": 2492000,
             "browser_download_url": "https://github.com/wwwwzzzzkkkk/macmon/releases/download/chipbar-v2.2.0/ChipBar-macOS-arm64.zip"},
            {"name": "SHA256SUMS", "size": 90,
             "browser_download_url": "https://github.com/wwwwzzzzkkkk/macmon/releases/download/chipbar-v2.2.0/SHA256SUMS"}
          ]
        }
        """.data(using: .utf8)!
        let release = try JSONDecoder().decode(ChipBarUpdateRelease.self, from: data)
        #expect(release.version == "2.2.0")
        #expect(release.asset(named: ChipBarUpdateRelease.archiveName)?.size == 2492000)
        #expect(release.asset(named: ChipBarUpdateRelease.checksumName) != nil)
    }

    @Test func checksumMustMatchExactlyNamedZip() {
        let digest = String(repeating: "a", count: 64)
        #expect(ChipBarUpdateRelease.archiveDigest(from:
            "\(digest)  ChipBar-macOS-arm64.zip\n") == digest)
        #expect(ChipBarUpdateRelease.archiveDigest(from:
            "\(digest)  different.zip\n") == nil)
        #expect(ChipBarUpdateRelease.archiveDigest(from:
            "1234  ChipBar-macOS-arm64.zip\n") == nil)
    }
}
