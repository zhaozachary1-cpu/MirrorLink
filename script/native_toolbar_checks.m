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
        close(sockets[0]); close(sockets[1]);
        printf("PASS: %lu native toolbar receiver checks (no UI or phone acceptance)\n", (unsigned long)checks);
    }
}
