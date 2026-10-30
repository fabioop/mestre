.PHONY: build bundle run test install icon clean

build:
	swift build

bundle:
	scripts/bundle.sh release

run: bundle
	-pkill -x Mestre
	open build/Mestre.app

test:
	scripts/test.sh

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
