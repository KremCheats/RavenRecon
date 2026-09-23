TARGET = iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RavenRecon
RavenRecon_FILES = Tweak.x
RavenRecon_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
RavenRecon_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
