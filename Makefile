# MarkView build/test helper.
#
# With full Xcode installed, plain `swift build` / `swift test` work directly.
# With Command Line Tools only, the Swift Testing framework lives under the
# CLT developer frameworks directory and is not on the default search path,
# so `make test` injects the needed flags automatically.

CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
DEV_DIR := $(shell xcode-select -p 2>/dev/null)

ifeq ($(DEV_DIR),/Library/Developer/CommandLineTools)
TEST_FLAGS := \
	-Xswiftc -F$(CLT_FRAMEWORKS) \
	-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
	-Xlinker -F$(CLT_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS)
else
TEST_FLAGS :=
endif

.PHONY: build release test clean

build:
	swift build

release:
	swift build -c release

test:
	swift test $(TEST_FLAGS)

clean:
	swift package clean
