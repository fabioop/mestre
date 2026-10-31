.PHONY: build bundle run test test-release release install icon clean

build:
	swift build

bundle:
	scripts/bundle.sh release

run: bundle
	-pkill -x Mestre
	open build/Mestre.app

test:
	scripts/test.sh

test-release:
	scripts/test-release.sh

# Suggests the next version and pushes the tag; set VERSION to choose it yourself.
release:
	scripts/release.sh $(VERSION)

install: bundle
	-pkill -x Mestre
	rm -rf ~/Applications/Mestre.app
	mkdir -p ~/Applications
	cp -R build/Mestre.app ~/Applications/
	open ~/Applications/Mestre.app

icon:
	swift scripts/make-icon.swift build/Mestre.iconset
	iconutil -c icns build/Mestre.iconset -o Resources/Mestre.icns

clean:
	rm -rf .build build
