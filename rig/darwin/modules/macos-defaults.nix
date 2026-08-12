{ ... }:

{
  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyleSwitchesAutomatically = true;
      AppleKeyboardUIMode = 3;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
    };

    dock = {
      autohide = true;
      mru-spaces = false;
      show-recents = false;
    };

    finder = {
      AppleShowAllExtensions = true;
      FXPreferredViewStyle = "Nlsv";
      ShowPathbar = true;
      ShowStatusBar = true;
    };

    # Third-party app prefs (equivalent to `defaults write <domain> …`).
    # Maccy: poll clipboard every 0.1s (default is 0.5).
    CustomUserPreferences = {
      "org.p0deje.Maccy" = {
        clipboardCheckInterval = 0.1;
      };
    };
  };
}
