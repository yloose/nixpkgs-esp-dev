{ rev ? "v5.1.2"
, sha256 ? "sha256-uEf3/3NPH+E39VgQ02AbxTG7nmG5bQlhwk/WcTeAUfg="
, toolsToInclude ? [
    "xtensa-esp-elf-gdb"
    "riscv32-esp-elf-gdb"
    "xtensa-esp32-elf"
    "xtensa-esp32s2-elf"
    "xtensa-esp32s3-elf"
    "esp-clang"
    "riscv32-esp-elf"
    "esp32ulp-elf"
    "openocd-esp32"
    "esp-rom-elfs"
  ]
, stdenv
, lib
, fetchFromGitHub
, makeWrapper
, callPackage

, python3

  # Tools for using ESP-IDF.
, git
, wget
, gnumake
, flex
, bison
, gperf
, pkg-config
, cmake
, ninja
, ncurses5
, dfu-util
}:

let
  src = fetchFromGitHub {
    owner = "espressif";
    repo = "esp-idf";
    rev = rev;
    sha256 = sha256;
    fetchSubmodules = true;
  };

  allTools = callPackage (import ./tools.nix) {
    toolSpecList = (builtins.fromJSON (builtins.readFile "${src}/tools/tools.json")).tools;
    versionSuffix = "esp-idf-${rev}";
  };

  toolDerivationsToInclude = builtins.map (toolName: allTools."${toolName}") toolsToInclude;

  customPython =
    (python3.withPackages
      (pythonPackages:
        let
          customPythonPackages = callPackage (import ./python-packages.nix) { inherit pythonPackages; };
        in
        with pythonPackages;
        with customPythonPackages;
        [
          # This list is from `tools/requirements/requirements.core.txt` in the
          # ESP-IDF checkout.
          setuptools
          click
          pyserial
          cryptography
          pyparsing
          pyelftools
          idf-component-manager
          esp-coredump
          esptool
          esp-idf-kconfig
          esp-idf-monitor
          esp-idf-size
          esp-idf-panic-decoder

          freertos_gdb

          # The esp idf vscode extension seems to want pip, too
          pip
        ]));
in
stdenv.mkDerivation rec {
  pname = "esp-idf";
  version = rev;

  inherit src;

  # This is so that downstream derivations will have IDF_PATH set.
  setupHook = ./setup-hook.sh;

  nativeBuildInputs = [ makeWrapper ];

  propagatedBuildInputs = [
    # This is in propagatedBuildInputs so that downstream derivations will run
    # the Python setup hook and get PYTHONPATH set up correctly.
    customPython

    # Tools required to use ESP-IDF.
    git
    wget
    gnumake

    flex
    bison
    gperf
    pkg-config

    cmake
    ninja

    ncurses5

    dfu-util
  ] ++ toolDerivationsToInclude;

  # We are including cmake and ninja so that downstream derivations (eg. shells)
  # get them in their environment, but we don't actually want any of their build
  # hooks to run, since we aren't building anything with them right now.
  dontUseCmakeConfigure = true;
  dontUseNinjaBuild = true;
  dontUseNinjaInstall = true;
  dontUseNinjaCheck = true;

  installPhase = ''
    mkdir -p $out
    cp -rv . $out/

    # Link the Python environment in so that:
    # - The setup hook can set IDF_PYTHON_ENV_PATH to it.
    # - In shell derivations, the Python setup hook will add the site-packages
    #   directory to PYTHONPATH.
    ln -s ${customPython} $out/python-env
    ln -s ${customPython}/lib $out/lib
  '';
}
