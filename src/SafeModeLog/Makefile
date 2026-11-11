TARGET := iphone:clang:16.5:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = SafeModeLog

SafeModeLog_FILES = main.m CrashLog.m
SafeModeLog_FRAMEWORKS = UIKit
SafeModeLog_CFLAGS = -fobjc-arc
# no-sandbox: crash logs live outside any app container
SafeModeLog_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
