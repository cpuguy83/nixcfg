# GitHub Copilot desktop app (github/app). Tauri/webkit2gtk binary, repackaged
# from the upstream x64 .deb. `src` and `version` are supplied from flake.nix so
# that bumping the github-copilot-deb input URL is the only update step.
#
# NOTE: We deliberately avoid autoPatchelfHook and stdenv's ELF fixups. Those use
# the patchelf pinned in nixpkgs (0.15.2), which corrupts this large Rust/Tauri
# PIE: shifting segments to fit the Nix interpreter/rpath mangles .rela.dyn and
# ld.so aborts at startup with
#   "elf_machine_rela_relative: Assertion R_X86_64_RELATIVE failed".
# patchelf 0.18 (patchelfUnstable) rewrites it correctly, so we patch by hand and
# disable dontPatchELF/dontStrip so nothing re-touches the binary afterwards.
{ lib
, stdenv
, dpkg
, patchelfUnstable
, wrapGAppsHook3
, webkitgtk_4_1
, gtk3
, glib
, glib-networking
, libsoup_3
, cairo
, pango
, gdk-pixbuf
, librsvg
, harfbuzz
, atk
, openssl
, alsa-lib
, libpulseaudio
, libayatana-appindicator
, gsettings-desktop-schemas
, src
, version
}:

stdenv.mkDerivation {
  pname = "github-copilot";
  inherit version src;

  nativeBuildInputs = [
    dpkg
    patchelfUnstable
    wrapGAppsHook3
  ];

  buildInputs = [
    webkitgtk_4_1
    gtk3
    glib
    glib-networking
    libsoup_3
    cairo
    pango
    gdk-pixbuf
    librsvg
    harfbuzz
    atk
    openssl
    alsa-lib
    libpulseaudio
    libayatana-appindicator
    gsettings-desktop-schemas
    stdenv.cc.cc.lib
  ];

  # Keep the upstream binary byte-for-byte except for our explicit patchelf call.
  dontConfigure = true;
  dontBuild = true;
  dontPatchELF = true;
  dontStrip = true;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    # Preserve the upstream FHS layout (bin/ + lib/"GitHub Copilot"/ + share/) so
    # Tauri's runtime resource resolution (exe/../lib/<product>) keeps working.
    cp -r usr/. "$out/"

    substituteInPlace "$out/share/applications/GitHub Copilot.desktop" \
      --replace-fail "Exec=github" "Exec=$out/bin/github"

    interp="$(cat "$NIX_CC/nix-support/dynamic-linker")"
    rpath="${lib.makeLibraryPath [
      webkitgtk_4_1
      gtk3
      glib
      libsoup_3
      cairo
      pango
      gdk-pixbuf
      harfbuzz
      atk
      openssl
      alsa-lib
      libpulseaudio
      libayatana-appindicator
      stdenv.cc.cc.lib
    ]}"

    patchelf --set-interpreter "$interp" --set-rpath "$rpath" "$out/bin/github"
    patchelf --set-interpreter "$interp" "$out/bin/git-credential-copilot"

    runHook postInstall
  '';

  meta = {
    description = "GitHub Copilot desktop app";
    homepage = "https://github.com/github/app";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "github";
  };
}
