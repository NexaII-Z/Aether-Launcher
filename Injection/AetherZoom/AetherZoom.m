// AetherZoom: a small overlay library that AETHER's patcher adds to your own Minecraft install.
// It draws one draggable button in its own window above the game. Tapping the button magnifies the
// game's root view (a digital zoom, not a field-of-view change). It reads no game memory, hooks no
// functions and ships no packs. Config is read from aether_zoom.json inside the app bundle.
#import <UIKit/UIKit.h>

static NSString *const kPosKey = @"aether.zoom.pos";

@interface AEZConfig : NSObject
@property (nonatomic) CGFloat strength, buttonSize, opacity;
@property (nonatomic) BOOL smooth;
+ (instancetype)load;
@end

@implementation AEZConfig
+ (instancetype)load {
    AEZConfig *c = [AEZConfig new];
    c.strength = 3.0; c.buttonSize = 54; c.opacity = 0.9; c.smooth = YES;
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"aether_zoom" withExtension:@"json"];
    NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
    id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = obj;
        if ([d[@"strength"] isKindOfClass:[NSNumber class]]) c.strength = MAX(1.25, MIN(8.0, [d[@"strength"] doubleValue]));
        if ([d[@"buttonSize"] isKindOfClass:[NSNumber class]]) c.buttonSize = MAX(32, MIN(96, [d[@"buttonSize"] doubleValue]));
        if ([d[@"opacity"] isKindOfClass:[NSNumber class]]) c.opacity = MAX(0.25, MIN(1.0, [d[@"opacity"] doubleValue]));
        if ([d[@"smooth"] isKindOfClass:[NSNumber class]]) c.smooth = [d[@"smooth"] boolValue];
    }
    return c;
}
@end

@interface AEZWindow : UIWindow
@end
@implementation AEZWindow
// Only the button is interactive; every other touch falls through to the game window below.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self || hit == self.rootViewController.view) ? nil : hit;
}
@end

@interface AEZController : UIViewController
@property (nonatomic, strong) AEZConfig *config;
@property (nonatomic, strong) UIView *button;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *toast;
@property (nonatomic) CGPoint fraction;
@property (nonatomic) CGFloat strength;
@property (nonatomic) BOOL zoomed;
@end

@implementation AEZController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.strength = self.config.strength;

    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kPosKey];
    self.fraction = (saved.count == 2) ? CGPointMake([saved[0] doubleValue], [saved[1] doubleValue]) : CGPointMake(0.93, 0.32);

    CGFloat s = self.config.buttonSize;
    UIView *b = [[UIView alloc] initWithFrame:CGRectMake(0, 0, s, s)];
    b.alpha = self.config.opacity;
    b.layer.cornerRadius = s / 2;
    b.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.08 alpha:0.82];
    b.layer.borderWidth = 1.5;
    b.layer.borderColor = [UIColor colorWithRed:0.86 green:0.12 blue:0.25 alpha:0.95].CGColor;
    b.isAccessibilityElement = YES;
    b.accessibilityLabel = @"AETHER zoom";
    b.accessibilityTraits = UIAccessibilityTraitButton;

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:s * 0.42 weight:UIImageSymbolWeightSemibold];
    self.icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"plus.magnifyingglass" withConfiguration:cfg]];
    self.icon.tintColor = UIColor.whiteColor;
    self.icon.frame = b.bounds;
    self.icon.contentMode = UIViewContentModeCenter;
    [b addSubview:self.icon];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)];
    hold.minimumPressDuration = 0.6;
    [tap requireGestureRecognizerToFail:pan];
    [b addGestureRecognizer:tap]; [b addGestureRecognizer:pan]; [b addGestureRecognizer:hold];
    self.button = b;
    [self.view addSubview:b];

    UILabel *t = [UILabel new];
    t.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    t.textColor = UIColor.whiteColor;
    t.textAlignment = NSTextAlignmentCenter;
    t.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    t.layer.cornerRadius = 10; t.layer.masksToBounds = YES;
    t.alpha = 0;
    self.toast = t;
    [self.view addSubview:t];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self placeButton];
}

- (void)placeButton {
    CGRect r = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGFloat h = self.config.buttonSize / 2;
    CGFloat x = r.origin.x + self.fraction.x * r.size.width;
    CGFloat y = r.origin.y + self.fraction.y * r.size.height;
    x = MAX(r.origin.x + h, MIN(CGRectGetMaxX(r) - h, x));
    y = MAX(r.origin.y + h, MIN(CGRectGetMaxY(r) - h, y));
    self.button.center = CGPointMake(x, y);
}

- (void)panned:(UIPanGestureRecognizer *)g {
    CGPoint d = [g translationInView:self.view];
    [g setTranslation:CGPointZero inView:self.view];
    CGRect r = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGFloat h = self.config.buttonSize / 2;
    CGPoint c = CGPointMake(self.button.center.x + d.x, self.button.center.y + d.y);
    c.x = MAX(r.origin.x + h, MIN(CGRectGetMaxX(r) - h, c.x));
    c.y = MAX(r.origin.y + h, MIN(CGRectGetMaxY(r) - h, c.y));
    self.button.center = c;
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        self.fraction = CGPointMake((c.x - r.origin.x) / r.size.width, (c.y - r.origin.y) / r.size.height);
        [[NSUserDefaults standardUserDefaults] setObject:@[@(self.fraction.x), @(self.fraction.y)] forKey:kPosKey];
    }
}

- (UIView *)gameView {
    UIWindow *own = self.view.window;
    UIWindow *game = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (w == own || w.hidden || w.windowLevel > UIWindowLevelNormal) continue;
        if (w.isKeyWindow) { game = w; break; }
        if (!game) game = w;
    }
    return game.rootViewController.view ?: game;
}

- (void)applyZoom {
    UIView *target = [self gameView];
    if (!target) { [self showToast:@"Game view not found"]; self.zoomed = NO; return; }
    CGAffineTransform t = self.zoomed ? CGAffineTransformMakeScale(self.strength, self.strength) : CGAffineTransformIdentity;
    void (^change)(void) = ^{ target.transform = t; };
    if (self.config.smooth) {
        [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:change completion:nil];
    } else { change(); }
    NSString *name = self.zoomed ? @"minus.magnifyingglass" : @"plus.magnifyingglass";
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:self.config.buttonSize * 0.42 weight:UIImageSymbolWeightSemibold];
    self.icon.image = [UIImage systemImageNamed:name withConfiguration:cfg];
    self.button.backgroundColor = self.zoomed ? [UIColor colorWithRed:0.86 green:0.12 blue:0.25 alpha:0.9] : [UIColor colorWithRed:0.07 green:0.07 blue:0.08 alpha:0.82];
}

- (void)tapped {
    self.zoomed = !self.zoomed;
    [self applyZoom];
    [self showToast:self.zoomed ? [NSString stringWithFormat:@"%.1fx", self.strength] : @"1x"];
}

// Long press cycles the strength in 1x steps (2x to 8x) so you can tune it in game.
- (void)held:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    CGFloat next = floor(self.strength) + 1;
    self.strength = next > 8 ? 2 : next;
    if (self.zoomed) [self applyZoom];
    [self showToast:[NSString stringWithFormat:@"Zoom strength %.0fx", self.strength]];
}

- (void)showToast:(NSString *)text {
    self.toast.text = text;
    [self.toast sizeToFit];
    CGRect f = self.toast.frame; f.size.width += 20; f.size.height += 10;
    self.toast.frame = f;
    self.toast.center = CGPointMake(self.button.center.x, self.button.center.y + self.config.buttonSize / 2 + 18);
    CGFloat maxX = CGRectGetMaxX(self.view.bounds) - 4, minX = 4;
    CGRect g = self.toast.frame;
    if (CGRectGetMaxX(g) > maxX) g.origin.x = maxX - g.size.width;
    if (g.origin.x < minX) g.origin.x = minX;
    self.toast.frame = g;
    [self.toast.layer removeAllAnimations];
    self.toast.alpha = 1;
    [UIView animateWithDuration:0.3 delay:1.0 options:0 animations:^{ self.toast.alpha = 0; } completion:nil];
}

- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
@end

@interface AEZInstaller : NSObject
+ (void)install;
@end

@implementation AEZInstaller
static AEZWindow *gWindow;

+ (void)install {
    if (gWindow) return;
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) { scene = (UIWindowScene *)s; break; }
    }
    AEZWindow *w = scene ? [[AEZWindow alloc] initWithWindowScene:scene] : [[AEZWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    AEZController *vc = [AEZController new];
    vc.config = [AEZConfig load];
    w.rootViewController = vc;
    w.windowLevel = UIWindowLevelAlert + 100;
    w.backgroundColor = UIColor.clearColor;
    w.hidden = NO; // deliberately not makeKeyAndVisible: the game keeps key-window status and input focus
    gWindow = w;
}
@end

__attribute__((constructor))
static void aether_zoom_entry(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [AEZInstaller install]; });
    }];
}
