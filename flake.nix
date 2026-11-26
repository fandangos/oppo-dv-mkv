{
  # Build environment for the releases: `nix develop` then `sh mkrelease.sh vX.Y.Z`.
  # Pinned: several code blobs fill their places in the player's programs to within a few bytes (e.g. the text
  # subtitle blob in vMPCMpgFilePbTest), so another compiler version can make them not fit. zig 0.16.0 (clang 21.1.8)
  # and lld 21.1.8 from this nixpkgs commit; mkrelease.sh checks the versions.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/21a67dc470149f337cecafbe965d8d252a390518";
  outputs = { self, nixpkgs }:
    let sys = "x86_64-linux"; pkgs = nixpkgs.legacyPackages.${sys}; in {
      devShells.${sys}.default = pkgs.mkShell {
        packages = with pkgs; [ zig lld llvm zip python3 ];
      };
    };
}
