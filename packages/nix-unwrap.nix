{
  lib,
  writeShellApplication,
  file,
  coreutils,
  gnugrep,
  gawk,
  binutils-unwrapped,
}:

writeShellApplication {
  name = "nix-unwrap";

  runtimeInputs = [
    file
    coreutils
    gnugrep
    gawk
    binutils-unwrapped
  ];

  text = builtins.readFile ./nix-unwrap.sh;

  meta = {
    description = "Recursively unwrap Nix wrappers to find the underlying binary";
    license = lib.licenses.mit;
    mainProgram = "nix-unwrap";
  };
}
