#include <UIKit/UIKit.h>
#include <libactivator/libactivator.h>

@interface SBOrientationLockManager
+(id)sharedInstance;
-(void)lock:(UIInterfaceOrientation)arg1;
-(BOOL)isUserLocked;
-(BOOL)isLocked;
-(void)unlock;
@end

@interface UIDevice (UndoRotation)
-(void)setOrientation:(NSInteger)arg1;
@end

@interface UIViewController (UndoRotation)
-(id)storyboardIdentifier;
-(void)setStoryboardIdentifier:(id)arg1 ;
@end

@interface DGUndoRotationListener : NSObject <LAListener> {
	UIAlertController *alert;
	UIWindow *window;
}
+(DGUndoRotationListener *)sharedInstance;
@end

@interface DGUndoRotation : NSObject {
	UIButton *_undoButton;
	NSInteger _currentDisplayedMode; // -1 = error, 0 = undo, 1 = lock, 2 = both
	NSInteger _fromOrientation;
	CGFloat _secondsVisible;
}
+(DGUndoRotation *)sharedInstance;
-(void)forceHide;
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
#define kIsLabelEnabled @"isLabelEnabled"
#define kDisplaySeconds @"displaySeconds"
#define kIsUndoEnabled @"isUndoEnabled"
#define kIsCurrentEnabled @"isCurrentEnabled"
#define kIsUnlockEnabled @"isUnlockEnabled"
#define kButtonOpacity @"buttonOpacity"
#define kButtonCorner @"buttonCorner"
#define kButtonSize @"buttonWidth"
#define kButtonRoundness @"buttonRoundness"
#define kAltModePrefix @"AltMode-"
#define kWhitelsitPrefix @"WhiteListApp-"
#define kHomescreenEnabled @"isHomescreenEnabled"

// Activator listener names
#define kOrientationListenerUp @"com.dgh0st.undorotation.up"
#define kOrientationListenerLeft @"com.dgh0st.undorotation.left"
#define kOrientationListenerRight @"com.dgh0st.undorotation.right"
#define kOrientationListenerPortrait @"com.dgh0st.undorotation.portrait"
#define kOrientationListenerPortraitUpsideDown @"com.dgh0st.undorotation.portraitupsidedown"
#define kOrientationListenerLandscapeRight @"com.dgh0st.undorotation.landscaperight"
#define kOrientationListenerLandscapeLeft @"com.dgh0st.undorotation.landscapeleft"
#define kUndoRotationListenerControlWindow @"com.dgh0st.undorotation.controlwindow"

// Activator listener notification to application
#define kOrientationNotificationListenerUp (CFStringRef)@"com.dgh0st.undorotation.uprotate"
#define kOrientationNotificationListenerLeft (CFStringRef)@"com.dgh0st.undorotation.leftrotate"
#define kOrientationNotificationListenerRight (CFStringRef)@"com.dgh0st.undorotation.rightrotate"
#define kOrientationNotificationListenerPortrait (CFStringRef)@"com.dgh0st.undorotation.portraitrotate"
#define kOrientationNotificationListenerPortraitUpsideDown (CFStringRef)@"com.dgh0st.undorotation.portraitupsidedownrotate"
#define kOrientationNotificationListenerLandscapeRight (CFStringRef)@"com.dgh0st.undorotation.landscaperightrotate"
#define kOrientationNotificationListenerLandscapeLeft (CFStringRef)@"com.dgh0st.undorotation.landscapeleftrotate"
#define kOrientationNotificationLockOrUnlock (CFStringRef)@"com.dgh0st.undorotation.lockorunlock"
#define kControlWindowNotificationToggle (CFStringRef)@"com.dgh0st.undorotation.controlwindowtoggle"

#define UIColorFromRGB(rgbValue) [UIColor colorWithRed:((CGFloat)((rgbValue & 0xFF0000) >> 16))/255.0f green:((CGFloat)((rgbValue & 0xFF00) >> 8))/255.0f blue:((CGFloat)(rgbValue & 0xFF))/255.0f alpha:1.0f]

BOOL isShowing = NO;
BOOL isControlWindowVisible = NO;
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

static void toggleControlWindowVisibility() {
	if (isShowing && [DGUndoRotation sharedInstance]) {
		[[DGUndoRotation sharedInstance] forceHide];
	}
	isControlWindowVisible = !isControlWindowVisible;
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

static BOOL getPerApp(NSString *appId, NSString *prefix, BOOL defaultValue) {
	if (prefs) {
	    for (NSString *key in [prefs allKeys]) {
			if ([key hasPrefix:prefix]) {
			    NSString *tempId = [key substringFromIndex:[prefix length]];
			    if ([tempId isEqualToString:appId]) {
			    	return [prefs objectForKey:key] ? [[prefs objectForKey:key] boolValue] : defaultValue;
			    }
			}
	   	}
	}
    return defaultValue;
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
	if ((self = [super init])) {
		alert = nil;
		window = nil;
	}
	return self;
}
-(void)sendLeftNotificaton {
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationNotificationListenerLeft, NULL, NULL, YES);
	if (alert) {
		[alert dismissViewControllerAnimated:YES completion:nil];
		alert = nil;
	}
	if (window) {
		[window release];
		window = nil;
	}
}
-(void)sendRightNotificaton {
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationNotificationListenerRight, NULL, NULL, YES);
	if (alert) {
		[alert dismissViewControllerAnimated:YES completion:nil];
		alert = nil;
	}
	if (window) {
		[window release];
		window = nil;
	}
}
-(void)sendUpNotificaton {
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationNotificationListenerUp, NULL, NULL, YES);
	if (alert) {
		[alert dismissViewControllerAnimated:YES completion:nil];
		alert = nil;
	}
	if (window) {
		[window release];
		window = nil;
	}
}
-(void)sendLockOrUnlockNotificaton {
	UIInterfaceOrientation currentOrientation = [[UIDevice currentDevice] orientation];
	if (currentOrientation == UIInterfaceOrientationPortrait) {
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationNotificationListenerPortrait, NULL, NULL, YES);
	} else if (currentOrientation == UIInterfaceOrientationPortraitUpsideDown) {
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationNotificationListenerPortraitUpsideDown, NULL, NULL, YES);
	} else if (currentOrientation == UIInterfaceOrientationLandscapeLeft) {
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationNotificationListenerLandscapeLeft, NULL, NULL, YES);
	} else if (currentOrientation == UIInterfaceOrientationLandscapeRight) {
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationNotificationListenerLandscapeRight, NULL, NULL, YES);
	}
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationNotificationLockOrUnlock, NULL, NULL, YES);
	if (alert) {
		[alert dismissViewControllerAnimated:YES completion:nil];
		alert = nil;
	}
	if (window) {
		[window release];
		window = nil;
	}
}
-(void)showControlWindow {
	if (alert) {
		[alert dismissViewControllerAnimated:YES completion:nil];
		alert = nil;
	}
	alert = [UIAlertController alertControllerWithTitle:@"UndoRotation" message:nil preferredStyle:UIAlertControllerStyleAlert];

	if (window) {
		[window release];
		window = nil;
	}
	window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	window.rootViewController = [[UIViewController alloc] init];
	[window.rootViewController setStoryboardIdentifier:@"UndoRotationViewController"];
	window.windowLevel = UIWindowLevelAlert + 1;

	UIViewController *v = [[UIViewController alloc] init];
	[v setStoryboardIdentifier:@"UndoRotationViewController"];
	v.view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 224, 160)];
	v.preferredContentSize = CGSizeMake(224, 160);
	[alert setValue:v forKey:@"contentViewController"];

	// bundle for images
	NSBundle *bundle = [[NSBundle alloc] initWithPath:kBundlePath];

	// left
	UIButton *leftButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
	[leftButton addTarget:self action:@selector(sendLeftNotificaton) forControlEvents:UIControlEventTouchUpInside];
	UIImage *imageLeft = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"undoRotationLeft" ofType:@"png"]];
	leftButton.frame = CGRectMake(0, 80, 64, 64);
	[leftButton setBackgroundImage:imageLeft forState:UIControlStateNormal];
	[v.view addSubview:leftButton];

	// right
	UIButton *rightButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
	[rightButton addTarget:self action:@selector(sendRightNotificaton) forControlEvents:UIControlEventTouchUpInside];
	UIImage *imageRight = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"undoRotationRight" ofType:@"png"]];
	rightButton.frame = CGRectMake(160, 80, 64, 64);
	[rightButton setBackgroundImage:imageRight forState:UIControlStateNormal];
	[v.view addSubview:rightButton];

	// up
	UIButton *upButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
	[upButton addTarget:self action:@selector(sendUpNotificaton) forControlEvents:UIControlEventTouchUpInside];
	UIImage *imageUp = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"undoRotationUp" ofType:@"png"]];
	upButton.frame = CGRectMake(80, 0, 64, 64);
	[upButton setBackgroundImage:imageUp forState:UIControlStateNormal];
	[v.view addSubview:upButton];

	// lock
	UIButton *lockButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
	[lockButton addTarget:self action:@selector(sendLockOrUnlockNotificaton) forControlEvents:UIControlEventTouchUpInside];
	UIImage *imageLock = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"undoRotationLock" ofType:@"png"]];
	lockButton.frame = CGRectMake(80, 80, 64, 64);
	[lockButton setBackgroundImage:imageLock forState:UIControlStateNormal];
	[v.view addSubview:lockButton];

	// cancel button
	UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler: ^(UIAlertAction *action){
		alert = nil;
		if (window) {
			[window release];
			window = nil;
		}
	}];
	[alert addAction:cancelAction];

	[window makeKeyAndVisible];
	[window.rootViewController presentViewController:alert animated:YES completion:nil];

	[bundle release];
	[v.view release];
	[v release];
	[window.rootViewController release];
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
	} else if ([name isEqualToString:kUndoRotationListenerControlWindow]) {
		[self showControlWindow];
	} else {
		[event setHandled:NO]; // default acion if none of our actions occured
	}
}
@end

@implementation DGUndoRotation
+(DGUndoRotation *)sharedInstance {
	static DGUndoRotation *sharedObject = nil;
	static dispatch_once_t p = 0;
	dispatch_once(&p, ^{
		sharedObject = [[self alloc] init];
	});
	return sharedObject;
}
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
	if (isControlWindowVisible) {
		return;
	}
	if (isShowing) {
		[self forceHide:_undoButton];
	}
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
			[self forceHide:_undoButton];
			return;
		}

		// after x seconds remove button
		[self performSelector:@selector(forceHide:) withObject:_undoButton afterDelay:doubleValueForKey(kDisplaySeconds, 5.0)];// / 5.0];
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
			CGSize statusBarSize = [UIApplication sharedApplication].statusBarFrame.size;
			NSInteger buttonSize = intValueForKey(kButtonSize, 64);
			NSInteger labelHeight = 0;
			if (boolValueForKey(kIsLabelEnabled, false)) {
				// set the label
				labelHeight = buttonSize / 4;
				[_undoButton setContentVerticalAlignment:UIControlContentVerticalAlignmentBottom];
				if (_currentDisplayedMode == 0) {
					[_undoButton setTitle:@"Undo" forState:UIControlStateNormal];
				} else if (_currentDisplayedMode == 1) {
					[_undoButton setTitle:@"Lock" forState:UIControlStateNormal];
				} else if (_currentDisplayedMode == 2) {
					[_undoButton setTitle:@"Undo & Lock" forState:UIControlStateNormal];
				}
				_undoButton.titleLabel.adjustsFontSizeToFitWidth = YES;
				_undoButton.titleLabel.font = [UIFont systemFontOfSize:labelHeight];
				[_undoButton layoutIfNeeded];
			}
			// set the icon
			if (selectedCorner == 0) { // top left
				_undoButton.frame = CGRectMake(buttonSize / 4, buttonSize / 4 + statusBarSize.height, buttonSize, buttonSize + labelHeight / 2);
				_undoButton.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleRightMargin;
			} else if (selectedCorner == 1) { // top right
				_undoButton.frame = CGRectMake(appSize.width - buttonSize * 1.25f, buttonSize / 4 + statusBarSize.height, buttonSize, buttonSize + labelHeight / 2);
				_undoButton.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin;
			} else if (selectedCorner == 2) { // bottom left
				_undoButton.frame = CGRectMake(buttonSize / 4, appSize.height - buttonSize * 1.25f - labelHeight, buttonSize, buttonSize + labelHeight / 2);
				_undoButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
			} else if (selectedCorner == 3) { // bottom right
				_undoButton.frame = CGRectMake(appSize.width - buttonSize * 1.25f, appSize.height - buttonSize * 1.25f - labelHeight, buttonSize, buttonSize + labelHeight / 2);
				_undoButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;
			}
			_undoButton.layer.cornerRadius = doubleValueForKey(kButtonRoundness, 5.0f);
			_undoButton.backgroundColor = UIColorFromRGB(0xCED1D6);
			_undoButton.clipsToBounds = YES;
			UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
			imageView.frame = CGRectMake(0, 0, buttonSize, buttonSize);
			imageView.contentMode = UIViewContentModeScaleAspectFill;
			[_undoButton addSubview:imageView];
			[_undoButton setAlpha:doubleValueForKey(kButtonOpacity, 0.8)];
		} else {
			[self forceHide:_undoButton];
		}
		[bundle release];
	}
}
-(void)forceHide:(id)object {
	if (_undoButton && object && [[object class] isEqual:[_undoButton class]] && object == _undoButton) {
		[_undoButton removeFromSuperview];
		_undoButton = nil;
	}
	_currentDisplayedMode = -1;
	isShowing = NO;
}
-(void)forceHide {
	[self forceHide:_undoButton];
}
-(void)undoRotation:(UIButton *)sender {
	if (isShowing && sender == _undoButton) {
		// undo orientation
		if (_currentDisplayedMode == 0 || _currentDisplayedMode == 2) { // undo or both mode
			resetToOrientation = _fromOrientation;
			[[UIDevice currentDevice] setOrientation:_fromOrientation];
		}
		// lock orietnation
		if (_currentDisplayedMode == 1 || _currentDisplayedMode == 2) { // lock or both mode
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
		[self forceHide:_undoButton];
	}
}
@end

%group applications
%hook UIViewController
-(void)didRotateFromInterfaceOrientation:(NSInteger)arg1 {
	%orig;
	if (boolValueForKey(kIsEnabled, YES) && !getPerApp([[NSBundle mainBundle] bundleIdentifier], kWhitelsitPrefix, NO)) {
		// don't do anything if control window is displaying (activator action)
		if ([[self storyboardIdentifier] isEqualToString:@"UndoRotationViewController"] || isControlWindowVisible) {
			return;
		}
		// display tweak button if alternative mode not enabled for this app
		if (!getPerApp([[NSBundle mainBundle] bundleIdentifier], kAltModePrefix, NO)) {
			if (resetToOrientation == [[UIDevice currentDevice] orientation] && !boolValueForKey(kIsUndoEnabled, NO)) {
				resetToOrientation = -1;
				return;
			}
			if ([DGUndoRotation sharedInstance]) {
				[[DGUndoRotation sharedInstance] showFromOrientation:arg1 toOrientation:[[UIDevice currentDevice] orientation]];
			}
		}
	}
}
-(void)viewWillDisappear:(BOOL)arg1 {
	if (boolValueForKey(kIsEnabled, YES)) {	
		// hide button
		if ([DGUndoRotation sharedInstance]) {
			[[DGUndoRotation sharedInstance] forceHide];
		}
		// unlock orientation if enabled
		if (boolValueForKey(kIsUnlockEnabled, NO)) {
			if (%c(SBOrientationLockManager) && (([[%c(SBOrientationLockManager) sharedInstance] respondsToSelector:@selector(isLocked)] && [[%c(SBOrientationLockManager) sharedInstance] isLocked]) || ([[%c(SBOrientationLockManager) sharedInstance] respondsToSelector:@selector(isUserLocked)] && [[%c(SBOrientationLockManager) sharedInstance] isUserLocked]))) {
				[[%c(SBOrientationLockManager) sharedInstance] unlock];
			} else {
				CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationUnlockNotification, NULL, NULL, YES);
			}
		}
	}
	%orig;
}
-(void)viewDidAppear:(BOOL)arg1 {
	%orig;
	if (boolValueForKey(kIsEnabled, YES)) {
		// don't do anything if control window is displaying (activator action)
		if ([[self storyboardIdentifier] isEqualToString:@"UndoRotationViewController"] || isControlWindowVisible) {
			return;
		}
		// display current orientation button if needed
		if (boolValueForKey(kIsCurrentEnabled, NO) && [DGUndoRotation sharedInstance]) {
			NSInteger orientation = [[UIDevice currentDevice] orientation];
			[[DGUndoRotation sharedInstance] showFromOrientation:orientation toOrientation:orientation];
		}
	}
}
%end

%hook UIDevice
-(void)setOrientation:(NSInteger)arg1 animated:(BOOL)arg2 {
	NSInteger lastOrientation = [self orientation];
	%orig;
	if (boolValueForKey(kIsEnabled, YES) && !getPerApp([[NSBundle mainBundle] bundleIdentifier], kWhitelsitPrefix, NO)) {
		// don't do anything if control window is displaying (activator action)
		if (isControlWindowVisible) {
			return;
		}
		// display tweak button if alternative mode enabled for this app
		if (getPerApp([[NSBundle mainBundle] bundleIdentifier], kAltModePrefix, NO)) {
			if (resetToOrientation == [self orientation] && resetToOrientation == arg1 && !boolValueForKey(kIsUndoEnabled, NO)) {
				resetToOrientation = -1;
				return;
			}
			if ([DGUndoRotation sharedInstance] && arg1 == [self orientation] && (arg1 != lastOrientation || !boolValueForKey(kIsCurrentEnabled, NO))) {
				[[DGUndoRotation sharedInstance] showFromOrientation:lastOrientation toOrientation:arg1];
			}
		}
	}
}
%end
%end

%group lockmanagernotificationcenter
static inline void lockRotation(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
	// orientation lock callback handler
	if (name == kOrientationNotificationLockOrUnlock) {
		if (([[%c(SBOrientationLockManager) sharedInstance] respondsToSelector:@selector(isLocked)] && [[%c(SBOrientationLockManager) sharedInstance] isLocked]) || ([[%c(SBOrientationLockManager) sharedInstance] respondsToSelector:@selector(isUserLocked)] && [[%c(SBOrientationLockManager) sharedInstance] isUserLocked])) {
			[[%c(SBOrientationLockManager) sharedInstance] unlock];
		} else {
			[[%c(SBOrientationLockManager) sharedInstance] lock:[[UIDevice currentDevice] orientation]];
		}
		return;
	} else if (name == kOrientationUnlockNotification) {
		if (([[%c(SBOrientationLockManager) sharedInstance] respondsToSelector:@selector(isLocked)] && [[%c(SBOrientationLockManager) sharedInstance] isLocked]) || ([[%c(SBOrientationLockManager) sharedInstance] respondsToSelector:@selector(isUserLocked)] && [[%c(SBOrientationLockManager) sharedInstance] isUserLocked])) {
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
	if (boolValueForKey(kIsUndoEnabled, NO) && (([[%c(SBOrientationLockManager) sharedInstance] respondsToSelector:@selector(isLocked)] && [[%c(SBOrientationLockManager) sharedInstance] isLocked]) || ([[%c(SBOrientationLockManager) sharedInstance] respondsToSelector:@selector(isUserLocked)] && [[%c(SBOrientationLockManager) sharedInstance] isUserLocked]))) {
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
	if (boolValueForKey(kIsEnabled, YES) && boolValueForKey(kHomescreenEnabled, YES)) {
		// don't do anything if control window is visible (activator action)
		if (isControlWindowVisible) {
			return;
		}
		// do not display button if taking tweak action
		if (resetToOrientation == [[UIDevice currentDevice] orientation] && !boolValueForKey(kIsUndoEnabled, NO)) {
			resetToOrientation = -1;
			return;
		}
		// display button if needed
		if([DGUndoRotation sharedInstance]) {
			[[DGUndoRotation sharedInstance] showFromOrientation:arg1 toOrientation:[[UIDevice currentDevice] orientation]];
		}
	}
}
-(void)viewWillDisappear:(BOOL)arg1 {
	if (boolValueForKey(kIsEnabled, YES)) {
		// hide button
		if ([DGUndoRotation sharedInstance]) {
			[[DGUndoRotation sharedInstance] forceHide];
		}
		// unlock orientation if needed
		if (boolValueForKey(kIsUnlockEnabled, NO)) {
			if (%c(SBOrientationLockManager) && (([[%c(SBOrientationLockManager) sharedInstance] respondsToSelector:@selector(isLocked)] && [[%c(SBOrientationLockManager) sharedInstance] isLocked]) || ([[%c(SBOrientationLockManager) sharedInstance] respondsToSelector:@selector(isUserLocked)] && [[%c(SBOrientationLockManager) sharedInstance] isUserLocked]))) {
				[[%c(SBOrientationLockManager) sharedInstance] unlock];
			} else {
				CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationUnlockNotification, NULL, NULL, YES);
			}
		}
	}
	%orig;
}
-(void)_launchIcon:(id)arg1 {
	if (boolValueForKey(kIsEnabled, YES)) {
		// hide button
		if ([DGUndoRotation sharedInstance]) {
			[[DGUndoRotation sharedInstance] forceHide];
		}
		// unlock orientation if needed
		if (boolValueForKey(kIsUnlockEnabled, NO)) {
			if (%c(SBOrientationLockManager) && (([[%c(SBOrientationLockManager) sharedInstance] respondsToSelector:@selector(isLocked)] && [[%c(SBOrientationLockManager) sharedInstance] isLocked]) || ([[%c(SBOrientationLockManager) sharedInstance] respondsToSelector:@selector(isUserLocked)] && [[%c(SBOrientationLockManager) sharedInstance] isUserLocked]))) {
				[[%c(SBOrientationLockManager) sharedInstance] unlock];
			} else {
				CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationUnlockNotification, NULL, NULL, YES);
			}
		}
	}
	%orig;	
}
-(void)_lockScreenUIWillLock:(id)arg1 {
	if (boolValueForKey(kIsEnabled, YES)) {
		// hide button
		if ([DGUndoRotation sharedInstance]) {
			[[DGUndoRotation sharedInstance] forceHide];
		}
		// unlock orientation if needed
		if (boolValueForKey(kIsUnlockEnabled, NO)) {
			if (%c(SBOrientationLockManager) && (([[%c(SBOrientationLockManager) sharedInstance] respondsToSelector:@selector(isLocked)] && [[%c(SBOrientationLockManager) sharedInstance] isLocked]) || ([[%c(SBOrientationLockManager) sharedInstance] respondsToSelector:@selector(isUserLocked)] && [[%c(SBOrientationLockManager) sharedInstance] isUserLocked]))) {
				[[%c(SBOrientationLockManager) sharedInstance] unlock];
			} else {
				CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationUnlockNotification, NULL, NULL, YES);
			}
		}
	}
	%orig;
}
-(void)viewDidAppear:(BOOL)arg1 {
	%orig;
	if (boolValueForKey(kIsEnabled, YES) && boolValueForKey(kHomescreenEnabled, YES)) {
		// don't do anything if control window is visible (activator action)
		if (isControlWindowVisible) {
			return;
		}
		// display current orientation button if needed
		if ( boolValueForKey(kIsCurrentEnabled, NO) && [DGUndoRotation sharedInstance]) {
			NSInteger orientation = [[UIDevice currentDevice] orientation];
			[[DGUndoRotation sharedInstance] showFromOrientation:orientation toOrientation:orientation];
		}
	}
}
%end
%end

%dtor {
	// remove preference notification listener
	CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kSettingsChangedNotification, NULL);

	// remove listeners for orientation lock from tweak button
	if (%c(SBOrientationLockManager)) {
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationLockNotificationPortarit, NULL);
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationLockNotificationPortaritUpsideDown, NULL);
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationLockNotificationLandscapeLeft, NULL);
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationLockNotificationLandscapeRight, NULL);
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationUnlockNotification, NULL);
		CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kOrientationNotificationLockOrUnlock, NULL);
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

	// remove controlwindow visibility listener
	CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kControlWindowNotificationToggle, NULL);
}

%ctor {
	// setup preferences
	preferencesChanged();
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)preferencesChanged, kSettingsChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

	// setup the tweak instance
	[DGUndoRotation sharedInstance];

	// setup notification system to listen for orientation lock from tweak button
	if (%c(SBOrientationLockManager)) {
		%init(lockmanagernotificationcenter);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)lockRotation, kOrientationLockNotificationPortarit, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)lockRotation, kOrientationLockNotificationPortaritUpsideDown, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)lockRotation, kOrientationLockNotificationLandscapeLeft, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)lockRotation, kOrientationLockNotificationLandscapeRight, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)lockRotation, kOrientationUnlockNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)lockRotation, kOrientationNotificationLockOrUnlock, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
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
		[[%c(LAActivator) sharedInstance] registerListener:[DGUndoRotationListener sharedInstance] forName:kUndoRotationListenerControlWindow];
	}

	// home screen or application screen
	NSArray *args = [[NSClassFromString(@"NSProcessInfo") processInfo] arguments];
	if (args.count != 0) {
		NSString *execPath = args[0];
		if (execPath) {
			if ([[execPath lastPathComponent] isEqualToString:@"SpringBoard"] && %c(SBIconController)) {
				%init(homescreen);
			} else if (execPath && ([execPath rangeOfString:@"/Application"].location != NSNotFound)) {
				%init(applications);
			}
		}	
	}

	// controlwindow visibility listener
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)toggleControlWindowVisibility, kControlWindowNotificationToggle, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}