SDK := $(shell xcrun --sdk macosx --show-sdk-path)
MIN_MACOS := 12.0
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/Lyra.app

# Build universal binary (arm64 + x86_64). The Swift binary is built once per
# architecture and then merged with `lipo`. whisper.cpp's static libs are also
# built fat (see scripts/build-whisper.sh: CMAKE_OSX_ARCHITECTURES). This is
# what we ship — Apple Silicon and Intel users both need to be able to run it.

SWIFT_FILES := \
	Lyra/Utilities/Settings.swift \
	Lyra/Utilities/LanguageCatalog.swift \
	Lyra/Utilities/HistoryStore.swift \
	Lyra/Utilities/KeyCodeNames.swift \
	Lyra/Utilities/AppInfo.swift \
	Lyra/Engine/WAVEncoder.swift \
	Lyra/Engine/SpeechProviderProtocol.swift \
	Lyra/Engine/OpenAISpeechService.swift \
	Lyra/Engine/WhisperBridge.swift \
	Lyra/Engine/TranscriptionCoordinator.swift \
	Lyra/Engine/SelectedTextReader.swift \
	Lyra/Engine/AudioCapture.swift \
	Lyra/Engine/AudioLevelAnalyzer.swift \
	Lyra/Engine/TextInjector.swift \
	Lyra/Engine/SoundFeedback.swift \
	Lyra/Engine/ModelManager.swift \
	Lyra/Engine/TextCorrector.swift \
	Lyra/Engine/VADSegmenter.swift \
	Lyra/Utilities/HotkeyMonitor.swift \
	Lyra/Utilities/PermissionManager.swift \
	Lyra/Utilities/LaunchAtLoginHelper.swift \
	Lyra/Utilities/AudioDeviceManager.swift \
	Lyra/Engine/DictationEngine.swift \
	Lyra/UI/MenuBarView.swift \
	Lyra/UI/SettingsView.swift \
	Lyra/UI/OnboardingView.swift \
	Lyra/UI/RecordingHUDView.swift \
	Lyra/UI/DynamicIslandHUDView.swift \
	Lyra/UI/RecordingHUDWindow.swift \
	Lyra/UI/HistorySection.swift \
	Lyra/UI/BrandViews.swift \
	Lyra/UI/HotkeyRecorder.swift \
	Lyra/UI/SpeechSection.swift \
	Lyra/UI/ProviderSection.swift \
	Lyra/UI/HotkeysSection.swift \
	Lyra/UI/AppearanceSection.swift \
	Lyra/UI/AdvancedSection.swift \
	Lyra/UI/AboutSection.swift \
	Lyra/App/LyraApp.swift

LIBS := -lwhisper -lggml -lggml-base -lggml-cpu -lggml-metal -lggml-blas -lc++
FRAMEWORKS := -framework Accelerate -framework Metal -framework MetalKit -framework AVFoundation -framework CoreGraphics -framework AppKit -framework Foundation -framework ServiceManagement -framework CoreAudio

.PHONY: all clean whisper model app run dmg

all: whisper app

whisper: lib/libwhisper.a

lib/libwhisper.a:
	./scripts/build-whisper.sh

model:
	./scripts/download-model.sh small.en

define BUILD_SLICE
xcrun swiftc \
	-sdk "$(SDK)" \
	-target $(1)-apple-macos$(MIN_MACOS) \
	-import-objc-header Lyra/Lyra-Bridging-Header.h \
	-I lib -L lib \
	$(LIBS) $(FRAMEWORKS) \
	-parse-as-library \
	-module-cache-path build/ModuleCache \
	$(SWIFT_FILES) \
	-o $(BUILD_DIR)/Lyra-$(1)
endef

$(BUILD_DIR)/Lyra-arm64: $(SWIFT_FILES) lib/libwhisper.a
	@mkdir -p $(BUILD_DIR)
	$(call BUILD_SLICE,arm64)

$(BUILD_DIR)/Lyra-x86_64: $(SWIFT_FILES) lib/libwhisper.a
	@mkdir -p $(BUILD_DIR)
	$(call BUILD_SLICE,x86_64)

$(BUILD_DIR)/Lyra: $(BUILD_DIR)/Lyra-arm64 $(BUILD_DIR)/Lyra-x86_64
	lipo -create $^ -output $@
	@lipo -info $@

$(BUILD_DIR)/app_icon_tool: scripts/generate_app_icon.swift
	@mkdir -p $(BUILD_DIR)
	xcrun swiftc -module-cache-path $(BUILD_DIR)/ModuleCache -sdk "$(SDK)" scripts/generate_app_icon.swift -o $@

$(BUILD_DIR)/icon_tool: scripts/generate_icons.swift
	@mkdir -p $(BUILD_DIR)
	xcrun swiftc -module-cache-path $(BUILD_DIR)/ModuleCache -sdk "$(SDK)" scripts/generate_icons.swift -o $@

app: $(BUILD_DIR)/Lyra $(BUILD_DIR)/app_icon_tool $(BUILD_DIR)/icon_tool
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp $(BUILD_DIR)/Lyra "$(APP_BUNDLE)/Contents/MacOS/"
	@sed \
		-e 's/$$(EXECUTABLE_NAME)/Lyra/g' \
		-e 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/com.lyra.Lyra/g' \
		-e 's/$$(PRODUCT_NAME)/Lyra/g' \
		-e 's/$$(DEVELOPMENT_LANGUAGE)/en/g' \
		-e 's/$$(PRODUCT_DISPLAY_NAME)/Lyra/g' \
		Lyra/Info.plist > "$(APP_BUNDLE)/Contents/Info.plist"
	@# Add LSMinimumSystemVersion (required for macOS to recognize the app)
	@/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $(MIN_MACOS)" "$(APP_BUNDLE)/Contents/Info.plist" 2>/dev/null || \
		/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $(MIN_MACOS)" "$(APP_BUNDLE)/Contents/Info.plist"
	@echo "APPL????" > "$(APP_BUNDLE)/Contents/PkgInfo"
	@# Generate app icon and menu bar icon
	@$(BUILD_DIR)/app_icon_tool "$(APP_BUNDLE)/Contents/Resources"
	@$(BUILD_DIR)/icon_tool "$(APP_BUNDLE)/Contents/Resources"
	@cp -f assets/lyra-symbol.svg "$(APP_BUNDLE)/Contents/Resources/LyraConstellation.svg" 2>/dev/null || true
	@cp -f assets/lyra.svg "$(APP_BUNDLE)/Contents/Resources/lyra.svg" 2>/dev/null || true
	@# Copy localization bundles
	@for lproj in Lyra/*.lproj; do \
		if [ -d "$$lproj" ]; then \
			cp -R "$$lproj" "$(APP_BUNDLE)/Contents/Resources/"; \
		fi; \
	done
	@# Ad-hoc code sign so macOS will run it
	@codesign --force --deep --sign - "$(APP_BUNDLE)"
	@touch "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

run: app
	open "$(APP_BUNDLE)"

dmg: app
	./scripts/create-dmg.sh

test: $(BUILD_DIR)/Lyra-x86_64
	@mkdir -p $(BUILD_DIR)
	@xcrun swiftc \
		-sdk "$(SDK)" \
		-target x86_64-apple-macos$(MIN_MACOS) \
		-import-objc-header Lyra/Lyra-Bridging-Header.h \
		-I lib -L lib \
		$(LIBS) $(FRAMEWORKS) \
		-module-cache-path build/ModuleCache \
		$(filter-out Lyra/App/LyraApp.swift,$(SWIFT_FILES)) scripts/run-unit-tests.swift \
		-o $(BUILD_DIR)/test_runner
	@./$(BUILD_DIR)/test_runner

clean:
	rm -rf $(BUILD_DIR)
