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
		echo -e "\033[0;32mRun 'lefthook install' if this is your first time!\033[0m"
    if [ -n "$DEVENV_CD" ]; then
      cd "$DEVENV_CD"
    fi
  '';
}
