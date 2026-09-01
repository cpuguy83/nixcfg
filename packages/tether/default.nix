# tether: bridges an iPhone to the Linux desktop -- clipboard sync over
# TCP+mTLS/mDNS, and SMS/iMessage over Bluetooth MAP/PBAP.
{ lib
, stdenv
, src
, cmake
, ninja
, pkg-config
, gettext
, wrapGAppsHook3
, avahi
, bluez
, glib
, gtk3
, gtk-layer-shell
, hicolor-icon-theme
, libnotify
, nlohmann_json
, openssl
, wayland
,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "tether";
  # Keep in sync with the `tether` input's tag in flake.nix; the derivation is
  # handed a plain source tree and cannot read the tag itself.
  version = "0.2.17";

  inherit src;

  # Closes a real hole in upstream's pairing flow: any device that can reach
  # the TCP port can send unlimited pair_request messages, each spawning a
  # keyboard-focus-grabbing dialog, so a stray Enter keystroke silently
  # pairs it. Gates dialog spawn behind the GTK app explicitly opening
  # pairing mode (Devices tab visible) with no device already paired.
  patches = [ ./patches/local-only-pairing.patch ];

  # Upstream pulls two dependencies with FetchContent at configure time, which
  # the sandbox has no network for:
  #   * nlohmann/json -- swapped for the nixpkgs package, same 3.12.0.
  #   * googletest    -- dropped along with the test target. `-DBUILD_TESTING=OFF`
  #     does not help: the root CMakeLists calls FetchContent_MakeAvailable and
  #     add_subdirectory(test) unconditionally, with no BUILD_TESTING guard.
  # `git describe` also runs at configure time and finds no .git here, which
  # would stamp the binaries "0.2.17-unknown" -- the version shows up in
  # `tether --bt-diagnostics`, which is what upstream asks for in bug reports.
  postPatch = ''
    substituteInPlace CMakeLists.txt \
      --replace-fail 'FetchContent_MakeAvailable(json)' \
                     'find_package(nlohmann_json REQUIRED)' \
      --replace-fail 'FetchContent_MakeAvailable(googletest)' ''' \
      --replace-fail 'add_subdirectory(test)' ''' \
      --replace-fail 'COMMAND git describe --tags --always --dirty' \
                     'COMMAND ''${CMAKE_COMMAND} -E echo v${finalAttrs.version}'
  '';

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    gettext # msgfmt: message catalogs + the localized .desktop entry
    wrapGAppsHook3 # tether-gtk / tether-dialog are GTK3 apps
  ];

  buildInputs = [
    avahi
    glib
    gtk3
    gtk-layer-shell
    hicolor-icon-theme
    libnotify
    nlohmann_json
    openssl
    wayland
  ];

  cmakeFlags = [
    # The OTP browser/mail WebExtension is out of scope and its build shells out
    # to npm, which cannot fetch in the sandbox.
    "-DTETHER_BUILD_EXTENSIONS=OFF"
    # Two of the four native-messaging manifest destinations are absolute paths
    # outside the store (/etc/chromium, /etc/opt/chrome) and fail the install
    # phase. Relative values land them under $out in the same FHS shape. The
    # mozilla/thunderbird ones already default to a relative ${CMAKE_INSTALL_LIBDIR}.
    "-DCHROME_MESSAGING_DIR=etc/chromium/native-messaging-hosts"
    "-DGOOGLE_CHROME_MESSAGING_DIR=etc/opt/chrome/native-messaging-hosts"
    # CMake otherwise probes /usr/libexec and /usr/lib and bakes a Debian path
    # into the bluetooth-experimental.conf drop-in it ships for reference.
    "-DBLUETOOTHD_PATH=${bluez}/libexec/bluetooth/bluetoothd"
  ];

  doCheck = false;

  meta = {
    description = "Bridge an iPhone to the Linux desktop: clipboard, files, and messages";
    homepage = "https://github.com/zackb/tether";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "tether";
  };
})
