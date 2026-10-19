{
  description = "lang-tptp: editor grammars generated from the TPTP SyntaxBNF";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      beam = pkgs.beam28Packages;
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          beam.erlang
          beam.elixir_1_20
          beam.rebar3
          pkgs.nodejs_24
          pkgs.pnpm
          pkgs.tree-sitter
          pkgs.python3
          pkgs.gnumake
        ];

        MIX_REBAR3 = pkgs.lib.getExe beam.rebar3;
      };
    };
}
