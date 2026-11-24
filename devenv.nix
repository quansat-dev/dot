{
  pkgs,
  ...
}:
{
  languages.zig = {
    enable = true;
  };
  packages = with pkgs; [ lefthook ];

  enterShell = ''
    if [ -n "$DEVENV_CD" ]; then
      cd "$DEVENV_CD"
    fi
  '';
}
