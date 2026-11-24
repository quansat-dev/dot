{
  pkgs,
  ...
}:
{
  languages.zig = {
    enable = true;
    version = "0.17.1";
  };
  packages = with pkgs; [ lefthook libX11 libXtst pkg-config ];

  enterShell = ''
		echo -e "\033[0;32mRun 'lefthook install' if this is your first time!\033[0m"
    if [ -n "$DEVENV_CD" ]; then
      cd "$DEVENV_CD"
    fi
  '';
}
