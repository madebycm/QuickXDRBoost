APP_NAME := QuickXDRBoost
BUILD_DIR := build
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
BIN := $(APP_DIR)/Contents/MacOS/$(APP_NAME)
SRC := Sources/QuickXDRBoost/main.swift

.PHONY: all clean install run

all: $(APP_DIR)

$(APP_DIR): $(SRC) AppBundle/Contents/Info.plist
	rm -rf $(APP_DIR)
	mkdir -p $(APP_DIR)/Contents/MacOS
	cp AppBundle/Contents/Info.plist $(APP_DIR)/Contents/Info.plist
	swiftc $(SRC) \
		-O \
		-parse-as-library \
		-framework AppKit \
		-framework CoreGraphics \
		-framework IOKit \
		-framework MetalKit \
		-framework ServiceManagement \
		-o $(BIN)
	codesign --force --deep --sign - $(APP_DIR)

install: all
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP_DIR) /Applications/$(APP_NAME).app

run: install
	open /Applications/$(APP_NAME).app

clean:
	rm -rf $(BUILD_DIR)
