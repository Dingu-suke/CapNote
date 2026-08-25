.PHONY: build run install dmg clean help

APP_NAME := mp4recorder
BUILD_DIR := .build/release
APP := build/$(APP_NAME).app

build: ## リリースビルドして build/mp4recorder.app を作る
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP)/Contents/MacOS/
	cp Support/Info.plist $(APP)/Contents/
	cp Support/AppIcon.icns $(APP)/Contents/Resources/
	printf 'APPL????' > $(APP)/Contents/PkgInfo
	codesign --force -s - $(APP)
	@echo "==> $(APP)"

run: build ## ビルドして起動
	open $(APP)

install: build ## /Applications にインストール
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP) /Applications/

dmg: build ## 配布用 dmg を dist/ に作成 (ad-hoc署名。配布の注意は README 参照)
	rm -rf dist
	mkdir -p dist/dmg
	cp -R $(APP) dist/dmg/
	ln -s /Applications dist/dmg/Applications
	hdiutil create -volname $(APP_NAME) -srcfolder dist/dmg -ov -format UDZO dist/$(APP_NAME).dmg
	rm -rf dist/dmg
	@echo "==> dist/$(APP_NAME).dmg"

clean:
	swift package clean
	rm -rf build dist

help:
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-10s %s\n", $$1, $$2}'
