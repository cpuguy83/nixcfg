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

    extraPkgs = pkgs: [
      pkgs.ocl-icd
      pkgs.numactl # libnuma.so.1
      pkgs.elfutils # libelf.so.1
    ];

    extraInstallCommands = ''
      # upstream ships pre-rendered icons for every hicolor size
      mkdir -p $out/share/icons
      cp -r ${appimageContents}/usr/share/icons/hicolor $out/share/icons/

      install -m 444 -D ${appimageContents}/ai.elementlabs.lmstudio.desktop \
        -t $out/share/applications

      mv $out/bin/lmstudio $out/bin/lm-studio

      substituteInPlace $out/share/applications/ai.elementlabs.lmstudio.desktop \
        --replace-fail 'Exec=AppRun %U' 'Exec=lm-studio %U'

      install -m 755 ${appimageContents}/resources/app/.webpack/lms $out/bin/

      patchelf --set-interpreter "${final.stdenv.cc.bintools.dynamicLinker}" $out/bin/lms
    '';
  };
}
