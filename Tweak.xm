#include <UIKit/UIKit.h>
#include <libactivator/libactivator.h>

@interface SBOrientationLockManager
+(id)sharedInstance;
-(void)lock:(UIInterfaceOrientation)arg1;
-(BOOL)isUserLocked;
-(void)unlock;
@end

@interface UIDevice (UndoRotation)
-(void)setOrientation:(NSInteger)arg1;
@end

@interface DGUndoRotationListener : NSObject <LAListener>
+(DGUndoRotationListener *)sharedInstance;
@end

@interface DGUndoRotation : NSObject {
@private
	UIButton *_undoButton;
	NSInteger _currentDisplayedMode; // -1 = error, 0 = undo, 1 = lock, 2 = both
	NSInteger _fromOrientation;
	CGFloat _secondsVisible;
}
@end

// notifications, preference and bundles
#define kBundlePath @"/Library/Application Support/UndoRotation/UndoRotationBundle.bundle"
#define kOrientationLockNotificationPortarit (CFStringRef)@"kOrientationLockNotificationPortarit"
#define kOrientationLockNotificationPortaritUpsideDown (CFStringRef)@"kOrientationLockNotificationPortaritUpsideDown"
#define kOrientationLockNotificationLandscapeLeft (CFStringRef)@"kOrientationLockNotificationLandscapeLeft"
#define kOrientationLockNotificationLandscapeRight (CFStringRef)@"kOrientationLockNotificationLandscapeRight"
#define kOrientationUnlockNotification (CFStringRef)@"kOrientationUnlockNotification"
#define kSettingsChangedNotification (CFStringRef)@"com.dgh0st.undorotation/settingschanged"
#define kIdentifier @"com.dgh0st.undorotation"
#define kSettingsPath @"/var/mobile/Library/Preferences/com.dgh0st.undorotation.plist"

// preference keys
#define kIsEnabled @"isEnabled"
#define kMode @"mode" // 0 = undo rotation only, 1 = lock orientation only, 2 = both
#define kDisplaySeconds @"displaySeconds"
#define kIsUndoEnabled @"isUndoEnabled"
#define kIsCurrentEnabled @"isCurrentEnabled"
#define kIsUnlockEnabled @"isUnlockEnabled"
#define kButtonOpacity @"buttonOpacity"
#define kButtonCorner @"buttonCorner"
#define kAltModePrefix @"AltMode-"

// Activator listener names
#define kOrientationListenerUp @"com.dgh0st.undorotation.up"
#define kOrientationListenerLeft @"com.dgh0st.undorotation.left"
#define kOrientationListenerRight @"com.dgh0st.undorotation.right"
#define kOrientationListenerPortrait @"com.dgh0st.undorotation.portrait"
#define kOrientationListenerPortraitUpsideDown @"com.dgh0st.undorotation.portraitupsidedown"
#define kOrientationListenerLandscapeRight @"com.dgh0st.undorotation.landscaperight"
#define kOrientationListenerLandscapeLeft @"com.dgh0st.undorotation.landscapeleft"

// Activator listener notification to application
#define kOrientationNotificationListenerUp (CFStringRef)@"com.dgh0st.undorotation.uprotate"
#define kOrientationNotificationListenerLeft (CFStringRef)@"com.dgh0st.undorotation.leftrotate"
#define kOrientationNotificationListenerRight (CFStringRef)@"com.dgh0st.undorotation.rightrotate"
#define kOrientationNotificationListenerPortrait (CFStringRef)@"com.dgh0st.undorotation.portraitrotate"
#define kOrientationNotificationListenerPortraitUpsideDown (CFStringRef)@"com.dgh0st.undorotation.portraitupsidedownrotate"
#define kOrientationNotificationListenerLandscapeRight (CFStringRef)@"com.dgh0st.undorotation.landscaperightrotate"
#define kOrientationNotificationListenerLandscapeLeft (CFStringRef)@"com.dgh0st.undorotation.landscapeleftrotate"

BOOL isShowing = NO;
DGUndoRotation *temp = nil;
NSInteger resetToOrientation = -1;
NSDictionary *prefs = nil;

static void reloadPrefs() {
	if ([NSHomeDirectory() isEqualToString:@"/var/mobile"]) {
		CFArrayRef keyList = CFPreferencesCopyKeyList((CFStringRef)kIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
		if (keyList) {
			prefs = (NSDictionary *)CFPreferencesCopyMultiple(keyList, (CFStringRef)kIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
			if (!prefs) {
				prefs = [NSDictionary new];
			}
			CFRelease(keyList);
		}
	} else {
		prefs = [NSDictionary dictionaryWithContentsOfFile:kSettingsPath];
	}
}

static void preferencesChanged() {
	CFPreferencesAppSynchronize((CFStringRef)kIdentifier);

	reloadPrefs();
}

static BOOL boolValueForKey(NSString *key, BOOL defaultValue) {
	return (prefs && [prefs objectForKey:key]) ? [[prefs objectForKey:key] boolValue] : defaultValue;
}

static NSInteger intValueForKey(NSString *key, NSInteger defaultValue) {
	return (prefs && [prefs objectForKey:key]) ? [[prefs objectForKey:key] intValue] : defaultValue;
}

static CGFloat doubleValueForKey(NSString *key, CGFloat defaultValue) {
	return (prefs && [prefs objectForKey:key]) ? [[prefs objectForKey:key] floatValue] : defaultValue;
}

static BOOL getPerApp(NSString *appId, NSString *prefix) {
	if (prefs) {
	    for (NSString *key in [prefs allKeys]) {
			if ([key hasPrefix:prefix]) {
			    NSString *tempId = [key substringFromIndex:[prefix length]];
			    if ([tempId isEqualToString:appId]) {
			    	return [prefs objectForKey:key] ? [[prefs objectForKey:key] boolValue] : NO;
			    }
			}
	   	}
	}
    return NO;
}

@implementation DGUndoRotationListener
+(DGUndoRotationListener *)sharedInstance {
	static DGUndoRotationListener *sharedObject = nil;
	static dispatch_once_t p = 0;
	dispatch_once(&p, ^{
		sharedObject = [[self alloc] init];
	});
	return sharedObject;
}
-(id)init {
	return (self = [super init]);
}
-(void)activator:(LAActivator *)activator receiveEvent:(LAEvent *)event {
	// prevent default ios action
	[event setHandled:YES];

	NSString *name = [activator assignedListenerNameForEvent:event];
	if ([name isEqualToString:kOrientationListenerPortrait]) {
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationNotificationListenerPortrait, NULL, NULL, YES);
	} else if ([name isEqualToString:kOrientationListenerPortraitUpsideDown]) {
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationNotificationListenerPortraitUpsideDown, NULL, NULL, YES);
	} else if ([name isEqualToString:kOrientationListenerLandscapeLeft]) {
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationNotificationListenerLandscapeLeft, NULL, NULL, YES);
	} else if ([name isEqualToString:kOrientationListenerLandscapeRight]) {
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationNotificationListenerLandscapeRight, NULL, NULL, YES);
	} else if ([name isEqualToString:kOrientationListenerUp]) {
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationNotificationListenerUp, NULL, NULL, YES);
	} else if ([name isEqualToString:kOrientationListenerRight]) {
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationNotificationListenerRight, NULL, NULL, YES);
	} else if ([name isEqualToString:kOrientationListenerLeft]) {
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationNotificationListenerLeft, NULL, NULL, YES);
	} else {
		[event setHandled:NO]; // default acion if none of our actions occured
	}
}
@end

@implementation DGUndoRotation
-(id)init {
	self = [super init];
	if(self != nil) {
		_undoButton = nil;
		_currentDisplayedMode = -1;
		isShowing = NO;
	}
	return self;
}
-(void)dealloc{
	if (_undoButton) {
		[_undoButton removeFromSuperview];
		_undoButton = nil;
	}
	
	[super dealloc];
}
-(void)showFromOrientation:(NSInteger)fromOrientation toOrientation:(NSInteger)toOrientation {
	_fromOrientation = fromOrientation;
	if (!isShowing) {
		isShowing = YES;
		// setup button
		if (_undoButton) {
			[_undoButton removeFromSuperview];
			_currentDisplayedMode = -1;
		}
		_undoButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
		[_undoButton addTarget:self action:@selector(undoRotation:) forControlEvents:UIControlEventTouchUpInside];
		UIWindow *window = [[UIApplication sharedApplication] keyWindow];
		if (window && ([[window class] isEqual:[%c(SBHomeScreenWindow) class]] || [[window class] isEqual:[UIWindow class]] || [[window superclass] isEqual:[UIWindow class]])) {
			[window addSubview:_undoButton];
			[window bringSubviewToFront:_undoButton];
		} else {
			[_undoButton removeFromSuperview];
			_undoButton = nil;
			_currentDisplayedMode = -1;
			isShowing = NO;
			return;
		}

		// after x seconds remove button
		[self performSelector:@selector(hide) withObject:nil afterDelay:doubleValueForKey(kDisplaySeconds, 5.0) / 5.0];
	}
	_secondsVisible = 0.0;
	if (_undoButton) {
		// load bundle for images
		NSBundle *bundle = [[NSBundle alloc] initWithPath:kBundlePath];
		UIImage *image = nil;
		NSInteger mode = intValueForKey(kMode, 2);
		_currentDisplayedMode = -1;
		if (toOrientation == _fromOrientation) { // down rotation
			if (mode == 0) { // undo rotation only
				image = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"undoRotationDown" ofType:@"png"]];
				_currentDisplayedMode = 0;
			} else if (mode == 1) { // lock orientation only
				image = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"undoRotationLock" ofType:@"png"]];
				_currentDisplayedMode = 1;
			} else if (mode == 2) { // both
				image = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"undoRotationDownLock" ofType:@"png"]];
				_currentDisplayedMode = 2;
			}
		} else if ((toOrientation == UIInterfaceOrientationPortrait && _fromOrientation == UIInterfaceOrientationPortraitUpsideDown) ||
			(toOrientation == UIInterfaceOrientationPortraitUpsideDown && _fromOrientation == UIInterfaceOrientationPortrait) ||
			(toOrientation == UIInterfaceOrientationLandscapeLeft && _fromOrientation == UIInterfaceOrientationLandscapeRight) ||
			(toOrientation == UIInterfaceOrientationLandscapeRight && _fromOrientation == UIInterfaceOrientationLandscapeLeft)) { // up rotation
			if (mode == 0) { // undo rotation only
				image = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"undoRotationUp" ofType:@"png"]];
				_currentDisplayedMode = 0;
			} else if (mode == 1) { // lock orientation only
				image = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"undoRotationLock" ofType:@"png"]];
				_currentDisplayedMode = 1;
			} else if (mode == 2) { // both
				image = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"undoRotationUpLock" ofType:@"png"]];
				_currentDisplayedMode = 2;
			}
		} else if ((toOrientation == UIInterfaceOrientationPortrait && _fromOrientation == UIInterfaceOrientationLandscapeRight) ||
			(toOrientation == UIInterfaceOrientationLandscapeRight && _fromOrientation == UIInterfaceOrientationPortraitUpsideDown) ||
			(toOrientation == UIInterfaceOrientationPortraitUpsideDown && _fromOrientation == UIInterfaceOrientationLandscapeLeft) ||
			(toOrientation == UIInterfaceOrientationLandscapeLeft && _fromOrientation == UIInterfaceOrientationPortrait)) { // left rotation
			if (mode == 0) { // undo rotation only
				image = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"undoRotationLeft" ofType:@"png"]];
				_currentDisplayedMode = 0;
			} else if (mode == 1) { // lock orientation only
				image = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"undoRotationLock" ofType:@"png"]];
				_currentDisplayedMode = 1;
			} else if (mode == 2) { // both
				image = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"undoRotationLeftLock" ofType:@"png"]];
				_currentDisplayedMode = 2;
			}
		} else if ((toOrientation == UIInterfaceOrientationPortrait && _fromOrientation == UIInterfaceOrientationLandscapeLeft) ||
			(toOrientation == UIInterfaceOrientationLandscapeLeft && _fromOrientation == UIInterfaceOrientationPortraitUpsideDown) ||
			(toOrientation == UIInterfaceOrientationPortraitUpsideDown && _fromOrientation == UIInterfaceOrientationLandscapeRight) ||
			(toOrientation == UIInterfaceOrientationLandscapeRight && _fromOrientation == UIInterfaceOrientationPortrait)) { // right rotation
			if (mode == 0) { // undo rotation only
				image = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"undoRotationRight" ofType:@"png"]];
				_currentDisplayedMode = 0;
			} else if (mode == 1) { // lock orientation only
				image = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"undoRotationLock" ofType:@"png"]];
				_currentDisplayedMode = 1;
			} else if (mode == 2) { // both
				image = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"undoRotationRightLock" ofType:@"png"]];
				_currentDisplayedMode = 2;
			}
		}
		if (image && _currentDisplayedMode != -1) {
			NSInteger selectedCorner = intValueForKey(kButtonCorner, 0);
			CGSize appSize = [[UIScreen mainScreen] bounds].size;
			if (selectedCorner == 0) { // top left
				_undoButton.frame = CGRectMake(16, 32, 64, 64);
				_undoButton.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleRightMargin;
			} else if (selectedCorner == 1) { // top right
				_undoButton.frame = CGRectMake(appSize.width - 80, 32, 64, 64);
				_undoButton.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin;
			} else if (selectedCorner == 2) { // bottom left
				_undoButton.frame = CGRectMake(16, appSize.height - 80, 64, 64);
				_undoButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
			} else if (selectedCorner == 3) { // bottom right
				_undoButton.frame = CGRectMake(appSize.width - 80, appSize.height - 80, 64, 64);
				_undoButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;
			}
			[_undoButton setBackgroundImage:image forState:UIControlStateNormal];
			[_undoButton setAlpha:doubleValueForKey(kButtonOpacity, 0.8)];
		} else {
			[_undoButton removeFromSuperview];
			_undoButton = nil;
			_currentDisplayedMode = -1;
			isShowing = NO;
		}
		[bundle release];
	}
}
-(void)forceHide {
	//_secondsVisible = doubleValueForKey(kDisplaySeconds, 5.0);
	if (_undoButton) {
		[_undoButton removeFromSuperview];
		_undoButton = nil;
	}
	_currentDisplayedMode = -1;
	isShowing = NO;
}
-(void)hide {
	if (isShowing) {
		// remove button if needed
		CGFloat displaySecs = doubleValueForKey(kDisplaySeconds, 5.0);
		if (_secondsVisible < displaySecs) {
			_secondsVisible += displaySecs / 5.0;
			[self performSelector:@selector(hide) withObject:nil afterDelay:displaySecs / 5.0];
		} else {
			if (_undoButton) {
				[_undoButton removeFromSuperview];
				_undoButton = nil;
			}
			_currentDisplayedMode = -1;
			isShowing = NO;
		}
	}
}
-(void)undoRotation:(UIButton *)sender {
	if (isShowing && sender == _undoButton) {
		// remove button and undo the rotation
		if (_undoButton) {
			[_undoButton removeFromSuperview];
			_undoButton = nil;
		}
		// undo orientation
		if (_currentDisplayedMode == 0 || _currentDisplayedMode == 2) { // undo or both mode
			resetToOrientation = _fromOrientation;
			[[UIDevice currentDevice] setOrientation:_fromOrientation];
		}
		// lock orietnation
		if (_currentDisplayedMode == 1 || _currentDisplayedMode == 2) { // lock or both mode
			if (%c(SBOrientationLockManager)) {
				if (boolValueForKey(kIsUndoEnabled, NO) && [[%c(SBOrientationLockManager) sharedInstance] isUserLocked]) {
					[[%c(SBOrientationLockManager) sharedInstance] unlock];
				} else {
					[[%c(SBOrientationLockManager) sharedInstance] lock:[[UIDevice currentDevice] orientation]];
				}
			} else {
				_fromOrientation = [[UIDevice currentDevice] orientation];
				if (_fromOrientation == UIInterfaceOrientationPortrait) {
					CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationLockNotificationPortarit, NULL, NULL, YES);
				} else if (_fromOrientation == UIInterfaceOrientationPortraitUpsideDown) {
					CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationLockNotificationPortaritUpsideDown, NULL, NULL, YES);
				} else if (_fromOrientation == UIInterfaceOrientationLandscapeLeft) {
					CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationLockNotificationLandscapeLeft, NULL, NULL, YES);
				} else if (_fromOrientation == UIInterfaceOrientationLandscapeRight) {
					CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationLockNotificationLandscapeRight, NULL, NULL, YES);
				}
			}
		}
		_currentDisplayedMode = -1;
		isShowing = NO;
	}
}
@end

%group applications
%hook UIViewController
-(void)didRotateFromInterfaceOrientation:(NSInteger)arg1 {
	// display tweak button if alternative mode not enabled for this app
	%orig;
	if (!getPerApp([[NSBundle mainBundle] bundleIdentifier], kAltModePrefix)) {
		if (resetToOrientation == [[UIDevice currentDevice] orientation] && !boolValueForKey(kIsUndoEnabled, NO)) {
			resetToOrientation = -1;
			return;
		}
		if (boolValueForKey(kIsEnabled, YES) && temp) {
			[temp showFromOrientation:arg1 toOrientation:[[UIDevice currentDevice] orientation]];
		}
	}
}
-(void)viewWillDisappear:(BOOL)arg1 {
	// hide button
	if (temp) {
		[temp forceHide];
	}
	// unlock orientation if enabled
	if (boolValueForKey(kIsUnlockEnabled, NO)) {
		if (%c(SBOrientationLockManager) && [[%c(SBOrientationLockManager) sharedInstance] isUserLocked]) {
			[[%c(SBOrientationLockManager) sharedInstance] unlock];
		} else {
			CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationUnlockNotification, NULL, NULL, YES);
		}
	}
	%orig;
}
-(void)viewDidAppear:(BOOL)arg1 {
	// display current orientation button if needed
	%orig;
	if (boolValueForKey(kIsEnabled, YES) && boolValueForKey(kIsCurrentEnabled, NO) && temp) {
		NSInteger orientation = [[UIDevice currentDevice] orientation];
		[temp showFromOrientation:orientation toOrientation:orientation];
	}
}
%end

%hook UIDevice
-(void)setOrientation:(NSInteger)arg1 animated:(BOOL)arg2 {
	// display tweak button if alternative mode enabled for this app
	NSInteger lastOrientation = [self orientation];
	%orig;
	if (getPerApp([[NSBundle mainBundle] bundleIdentifier], kAltModePrefix)) {
		if (resetToOrientation == [self orientation] && resetToOrientation == arg1 && !boolValueForKey(kIsUndoEnabled, NO)) {
			resetToOrientation = -1;
			return;
		}
		if (boolValueForKey(kIsEnabled, YES) && temp && arg1 == [self orientation] && (arg1 != lastOrientation || !boolValueForKey(kIsCurrentEnabled, NO))) {
			[temp showFromOrientation:lastOrientation toOrientation:arg1];
		}
	}
}
%end
%end

%group lockmanagernotificationcenter
static inline void lockRotation(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
	// orientation lock callback handler
	if (name == kOrientationUnlockNotification) {
		if ([[%c(SBOrientationLockManager) sharedInstance] isUserLocked]) {
			[[%c(SBOrientationLockManager) sharedInstance] unlock];
		}
		return;
	} else if (name == kOrientationLockNotificationPortarit) {
		[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationPortrait];
		resetToOrientation = UIInterfaceOrientationPortrait;
	} else if (name == kOrientationLockNotificationPortaritUpsideDown) {
		[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationPortraitUpsideDown];
		resetToOrientation = UIInterfaceOrientationPortraitUpsideDown;
	} else if (name == kOrientationLockNotificationLandscapeLeft) {
		[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationLandscapeLeft];
		resetToOrientation = UIInterfaceOrientationLandscapeLeft;
	} else if (name == kOrientationLockNotificationLandscapeRight) {
		[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationLandscapeRight];
		resetToOrientation = UIInterfaceOrientationLandscapeRight;
	}
	if (boolValueForKey(kIsUndoEnabled, NO) && [[%c(SBOrientationLockManager) sharedInstance] isUserLocked]) {
		[[%c(SBOrientationLockManager) sharedInstance] unlock];
	} else {
		[[%c(SBOrientationLockManager) sharedInstance] lock:resetToOrientation];
	}
}
%end

%group activatorrotationnotificationcenter
static inline void activatorRotateNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
	// activator notification center callback handler
	if (name == kOrientationNotificationListenerPortrait) {
		[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationPortrait];
	} else if (name == kOrientationNotificationListenerPortraitUpsideDown) {
		[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationPortraitUpsideDown];
	} else if (name == kOrientationNotificationListenerLandscapeLeft) {
		[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationLandscapeLeft];
	} else if (name == kOrientationNotificationListenerLandscapeRight) {
		[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationLandscapeRight];
	} else if (name == kOrientationNotificationListenerUp) {
		UIInterfaceOrientation currentOrientation = [[UIDevice currentDevice] orientation];
		if (currentOrientation == UIInterfaceOrientationPortrait) {
			[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationPortraitUpsideDown];
		} else if (currentOrientation == UIInterfaceOrientationPortraitUpsideDown) {
			[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationPortrait];
		} else if (currentOrientation == UIInterfaceOrientationLandscapeLeft) {
			[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationLandscapeRight];
		} else if (currentOrientation == UIInterfaceOrientationLandscapeRight) {
			[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationLandscapeLeft];
		}
	} else if (name == kOrientationNotificationListenerRight) {
		UIInterfaceOrientation currentOrientation = [[UIDevice currentDevice] orientation];
		if (currentOrientation == UIInterfaceOrientationPortrait) {
			[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationLandscapeLeft];
		} else if (currentOrientation == UIInterfaceOrientationPortraitUpsideDown) {
			[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationLandscapeRight];
		} else if (currentOrientation == UIInterfaceOrientationLandscapeLeft) {
			[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationPortraitUpsideDown];
		} else if (currentOrientation == UIInterfaceOrientationLandscapeRight) {
			[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationPortrait];
		}
	} else if (name == kOrientationNotificationListenerLeft) {
		UIInterfaceOrientation currentOrientation = [[UIDevice currentDevice] orientation];
		if (currentOrientation == UIInterfaceOrientationPortrait) {
			[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationLandscapeRight];
		} else if (currentOrientation == UIInterfaceOrientationPortraitUpsideDown) {
			[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationLandscapeLeft];
		} else if (currentOrientation == UIInterfaceOrientationLandscapeLeft) {
			[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationPortrait];
		} else if (currentOrientation == UIInterfaceOrientationLandscapeRight) {
			[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationPortraitUpsideDown];
		}
	}
}
%end

%group homescreen
%hook SBIconController
-(void)_didRotateFromInterfaceOrientation:(NSInteger)arg1 {
	%orig;
	// do not display button if taking tweak action
	if (resetToOrientation == [[UIDevice currentDevice] orientation] && !boolValueForKey(kIsUndoEnabled, NO)) {
		resetToOrientation = -1;
		return;
	}
	// display button if needed
	if(boolValueForKey(kIsEnabled, YES) && temp) {
		[temp showFromOrientation:arg1 toOrientation:[[UIDevice currentDevice] orientation]];
	}
}
-(void)viewWillDisappear:(BOOL)arg1 {
	// hide button
	if (temp) {
		[temp forceHide];
	}
	// unlock orientation if needed
	if (boolValueForKey(kIsUnlockEnabled, NO)) {
		if (%c(SBOrientationLockManager) && [[%c(SBOrientationLockManager) sharedInstance] isUserLocked]) {
			[[%c(SBOrientationLockManager) sharedInstance] unlock];
		} else {
			CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationUnlockNotification, NULL, NULL, YES);
		}
	}
	%orig;
}
-(void)_launchIcon:(id)arg1 {
	// hide button
	if (temp) {
		[temp forceHide];
	}
	// unlock orientation if needed
	if (boolValueForKey(kIsUnlockEnabled, NO)) {
		if (%c(SBOrientationLockManager) && [[%c(SBOrientationLockManager) sharedInstance] isUserLocked]) {
			[[%c(SBOrientationLockManager) sharedInstance] unlock];
		} else {
			CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationUnlockNotification, NULL, NULL, YES);
		}
	}
	%orig;	
}
-(void)_lockScreenUIWillLock:(id)arg1 {
	// hide button
	if (temp) {
		[temp forceHide];
	}
	// unlock orientation if needed
	if (boolValueForKey(kIsUnlockEnabled, NO)) {
		if (%c(SBOrientationLockManager) && [[%c(SBOrientationLockManager) sharedInstance] isUserLocked]) {
			[[%c(SBOrientationLockManager) sharedInstance] unlock];
		} else {
			CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationUnlockNotification, NULL, NULL, YES);
		}
	}
	%orig;
}
-(void)viewDidAppear:(BOOL)arg1 {
	// display current orientation button if needed
	%orig;
	if (boolValueForKey(kIsEnabled, YES) && boolValueForKey(kIsCurrentEnabled, NO) && temp) {
		NSInteger orientation = [[UIDevice currentDevice] orientation];
		[temp showFromOrientation:orientation toOrientation:orientation];
	}
}
%end
%end

%dtor {
	// remove preference notification listener
	CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kSettingsChangedNotification, NULL);

	// dealloc tweak instance
	[temp release];
	temp = nil;

	// remove listeners for orientation lock from tweak button
	if (%c(SBOrientationLockManager)) {
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationLockNotificationPortarit, NULL);
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationLockNotificationPortaritUpsideDown, NULL);
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationLockNotificationLandscapeLeft, NULL);
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationLockNotificationLandscapeRight, NULL);
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationUnlockNotification, NULL);
	}

	// remove listeners for rotations from activator
	if (%c(UIDevice)) {
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationNotificationListenerPortrait, NULL);
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationNotificationListenerPortraitUpsideDown, NULL);
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationNotificationListenerLandscapeLeft, NULL);
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationNotificationListenerLandscapeRight, NULL);
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationNotificationListenerUp, NULL);
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationNotificationListenerLeft, NULL);
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationNotificationListenerRight, NULL);
	}
}

%ctor {
	// setup preferences
	preferencesChanged();
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)preferencesChanged, kSettingsChangedNotification, NULL, CFNotificationSuspensionBehaviorCoalesce);

	// setup the tweak instance
	temp = [[%c(DGUndoRotation) alloc] init];

	// setup notification system to listen for orientation lock from tweak button
	if (%c(SBOrientationLockManager)) {
		%init(lockmanagernotificationcenter);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)lockRotation, kOrientationLockNotificationPortarit, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)lockRotation, kOrientationLockNotificationPortaritUpsideDown, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)lockRotation, kOrientationLockNotificationLandscapeLeft, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)lockRotation, kOrientationLockNotificationLandscapeRight, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)lockRotation, kOrientationUnlockNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	}

	// setup notification system to listen for rotations from activator
	if (%c(UIDevice)) {
		%init(activatorrotationnotificationcenter);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)activatorRotateNotification, kOrientationNotificationListenerPortrait, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)activatorRotateNotification, kOrientationNotificationListenerPortraitUpsideDown, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)activatorRotateNotification, kOrientationNotificationListenerLandscapeLeft, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)activatorRotateNotification, kOrientationNotificationListenerLandscapeRight, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)activatorRotateNotification, kOrientationNotificationListenerUp, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)activatorRotateNotification, kOrientationNotificationListenerLeft, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)activatorRotateNotification, kOrientationNotificationListenerRight, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	}

	// setup activator listener
	[DGUndoRotationListener sharedInstance];
	// setup Activator listeneres if it's installed
	dlopen("/usr/lib/libactivator.dylib", RTLD_LAZY);
	if (%c(SpringBoard) && %c(LAActivator)) {
		[[%c(LAActivator) sharedInstance] registerListener:[DGUndoRotationListener sharedInstance] forName:kOrientationListenerPortrait];
		[[%c(LAActivator) sharedInstance] registerListener:[DGUndoRotationListener sharedInstance] forName:kOrientationListenerPortraitUpsideDown];
		[[%c(LAActivator) sharedInstance] registerListener:[DGUndoRotationListener sharedInstance] forName:kOrientationListenerLandscapeLeft];
		[[%c(LAActivator) sharedInstance] registerListener:[DGUndoRotationListener sharedInstance] forName:kOrientationListenerLandscapeRight];
		[[%c(LAActivator) sharedInstance] registerListener:[DGUndoRotationListener sharedInstance] forName:kOrientationListenerUp];
		[[%c(LAActivator) sharedInstance] registerListener:[DGUndoRotationListener sharedInstance] forName:kOrientationListenerLeft];
		[[%c(LAActivator) sharedInstance] registerListener:[DGUndoRotationListener sharedInstance] forName:kOrientationListenerRight];
	}

	// home screen or application screen
	if (%c(SBIconController)) {
		%init(homescreen);
	} else {
		%init(applications);
	}
}