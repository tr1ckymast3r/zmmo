// tweak/ZRMRemote/Tweak.x — Floating button UI + SpringBoard hooks

#import <UIKit/UIKit.h>
#import <substrate.h>

static UIWindow *floatingWindow = nil;

static void showFloatingButton() {
    if (floatingWindow) return;

    CGRect screen = [UIScreen mainScreen].bounds;
    floatingWindow = [[UIWindow alloc] initWithFrame:CGRectMake(screen.size.width - 60, 200, 50, 50)];
    floatingWindow.windowLevel = UIWindowLevelAlert + 1;
    floatingWindow.backgroundColor = [UIColor clearColor];

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = floatingWindow.bounds;
    btn.backgroundColor = [UIColor colorWithRed:0 green:0.67 blue:0.92 alpha:0.9];
    btn.layer.cornerRadius = 25;
    btn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [btn setTitle:@"RMT" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

    // Tap → toggle control panel
    [btn addTarget:btn action:@selector(toggleControlPanel:) forControlEvents:UIControlEventTouchUpInside];

    // Pan → move
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:btn action:@selector(handlePan:)];
    [btn addGestureRecognizer:pan];

    [floatingWindow addSubview:btn];
    floatingWindow.hidden = NO;
}

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        showFloatingButton();
    });
}

%end

// Button actions (categories)
@interface UIButton (ZRMRemote)
- (void)toggleControlPanel:(id)sender;
- (void)handlePan:(UIPanGestureRecognizer *)gesture;
@end

@implementation UIButton (ZRMRemote)

- (void)toggleControlPanel:(id)sender {
    // Post notification → daemon handles
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.zmmo.iosrmt.togglePanel"), NULL, NULL, YES);
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint trans = [gesture translationInView:self.superview];
    self.superview.center = CGPointMake(self.superview.center.x + trans.x,
                                        self.superview.center.y + trans.y);
    [gesture setTranslation:CGPointZero inView:self.superview];
}

@end

%ctor {
    NSLog(@"[ZRMRemote] Loaded — Remote floating button");
}
