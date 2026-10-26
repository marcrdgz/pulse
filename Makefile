PROJECT := Pulse.xcodeproj
SCHEME := Pulse
DERIVED_DATA := build/DerivedData
DEV_APP := $(DERIVED_DATA)/Build/Products/Debug/Pulse Dev.app
RELEASE_APP := $(DERIVED_DATA)/Build/Products/Release/Pulse.app
INSTALL_DIR := /Applications
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS,arch=$(shell uname -m)' -derivedDataPath $(DERIVED_DATA) -quiet

VERSION := $(shell sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
TEAM_ID := Q766SSKRK9
# A notarytool profile in the login keychain: `xcrun notarytool store-credentials pulse`.
NOTARY_PROFILE := pulse
ARCHIVE := build/Pulse.xcarchive
EXPORT_DIR := build/export
DMG := build/Pulse.dmg

.PHONY: generate build run test release install dist clean

generate:
	xcodegen generate

build:
	$(XCODEBUILD) -configuration Debug build

# Quits a running copy first, otherwise `open` would just focus the stale build. A real quit,
# not pkill: SIGTERM skips willTerminate, so the debounced session save would be lost.
run: build
	-osascript -e 'quit app id "dev.doblefilo.pulse.dev"'
	@# Opening while the old copy is still exiting fails with LaunchServices -609.
	@while pgrep -qx "Pulse Dev"; do sleep 0.1; done
	open "$(DEV_APP)"

test:
	$(XCODEBUILD) test

release:
	$(XCODEBUILD) -configuration Release build

# Replacing the bundle under a running copy leaves it in a broken state, so quit it first.
install: release
	-osascript -e 'quit app id "dev.doblefilo.pulse"'
	@while pgrep -qx Pulse; do sleep 0.1; done
	rm -rf "$(INSTALL_DIR)/Pulse.app"
	ditto "$(RELEASE_APP)" "$(INSTALL_DIR)/Pulse.app"
	@echo "Installed $(INSTALL_DIR)/Pulse.app"

# The signed, notarized DMG for a release. Developer ID signing lives here rather than in
# project.yml so Release builds keep working for anyone without the certificate.
# Only builds a clean, tagged HEAD, so what ships is exactly the tag.
dist: generate
	@test -z "$$(git status --porcelain)" || { echo "dist: working tree isn't clean"; exit 1; }
	@git describe --exact-match --match "v$(VERSION)" HEAD >/dev/null 2>&1 || { echo "dist: HEAD isn't tagged v$(VERSION)"; exit 1; }
	rm -rf $(ARCHIVE) $(EXPORT_DIR) $(DMG)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination 'generic/platform=macOS' \
		-archivePath $(ARCHIVE) -quiet archive \
		CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM=$(TEAM_ID)
	xcodebuild -exportArchive -archivePath $(ARCHIVE) -exportOptionsPlist scripts/ExportOptions.plist \
		-exportPath $(EXPORT_DIR) -quiet
	ln -s /Applications $(EXPORT_DIR)/Applications
	hdiutil create -quiet -volname Pulse -srcfolder $(EXPORT_DIR) -format UDZO $(DMG)
	codesign --sign "Developer ID Application" --timestamp $(DMG)
	xcrun notarytool submit $(DMG) --keychain-profile $(NOTARY_PROFILE) --wait
	@# Stapling fails without an accepted ticket, so a rejected submission stops here.
	xcrun stapler staple $(DMG)
	spctl --assess --type open --context context:primary-signature -v $(DMG)
	@echo "Built $(DMG) for v$(VERSION)"

clean:
	rm -rf $(DERIVED_DATA)
