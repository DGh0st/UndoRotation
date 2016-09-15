#include <UIKit/UIKit.h>

@interface SBOrientationLockManager
+(id)sharedInstance;
-(void)lock:(UIInterfaceOrientation)arg1;
@end

@interface UIDevice (UndoRotation)
-(void)setOrientation:(NSInteger)arg1;
@end

@interface DGUndoRotation : NSObject {
@private
	UIButton *_undoButton;
	NSInteger _currentDisplayedMode; // -1 = error, 0 = undo, 1 = lock, 2 = both
	NSInteger _fromOrientation;
	CGFloat _secondsVisible;
}
@end

#define kBundlePath @"/Library/Application Support/UndoRotation/UndoRotationBundle.bundle"
#define kOrientationLockNotificationPortarit (CFStringRef)@"kOrientationLockNotificationPortarit"
#define kOrientationLockNotificationPortaritUpsideDown (CFStringRef)@"kOrientationLockNotificationPortaritUpsideDown"
#define kOrientationLockNotificationLandscapeLeft (CFStringRef)@"kOrientationLockNotificationLandscapeLeft"
#define kOrientationLockNotificationLandscapeRight (CFStringRef)@"kOrientationLockNotificationLandscapeRight"
#define kSettingsChangedNotification (CFStringRef)@"com.dgh0st.undorotation/settingschanged"
static NSString *const identifier = @"com.dgh0st.undorotation";
static NSString *const kIsEnabled = @"isEnabled";
static NSString *const kMode = @"mode"; // 0 = undo rotation only, 1 = lock orientation only, 2 = both
static NSString *const kDisplaySeconds = @"displaySeconds";
static NSString *const kIsUndoEnabled = @"isUndoEnabled";
static NSString *const kIsCurrentEnabled = @"isCurrentEnabled";
static NSString *const kButtonOpacity = @"buttonOpacity";
static NSString *const kButtonCorner = @"buttonCorner";
BOOL isShowing = NO;
DGUndoRotation *temp = nil;
NSInteger resetToOrientation = -1;

static void PreferencesChanged() {
	CFPreferencesAppSynchronize((CFStringRef)identifier);
}

static BOOL boolValueForKey(NSString *key, BOOL defaultValue){
	NSNumber *result = (__bridge NSNumber *)CFPreferencesCopyAppValue((CFStringRef)key, (CFStringRef)identifier);
	BOOL temp = result ? [result boolValue] : defaultValue;
	[result release];
	return temp;
}

static NSInteger intValueForKey(NSString *key, NSInteger defaultValue){
	NSNumber *result= (__bridge NSNumber *)CFPreferencesCopyAppValue((CFStringRef)key, (CFStringRef)identifier);
	NSInteger temp = result ? [result intValue] : defaultValue;
	[result release];
	return temp;
}

static CGFloat doubleValueForKey(NSString *key, CGFloat defaultValue){
	NSNumber *result= (__bridge NSNumber *)CFPreferencesCopyAppValue((CFStringRef)key, (CFStringRef)identifier);
	CGFloat temp = result ? [result floatValue] : defaultValue;
	[result release];
	return temp;
}

static inline void lockRotation(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
	if (name == kOrientationLockNotificationPortarit) {
		[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationPortrait];
	} else if (name == kOrientationLockNotificationPortaritUpsideDown) {
		[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationPortraitUpsideDown];
	} else if (name == kOrientationLockNotificationLandscapeLeft) {
		[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationLandscapeLeft];
	} else if (name == kOrientationLockNotificationLandscapeRight) {
		[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationLandscapeRight];
	}
	resetToOrientation = [[UIDevice currentDevice] orientation];
	[[%c(SBOrientationLockManager) sharedInstance] lock:resetToOrientation];
}

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
			[_undoButton setAlpha:doubleValueForKey(kButtonOpacity, 0.75)];
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
		CGFloat displaySecs = doubleValueForKey(kDisplaySeconds, 5);
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
	if (isShowing) {
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
				[[%c(SBOrientationLockManager) sharedInstance] lock:[[UIDevice currentDevice] orientation]];
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
	%orig;
	if (resetToOrientation == [[UIDevice currentDevice] orientation] && !boolValueForKey(kIsUndoEnabled, NO)) {
		resetToOrientation = -1;
		return;
	}
	if (boolValueForKey(kIsEnabled, YES) && temp) {
		[temp showFromOrientation:arg1 toOrientation:[[UIDevice currentDevice] orientation]];
	}
}

-(void)viewWillDisappear:(BOOL)arg1 {
	if (temp) {
		[temp forceHide];
	}
	%orig;
}
-(void)viewDidAppear:(BOOL)arg1 {
	%orig;
	if (boolValueForKey(kIsEnabled, YES) && boolValueForKey(kIsCurrentEnabled, NO) && temp) {
		NSInteger orientation = [[UIDevice currentDevice] orientation];
		[temp showFromOrientation:orientation toOrientation:orientation];
	}
}
%end
%end

%group homescreen
%hook SBIconController
-(void)_didRotateFromInterfaceOrientation:(NSInteger)arg1 {
	%orig;
	if (resetToOrientation == [[UIDevice currentDevice] orientation] && !boolValueForKey(kIsUndoEnabled, NO)) {
		resetToOrientation = -1;
		return;
	}
	if(boolValueForKey(kIsEnabled, YES) && temp) {
		[temp showFromOrientation:arg1 toOrientation:[[UIDevice currentDevice] orientation]];
	}
}
-(void)viewWillDisappear:(BOOL)arg1 {
	if (temp) {
		[temp forceHide];
	}
	%orig;
}
-(void)_launchIcon:(id)arg1 {
	if (temp) {
		[temp forceHide];
	}
	%orig;	
}
-(void)_lockScreenUIWillLock:(id)arg1 {
	if (temp) {
		[temp forceHide];
	}
	%orig;
}
-(void)viewDidAppear:(BOOL)arg1 {
	%orig;
	if (boolValueForKey(kIsEnabled, YES) && boolValueForKey(kIsCurrentEnabled, NO) && temp) {
		NSInteger orientation = [[UIDevice currentDevice] orientation];
		[temp showFromOrientation:orientation toOrientation:orientation];
	}
}
%end
%end

%dtor {
	[temp release];
	temp = nil;
	if (%c(SBOrientationLockManager)) {
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationLockNotificationPortarit, NULL);
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationLockNotificationPortaritUpsideDown, NULL);
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationLockNotificationLandscapeLeft, NULL);
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationLockNotificationLandscapeRight, NULL);
	}
	CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kSettingsChangedNotification, NULL);
}

%ctor {
	temp = [[%c(DGUndoRotation) alloc] init];
	if (%c(SBOrientationLockManager)) {
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)lockRotation, kOrientationLockNotificationPortarit, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)lockRotation, kOrientationLockNotificationPortaritUpsideDown, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)lockRotation, kOrientationLockNotificationLandscapeLeft, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)lockRotation, kOrientationLockNotificationLandscapeRight, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	}
	if (%c(SBIconController)) {
		%init(homescreen);
	} else {
		%init(applications);
	}
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)PreferencesChanged, kSettingsChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}