{ config, ... }:

let
  primaryUser = config.system.primaryUser;
  primaryHome = config.users.users.${primaryUser}.home;
in
{
  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyleSwitchesAutomatically = true;
      AppleKeyboardUIMode = 3;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      ApplePressAndHoldEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
      NSDocumentSaveNewDocumentsToCloud = false;
    };

    dock = {
      autohide = true;
      mru-spaces = false;
      show-recents = false;
    };

    trackpad = {
      Clicking = true;
      TrackpadThreeFingerDrag = true;
    };

    finder = {
      AppleShowAllExtensions = true;
      FXPreferredViewStyle = "Nlsv";
      ShowPathbar = true;
      ShowStatusBar = true;
      FXDefaultSearchScope = "SCcf";
      FXEnableExtensionChangeWarning = false;
      _FXSortFoldersFirst = true;
      ShowHardDrivesOnDesktop = false;
      ShowExternalHardDrivesOnDesktop = false;
      ShowRemovableMediaOnDesktop = false;
      ShowMountedServersOnDesktop = false;
    };

    # Third-party app prefs (equivalent to `defaults write <domain> …`).
    # Maccy: poll clipboard every 0.1s (default is 0.5).
    CustomUserPreferences = {
      "org.p0deje.Maccy" = {
        clipboardCheckInterval = 0.1;
      };
      "com.colliderli.iina" = {
        currentInputConfigName = "IINA-QoL";
        # 3 = passToMpv so WHEEL_* pan bindings in IINA-QoL.conf run.
        # (1 = seek, 4 = playbackSpeed — those fight Cmd+scroll zoom / pan.)
        horizontalScrollAction = 3;
        verticalScrollAction = 3;
        # 0 = none. Hammerspoon posts a middle-click poke before zoom F-keys;
        # IINA 4 = togglePIP (live 1.5.0-beta1 default-was-none, this Mac was 4).
        middleClickAction = 0;
        playbackSpeedScrollAmount = 3;
        screenshotSaveToFile = true;
        screenshotCopyToClipboard = true;
        screenShotIncludeSubtitle = true;
        screenshotShowPreview = true;
        screenShotFormat = 0;
        useMediaKeys = true;
        enableAdvancedSettings = true;
        fullScreenWhenOpen = false;
        audioDriverEnableAVFoundation = true;
        enableThumbnailPreview = true;
        enableThumbnailForRemoteFiles = true;
        thumbnailWidth = 480;
        maxThumbnailPreviewCacheSize = 1024;
        useUserDefinedConfDir = true;
        userDefinedConfDir = "${primaryHome}/.config/iina-mpv";
      };
    };
  };
}
