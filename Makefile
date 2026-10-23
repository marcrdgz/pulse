PROJECT := Pulse.xcodeproj
SCHEME := Pulse
DERIVED_DATA := build/DerivedData
DEV_APP := $(DERIVED_DATA)/Build/Products/Debug/Pulse Dev.app
RELEASE_APP := $(DERIVED_DATA)/Build/Products/Release/Pulse.app
INSTALL_DIR := /Applications
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS,arch=$(shell uname -m)' -derivedDataPath $(DERIVED_DATA) -quiet

.PHONY: generate build run test release install clean

generate:
	xcodegen generate

build:
	$(XCODEBUILD) -configuration Debug build

# Quits a running copy first, otherwise `open` would just focus the stale build.
run: build
	-pkill -x "Pulse Dev"
	@# pkill doesn't wait; opening while the old copy is still exiting fails with LaunchServices -609.
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

clean:
	rm -rf $(DERIVED_DATA)
