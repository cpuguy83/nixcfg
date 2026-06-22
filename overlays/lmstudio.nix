{ pkgs-unstable }:
final: _prev:
let
  inherit (pkgs-unstable.lmstudio) version src meta;
  appimageContents = final.appimageTools.extractType2 {
    pname = "lmstudio";
    inherit version src;
  };
in
{
  # Upstream's FHS sandbox ships only ocl-icd, omitting libnuma.so.1 and
  # libelf.so.1. The ROCm llama.cpp backend's llama-server links both, so
  # without them the GPU hardware survey fails ("Error surveying hardware")
  # and LM Studio silently can't use the 7900 XTX. Re-wrap the AppImage with
  # those libs added to the sandbox. (libnuma is the one that actually crashes
  # the survey; libelf is the next missing dependency.)
  lmstudio = final.appimageTools.wrapType2 {
    pname = "lmstudio";
    inherit version src meta;
    passthru.updateScript = pkgs-unstable.lmstudio.updateScript;

    nativeBuildInputs = [ final.graphicsmagick ];

    extraPkgs = pkgs: [
      pkgs.ocl-icd
      pkgs.numactl # libnuma.so.1
      pkgs.elfutils # libelf.so.1
    ];

    extraInstallCommands = ''
      mkdir -p $out/share/applications

      src_icon="${appimageContents}/usr/share/icons/hicolor/0x0/apps/lm-studio.png"
      sizes=("16x16" "32x32" "48x48" "64x64" "128x128" "256x256")
      for size in "''${sizes[@]}"; do
        install -dm755 "$out/share/icons/hicolor/$size/apps"
        gm convert "$src_icon" -resize "$size" "$out/share/icons/hicolor/$size/apps/lm-studio.png"
      done

      install -m 444 -D ${appimageContents}/lm-studio.desktop -t $out/share/applications

      mv $out/bin/lmstudio $out/bin/lm-studio

      substituteInPlace $out/share/applications/lm-studio.desktop \
        --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=lm-studio'

      install -m 755 ${appimageContents}/resources/app/.webpack/lms $out/bin/

      patchelf --set-interpreter "${final.stdenv.cc.bintools.dynamicLinker}" $out/bin/lms
    '';
  };
}
