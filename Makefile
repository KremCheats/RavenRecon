ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = CombatMaster

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RavenRecon
RavenRecon_FILES = Tweak.mm
RavenRecon_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
RavenRecon_FRAMEWORKS = Foundation UIKit
RavenRecon_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
