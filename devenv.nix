{
  config,
  pkgs,
  ...
}:
{
  languages.zig = {
    enable = true;
    version = "0.17.1";
  };
  packages = with pkgs; [
    lefthook
    libX11
    libXtst
    pkg-config
  ];

  tasks."cli:build" = {
    exec = "zig build";
    cwd = "${config.git.root}/packages/cli";
  };

  tasks."engine:build" = {
    exec = "zig build";
    cwd = "${config.git.root}/packages/engine";
  };

  tasks."workspace:init" = {
    exec = ''
      lefthook install
      touch .devenv/.initialized
      echo '{"devenv":{"messages":["\u001b[1;32m✓ Workspace initialized!\u001b[0m"]}}' > "$DEVENV_TASK_OUTPUT_FILE"
    '';
    status = "test -f .devenv/.initialized";
    before = [ "devenv:enterShell" ];
  };

  enterShell = ''
    if [ -n "$DEVENV_CD" ]; then
    	cd "$DEVENV_CD"
    fi
  '';
}
