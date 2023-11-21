on run {spaceName}
	tell application "Arc"
		tell front window
			tell space spaceName to focus
		end tell
		activate
	end tell
end run