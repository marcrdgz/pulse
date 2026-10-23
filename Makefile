PROJECT := Pulse.xcodeproj
SCHEME := Pulse
DERIVED_DATA := build/DerivedData
APP := $(DERIVED_DATA)/Build/Products/Debug/Pulse.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS,arch=$(shell uname -m)' -derivedDataPath $(DERIVED_DATA) -quiet

.PHONY: generate build run test clean

generate:
	xcodegen generate

build:
	$(XCODEBUILD) -configuration Debug build

# Quits a running copy first, otherwise `open` would just focus the stale build.
run: build
	-pkill -x Pulse
	open $(APP)

test:
	$(XCODEBUILD) test

clean:
	rm -rf $(DERIVED_DATA)
