{
  description = "A Nix-flake-based Zig development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }: let
    inherit (nixpkgs) lib;
    genSystems =
      lib.genAttrs
      [
        "x86_64-linux"
        "aarch64-linux"
      ];

    pkgsFor = genSystems (system: import nixpkgs {inherit system;});
  in {
    devShells = genSystems (system: let
      pkgs = pkgsFor.${system};
    in {
      default = pkgs.mkShell {
        packages = with pkgs; [zig zls ncurses pkg-config];

        shellHook = ''
          echo "zig `${pkgs.zig}/bin/zig version`"
        '';
      };
    });
  };
}
