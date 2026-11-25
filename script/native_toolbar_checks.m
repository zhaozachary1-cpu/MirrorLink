// Copyright MirrorLink contributors. SPDX-License-Identifier: Apache-2.0
// Exercise the production receiver through real socketpairs without opening UI
// or accessing a phone. Only the display side effects and SDL lookup are stubbed.
#import "../vendor/mirror-window/MirrorWindowToolbar.m"
#include <assert.h>

SDL_PropertiesID SDL_GetWindowProperties(SDL_Window *window) { return 0; }
void *SDL_GetPointerProperty(SDL_PropertiesID props, const char *name, void *fallback) { return fallback; }

@interface MLTestPopover : NSPopover
@property BOOL testVisible;
@end
@implementation MLTestPopover
- (BOOL)isShown { return self.testVisible; }
// AppKit may continue reporting shown during the asynchronous closing animation.
- (void)close {}
@end

@interface MLTestToolbar : MLWindowToolbar
@property NSUInteger presentations;
@end
@implementation MLTestToolbar
- (void)update {}
- (void)showResult {
    self.presentations++;
    if (!self.result) self.result = [MLTestPopover new];
    ((MLTestPopover *)self.result).testVisible = YES;
}
@end

// A closed native sheet may never deliver its deferred completion under SDL.
// These panels deliberately never invoke beginSheet's handler. The production
// toolbar must use the modal return value, with no user interaction in tests.
@interface MLTestFilePanel : NSObject
@property NSString *title, *prompt, *message, *nameFieldStringValue;
@property NSArray *allowedFileTypes;
@property NSURL *URL, *directoryURL;
@property BOOL canChooseDirectories, allowsMultipleSelection, canCreateDirectories;
@property NSModalResponse response;
@property NSUInteger modalCalls, sheetCalls, cancellations;
@property(copy) void (^duringModal)(void);
@end
@implementation MLTestFilePanel
- (NSModalResponse)runModal {
    self.modalCalls++;
    if (self.duringModal) self.duringModal();
    return self.response;
}
- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))handler {
    self.sheetCalls++;
}
- (void)orderOut:(id)sender {}
- (void)cancel:(id)sender { self.cancellations++; }
@end

@interface MLPanelTestToolbar : MLWindowToolbar
@property MLTestFilePanel *testPanel;
@property NSMutableArray<NSDictionary *> *requests;
@property(copy) void (^pendingConfirmation)(NSModalResponse);
@end
@implementation MLPanelTestToolbar
- (NSOpenPanel *)makeOpenPanel { return (NSOpenPanel *)self.testPanel; }
- (NSSavePanel *)makeSavePanel { return (NSSavePanel *)self.testPanel; }
- (void)send:(NSString *)action path:(NSString *)path {
    [self.requests addObject:@{@"action": action, @"path": path ?: @""}];
}
- (void)presentAlert:(NSAlert *)alert completion:(void (^)(NSModalResponse))completion {
    self.pendingConfirmation = completion;
}
@end

static NSUInteger checks;
static void check(BOOL condition, NSString *name) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", name.UTF8String); exit(1); }
    checks++;
    printf("PASS: %s\n", name.UTF8String);
}
static void deliver(int socket, MLTestToolbar *toolbar, NSString *identifier,
                    NSString *status, BOOL busy, BOOL error) {
    NSDictionary *state = @{@"type": @"state", @"resultID": identifier,
                            @"status": status, @"busy": @(busy), @"isError": @(error)};
    NSData *data = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
    assert(send(socket, data.bytes, data.length, 0) == data.length);
    [toolbar receive];
}
int main(void) {
    @autoreleasepool {
        int sockets[2]; assert(socketpair(AF_UNIX, SOCK_DGRAM, 0, sockets) == 0);
        MLTestToolbar *toolbar = [MLTestToolbar new];
        toolbar.channel = sockets[1]; toolbar.state = @{};
        MLTestPopover *popover = [MLTestPopover new]; toolbar.result = popover;
        deliver(sockets[0], toolbar, @"initial", @"", NO, NO);
        check(toolbar.presentations == 0, @"initial state stays quiet");
        for (NSString *action in @[@"home", @"drawer", @"screenshot", @"sendFile", @"installAPK", @"recording"]) {
            deliver(sockets[0], toolbar, action, @"Working", YES, NO);
            deliver(sockets[0], toolbar, action, @"Completed", NO, NO);
            check(toolbar.presentations == 0, [action stringByAppendingString:@" progress and success stay quiet"]);
        }
        deliver(sockets[0], toolbar, @"invalidAPK", @"Installing", YES, NO);
        deliver(sockets[0], toolbar, @"invalidAPK", @"Invalid package", NO, YES);
        check(toolbar.presentations == 1, @"failure after busy opens an explanation");
        popover.testVisible = NO;
        deliver(sockets[0], toolbar, @"invalidAPK", @"Invalid package", NO, YES);
        check(toolbar.presentations == 1, @"dismissed failure does not reopen on repeated state");
        deliver(sockets[0], toolbar, @"invalidAPK", @"无效安装包", NO, YES);
        check(toolbar.presentations == 1, @"language change does not reopen dismissed failure");
        deliver(sockets[0], toolbar, @"invalidAPK-again", @"无效安装包", NO, YES);
        check(toolbar.presentations == 2, @"a distinct failed request still reports its error");
        popover.testVisible = NO;
        deliver(sockets[0], toolbar, @"home-again", @"Working", YES, NO);
        deliver(sockets[0], toolbar, @"home-again", @"Completed", NO, NO);
        check(toolbar.presentations == 2, @"successful action after an error stays quiet");
        [toolbar result:nil];
        check(toolbar.presentations == 3, @"explicit View Result still opens details");
        deliver(sockets[0], toolbar, @"transfer", @"Sending", YES, NO);
        check(toolbar.presentations == 4, @"already-open details refresh during progress");
        deliver(sockets[0], toolbar, @"transfer", @"Saved", NO, NO);
        check(toolbar.presentations == 5, @"already-open details refresh on completion");
        popover.testVisible = NO;
        deliver(sockets[0], toolbar, @"transfer", @"Saved", NO, NO);
        check(toolbar.presentations == 5, @"closed success details remain closed");
        toolbar.dialogOpen = YES;
        deliver(sockets[0], toolbar, @"failure-during-sheet", @"Failed", NO, YES);
        check(toolbar.presentations == 5, @"an active confirmation is not covered by a status popover");
        toolbar.dialogOpen = NO;
        toolbar.result = popover; popover.testVisible = YES;
        NSButton *home = [NSButton new]; home.enabled = YES; home.identifier = @"home";
        [toolbar pressed:home];
        deliver(sockets[0], toolbar, @"home-after-error", @"Working", YES, NO);
        deliver(sockets[0], toolbar, @"home-after-error", @"Completed", NO, NO);
        check(toolbar.presentations == 5, @"closing-animation race cannot reopen a popover for the next action");
        NSDictionary *inlineFailure = @{@"type": @"state", @"resultID": @"inlineAPK",
            @"status": @"Invalid APK", @"installStatus": @"Invalid APK", @"busy": @NO, @"isError": @YES};
        NSData *inlineData = [NSJSONSerialization dataWithJSONObject:inlineFailure options:0 error:nil];
        assert(send(sockets[0], inlineData.bytes, inlineData.length, 0) == inlineData.length);
        [toolbar receive];
        check(toolbar.presentations == 5, @"inline APK failure does not open a duplicate popover");
        deliver(sockets[0], toolbar, @"inlineAPK", @"Invalid APK", NO, YES);
        check(toolbar.presentations == 5, @"expiry of inline failure cannot reopen a dismissed result");
        close(sockets[0]); close(sockets[1]);

        MLPanelTestToolbar *files = [MLPanelTestToolbar new];
        files.state = @{@"ready": @YES, @"controlAllowed": @YES, @"recordAllowed": @YES,
                        @"installConfirm": @"Install", @"cancelTitle": @"Cancel"};
        files.buttons = [NSMutableDictionary new]; files.items = [NSMutableDictionary new];
        files.requests = [NSMutableArray new];
        for (NSString *key in @[@"home", @"drawer", @"screenshot", @"record", @"sendFile", @"installAPK", @"more"]) {
            files.buttons[key] = [NSButton new];
        }
        MLTestFilePanel *panel = [MLTestFilePanel new]; files.testPanel = panel;
        panel.response = NSModalResponseCancel;
        __weak MLPanelTestToolbar *weakFiles = files;
        panel.duringModal = ^{
            check(weakFiles.dialogOpen && !weakFiles.buttons[@"installAPK"].enabled,
                  @"controls are disabled only while the file chooser is open");
        };
        [files chooseFile:YES];
        check(!files.dialogOpen && files.buttons[@"installAPK"].enabled && files.buttons[@"home"].enabled,
              @"cancel APK chooser restores actual controls without a sheet callback");
        check(panel.modalCalls == 1 && panel.sheetCalls == 0 && files.activePanel == nil && files.requests.count == 0,
              @"cancel releases panel and sends no installation request");
        [files chooseFile:YES];
        check(panel.modalCalls == 2 && files.buttons[@"installAPK"].enabled,
              @"APK chooser can be reopened and cancelled repeatedly");
        [files chooseFile:NO];
        check(files.buttons[@"sendFile"].enabled && files.requests.count == 0,
              @"cancel file transfer chooser restores controls without sending a file");
        panel.duringModal = nil;
        panel.response = NSModalResponseOK; panel.URL = [NSURL fileURLWithPath:@"/test/selected.apk"];
        [files chooseFile:YES];
        check(files.dialogOpen && files.pendingConfirmation != nil && files.requests.count == 0,
              @"selecting APK requires separate confirmation before installation");
        files.pendingConfirmation(NSAlertSecondButtonReturn); files.pendingConfirmation = nil;
        check(!files.dialogOpen && files.buttons[@"installAPK"].enabled && files.requests.count == 0,
              @"cancel installation confirmation restores controls and does not install");
        [files chooseFile:YES];
        files.pendingConfirmation(NSAlertFirstButtonReturn); files.pendingConfirmation = nil;
        check(files.requests.count == 1 && [files.requests.lastObject[@"action"] isEqual:@"installAPK"] &&
              [files.requests.lastObject[@"path"] isEqual:@"/test/selected.apk"] && !files.dialogOpen,
              @"confirmed APK selection sends one exact file request and releases controls");
        panel.URL = [NSURL fileURLWithPath:@"/test/document.txt"];
        [files chooseFile:NO];
        check(files.requests.count == 2 && [files.requests.lastObject[@"action"] isEqual:@"sendFile"],
              @"confirmed ordinary file selection dispatches transfer");
        panel.response = NSModalResponseCancel;
        [files confirmRecording];
        files.pendingConfirmation(NSAlertFirstButtonReturn); files.pendingConfirmation = nil;
        check(!files.dialogOpen && files.buttons[@"record"].enabled && files.requests.count == 2,
              @"cancel recording save panel restores controls and never starts recording");
        panel.response = NSModalResponseOK; panel.URL = [NSURL fileURLWithPath:@"/test/recording.mp4"];
        [files confirmRecording];
        files.pendingConfirmation(NSAlertFirstButtonReturn); files.pendingConfirmation = nil;
        check(files.requests.count == 3 && [files.requests.lastObject[@"action"] isEqual:@"recordStart"] && !files.dialogOpen,
              @"recording save selection dispatches only after a confirmed file URL");
        panel.URL = [NSURL URLWithString:@"https://invalid.example/test.apk"];
        [files chooseFile:YES];
        check(files.requests.count == 3 && !files.dialogOpen && files.pendingConfirmation == nil,
              @"non-file URL cannot produce an installation request");
        files.state = @{@"ready": @YES, @"controlAllowed": @NO, @"recordAllowed": @YES};
        panel.response = NSModalResponseCancel; [files chooseFile:YES];
        check(!files.buttons[@"installAPK"].enabled && files.buttons[@"screenshot"].enabled,
              @"closing file panel preserves presentation-mode restrictions");
        panel.response = NSModalResponseOK; panel.URL = [NSURL fileURLWithPath:@"/test/selected.apk"];
        panel.duringModal = ^{ [weakFiles invalidate]; };
        [files chooseFile:YES];
        check(files.closed && panel.cancellations == 1 && files.requests.count == 3 && !files.buttons[@"home"].enabled,
              @"closing session cancels active panel and prevents late installation");
        printf("PASS: %lu native toolbar receiver checks (no UI or phone acceptance)\n", (unsigned long)checks);
    }
}
