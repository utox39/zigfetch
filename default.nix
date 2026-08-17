{ pkgs ? import <nixpkgs> {} }:

pkgs.stdenv.mkDerivation {
  pname = "zigfetch";
  version = "0.29.0";

  src = ./.;

  nativeBuildInputs = with pkgs; [
    zig.hook
  ];

  buildInputs = with pkgs; [
    pciutils
  ];

  zigBuildFlags = [
    "-Doptimize=ReleaseSafe"
  ];
}
