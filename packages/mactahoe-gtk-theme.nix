{
  lib,
  stdenv,
  fetchFromGitHub,
  dialog,
  glib,
  gnome-themes-extra,
  jdupes,
  libxml2,
  sassc,
  util-linux,
  colorVariants ? [ "dark" ],
  opacityVariants ? [ ],
  themeVariants ? [ ],
  schemeVariants ? [ ],
  altVariants ? [ ],
  roundedMaxWindow ? false,
  darkerColor ? false,
}:

let
  pname = "mactahoe-gtk-theme";
in
lib.checkListOfEnum "${pname}: color variants" [ "light" "dark" ] colorVariants lib.checkListOfEnum
  "${pname}: opacity variants"
  [ "normal" "solid" ]
  opacityVariants
  lib.checkListOfEnum
  "${pname}: accent color variants"
  [
    "default"
    "blue"
    "purple"
    "pink"
    "red"
    "orange"
    "yellow"
    "green"
    "grey"
    "all"
  ]
  themeVariants
  lib.checkListOfEnum
  "${pname}: colorscheme style variants"
  [ "standard" "nord" ]
  schemeVariants
  lib.checkListOfEnum
  "${pname}: window control button variants"
  [ "normal" "alt" "all" ]
  altVariants

  stdenv.mkDerivation
  rec {
    pname = "mactahoe-gtk-theme";
    version = "2025-08-30";

    src = fetchFromGitHub {
      owner = "vinceliuice";
      repo = "MacTahoe-gtk-theme";
      rev = "59fc8131e293bcf0c7a8eb55ba773cbcbcccb378";
      hash = "sha256-xS/RAPAREzteA6BRL3ZGrKk8Uml6/AjZRGQGQCOCrek=";
    };

    nativeBuildInputs = [
      dialog
      glib
      jdupes
      libxml2
      sassc
      util-linux
    ];

    buildInputs = [ gnome-themes-extra ];

    postPatch = ''
      find -name "*.sh" -print0 | while IFS= read -r -d ''' file; do
        patchShebangs "$file"
      done

      substituteInPlace libs/lib-core.sh --replace-fail '$(which sudo)' false
      substituteInPlace libs/lib-core.sh --replace-fail 'MY_HOME=$(getent passwd "''${MY_USERNAME}" | cut -d: -f6)' 'MY_HOME=/tmp'
    '';

    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/themes

      ./install.sh \
        ${toString (map (x: "--alt " + x) altVariants)} \
        ${toString (map (x: "--color " + x) colorVariants)} \
        ${toString (map (x: "--opacity " + x) opacityVariants)} \
        ${toString (map (x: "--theme " + x) themeVariants)} \
        ${toString (map (x: "--scheme " + x) schemeVariants)} \
        ${lib.optionalString roundedMaxWindow "--roundedmaxwindow"} \
        ${lib.optionalString darkerColor "--darkercolor"} \
        --dest $out/share/themes

      jdupes --quiet --link-soft --recurse $out/share

      runHook postInstall
    '';

    meta = {
      description = "macOS Tahoe-like GTK theme";
      homepage = "https://github.com/vinceliuice/MacTahoe-gtk-theme";
      license = lib.licenses.mit;
      platforms = lib.platforms.unix;
    };
  }
