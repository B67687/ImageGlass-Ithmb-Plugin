.PHONY: build test lint check package clean

# Build the release cdylib
build:
	cargo build --release

# Run unit tests
test:
	cargo test

# Lint (CI enforces clippy all + pedantic as deny)
lint:
	cargo clippy --all-features --all-targets -- -D warnings

# Full local CI gate (clippy + test + build + deny + gitleaks)
check:
	./scripts/check-local.sh

# Package as .igplugin.zip
package:
	./scripts/package.sh

clean:
	cargo clean