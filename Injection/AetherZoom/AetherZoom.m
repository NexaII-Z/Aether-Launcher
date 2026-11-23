// AETHER Client overlay (AetherZoom.dylib). Added to your own Minecraft install by aether_patch.py.
// It owns one passthrough window above the game with: a zoom button, a panel button, and a small HUD.
// It only READS: frames handed to Metal, tap times, battery, memory, clock. It does not read or change
// game memory, hook game functions, or add packs. Zoom is a screen magnification of the game view.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <mach/mach.h>

static NSString *const kPosKey = @"aether.zoom.pos";
static NSString *const kSetKey = @"aether.client.v1";

static uint64_t gFrames;                    // frames the game asked Metal for (render thread)
static NSMutableArray<NSNumber *> *gTaps;   // tap timestamps (main thread)
static UIWindow *gOwnWindow;

#pragma mark - Settings

static NSDictionary *aez_defaults(void) {
    return @{@"fps": @YES, @"cps": @NO, @"clock": @NO, @"battery": @NO, @"memory": @NO, @"thermal": @NO,
             @"zoomButton": @YES, @"hudScale": @1.0, @"hudOpacity": @0.85, @"accent": @0,
             @"hudX": @0.02, @"hudY": @0.06};
}
static id aez_get(NSString *k) {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSetKey];
    return d[k] ?: aez_defaults()[k];
}
static void aez_set(NSString *k, id v) {
    NSMutableDictionary *d = [([[NSUserDefaults standardUserDefaults] dictionaryForKey:kSetKey] ?: @{}) mutableCopy];
    d[k] = v;
    [[NSUserDefaults standardUserDefaults] setObject:d forKey:kSetKey];
}
static UIColor *aez_accent(void) {
    switch ([aez_get(@"accent") integerValue]) {
        case 1: return [UIColor colorWithWhite:0.95 alpha:1];
        case 2: return [UIColor colorWithRed:0.20 green:0.80 blue:0.95 alpha:1];
        case 3: return [UIColor colorWithRed:0.30 green:0.85 blue:0.45 alpha:1];
        default: return [UIColor colorWithRed:0.86 green:0.12 blue:0.25 alpha:1];
    }
}
static UIColor *aez_dark(CGFloat a) { return [UIColor colorWithRed:0.07 green:0.07 blue:0.08 alpha:a]; }
static CGFloat aez_clamp(CGFloat v, CGFloat lo, CGFloat hi) { return v < lo ? lo : (v > hi ? hi : v); }

static double aez_memory_mb(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) == KERN_SUCCESS) return info.phys_footprint / 1048576.0;
    return 0;
}

#pragma mark - Read-only probes (method swizzles that only count)

static id (*gOrigNextDrawable)(id, SEL);
static id aez_nextDrawable(id self, SEL _cmd) {
    __atomic_fetch_add(&gFrames, 1, __ATOMIC_RELAXED);
    return gOrigNextDrawable(self, _cmd);
}

static void (*gOrigSendEvent)(id, SEL, UIEvent *);
static void aez_sendEvent(id self, SEL _cmd, UIEvent *event) {
    if (event.type == UIEventTypeTouches) {
        for (UITouch *t in event.allTouches) {
            if (t.phase == UITouchPhaseBegan && t.window != gOwnWindow) {
                if (!gTaps) gTaps = [NSMutableArray new];
                [gTaps addObject:@(CACurrentMediaTime())];
            }
        }
    }
    gOrigSendEvent(self, _cmd, event);
}

static void aez_install_probes(void) {
    Class metal = objc_getClass("CAMetalLayer");
    if (metal) {
        Method m = class_getInstanceMethod(metal, @selector(nextDrawable));
        if (m) { gOrigNextDrawable = (id (*)(id, SEL))method_getImplementation(m); method_setImplementation(m, (IMP)aez_nextDrawable); }
    }
    Method e = class_getInstanceMethod([UIApplication class], @selector(sendEvent:));
    if (e) { gOrigSendEvent = (void (*)(id, SEL, UIEvent *))method_getImplementation(e); method_setImplementation(e, (IMP)aez_sendEvent); }
}

#pragma mark - Config baked in by the patcher

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
        if ([d[@"strength"] isKindOfClass:[NSNumber class]]) c.strength = aez_clamp([d[@"strength"] doubleValue], 1.25, 8.0);
        if ([d[@"buttonSize"] isKindOfClass:[NSNumber class]]) c.buttonSize = aez_clamp([d[@"buttonSize"] doubleValue], 32, 96);
        if ([d[@"opacity"] isKindOfClass:[NSNumber class]]) c.opacity = aez_clamp([d[@"opacity"] doubleValue], 0.25, 1.0);
        if ([d[@"smooth"] isKindOfClass:[NSNumber class]]) c.smooth = [d[@"smooth"] boolValue];
    }
    return c;
}
@end

#pragma mark - Window

@interface AEZWindow : UIWindow
@end
@implementation AEZWindow
// Only our own controls are interactive; every other touch falls through to the game window.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self || hit == self.rootViewController.view) ? nil : hit;
}
@end

#pragma mark - Controller

@interface AEZController : UIViewController
@property (nonatomic, strong) AEZConfig *config;
@property (nonatomic, strong) UIView *dock, *zoomBtn, *menuBtn, *panel, *hud;
@property (nonatomic, strong) UIImageView *zoomIcon;
@property (nonatomic, strong) UILabel *hudLabel, *toast;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UILabel *> *valueLabels;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSDateFormatter *clockFormat;
@property (nonatomic) CGPoint dockFraction;
@property (nonatomic) CGFloat strength;
@property (nonatomic) BOOL zoomed;
@property (nonatomic) uint64_t lastFrames;
@property (nonatomic) CFTimeInterval lastTime;
@property (nonatomic) double fps;
@end

@implementation AEZController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.valueLabels = [NSMutableDictionary new];
    self.clockFormat = [NSDateFormatter new];
    self.clockFormat.dateFormat = @"HH:mm";
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;

    id savedStrength = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSetKey][@"strength"];
    self.strength = savedStrength ? aez_clamp([savedStrength doubleValue], 1.25, 8) : self.config.strength;
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kPosKey];
    self.dockFraction = (saved.count == 2) ? CGPointMake([saved[0] doubleValue], [saved[1] doubleValue]) : CGPointMake(0.93, 0.32);

    [self buildHUD];
    [self buildDock];
    [self buildPanel];

    self.lastTime = CACurrentMediaTime();
    self.lastFrames = __atomic_load_n(&gFrames, __ATOMIC_RELAXED);
    self.timer = [NSTimer timerWithTimeInterval:0.5 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self applyTheme];
}

#pragma mark Dock (zoom + panel buttons)

- (UIView *)circleButtonWithSymbol:(NSString *)name icon:(UIImageView **)iconOut label:(NSString *)label {
    CGFloat s = self.config.buttonSize;
    UIView *b = [[UIView alloc] initWithFrame:CGRectMake(0, 0, s, s)];
    b.layer.cornerRadius = s / 2;
    b.layer.borderWidth = 1.5;
    b.backgroundColor = aez_dark(0.82);
    b.isAccessibilityElement = YES;
    b.accessibilityLabel = label;
    b.accessibilityTraits = UIAccessibilityTraitButton;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:s * 0.42 weight:UIImageSymbolWeightSemibold];
    UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:name withConfiguration:cfg]];
    iv.tintColor = UIColor.whiteColor;
    iv.frame = b.bounds;
    iv.contentMode = UIViewContentModeCenter;
    [b addSubview:iv];
    if (iconOut) *iconOut = iv;
    return b;
}

- (void)buildDock {
    CGFloat s = self.config.buttonSize;
    self.dock = [[UIView alloc] initWithFrame:CGRectMake(0, 0, s, s * 2 + 8)];
    self.dock.alpha = self.config.opacity;
    UIImageView *zi = nil;
    self.zoomBtn = [self circleButtonWithSymbol:@"plus.magnifyingglass" icon:&zi label:@"AETHER zoom"];
    self.zoomIcon = zi;
    self.menuBtn = [self circleButtonWithSymbol:@"slider.horizontal.3" icon:nil label:@"AETHER client panel"];
    [self.dock addSubview:self.zoomBtn];
    [self.dock addSubview:self.menuBtn];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dockPanned:)];
    [self.dock addGestureRecognizer:pan];
    UITapGestureRecognizer *zt = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(zoomTapped)];
    UITapGestureRecognizer *mt = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(menuTapped)];
    [zt requireGestureRecognizerToFail:pan];
    [mt requireGestureRecognizerToFail:pan];
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(zoomHeld:)];
    hold.minimumPressDuration = 0.6;
    [self.zoomBtn addGestureRecognizer:zt];
    [self.zoomBtn addGestureRecognizer:hold];
    [self.menuBtn addGestureRecognizer:mt];
    [self.view addSubview:self.dock];
}

- (void)layoutDock {
    CGFloat s = self.config.buttonSize;
    BOOL zoomOn = [aez_get(@"zoomButton") boolValue];
    self.zoomBtn.hidden = !zoomOn;
    self.zoomBtn.frame = CGRectMake(0, 0, s, s);
    self.menuBtn.frame = CGRectMake(0, zoomOn ? s + 8 : 0, s, s);
    self.dock.bounds = CGRectMake(0, 0, s, zoomOn ? s * 2 + 8 : s);
    CGRect r = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGFloat hw = s / 2, hh = self.dock.bounds.size.height / 2;
    CGFloat x = r.origin.x + self.dockFraction.x * r.size.width;
    CGFloat y = r.origin.y + self.dockFraction.y * r.size.height;
    self.dock.center = CGPointMake(aez_clamp(x, r.origin.x + hw, r.origin.x + r.size.width - hw),
                                   aez_clamp(y, r.origin.y + hh, r.origin.y + r.size.height - hh));
}

- (void)dockPanned:(UIPanGestureRecognizer *)g {
    CGPoint d = [g translationInView:self.view];
    [g setTranslation:CGPointMake(0, 0) inView:self.view];
    CGRect r = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGFloat hw = self.dock.bounds.size.width / 2, hh = self.dock.bounds.size.height / 2;
    CGPoint c = CGPointMake(self.dock.center.x + d.x, self.dock.center.y + d.y);
    c.x = aez_clamp(c.x, r.origin.x + hw, r.origin.x + r.size.width - hw);
    c.y = aez_clamp(c.y, r.origin.y + hh, r.origin.y + r.size.height - hh);
    self.dock.center = c;
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        self.dockFraction = CGPointMake((c.x - r.origin.x) / r.size.width, (c.y - r.origin.y) / r.size.height);
        [[NSUserDefaults standardUserDefaults] setObject:@[@(self.dockFraction.x), @(self.dockFraction.y)] forKey:kPosKey];
    }
}

#pragma mark Zoom

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
    CGAffineTransform t = self.zoomed ? ((CGAffineTransform){self.strength, 0, 0, self.strength, 0, 0}) : ((CGAffineTransform){1, 0, 0, 1, 0, 0});
    void (^change)(void) = ^{ target.transform = t; };
    if (self.config.smooth) {
        [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:change completion:nil];
    } else { change(); }
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:self.config.buttonSize * 0.42 weight:UIImageSymbolWeightSemibold];
    self.zoomIcon.image = [UIImage systemImageNamed:(self.zoomed ? @"minus.magnifyingglass" : @"plus.magnifyingglass") withConfiguration:cfg];
    self.zoomBtn.backgroundColor = self.zoomed ? [aez_accent() colorWithAlphaComponent:0.9] : aez_dark(0.82);
}

- (void)zoomTapped {
    self.zoomed = !self.zoomed;
    [self applyZoom];
    [self showToast:self.zoomed ? [NSString stringWithFormat:@"%.1fx", self.strength] : @"1x"];
}

- (void)zoomHeld:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    CGFloat next = floor(self.strength) + 1;
    self.strength = next > 8 ? 2 : next;
    aez_set(@"strength", @(self.strength));
    if (self.zoomed) [self applyZoom];
    [self refreshValueLabels];
    [self showToast:[NSString stringWithFormat:@"Zoom strength %.0fx", self.strength]];
}

#pragma mark HUD

- (void)buildHUD {
    self.hud = [UIView new];
    self.hud.layer.cornerRadius = 8;
    self.hud.layer.borderWidth = 1;
    self.hud.backgroundColor = aez_dark(0.55);
    self.hudLabel = [UILabel new];
    self.hudLabel.numberOfLines = 0;
    [self.hud addSubview:self.hudLabel];
    [self.hud addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(hudPanned:)]];
    [self.view addSubview:self.hud];
}

- (NSString *)hudText {
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    if ([aez_get(@"fps") boolValue]) {
        BOOL seen = __atomic_load_n(&gFrames, __ATOMIC_RELAXED) > 0;
        [lines addObject:seen ? [NSString stringWithFormat:@"FPS  %.0f", self.fps] : @"FPS  n/a"];
    }
    if ([aez_get(@"cps") boolValue]) {
        CFTimeInterval now = CACurrentMediaTime();
        while (gTaps.count && now - gTaps.firstObject.doubleValue > 1.0) [gTaps removeObjectAtIndex:0];
        [lines addObject:[NSString stringWithFormat:@"CPS  %lu", (unsigned long)gTaps.count]];
    }
    if ([aez_get(@"clock") boolValue]) [lines addObject:[@"TIME " stringByAppendingString:[self.clockFormat stringFromDate:[NSDate date]]]];
    if ([aez_get(@"battery") boolValue]) {
        float lvl = UIDevice.currentDevice.batteryLevel;
        BOOL charging = UIDevice.currentDevice.batteryState == UIDeviceBatteryStateCharging;
        [lines addObject:lvl < 0 ? @"BAT  n/a" : [NSString stringWithFormat:@"BAT  %d%%%@", (int)lroundf(lvl * 100), charging ? @"+" : @""]];
    }
    if ([aez_get(@"memory") boolValue]) [lines addObject:[NSString stringWithFormat:@"MEM  %.0f MB", aez_memory_mb()]];
    if ([aez_get(@"thermal") boolValue]) {
        NSString *t = @"nominal";
        switch (NSProcessInfo.processInfo.thermalState) {
            case NSProcessInfoThermalStateFair: t = @"fair"; break;
            case NSProcessInfoThermalStateSerious: t = @"serious"; break;
            case NSProcessInfoThermalStateCritical: t = @"critical"; break;
            default: break;
        }
        [lines addObject:[@"HEAT " stringByAppendingString:t]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (void)refreshHUD {
    NSString *text = [self hudText];
    self.hud.hidden = text.length == 0;
    if (self.hud.hidden) return;
    CGFloat scale = [aez_get(@"hudScale") doubleValue];
    self.hudLabel.font = [UIFont monospacedSystemFontOfSize:12 * scale weight:UIFontWeightSemibold];
    self.hudLabel.text = text;
    CGSize sz = [self.hudLabel sizeThatFits:((CGSize){260, CGFLOAT_MAX})];
    self.hudLabel.frame = CGRectMake(8, 6, ceil(sz.width), ceil(sz.height));
    CGRect r = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGSize hs = (CGSize){ceil(sz.width) + 16, ceil(sz.height) + 12};
    CGFloat x = r.origin.x + [aez_get(@"hudX") doubleValue] * r.size.width;
    CGFloat y = r.origin.y + [aez_get(@"hudY") doubleValue] * r.size.height;
    x = aez_clamp(x, r.origin.x, MAX(r.origin.x, r.origin.x + r.size.width - hs.width));
    y = aez_clamp(y, r.origin.y, MAX(r.origin.y, r.origin.y + r.size.height - hs.height));
    self.hud.frame = CGRectMake(x, y, hs.width, hs.height);
    self.hud.alpha = [aez_get(@"hudOpacity") doubleValue];
}

- (void)hudPanned:(UIPanGestureRecognizer *)g {
    CGPoint d = [g translationInView:self.view];
    [g setTranslation:CGPointMake(0, 0) inView:self.view];
    CGRect r = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGRect f = self.hud.frame;
    f.origin.x += d.x;
    f.origin.y += d.y;
    f.origin.x = aez_clamp(f.origin.x, r.origin.x, MAX(r.origin.x, r.origin.x + r.size.width - f.size.width));
    f.origin.y = aez_clamp(f.origin.y, r.origin.y, MAX(r.origin.y, r.origin.y + r.size.height - f.size.height));
    self.hud.frame = f;
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        aez_set(@"hudX", @((f.origin.x - r.origin.x) / r.size.width));
        aez_set(@"hudY", @((f.origin.y - r.origin.y) / r.size.height));
    }
}

- (void)tick {
    uint64_t f = __atomic_load_n(&gFrames, __ATOMIC_RELAXED);
    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval dt = now - self.lastTime;
    if (dt > 0) self.fps = (double)(f - self.lastFrames) / dt;
    self.lastFrames = f;
    self.lastTime = now;
    [self refreshHUD];
}

#pragma mark Panel

- (void)buildPanel {
    self.panel = [UIView new];
    self.panel.hidden = YES;
    self.panel.backgroundColor = aez_dark(0.95);
    self.panel.layer.cornerRadius = 18;
    self.panel.layer.borderWidth = 1.5;
    self.panel.clipsToBounds = YES;

    UILabel *title = [UILabel new];
    title.text = @"AETHER CLIENT";
    title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightHeavy];
    title.textColor = UIColor.whiteColor;
    title.frame = CGRectMake(16, 0, 200, 44);
    title.tag = 901;
    [self.panel addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    close.tintColor = [UIColor colorWithWhite:0.7 alpha:1];
    close.tag = 902;
    [close addTarget:self action:@selector(menuTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:close];

    self.scroll = [UIScrollView new];
    self.scroll.alwaysBounceVertical = YES;
    [self.panel addSubview:self.scroll];

    self.stack = [UIStackView new];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 12;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scroll addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.stack.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor constant:6],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor constant:-14],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.leadingAnchor constant:16],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [self.stack.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor constant:-32],
    ]];

    [self addSection:@"HUD modules"];
    [self addSwitch:@"FPS (game frames)" key:@"fps"];
    [self addSwitch:@"CPS (your taps)" key:@"cps"];
    [self addSwitch:@"Clock" key:@"clock"];
    [self addSwitch:@"Battery" key:@"battery"];
    [self addSwitch:@"Memory" key:@"memory"];
    [self addSwitch:@"Heat state" key:@"thermal"];
    [self addSection:@"Look"];
    [self addSliderTitle:@"HUD size" key:@"hudScale" min:0.7 max:1.8 step:0.1 format:@"%.1fx"];
    [self addSliderTitle:@"HUD opacity" key:@"hudOpacity" min:0.3 max:1.0 step:0.05 format:@"%.2f"];
    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"Red", @"White", @"Cyan", @"Green"]];
    seg.selectedSegmentIndex = [aez_get(@"accent") integerValue];
    [seg addTarget:self action:@selector(accentChanged:) forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:seg];
    [self addSection:@"Zoom"];
    [self addSwitch:@"Show zoom button" key:@"zoomButton"];
    [self addSliderTitle:@"Zoom strength" key:@"strength" min:1.5 max:8 step:0.5 format:@"%.1fx"];

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [reset setTitle:@"Reset positions" forState:UIControlStateNormal];
    reset.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [reset addTarget:self action:@selector(resetPositions) forControlEvents:UIControlEventTouchUpInside];
    [self.stack addArrangedSubview:reset];
    [self.view addSubview:self.panel];
}

- (void)addSection:(NSString *)text {
    UILabel *l = [UILabel new];
    l.text = [text uppercaseString];
    l.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    l.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    [self.stack addArrangedSubview:l];
}

- (void)addSwitch:(NSString *)title key:(NSString *)key {
    UILabel *l = [UILabel new];
    l.text = title;
    l.font = [UIFont systemFontOfSize:15];
    l.textColor = UIColor.whiteColor;
    UISwitch *sw = [UISwitch new];
    sw.on = [aez_get(key) boolValue];
    sw.accessibilityIdentifier = key;
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[l, sw]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    [self.stack addArrangedSubview:row];
}

- (void)addSliderTitle:(NSString *)title key:(NSString *)key min:(float)mn max:(float)mx step:(float)step format:(NSString *)fmt {
    UILabel *l = [UILabel new];
    l.text = title;
    l.font = [UIFont systemFontOfSize:14];
    l.textColor = UIColor.whiteColor;
    UILabel *v = [UILabel new];
    v.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    v.textColor = [UIColor colorWithWhite:0.7 alpha:1];
    v.textAlignment = NSTextAlignmentRight;
    v.accessibilityIdentifier = [NSString stringWithFormat:@"%@|%@", key, fmt];
    self.valueLabels[key] = v;
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[l, v]];
    UISlider *s = [UISlider new];
    s.minimumValue = mn; s.maximumValue = mx;
    s.accessibilityIdentifier = [NSString stringWithFormat:@"%@|%g", key, step];
    [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    double cur = [key isEqualToString:@"strength"] ? self.strength : [aez_get(key) doubleValue];
    s.value = (float)cur;
    v.text = [NSString stringWithFormat:fmt, cur];
    UIStackView *col = [[UIStackView alloc] initWithArrangedSubviews:@[top, s]];
    col.axis = UILayoutConstraintAxisVertical;
    col.spacing = 2;
    [self.stack addArrangedSubview:col];
}

- (void)refreshValueLabels {
    for (NSString *key in self.valueLabels) {
        UILabel *v = self.valueLabels[key];
        NSString *fmt = [v.accessibilityIdentifier componentsSeparatedByString:@"|"].lastObject;
        double cur = [key isEqualToString:@"strength"] ? self.strength : [aez_get(key) doubleValue];
        v.text = [NSString stringWithFormat:fmt, cur];
    }
    [self syncStrengthSlider];
}

- (void)syncStrengthSlider {
    for (UIView *sv in [self allSubviewsOf:self.stack]) {
        if ([sv isKindOfClass:[UISlider class]] && [[(UISlider *)sv accessibilityIdentifier] hasPrefix:@"strength|"]) ((UISlider *)sv).value = (float)self.strength;
    }
}

- (NSArray<UIView *> *)allSubviewsOf:(UIView *)root {
    NSMutableArray *out = [NSMutableArray new];
    for (UIView *v in root.subviews) { [out addObject:v]; [out addObjectsFromArray:[self allSubviewsOf:v]]; }
    return out;
}

- (void)switchChanged:(UISwitch *)sw {
    NSString *key = sw.accessibilityIdentifier;
    aez_set(key, @(sw.on));
    if ([key isEqualToString:@"zoomButton"]) {
        if (!sw.on && self.zoomed) { self.zoomed = NO; [self applyZoom]; }
        [self layoutDock];
    }
    [self refreshHUD];
}

- (void)sliderChanged:(UISlider *)s {
    NSArray *parts = [s.accessibilityIdentifier componentsSeparatedByString:@"|"];
    NSString *key = parts[0];
    double step = [parts[1] doubleValue];
    double val = step > 0 ? round(s.value / step) * step : s.value;
    if ([key isEqualToString:@"strength"]) {
        self.strength = val;
        aez_set(@"strength", @(val));
        if (self.zoomed) [self applyZoom];
    } else {
        aez_set(key, @(val));
    }
    UILabel *v = self.valueLabels[key];
    NSString *fmt = [v.accessibilityIdentifier componentsSeparatedByString:@"|"].lastObject;
    v.text = [NSString stringWithFormat:fmt, val];
    [self refreshHUD];
}

- (void)accentChanged:(UISegmentedControl *)seg {
    aez_set(@"accent", @(seg.selectedSegmentIndex));
    [self applyTheme];
    if (self.zoomed) [self applyZoom];
}

- (void)resetPositions {
    aez_set(@"hudX", aez_defaults()[@"hudX"]);
    aez_set(@"hudY", aez_defaults()[@"hudY"]);
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPosKey];
    self.dockFraction = CGPointMake(0.93, 0.32);
    [self layoutDock];
    [self refreshHUD];
    [self showToast:@"Positions reset"];
}

- (void)menuTapped {
    BOOL show = self.panel.hidden;
    self.panel.hidden = !show;
    [self.view bringSubviewToFront:self.panel];
    [self.view setNeedsLayout];
}

- (void)applyTheme {
    UIColor *a = aez_accent();
    self.zoomBtn.layer.borderColor = a.CGColor;
    self.menuBtn.layer.borderColor = a.CGColor;
    self.hud.layer.borderColor = [a colorWithAlphaComponent:0.8].CGColor;
    self.hudLabel.textColor = a;
    self.panel.layer.borderColor = a.CGColor;
    for (UIView *v in [self allSubviewsOf:self.stack]) {
        if ([v isKindOfClass:[UISwitch class]]) ((UISwitch *)v).onTintColor = a;
        if ([v isKindOfClass:[UISlider class]]) ((UISlider *)v).minimumTrackTintColor = a;
        if ([v isKindOfClass:[UISegmentedControl class]]) { ((UISegmentedControl *)v).selectedSegmentTintColor = a; }
        if ([v isKindOfClass:[UIButton class]]) ((UIButton *)v).tintColor = a;
    }
}

#pragma mark Layout and toast

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutDock];
    CGRect r = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGFloat w = MIN(320, r.size.width - 24), h = MIN(460, r.size.height - 16);
    self.panel.frame = CGRectMake(r.origin.x + (r.size.width - w) / 2, r.origin.y + (r.size.height - h) / 2, w, h);
    [self.panel viewWithTag:902].frame = CGRectMake(w - 48, 0, 44, 44);
    self.scroll.frame = CGRectMake(0, 44, w, h - 44);
    [self refreshHUD];
}

- (void)showToast:(NSString *)text {
    if (!self.toast) {
        UILabel *t = [UILabel new];
        t.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        t.textColor = UIColor.whiteColor;
        t.textAlignment = NSTextAlignmentCenter;
        t.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
        t.layer.cornerRadius = 10;
        t.layer.masksToBounds = YES;
        t.alpha = 0;
        self.toast = t;
        [self.view addSubview:t];
    }
    self.toast.text = text;
    [self.toast sizeToFit];
    CGRect f = self.toast.frame; f.size.width += 20; f.size.height += 10;
    f.origin.x = aez_clamp(self.dock.center.x - f.size.width / 2, 4, self.view.bounds.size.width - f.size.width - 4);
    f.origin.y = self.dock.frame.origin.y + self.dock.frame.size.height + 6;
    self.toast.frame = f;
    [self.toast.layer removeAllAnimations];
    self.toast.alpha = 1;
    [UIView animateWithDuration:0.3 delay:1.0 options:0 animations:^{ self.toast.alpha = 0; } completion:nil];
}

- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
@end

#pragma mark - Install

@interface AEZInstaller : NSObject
+ (void)install;
@end
@implementation AEZInstaller
+ (void)install {
    if (gOwnWindow) return;
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
    gOwnWindow = w;
}
@end

__attribute__((constructor))
static void aether_client_entry(void) {
    aez_install_probes();
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [AEZInstaller install]; });
    }];
}
