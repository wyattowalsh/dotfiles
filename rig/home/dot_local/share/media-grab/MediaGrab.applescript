property appName : "MediaGrab"
property appVersion : "1.3.0"

on run
  my showMainMenu(missing value)
end run

on open droppedItems
  my showMainMenu(my URLFromDroppedItems(droppedItems))
end open

on open location theURL
  my showMainMenu(theURL)
end open location

on showMainMenu(seedURL)
  set choices to {¬
    "🎬 Max video — best source quality", ¬
    "🇬🇧 Max video — prefer English audio", ¬
    "🎧 Max audio — preserve source quality", ¬
    "🇬🇧 Max audio — prefer English", ¬
    "🎯 Exact format — inspect and choose IDs", ¬
    "📦 Archive — safe metadata + English subtitles", ¬
    "🕵️ Exhaustive archive — comments + raw metadata", ¬
    "📚 Playlist / channel — maximum quality", ¬
    "🔴 Live stream — record from earliest available", ¬
    "📱 Compatible MP4 — may reduce resolution", ¬
    "🛠 Utilities…"}
  set picked to choose from list choices with title appName with prompt "What should the tiny ghost steal from the internet?" default items {item 1 of choices} OK button name "Continue" cancel button name "Cancel"
  if picked is false then return
  set selectedMode to item 1 of picked
  if selectedMode is "🛠 Utilities…" then
    my showUtilities()
    return
  end if
  if selectedMode is "🎬 Max video — best source quality" then
    set modeName to "video"
  else if selectedMode is "🇬🇧 Max video — prefer English audio" then
    set modeName to "video-en"
  else if selectedMode is "🎧 Max audio — preserve source quality" then
    set modeName to "audio"
  else if selectedMode is "🇬🇧 Max audio — prefer English" then
    set modeName to "audio-en"
  else if selectedMode is "🎯 Exact format — inspect and choose IDs" then
    set modeName to "exact"
  else if selectedMode is "📦 Archive — safe metadata + English subtitles" then
    set modeName to "archive"
  else if selectedMode is "🕵️ Exhaustive archive — comments + raw metadata" then
    set archiveDialog to display dialog "Raw info JSON may contain personal/session fields. Choose subtitle scope:" with title appName buttons {"Cancel", "English only", "All languages"} default button "English only" cancel button "Cancel" with icon caution
    if button returned of archiveDialog is "All languages" then
      set modeName to "archive-full-allsubs"
    else
      set modeName to "archive-full"
    end if
  else if selectedMode is "📚 Playlist / channel — maximum quality" then
    set modeName to "playlist"
  else if selectedMode is "🔴 Live stream — record from earliest available" then
    set modeName to "live"
  else
    display dialog "Compatible MP4 prefers H.264/AAC and may choose a lower resolution." with title appName buttons {"Cancel", "Continue"} default button "Continue" cancel button "Cancel" with icon caution
    set modeName to "compatible"
  end if
  set defaultURL to ""
  if seedURL is not missing value then
    set defaultURL to seedURL as text
  else
    try
      set clipboardText to the clipboard as text
      if my looksLikeURL(clipboardText) then set defaultURL to clipboardText
    end try
  end if
  set resultDialog to display dialog "Paste one video, Reel, playlist, channel, or live-stream URL:" with title appName default answer defaultURL buttons {"Cancel", "Download"} default button "Download" cancel button "Cancel"
  set urlText to my trimText(text returned of resultDialog)
  if urlText is "" then return
  if not my looksLikeURL(urlText) then
    display alert "That does not look like a web URL." message "MediaGrab accepts http:// and https:// links." as warning
    return
  end if
  my launchCommand({modeName, urlText})
end showMainMenu

on showUtilities()
  set choices to {"🩺 Run diagnostics", "🌐 Run network diagnostic", "🧰 Repair Desktop app", "⚙️ Open settings", "📂 Open downloads", "📜 Open logs", "💻 Open source", "ℹ️ About MediaGrab"}
  set picked to choose from list choices with title appName with prompt "Utility drawer:" default items {item 1 of choices} OK button name "Open" cancel button name "Cancel"
  if picked is false then return
  set selectedUtility to item 1 of picked
  if selectedUtility is "🩺 Run diagnostics" then
    my launchCommand({"doctor"})
  else if selectedUtility is "🌐 Run network diagnostic" then
    my launchCommand({"doctor", "--network"})
  else if selectedUtility is "🧰 Repair Desktop app" then
    my launchCommand({"install", "--apply"})
  else if selectedUtility is "⚙️ Open settings" then
    my runBackend({"open-settings"})
  else if selectedUtility is "📂 Open downloads" then
    my runBackend({"open-downloads"})
  else if selectedUtility is "📜 Open logs" then
    my runBackend({"open-logs"})
  else if selectedUtility is "💻 Open source" then
    do shell script "/usr/bin/open https://github.com/wyattowalsh/dotfiles/tree/main/rig/home/dot_local/share/media-grab"
  else
    display dialog "MediaGrab " & appVersion & return & return & "A tiny local front end for yt-dlp, FFmpeg, and Deno." & return & "The ghost is smug because it has no analytics dashboard." with title appName buttons {"OK"} default button "OK"
  end if
end showUtilities

on launchCommand(argumentsList)
  set launcherPath to POSIX path of (path to home folder) & ".local/libexec/media-grab/launch-media-grab"
  set commandText to quoted form of launcherPath
  repeat with argumentValue in argumentsList
    set commandText to commandText & space & quoted form of (argumentValue as text)
  end repeat
  try
    do shell script commandText
  on error errorMessage
    display alert "MediaGrab could not start." message errorMessage as critical
  end try
end launchCommand

on runBackend(argumentsList)
  set backendPath to POSIX path of (path to home folder) & ".local/bin/media-grab"
  set commandText to quoted form of backendPath
  repeat with argumentValue in argumentsList
    set commandText to commandText & space & quoted form of (argumentValue as text)
  end repeat
  try
    do shell script commandText
  on error errorMessage
    display alert "MediaGrab utility failed." message errorMessage as critical
  end try
end runBackend

on URLFromDroppedItems(droppedItems)
  repeat with droppedItem in droppedItems
    set itemPath to POSIX path of droppedItem
    if itemPath ends with ".webloc" then
      try
        set foundURL to do shell script "/usr/bin/plutil -extract URL raw " & quoted form of itemPath
        if my looksLikeURL(foundURL) then return my trimText(foundURL)
      end try
    else if itemPath ends with ".url" then
      try
        set foundURL to do shell script "/usr/bin/grep -m 1 '^URL=' " & quoted form of itemPath & " | /usr/bin/cut -c 5-"
        if my looksLikeURL(foundURL) then return my trimText(foundURL)
      end try
    else if itemPath ends with ".txt" then
      try
        set foundURL to do shell script "/usr/bin/head -c 16384 " & quoted form of itemPath & " | /usr/bin/grep -E -o -m 1 'https?://[^[:space:]]+'"
        if my looksLikeURL(foundURL) then return my trimText(foundURL)
      end try
    end if
  end repeat
  return missing value
end URLFromDroppedItems

on looksLikeURL(candidateText)
  try
    set candidateText to candidateText as text
    return candidateText starts with "https://" or candidateText starts with "http://"
  on error
    return false
  end try
end looksLikeURL

on trimText(sourceText)
  set sourceText to sourceText as text
  set whitespace to {space, tab, return, linefeed}
  repeat while sourceText is not "" and character 1 of sourceText is in whitespace
    if (length of sourceText) is 1 then set sourceText to "" else set sourceText to text 2 thru -1 of sourceText
  end repeat
  repeat while sourceText is not "" and character -1 of sourceText is in whitespace
    if (length of sourceText) is 1 then set sourceText to "" else set sourceText to text 1 thru -2 of sourceText
  end repeat
  return sourceText
end trimText
