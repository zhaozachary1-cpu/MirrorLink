# Bundled runtime sources and rebuilding

MirrorLink runs scrcpy and ADB as separate executables. Their upstream licenses
are not replaced by MirrorLink's Apache-2.0 license. No additional restriction
is imposed on modifying the LGPL libraries or reverse engineering for debugging
such modifications. Modifying an installed bundle invalidates its seal; build
and ad-hoc sign your own copy instead of reusing a publisher's signature.

The community release includes a `MirrorLink-<version>-third-party-sources.tar.gz`
asset **on the same release as the application**. It includes the unmodified
sources for scrcpy 4.1, FFmpeg 8.1.2, SDL 3.4.12, libusb 1.0.30, dav1d 1.5.3 and
zlib 1.3.2, the complete licenses collected here, and a hash/URL manifest.
`script/prepare_third_party.sh` retrieves and verifies the pinned materials;
it compares both bundled architectures with upstream's official scrcpy archives
and compares ADB with Google's exact Platform-Tools 37.0.0 archive.

The scrcpy 4.1 source archive corresponds to upstream commit
`2926c06c5dc3064ae6d8db706f1a98a37cfcf3f0`. Its `release/build_macos.sh` and
`app/deps/{_init,sdl.sh,dav1d.sh,ffmpeg.sh,libusb.sh,adb_macos.sh}` contain the
dependency versions, configuration and build commands. The macOS FFmpeg script
does not enable GPL or nonfree components. scrcpy statically links these
libraries; the arm64 executable also contains zlib 1.3.2, while x86_64 uses the
macOS system zlib. Apple system libraries are supplied by macOS, not this package.

## Rebuild / relink a modified runtime

1. Extract the scrcpy source archive and other source archives from the supplied
   source package. Install Apple's command-line development tools and scrcpy's
   build prerequisites (Meson, Ninja, pkg-config, CMake, Autoconf, Automake,
   libtool, NASM as required by the selected architecture).
2. In the scrcpy tree, put the supplied dependency source directories under
   `app/deps/work/sources/`, using the names expected by `app/deps/*.sh`
   (e.g. `sdl-3.4.12` for SDL's extracted `SDL-release-3.4.12`). Change a library's
   source there. Existing source directories are used by the upstream scripts.
   Build/install zlib 1.3.2 to your chosen prefix when reproducing the arm64
   static dependency, and point `PKG_CONFIG_PATH` in `app/deps/ffmpeg.sh` at that
   prefix instead of the original build machine's `/opt/homebrew/opt/zlib`.
3. On each native architecture, run `VERSION=4.1 release/build_macos.sh aarch64`
   or `VERSION=4.1 release/build_macos.sh x86_64`. The source includes scrcpy's
   complete application code, allowing recompilation/relinking against modified
   FFmpeg/libusb, not just the libraries alone. See upstream `doc/build.md` for
   server and alternative build instructions. The unchanged bundled server can
   be retained when modifying desktop libraries.
4. Copy your rebuilt scrcpy executable into the corresponding
   `vendor/scrcpy/arm64/` or `vendor/scrcpy/x86_64/` directory in a personal clone
   of MirrorLink. Run `./script/build_and_run.sh --verify --no-launch`. The local
   build signs your modified bundle ad-hoc; it does not need our update private
   key. Keep custom builds outside the official update channel.

The official prebuilt runtime is byte-for-byte verified against upstream;
these source instructions are not a claim of byte-reproducible rebuilding on
every SDK or of having executed every third-party build on this Mac. No scrcpy,
FFmpeg or libusb source changes were made for the distributed runtime. ADB's
complete upstream Platform-Tools notice is retained (including notices for
components not shipped by MirrorLink); only `adb` is bundled, not the rest of
the SDK tools.
