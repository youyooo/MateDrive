XCODEGEN := $(shell command -v xcodegen 2>/dev/null)
PROJECT := MateDroidIOS.xcodeproj
SCHEME := MateDrive
DESTINATION := platform=iOS Simulator,name=iPhone 17,OS=26.5

.PHONY: bootstrap generate generate-app-icon build build-code install-device archive-release archive-audit vehicle-privacy-audit vehicle-image-audit regional-tariff-audit release-technical-gate test test-build test-scripts localization-audit app-store-technical-audit app-store-audit preflight verify integration-test

bootstrap:
	@if [ -z "$(XCODEGEN)" ]; then echo "xcodegen is required. Install with: brew install xcodegen"; exit 1; fi

generate-app-icon:
	swift scripts/generate_app_icons.swift

generate: bootstrap
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' build

build-code: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'generic/platform=iOS Simulator' ASSETCATALOG_COMPILER_APPICON_NAME= build

install-device:
	./scripts/install_on_iphone.sh

archive-release: generate
	rm -rf build/MateDrive.xcarchive
	xcodebuild archive -project $(PROJECT) -scheme $(SCHEME) -destination 'generic/platform=iOS' -archivePath build/MateDrive.xcarchive CODE_SIGNING_ALLOWED=NO

archive-audit:
	python3 scripts/audit_release_archive.py

vehicle-privacy-audit:
	python3 scripts/audit_vehicle_fixture_privacy.py

vehicle-image-audit:
	python3 scripts/validate_vehicle_images.py

regional-tariff-audit:
	python3 scripts/audit_regional_tariffs.py

release-technical-gate: app-store-technical-audit archive-release archive-audit

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' test

test-build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'generic/platform=iOS Simulator' ASSETCATALOG_COMPILER_APPICON_NAME= build-for-testing

test-scripts:
	./scripts/test_probe_teslamate_integration.sh
	python3 scripts/test_audit_release_archive.py
	python3 scripts/test_audit_vehicle_fixture_privacy.py
	python3 scripts/test_validate_vehicle_images.py

localization-audit:
	python3 scripts/audit_localization.py

app-store-audit:
	python3 scripts/audit_app_store_submission.py

app-store-technical-audit: vehicle-image-audit
	python3 scripts/audit_app_store_submission.py --technical-only

preflight: regional-tariff-audit vehicle-privacy-audit vehicle-image-audit test-scripts localization-audit build-code test-build

verify: vehicle-privacy-audit vehicle-image-audit test-scripts test

integration-test: generate
	@env_file="$${MATEDRIVE_INTEGRATION_ENV_FILE:-.matedrive-integration.env}"; \
	if [ -f "$$env_file" ]; then set -a; . "$$env_file"; set +a; fi; \
	./scripts/probe_teslamate_integration.sh; \
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -only-testing:MateDroidIOSTests/LocalTeslamateIntegrationTests test
