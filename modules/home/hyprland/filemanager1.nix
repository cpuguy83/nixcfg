{ pkgs
, lib
, ...
}:

# Lightweight org.freedesktop.FileManager1 D-Bus shim.
#
# Desktop apps (e.g. the GitHub Copilot app) implement "show in files" by calling
# org.freedesktop.FileManager1.ShowItems over D-Bus. On a terminal-only file
# manager setup nothing owns that name, so the call fails with
# "ServiceUnknown: The name is not activatable". This provides the name and opens
# the requested path in yazi (in ghostty), matching the `$file_manager` binding.
let
  fmPython = pkgs.python3.withPackages (ps: [
    ps.dbus-python
    ps.pygobject3
  ]);

  filemanager1Service = pkgs.writeTextFile {
    name = "filemanager1-service";
    executable = true;
    destination = "/bin/filemanager1-service";
    text = ''
      #!${fmPython}/bin/python3
    '' + builtins.readFile ./filemanager1.py;
  };

  # Opens a file or directory in yazi. yazi opens a file's parent directory with
  # the file hovered, and opens a directory directly.
  filemanager1Launcher = pkgs.writeShellScript "filemanager1-launch" ''
    exec ${pkgs.uwsm}/bin/uwsm app -- \
      ${pkgs.ghostty}/bin/ghostty --class=yazi --title=yazi \
      -e ${pkgs.yazi}/bin/yazi "$1"
  '';
in
{
  xdg.dataFile."dbus-1/services/org.freedesktop.FileManager1.service".text = ''
    [D-BUS Service]
    Name=org.freedesktop.FileManager1
    Exec=${filemanager1Service}/bin/filemanager1-service ${filemanager1Launcher}
  '';
}
