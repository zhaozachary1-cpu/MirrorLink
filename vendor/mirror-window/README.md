# MirrorLink native phone-window toolbar

This Apache-2.0 code is compiled into pinned scrcpy 4.1, with the integration
patch included here. `script/build_scrcpy.sh` verifies the source archives,
builds static dependencies for macOS 13 on arm64/x86_64, and applies this patch.
The upstream server and checked-in original binaries are not modified.

Each MirrorLink-owned child inherits a private Unix datagram socket as stdin.
An explicit environment marker and socket-type check enable the toolbar.
Actions are enums, never shell commands. The parent validates the active
session token, original device route, presentation mode, busy state and paths.
There is no network listener, authentication secret, or filesystem socket.

Toolbar buttons, native file panels, installation and recording confirmations,
operation status and cancellation all belong to the actual SDL Cocoa window.
Routine progress and successful results do not open a popover automatically.
More retains status and cancellation; a new failure can still open its details.
An already-open status popover refreshes as the operation changes.
AppKit confirmation buttons resolve explicitly because SDL owns its event loop.
State is bilingual, bounded, nonblocking and deduplicated. Socket buffers are
configured above Darwin's default 2 KB to fit localized states and media paths.

The signed nested `MirrorLinkWindow.app` gives these windows a distinct native
identity. The compatibility `Contents/MacOS/scrcpy` link stays inside the
application bundle. It uses no Accessibility permissions or injected libraries.
All runtime outputs remain under the project work directory; source archives
and modifications accompany the public release for rebuilding/relinking.
