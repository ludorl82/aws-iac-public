{
  description = "AWS infrastructure as code for account 123456789012 (ca-central-1)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.opentofu
            pkgs.awscli2
            pkgs.jq
          ];

          # The fleet already trusts the private CA declaratively; nothing here
          # should ever need TLS shortcuts. See modules/private-ca.nix in nixos-iac.
          shellHook = ''
            export AWS_REGION=ca-central-1
            export TF_CLI_ARGS_plan="-lock-timeout=60s"

            # Git hooks live in hooks/ so they are versioned and shared;
            # .git/hooks is not tracked and would have to be set up by hand.
            if [ -d hooks ] && [ "$(git config --get core.hooksPath || true)" != "hooks" ]; then
              git config core.hooksPath hooks
              echo "enabled pre-commit hook (core.hooksPath=hooks)"
            fi

            echo "aws-iac devshell — tofu $(tofu version | head -n1 | cut -d' ' -f2)"
          '';
        };
      });
    };
}
