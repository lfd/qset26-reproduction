{
  description = "Flake-based repro environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowBroken = true;
        };

        myPython = pkgs.python313.withPackages (p: with p; [
          # Add additional python packages here
        ]);

        rPackageNames = builtins.filter (x: x != "") (pkgs.lib.splitString "\n" (builtins.readFile ./analysis/requirements.R));

        rPackages = map (name: pkgs.rPackages.${name}) rPackageNames;

        myR = pkgs.rWrapper.override {
          packages = rPackages;
        };

        myTex = (pkgs.texliveBasic.withPackages (
          ps: with ps; [
            # For the paper creation on its own:
            biblatex
            biblatex-ieee
            collection-publishers
            latexmk

            #other useful packages:
            #censor
            #cite
            #cleveref
            #pbox
            #preprint
            #tokcycle

            # Required for R's tikzDevice:
            collection-latexextra
        ]));
      in
      {
        devShell = pkgs.mkShell {
          NIX_HARDENING_ENABLE="";
          buildInputs = with pkgs; [
            # R + building the paper
            cloc
            myTex
            myR
            myPython

            # Packages for development
            less
            git
            which
          ];
          shellHook = ''
            export VENV="$PWD/.venv"
            if [ ! -d "$VENV" ]; then
              echo "Creating virtualenv..."
              python -m venv "$VENV"
            fi
            source "$VENV/bin/activate"
            if [ -f analysis/requirements.txt ]; then
              echo "Installing Python requirements..."
              pip install -r analysis/requirements.txt
            fi
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [
              pkgs.stdenv.cc.cc.lib
              pkgs.zlib
            ]}:$LD_LIBRARY_PATH"
            echo "Python environment ready."
          '';
        };
      }
    );
}
