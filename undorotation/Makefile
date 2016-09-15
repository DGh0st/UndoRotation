include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = undorotation
undorotation_FILES = URPRootListController.m
undorotation_INSTALL_PATH = /Library/PreferenceBundles
undorotation_FRAMEWORKS = UIKit MessageUI
undorotation_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/undorotation.plist$(ECHO_END)
