on run argv
  set folderPath to item 1 of argv
  set appItemName to item 2 of argv
  set backgroundPath to item 3 of argv

  tell application "Finder"
    set targetFolder to POSIX file folderPath as alias
    open targetFolder
    delay 1

    set targetWindow to window 1
    set current view of targetWindow to icon view
    set toolbar visible of targetWindow to false
    set statusbar visible of targetWindow to false
    set bounds of targetWindow to {120, 120, 760, 480}

    set viewOptions to icon view options of targetWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 144
    set background picture of viewOptions to POSIX file backgroundPath

    set position of item appItemName of targetFolder to {170, 185}
    set position of item "Applications" of targetFolder to {470, 185}

    close targetWindow
    open targetFolder
    update targetFolder without registering applications
    delay 1
  end tell
end run
