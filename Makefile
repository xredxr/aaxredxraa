TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = AWSLivenessPractice

AWSLivenessPractice_FILES = \
    Sources/main.m \
    Sources/AppDelegate.m \
    Sources/AWSLivenessViewController.m

AWSLivenessPractice_FRAMEWORKS = UIKit Foundation QuartzCore AVFoundation Vision ImageIO PhotosUI UniformTypeIdentifiers
AWSLivenessPractice_CFLAGS = -fobjc-arc
AWSLivenessPractice_CODESIGN_FLAGS = -SApp.entitlements
AWSLivenessPractice_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/application.mk
