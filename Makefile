NAME := zsignapp
PLATFORM := iphoneos
SCHEMES := zsignapp
TMP := $(TMPDIR)/$(NAME)
STAGE := $(TMP)/stage
APP := $(TMP)/Build/Products/Release-$(PLATFORM)
PROJECT_DIR := $(shell pwd)
CERT_JSON_URL := https://ryuksign-install.ryuksign.workers.dev/pack.json

.PHONY: all clean deps $(SCHEMES) resolve-packages

all: $(SCHEMES)

clean:
	rm -rf $(TMP)
	rm -rf packages
	rm -rf Payload
	rm -rf .build
	rm -rf .swiftpm

# ⭐ NEW: Resolve packages first in project directory
resolve-packages:
	@echo "🔄 Resolving package dependencies..."
	xcodebuild -resolvePackageDependencies \
		-project zsignapp.xcodeproj
	@echo "✅ Packages resolved"

# ⭐ Fetch the install-server TLS pack. iOS 27+ refuses plain-HTTP install
# payloads, so the local server terminates TLS with this public-CA cert
# (*.backloop.dev resolves to 127.0.0.1). Files land inside the zsignapp
# folder, which the synchronized project auto-bundles as resources.
deps:
	@mkdir -p zsignapp/Certs
	@if curl -fsSL "$(CERT_JSON_URL)" -o /tmp/zsignapp-cert.json; then \
	    jq -r '.cert, .ca' /tmp/zsignapp-cert.json > zsignapp/Certs/server.crt; \
	    jq -rj '.key1, .key2' /tmp/zsignapp-cert.json > zsignapp/Certs/server.pem; \
	    jq -r '.info.domains.commonName' /tmp/zsignapp-cert.json > zsignapp/Certs/commonName.txt; \
	    echo "✅ TLS pack fetched (server.crt, server.pem, commonName.txt)"; \
	else \
	    echo "warning: $(CERT_JSON_URL) unavailable, building without the install TLS pack (installs stay plain HTTP and will not work on iOS 27+)"; \
	fi

# ⭐ UPDATED: Add resolve-packages as dependency
$(SCHEMES): deps resolve-packages
	@echo "🔨 Building $@..."
	xcodebuild \
		-project zsignapp.xcodeproj \
		-scheme "$@" \
		-configuration Release \
		-arch arm64 \
		-sdk $(PLATFORM) \
		-derivedDataPath $(TMP) \
		-skipPackagePluginValidation \
		CODE_SIGNING_ALLOWED=NO \
		ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=NO
	@echo "📦 Creating IPA..."
	rm -rf Payload
	rm -rf $(STAGE)/
	mkdir -p $(STAGE)/Payload
	mv "$(APP)/$@.app" "$(STAGE)/Payload/$@.app"
	rm -rf "$(STAGE)/Payload/$@.app/_CodeSignature"
	ln -sf "$(STAGE)/Payload" Payload
	mkdir -p packages
	cd $(STAGE) && zip -r9 "$(CURDIR)/packages/$@.ipa" Payload
	@echo "✅ IPA created: packages/$@.ipa"