PROJECT := WedoProbe
SCHEME := WedoProbe
CONFIG := Debug
DERIVED_DATA := .build
APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIG)/$(PROJECT).app

.PHONY: generate build-macos start-macos clean

generate:
	xcodegen generate

build-macos: generate
	xcodebuild -project $(PROJECT).xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) -destination 'platform=macOS' -derivedDataPath $(DERIVED_DATA) build

start-macos: build-macos
	open $(APP_PATH)

clean:
	rm -rf $(DERIVED_DATA)
