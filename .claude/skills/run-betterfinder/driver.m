// In-process test driver for BetterFinder. drive.sh compiles this to a dylib and
// injects it with DYLD_INSERT_LIBRARIES. It reads a script of steps, runs them
// strictly in order on the main thread, and writes results to <out>/driver.log.
//
// Working from inside the process is deliberate: synthetic NSEvents and snapshots
// of the app's own window need no Accessibility or Screen Recording permission.
// See SKILL.md for the step reference.
#import <Cocoa/Cocoa.h>

static NSString *outDir;
static NSFileHandle *logHandle;
static CFAbsoluteTime startTime;
static NSArray<NSString *> *steps;
static NSUInteger stepIndex;
static NSString *currentStep = @"(startup)";
static NSMenu *openMenu;

static void runNextStep(void);

static void logLine(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void logLine(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"[%7.3f] %@\n", CFAbsoluteTimeGetCurrent() - startTime, message];
    [logHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
}

// dispatch_after coalesces timers and fires late, so use a strict one-shot source.
static void after(double seconds, dispatch_block_t block) {
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, DISPATCH_TIMER_STRICT, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), DISPATCH_TIME_FOREVER, 0);
    dispatch_source_set_event_handler(timer, ^{
        dispatch_source_cancel(timer);
        block();
    });
    dispatch_resume(timer);
}

static NSWindow *mainWindow(void) {
    for (NSWindow *window in NSApp.windows) {
        if (window.isVisible && window.contentView && window.frame.size.width > 300) return window;
    }
    return nil;
}

static void quitNow(int code) {
    logLine(@"quit");
    [logHandle synchronizeFile];
    _exit(code);
}

// MARK: - Snapshots

static NSBitmapImageRep *captureWindow(NSWindow *window) {
    NSView *view = window.contentView;
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    return rep;
}

// The capture has an alpha channel, and viewers show translucent pixels misleadingly
// (a 20% tint can look solid), so the saved PNG is flattened onto white.
static void snap(NSString *name) {
    NSWindow *window = mainWindow();
    NSBitmapImageRep *rep = captureWindow(window);
    NSInteger width = rep.pixelsWide, height = rep.pixelsHigh;
    NSBitmapImageRep *flat = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height bitsPerSample:8
                 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
                     bytesPerRow:0 bitsPerPixel:0];
    NSRect rect = NSMakeRect(0, 0, width, height);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:flat];
    [NSColor.whiteColor setFill];
    NSRectFill(rect);
    [rep drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:NO hints:nil];
    [NSGraphicsContext restoreGraphicsState];
    NSData *png = [flat representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [png writeToFile:[outDir stringByAppendingPathComponent:[name stringByAppendingString:@".png"]] atomically:YES];
    logLine(@"snap %@.png (%ldx%ld px)", name, (long)width, (long)height);
}

// Logs unflattened RGBA, so "nothing drawn here" reads as alpha 0. getPixel returns
// premultiplied values, so undo that to make colors comparable with the source color.
static void pixel(CGFloat x, CGFloat y, NSString *label) {
    NSWindow *window = mainWindow();
    NSBitmapImageRep *rep = captureWindow(window);
    CGFloat scale = rep.pixelsWide / window.contentView.bounds.size.width;
    NSUInteger rgba[5] = {0, 0, 0, 255, 0};
    [rep getPixel:rgba atX:(NSInteger)(x * scale) y:(NSInteger)(y * scale)];
    NSUInteger alpha = rgba[3];
    for (int channel = 0; channel < 3 && alpha > 0; channel++) {
        rgba[channel] = MIN(255, (rgba[channel] * 255 + alpha / 2) / alpha);
    }
    logLine(@"pixel %@ (%.0f,%.0f) rgba=(%lu,%lu,%lu,%lu)", label, x, y,
            (unsigned long)rgba[0], (unsigned long)rgba[1], (unsigned long)rgba[2], (unsigned long)alpha);
}

// MARK: - Input

static NSEvent *mouseEvent(NSEventType type, NSPoint point, NSWindow *window, NSInteger clicks, NSEventModifierFlags flags) {
    BOOL down = type == NSEventTypeLeftMouseDown || type == NSEventTypeRightMouseDown;
    return [NSEvent mouseEventWithType:type location:point modifierFlags:flags
                             timestamp:NSProcessInfo.processInfo.systemUptime
                          windowNumber:window.windowNumber context:nil eventNumber:0
                            clickCount:clicks pressure:down ? 1.0 : 0.0];
}

// Events must go through postEvent. sendEvent bypasses the queue, so NSTableView's
// mouse tracking loop never sees the mouse-up and the app hangs.
static void postClick(CGFloat x, CGFloat y, NSEventType downType, NSEventType upType, NSInteger clicks, NSEventModifierFlags flags) {
    NSWindow *window = mainWindow();
    NSPoint point = NSMakePoint(x, window.contentView.bounds.size.height - y);
    if (!window.isKeyWindow || !NSApp.isActive) {
        logLine(@"WARNING: window not key/active (key=%d active=%d); result may be invalid", window.isKeyWindow, NSApp.isActive);
    }
    // Hold each press like a real click does: .onTapGesture can miss a zero-length one.
    const double hold = 0.06;
    for (NSInteger count = 1; count <= clicks; count++) {
        double start = (count - 1) * 2 * hold;
        after(start, ^{ [NSApp postEvent:mouseEvent(downType, point, window, count, flags) atStart:NO]; });
        after(start + hold, ^{ [NSApp postEvent:mouseEvent(upType, point, window, count, flags) atStart:NO]; });
    }
}

// Tracking areas only react to the real cursor, so hand the views under the point
// the same callbacks they would get. The cursor itself doesn't move. List rows have
// their own hosting views inside the table, so the window's root view isn't enough.
static void moveMouse(CGFloat x, CGFloat y) {
    NSWindow *window = mainWindow();
    NSPoint point = NSMakePoint(x, window.contentView.bounds.size.height - y);
    NSEvent *event = mouseEvent(NSEventTypeMouseMoved, point, window, 0, 0);
    for (NSView *view = [window.contentView.superview hitTest:point]; view; view = view.superview) {
        if ([NSStringFromClass(view.class) containsString:@"Hosting"]) {
            [view mouseEntered:event];
            [view mouseMoved:event];
        }
        if (view == window.contentView) break;
    }
}

static NSEventModifierFlags parseModifiers(NSArray<NSString *> *names) {
    NSEventModifierFlags flags = 0;
    for (NSString *name in names) {
        if ([name isEqual:@"cmd"]) flags |= NSEventModifierFlagCommand;
        else if ([name isEqual:@"shift"]) flags |= NSEventModifierFlagShift;
        else if ([name isEqual:@"opt"]) flags |= NSEventModifierFlagOption;
        else if ([name isEqual:@"ctrl"]) flags |= NSEventModifierFlagControl;
    }
    return flags;
}

static void postKey(NSString *name, NSEventModifierFlags flags) {
    NSDictionary<NSString *, NSArray *> *named = @{
        @"return": @[@"\r", @36], @"escape": @[@"\x1b", @53], @"tab": @[@"\t", @48], @"delete": @[@"\x7f", @51],
        @"left": @[[NSString stringWithFormat:@"%C", (unichar)NSLeftArrowFunctionKey], @123],
        @"right": @[[NSString stringWithFormat:@"%C", (unichar)NSRightArrowFunctionKey], @124],
        @"down": @[[NSString stringWithFormat:@"%C", (unichar)NSDownArrowFunctionKey], @125],
        @"up": @[[NSString stringWithFormat:@"%C", (unichar)NSUpArrowFunctionKey], @126],
    };
    NSString *characters = named[name] ? named[name][0] : name;
    unsigned short keyCode = named[name] ? [named[name][1] unsignedShortValue] : 0;
    NSWindow *window = mainWindow();
    for (NSNumber *type in @[@(NSEventTypeKeyDown), @(NSEventTypeKeyUp)]) {
        [NSApp postEvent:[NSEvent keyEventWithType:type.unsignedIntegerValue location:NSZeroPoint modifierFlags:flags
                                         timestamp:NSProcessInfo.processInfo.systemUptime
                                      windowNumber:window.windowNumber context:nil characters:characters
                       charactersIgnoringModifiers:characters isARepeat:NO keyCode:keyCode] atStart:NO];
    }
}

// MARK: - Context menus

static void logMenu(void) {
    if (!openMenu) { logLine(@"menu: no context menu is open"); return; }
    NSMutableArray *titles = [NSMutableArray array];
    for (NSMenuItem *item in openMenu.itemArray) {
        if (!item.isSeparatorItem) [titles addObject:item.title];
    }
    logLine(@"menu: %@", [titles componentsJoinedByString:@" | "]);
}

static void pickMenuItem(NSString *title) {
    NSMenuItem *item = [openMenu itemWithTitle:title];
    if (!item) { logLine(@"pick: no open menu item titled \"%@\"", title); return; }
    // Same order as a real selection: the menu closes first, then the action fires.
    [openMenu cancelTrackingWithoutAnimation];
    after(0.1, ^{
        [NSApp sendAction:item.action to:item.target from:item];
        logLine(@"pick: %@", title);
    });
}

// MARK: - Measurement

// A 2ms heartbeat on the main queue: the longest gap between ticks is the longest
// main-thread stall. It runs alongside later steps, so it has to start before the
// action it measures: a click's work is already over by the time the next step runs.
static void measureStall(double seconds) {
    __block CFAbsoluteTime last = CFAbsoluteTimeGetCurrent();
    CFAbsoluteTime begin = last;
    __block double longest = 0;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, DISPATCH_TIMER_STRICT, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 2 * NSEC_PER_MSEC, 0);
    dispatch_source_set_event_handler(timer, ^{
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        longest = MAX(longest, now - last);
        last = now;
        if (now - begin >= seconds) {
            dispatch_source_cancel(timer);
            logLine(@"stall: longest %.1f ms", longest * 1000);
        }
    });
    dispatch_resume(timer);
}

// MARK: - Script runner

static void runStep(NSString *line) {
    NSArray<NSString *> *parts = [line componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString *command = parts[0];
    NSArray<NSString *> *args = [parts subarrayWithRange:NSMakeRange(1, parts.count - 1)];
    NSString *rest = [args componentsJoinedByString:@" "];

    if ([command isEqual:@"wait"]) {
        after(args[0].doubleValue, ^{ runNextStep(); });
        return;
    }

    if ([command isEqual:@"stall"]) {
        measureStall(args[0].doubleValue);
    } else if ([command isEqual:@"move"]) {
        moveMouse(args[0].doubleValue, args[1].doubleValue);
        logLine(@"%@", line);
    } else if ([command isEqual:@"click"] || [command isEqual:@"dclick"]) {
        NSEventModifierFlags flags = parseModifiers([args subarrayWithRange:NSMakeRange(2, args.count - 2)]);
        NSInteger clicks = [command isEqual:@"dclick"] ? 2 : 1;
        postClick(args[0].doubleValue, args[1].doubleValue, NSEventTypeLeftMouseDown, NSEventTypeLeftMouseUp, clicks, flags);
        logLine(@"%@", line);
    } else if ([command isEqual:@"rclick"]) {
        // SwiftUI ignores a synthetic right mouse-down; Ctrl+click opens the real menu.
        postClick(args[0].doubleValue, args[1].doubleValue, NSEventTypeLeftMouseDown, NSEventTypeLeftMouseUp, 1, NSEventModifierFlagControl);
        logLine(@"%@", line);
    } else if ([command isEqual:@"key"]) {
        postKey(args[0], parseModifiers([args subarrayWithRange:NSMakeRange(1, args.count - 1)]));
        logLine(@"%@", line);
    } else if ([command isEqual:@"type"]) {
        // insertText: "succeeds" on plenty of non-text responders, so check focus first.
        NSResponder *responder = mainWindow().firstResponder;
        if ([responder isKindOfClass:NSTextView.class]) {
            [(NSTextView *)responder insertText:rest replacementRange:((NSTextView *)responder).selectedRange];
            logLine(@"type \"%@\"", rest);
        } else {
            logLine(@"WARNING: type dropped \"%@\", focus is on %@", rest, NSStringFromClass(responder.class));
        }
    } else if ([command isEqual:@"menu"]) {
        logMenu();
    } else if ([command isEqual:@"pick"]) {
        pickMenuItem(rest);
    } else if ([command isEqual:@"windows"]) {
        for (NSWindow *window in NSApp.windows) {
            logLine(@"window %@ visible=%d level=%ld %.0fx%.0f", NSStringFromClass(window.class), window.isVisible,
                    (long)window.level, window.frame.size.width, window.frame.size.height);
        }
        logLine(@"runloop mode: %@", NSRunLoop.currentRunLoop.currentMode);
    } else if ([command isEqual:@"snap"]) {
        snap(args[0]);
    } else if ([command isEqual:@"pixel"]) {
        pixel(args[0].doubleValue, args[1].doubleValue, args.count > 2 ? args[2] : @"-");
    } else if ([command isEqual:@"touch"]) {
        // The only step that writes directly, so it's confined to generated fixtures.
        NSString *folder = [NSString stringWithUTF8String:getenv("DRIVER_FOLDER")];
        NSString *fixtures = [NSString stringWithUTF8String:getenv("DRIVER_FIXTURES")];
        if (![folder hasPrefix:fixtures]) {
            logLine(@"ERROR: touch refused, %@ is not a fixture folder", folder);
            quitNow(2);
        }
        [NSFileManager.defaultManager createFileAtPath:[folder stringByAppendingPathComponent:rest] contents:NSData.data attributes:nil];
        logLine(@"touch %@", rest);
    } else if ([command isEqual:@"quit"]) {
        quitNow(0);
    } else {
        logLine(@"ERROR: unknown step: %@", line);
        quitNow(2);
    }
    runNextStep();
}

static void runNextStep(void) {
    // Hop through the queue so events posted by the previous step get delivered.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (stepIndex >= steps.count) quitNow(0);
        currentStep = steps[stepIndex++];
        runStep(currentStep);
    });
}

// Activation is asynchronous and can lose a race with whatever app had focus, so
// keep asking. Failing here only warns: drive.sh then reports the run as invalid.
static void activateThenStart(NSWindow *window, int attempts) {
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
    if ((NSApp.isActive && window.isKeyWindow) || attempts == 0) {
        logLine(@"window ready: %.0fx%.0f points", window.contentView.bounds.size.width, window.contentView.bounds.size.height);
        if (!NSApp.isActive || !window.isKeyWindow) logLine(@"WARNING: could not take focus");
        runNextStep();
    } else {
        after(0.1, ^{ activateThenStart(window, attempts - 1); });
    }
}

static void waitForWindowThenStart(int attempts) {
    NSWindow *window = mainWindow();
    if (window) {
        activateThenStart(window, 50);
    } else if (attempts > 0) {
        after(0.1, ^{ waitForWindowThenStart(attempts - 1); });
    } else {
        logLine(@"ERROR: no window appeared");
        quitNow(3);
    }
}

__attribute__((constructor)) static void start(void) {
    const char *script = getenv("DRIVER_SCRIPT"), *out = getenv("DRIVER_OUT"), *timeout = getenv("DRIVER_TIMEOUT");
    if (!script || !out) return;
    unsetenv("DYLD_INSERT_LIBRARIES");

    outDir = [NSString stringWithUTF8String:out];
    NSString *logPath = [outDir stringByAppendingPathComponent:@"driver.log"];
    [NSFileManager.defaultManager createFileAtPath:logPath contents:nil attributes:nil];
    logHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    startTime = CFAbsoluteTimeGetCurrent();

    NSString *text = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:script] encoding:NSUTF8StringEncoding error:nil];
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *raw in [text componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (line.length && ![line hasPrefix:@"#"]) [lines addObject:line];
    }
    steps = lines;

    [NSNotificationCenter.defaultCenter addObserverForName:NSMenuDidBeginTrackingNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) { openMenu = note.object; }];
    [NSNotificationCenter.defaultCenter addObserverForName:NSMenuDidEndTrackingNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) { openMenu = nil; }];

    // Says who took focus, which explains an invalid run.
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidActivateApplicationNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
            logLine(@"focus: %@ became active", app.localizedName);
        }];

    // Runs off the main thread, so it still fires when a step wedges the app.
    double limit = timeout ? atof(timeout) : 60;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(limit * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        logLine(@"WATCHDOG: exceeded %.0fs, stuck at step: %@", limit, currentStep);
        [logHandle synchronizeFile];
        _exit(124);
    });

    dispatch_async(dispatch_get_main_queue(), ^{ waitForWindowThenStart(150); });
}
