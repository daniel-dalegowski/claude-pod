{ stdenv, lib }:

stdenv.mkDerivation {
  pname = "claude-pod";
  version = lib.fileContents ../VERSION;
  src = ../.;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    datadir="$out/share/claude-pod"
    install -Dm644 Containerfile       "$datadir/Containerfile"
    install -Dm644 container-xdg-open  "$datadir/container-xdg-open"
    install -Dm644 container-claude.md "$datadir/container-claude.md"
    install -Dm644 VERSION             "$datadir/VERSION"
    install -Dm644 agents/debugger.md  "$datadir/agents/debugger.md"
    install -Dm644 agents/architect.md "$datadir/agents/architect.md"

    install -Dm755 claude-pod "$out/bin/claude-pod"
    # Replace the runtime self-location with the fixed Nix store path so
    # 'podman build' finds the Containerfile and COPY sources correctly.
    sed -i "s|^SCRIPT_DIR=.*|SCRIPT_DIR=\"$datadir\"|" "$out/bin/claude-pod"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Ephemeral Podman sandbox for a single project directory";
    mainProgram = "claude-pod";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
