ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
include $(THEOS)/makefiles/common.mk

TOOL_NAME = iosstream
iosstream_FILES = main.m
iosstream_FRAMEWORKS = UIKit Foundation VideoToolbox CoreMedia IOSurface CoreGraphics
iosstream_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/tool.mk
