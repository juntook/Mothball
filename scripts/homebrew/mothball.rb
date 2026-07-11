# SPDX-License-Identifier: Apache-2.0
# Cask draft for the self-hosted tap (github.com/juntook/homebrew-tap).
# Copy into the tap repo as Casks/mothball.rb and fill in sha256 per release:
#   shasum -a 256 dist/Mothball-<version>.dmg
#
# Install: brew install --cask juntook/tap/mothball
#
# The official homebrew/cask repo has notability requirements (GitHub stars
# etc.); graduate there once the project qualifies.
cask "mothball" do
  version "0.1.0"
  sha256 "REPLACE_WITH_DMG_SHA256"

  url "https://github.com/juntook/Mothball/releases/download/v#{version}/Mothball-#{version}.dmg"
  name "Mothball"
  desc "Reclaim disk space left behind by dev tools, organized by project"
  homepage "https://mothball.dev"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "Mothball.app"

  auto_updates true # Sparkle

  zap trash: [
    "~/Library/Application Support/Mothball",
    "~/Library/Logs/Mothball",
    "~/Library/Preferences/dev.mothball.app.plist",
  ]
end
