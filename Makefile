export ARCHS = armv7 arm64
export TARGET = iphone:clang:latest:latest

PACKAGE_VERSION = 0.0.8-1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = UndoRotation
UndoRotation_FILES = Tweak.xm
UndoRotation_FRAMEWORKS = UIKit
UndoRotation_LDFLAGS += -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/tweak.mk

BUNDLE_NAME = UndoRotationBundle
UndoRotationBundle_INSTALL_PATH = /Library/Application Support/UndoRotation

include $(THEOS)/makefiles/bundle.mk

after-install::
	install.exec "killall -9 SpringBoard"
SUBPROJECTS += undorotation
include $(THEOS_MAKE_PATH)/aggregate.mk
