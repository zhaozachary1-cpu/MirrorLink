// Copyright MirrorLink contributors. SPDX-License-Identifier: Apache-2.0
// Compiled into our scrcpy client. Uses its actual Cocoa window, without
// Accessibility access, window tracking, injection, or video overlays.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <unistd.h>
#include "mirrorlink_toolbar.h"

@interface MLWindowToolbar : NSObject <NSToolbarDelegate>
@property(nonatomic, weak) NSWindow *window;
@property(nonatomic) NSDictionary *state;
@property(nonatomic) NSMutableDictionary<NSString *, NSButton *> *buttons;
@property(nonatomic) NSMutableDictionary<NSString *, NSToolbarItem *> *items;
@property(nonatomic) dispatch_source_t reader;
@property(nonatomic) int channel;
@property(nonatomic) BOOL closed;
@property(nonatomic) BOOL dialogOpen;
@property(nonatomic) NSPopover *result;
@property(nonatomic) id closeObserver;
@property(nonatomic) NSAlert *activeAlert;
@property(nonatomic, copy) void (^alertAnswer)(NSModalResponse);
- (void)send:(NSString *)action path:(NSString *)path;
- (void)receive;
- (void)invalidate;
@end

@implementation MLWindowToolbar
- (void)presentAlert:(NSAlert *)alert completion:(void (^)(NSModalResponse))completion {
    self.activeAlert = alert;
    self.alertAnswer = completion;
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
    // SDL owns the event loop, not NSApplication.run. Resolve button actions
    // directly instead of relying on AppKit's deferred modal completion cycle.
    for (NSUInteger index = 0; index < alert.buttons.count; index++) {
        NSButton *button = alert.buttons[index];
        button.target = self; button.action = @selector(alertPressed:);
        button.tag = NSAlertFirstButtonReturn + index;
    }
}
- (void)alertPressed:(NSButton *)button {
    NSAlert *alert = self.activeAlert;
    void (^answer)(NSModalResponse) = self.alertAnswer;
    self.alertAnswer = nil; self.activeAlert = nil;
    NSModalResponse response = button.tag;
    [self.window endSheet:alert.window returnCode:response];
    [alert.window orderOut:nil];
    if (answer && !self.closed) answer(response);
}
- (NSString *)text:(NSString *)key {
    id value = self.state[key];
    return [value isKindOfClass:NSString.class] ? value : @"";
}
- (BOOL)flag:(NSString *)key { return [self.state[key] isEqual:@YES]; }
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[@"home", @"drawer", @"screenshot", @"record", @"sendFile", @"installAPK", @"more"];
}
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return [self toolbarAllowedItemIdentifiers:toolbar];
}
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)inserted {
    NSDictionary *symbols = @{@"home": @"house", @"drawer": @"square.grid.3x3",
        @"screenshot": @"camera", @"record": @"record.circle", @"sendFile": @"paperplane",
        @"installAPK": @"shippingbox", @"more": @"ellipsis.circle"};
    NSButton *button = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:symbols[identifier]
        accessibilityDescription:nil] target:self action:@selector(pressed:)];
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.imagePosition = NSImageOnly;
    button.identifier = identifier;
    button.frame = NSMakeRect(0, 0, 32, 28);
    button.enabled = NO;
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.view = button;
    item.visibilityPriority = [identifier isEqualToString:@"more"] ? NSToolbarItemVisibilityPriorityLow : NSToolbarItemVisibilityPriorityHigh;
    self.buttons[identifier] = button;
    self.items[identifier] = item;
    return item;
}
- (void)update {
    for (NSString *key in self.buttons) {
        NSButton *button = self.buttons[key];
        NSString *title = [self text:[key stringByAppendingString:@"Title"]];
        button.toolTip = title;
        [button setAccessibilityLabel:title];
        self.items[key].label = title;
        self.items[key].paletteLabel = title;
        self.items[key].toolTip = title;
        BOOL enabled = [self flag:@"ready"] && !self.closed && !self.dialogOpen;
        if ([key isEqualToString:@"home"] || [key isEqualToString:@"drawer"] ||
            [key isEqualToString:@"sendFile"] || [key isEqualToString:@"installAPK"]) {
            enabled &= [self flag:@"controlAllowed"] && ![self flag:@"busy"];
        } else if ([key isEqualToString:@"screenshot"]) {
            enabled &= ![self flag:@"busy"];
        } else if ([key isEqualToString:@"record"]) {
            enabled = !self.closed && !self.dialogOpen && [self flag:@"recordAllowed"];
            button.image = [NSImage imageWithSystemSymbolName:[self flag:@"recording"] ? @"stop.circle.fill" : @"record.circle" accessibilityDescription:title];
            button.contentTintColor = [self flag:@"recording"] ? NSColor.systemRedColor : nil;
        } else if ([key isEqualToString:@"more"] && [self flag:@"busy"]) {
            button.image = [NSImage imageWithSystemSymbolName:@"hourglass" accessibilityDescription:title];
            button.toolTip = [self text:@"status"];
        } else if ([key isEqualToString:@"more"]) {
            button.image = [NSImage imageWithSystemSymbolName:@"ellipsis.circle" accessibilityDescription:title];
        }
        button.enabled = enabled;
    }
}
- (void)receive {
    char bytes[8192];
    ssize_t length;
    while ((length = recv(self.channel, bytes, sizeof(bytes), MSG_DONTWAIT)) > 0) {
        if (length >= sizeof(bytes)) continue;
        NSDictionary *message = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:bytes length:length] options:0 error:nil];
        if (![message isKindOfClass:NSDictionary.class] || ![message[@"type"] isEqual:@"state"]) continue;
        NSString *previous = [self text:@"resultID"];
        NSString *previousStatus = [self text:@"status"];
        BOOL wasBusy = [self flag:@"busy"];
        BOOL wasError = [self flag:@"isError"];
        self.state = message;
        [self update];
        NSString *current = [self text:@"resultID"];
        BOOL resultChanged = ![current isEqual:previous];
        BOOL statusChanged = resultChanged || wasBusy != [self flag:@"busy"] ||
            ![previousStatus isEqual:[self text:@"status"]] || wasError != [self flag:@"isError"];
        // Routine actions should leave the phone picture unobstructed. Progress
        // and results remain available in More; only a new failure opens it.
        BOOL newFailure = [self flag:@"isError"] && ![self flag:@"busy"] && (resultChanged || !wasError);
        if (previous.length && current.length && statusChanged &&
            (self.result.shown || newFailure) && [self text:@"status"].length && !self.dialogOpen) {
            [self showResult];
        }
    }
}
- (void)send:(NSString *)action path:(NSString *)path {
    if (self.closed) return;
    NSMutableDictionary *message = [@{@"action": action} mutableCopy];
    if (path) message[@"path"] = path;
    NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    if (data.length > 0 && data.length < 8192) {
        ssize_t sent = send(self.channel, data.bytes, data.length, MSG_DONTWAIT);
        if (sent != data.length) {
            self.state = @{};
            [self update];
        }
    }
}
- (void)pressed:(NSButton *)sender {
    if (!sender.enabled || self.closed) return;
    [self.result close];
    // Closing is animated: isShown may remain true until AppKit finishes.
    // Forget it immediately so the next action cannot reopen the old popover.
    self.result = nil;
    NSString *action = sender.identifier;
    if ([action isEqual:@"record"]) { [self confirmRecording]; return; }
    if ([action isEqual:@"more"]) { [self showMenu:sender]; return; }
    if ([action isEqual:@"sendFile"] || [action isEqual:@"installAPK"]) {
        [self chooseFile:[action isEqual:@"installAPK"]]; return;
    }
    [self send:action path:nil];
}
- (void)chooseFile:(BOOL)apk {
    self.dialogOpen = YES; [self update];
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = [self text:apk ? @"chooseAPKTitle" : @"chooseFileTitle"];
    panel.prompt = [self text:apk ? @"installAPKTitle" : @"sendPrompt"];
    panel.message = [self text:apk ? @"installExplanation" : @"sendExplanation"];
    panel.canChooseDirectories = NO; panel.allowsMultipleSelection = NO;
    if (apk) panel.allowedFileTypes = @[@"apk"];
    __weak MLWindowToolbar *weakSelf = self;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse choice) {
        MLWindowToolbar *owner = weakSelf;
        if (!owner || owner.closed) return;
        owner.dialogOpen = NO;
        if (choice != NSModalResponseOK || !panel.URL.isFileURL) { [owner update]; return; }
        NSURL *url = panel.URL;
        if ([url.pathExtension.lowercaseString isEqual:@"apk"]) {
            owner.dialogOpen = YES;
            NSAlert *alert = [[NSAlert alloc] init];
            owner.activeAlert = alert;
            alert.messageText = [owner text:@"installTitle"];
            alert.informativeText = [NSString stringWithFormat:@"%@\n\n%@", url.lastPathComponent, [owner text:@"installExplanation"]];
            [alert addButtonWithTitle:[owner text:@"installConfirm"]];
            [alert addButtonWithTitle:[owner text:@"cancelTitle"]];
            [owner presentAlert:alert completion:^(NSModalResponse response) {
                MLWindowToolbar *owner = weakSelf;
                if (!owner || owner.closed) return;
                owner.activeAlert = nil;
                owner.dialogOpen = NO;
                if (response == NSAlertFirstButtonReturn) [owner send:@"installAPK" path:url.path];
                [owner update];
            }];
        } else if (!apk) { [owner send:@"sendFile" path:url.path]; }
        [owner update];
    }];
}
- (void)confirmRecording {
    BOOL stopping = [self flag:@"recording"];
    self.dialogOpen = YES;
    [self update];
    NSAlert *alert = [[NSAlert alloc] init];
    self.activeAlert = alert;
    alert.messageText = [self text:stopping ? @"stopTitle" : @"startTitle"];
    alert.informativeText = [self text:stopping ? @"stopExplanation" : @"startExplanation"];
    [alert addButtonWithTitle:[self text:stopping ? @"stopConfirm" : @"startConfirm"]];
    [alert addButtonWithTitle:[self text:@"cancelTitle"]];
    __weak MLWindowToolbar *weakSelf = self;
    [self presentAlert:alert completion:^(NSModalResponse response) {
        MLWindowToolbar *owner = weakSelf;
        if (!owner || owner.closed) return;
        owner.activeAlert = nil;
        if (response != NSAlertFirstButtonReturn) {
            owner.dialogOpen = NO; [owner update]; return;
        }
        if (stopping) {
            owner.dialogOpen = NO;
            [owner send:@"recordStop" path:nil];
            [owner update];
        } else {
            NSSavePanel *panel = [NSSavePanel savePanel];
            panel.title = [owner text:@"saveRecordingTitle"];
            panel.allowedFileTypes = @[@"mp4"];
            panel.canCreateDirectories = YES;
            NSString *directory = [owner text:@"directory"];
            if (directory.length) panel.directoryURL = [NSURL fileURLWithPath:directory isDirectory:YES];
            panel.nameFieldStringValue = [NSString stringWithFormat:@"MirrorLink-Recording-%.0f.mp4", NSDate.date.timeIntervalSince1970];
            [panel beginSheetModalForWindow:owner.window completionHandler:^(NSModalResponse choice) {
                MLWindowToolbar *owner = weakSelf;
                if (!owner || owner.closed) return;
                owner.dialogOpen = NO;
                if (choice == NSModalResponseOK && panel.URL.isFileURL) [owner send:@"recordStart" path:panel.URL.path];
                [owner update];
            }];
        }
    }];
}
- (void)showResult {
    if (!self.window.visible || self.closed) return;
    [self.result close];
    NSViewController *content = [[NSViewController alloc] init];
    NSTextField *text = [NSTextField wrappingLabelWithString:[self text:@"status"]];
    text.font = [NSFont systemFontOfSize:12];
    text.textColor = [self flag:@"isError"] ? NSColor.systemRedColor : NSColor.labelColor;
    CGFloat height = MAX(44, MIN(300, [text sizeThatFits:NSMakeSize(276, CGFLOAT_MAX)].height));
    CGFloat footer = [self flag:@"busy"] ? 36 : 0;
    text.frame = NSMakeRect(12, 12 + footer, 276, height);
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, height + 24 + footer)];
    [view addSubview:text];
    if (footer) {
        NSButton *cancel = [NSButton buttonWithTitle:[self text:@"cancelOperationTitle"] target:self action:@selector(cancelOperation:)];
        cancel.frame = NSMakeRect(172, 8, 116, 28); [view addSubview:cancel];
    }
    content.view = view;
    self.result = [[NSPopover alloc] init];
    self.result.contentViewController = content;
    self.result.behavior = NSPopoverBehaviorTransient;
    NSButton *anchor = self.buttons[@"more"];
    [self.result showRelativeToRect:anchor.bounds ofView:anchor preferredEdge:NSRectEdgeMinY];
}
- (void)showMenu:(NSButton *)sender {
    NSMenu *menu = [[NSMenu alloc] init];
    if ([self flag:@"busy"]) {
        NSMenuItem *progress = [[NSMenuItem alloc] initWithTitle:[self text:@"status"] action:nil keyEquivalent:@""];
        progress.enabled = NO; [menu addItem:progress];
        NSMenuItem *cancel = [[NSMenuItem alloc] initWithTitle:[self text:@"cancelOperationTitle"] action:@selector(cancelOperation:) keyEquivalent:@""];
        cancel.target = self; [menu addItem:cancel];
        [menu addItem:NSMenuItem.separatorItem];
    }
    NSMenuItem *swipe = [[NSMenuItem alloc] initWithTitle:[self text:@"swipeTitle"] action:@selector(swipe:) keyEquivalent:@""];
    swipe.target = self;
    swipe.enabled = [self flag:@"controlAllowed"] && ![self flag:@"busy"];
    [menu addItem:swipe];
    [menu addItem:NSMenuItem.separatorItem];
    for (NSString *key in @[@"screenshotPath", @"recordingPath"]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[self text:[key isEqual:@"screenshotPath"] ? @"showScreenshotTitle" : @"showRecordingTitle"] action:@selector(reveal:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = [self text:key];
        item.enabled = [self text:key].length > 0;
        [menu addItem:item];
    }
    NSMenuItem *status = [[NSMenuItem alloc] initWithTitle:[self text:@"statusTitle"] action:@selector(result:) keyEquivalent:@""];
    status.target = self;
    status.enabled = [self text:@"status"].length > 0;
    [menu addItem:status];
    menu.autoenablesItems = NO;
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, -4) inView:sender];
}
- (void)swipe:(id)sender { if ([self flag:@"controlAllowed"] && ![self flag:@"busy"]) [self send:@"swipe" path:nil]; }
- (void)cancelOperation:(id)sender { [self send:@"cancel" path:nil]; }
- (void)reveal:(NSMenuItem *)sender {
    NSString *path = sender.representedObject;
    if ([path isKindOfClass:NSString.class] && path.isAbsolutePath) [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
}
- (void)result:(id)sender { [self showResult]; }
- (void)invalidate {
    if (self.closed) return;
    self.closed = YES;
    self.activeAlert = nil;
    self.alertAnswer = nil;
    [self.result close];
    [self update];
    if (self.reader) { dispatch_source_cancel(self.reader); self.reader = nil; }
    if (self.closeObserver) { [NSNotificationCenter.defaultCenter removeObserver:self.closeObserver]; self.closeObserver = nil; }
}
@end

static const char associationKey;
void mirrorlink_toolbar_install(SDL_Window *window) {
    const char *enabled = getenv("MIRRORLINK_WINDOW_CONTROLS");
    if (!enabled || strcmp(enabled, "1")) return;
    int kind = 0; socklen_t length = sizeof(kind);
    if (getsockopt(STDIN_FILENO, SOL_SOCKET, SO_TYPE, &kind, &length) || kind != SOCK_DGRAM) return;
    NSWindow *native = (__bridge NSWindow *)SDL_GetPointerProperty(SDL_GetWindowProperties(window), SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
    if (!native || objc_getAssociatedObject(native, &associationKey)) return;
    int channel = dup(STDIN_FILENO);
    if (channel < 0) return;
    fcntl(channel, F_SETFD, FD_CLOEXEC);
    fcntl(channel, F_SETFL, O_NONBLOCK);
    MLWindowToolbar *owner = [[MLWindowToolbar alloc] init];
    owner.channel = channel; owner.window = native; owner.state = @{};
    owner.buttons = [NSMutableDictionary dictionary]; owner.items = [NSMutableDictionary dictionary];
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"MirrorLink.PhoneControls"];
    toolbar.delegate = owner; toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    toolbar.allowsUserCustomization = NO; toolbar.autosavesConfiguration = NO;
    native.titleVisibility = NSWindowTitleVisible;
    native.toolbarStyle = NSWindowToolbarStyleExpanded;
    native.toolbar = toolbar;
    objc_setAssociatedObject(native, &associationKey, owner, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    owner.reader = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, channel, 0, dispatch_get_main_queue());
    __weak MLWindowToolbar *weakOwner = owner;
    dispatch_source_set_event_handler(owner.reader, ^{ [weakOwner receive]; });
    dispatch_source_set_cancel_handler(owner.reader, ^{ close(channel); });
    dispatch_resume(owner.reader);
    owner.closeObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:native queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [weakOwner invalidate]; }];
    [owner send:@"ready" path:nil];
}
void mirrorlink_toolbar_remove(SDL_Window *window) {
    NSWindow *native = (__bridge NSWindow *)SDL_GetPointerProperty(SDL_GetWindowProperties(window), SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
    MLWindowToolbar *owner = objc_getAssociatedObject(native, &associationKey);
    [owner invalidate];
    if (owner) native.toolbar = nil;
    objc_setAssociatedObject(native, &associationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
