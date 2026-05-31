# VHS tape for the `resume` feature showcase GIF.
#
#   render:  DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/Cellar/x265/4.1/lib \
#              vhs demo/resume.tape
#
# The hidden setup block points HOME at a freshly generated tree of synthetic
# sessions (demo/make-fixtures.mjs) so the demo shows all six supported tools
# without touching any real session history. Search terms avoid the letter "t"
# because the picker binds `t` to the timestamp-column toggle.
#
# The CLI flags run first, in a clean shell; the interactive picker comes last
# and ends on the printed resume command (its selection is the natural finale).

Output demo/resume.gif

Set Shell "bash"
Set FontSize 18
Set Width 1320
Set Height 700
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 95ms
Set Framerate 30

# --- hidden setup: build clean fixture data, put real `resume` on PATH ---
Hide
Type 'export PATH="/Users/helge/.nvm/versions/node/v22.22.3/bin:$PATH"'
Enter
Type 'cd /Users/helge/code/resume'
Enter
Type 'export HOME="/Users/helge/code/resume/demo/home"'
Enter
Type 'node demo/make-fixtures.mjs "$HOME"'
Enter
Type 'clear'
Enter
Show

# --- the help screen: usage and keybindings ---
Type "resume --help"
Sleep 600ms
Enter
Sleep 2.4s
Type "clear"
Enter
Sleep 300ms

# --- export every normalized session as JSON ---
Type "resume --json | head -n 16"
Sleep 500ms
Enter
Sleep 2.6s
Type "clear"
Enter
Sleep 300ms

# --- copy a resume command straight to the clipboard by id prefix ---
Type "resume --copy 7f3a9c21"
Sleep 500ms
Enter
Sleep 2.4s
Type "clear"
Enter
Sleep 400ms

# --- open the searchable picker: every tool in one list ---
Type "resume"
Sleep 500ms
Enter
Sleep 2.4s

# --- search across tool, title, cwd, id and preview ---
Type "login"
Sleep 2.2s

# --- move the selection; the details panel follows ---
Down
Sleep 600ms
Down
Sleep 1.2s

# --- toggle the exact yyyy-mm-dd hh:mm:ss timestamp column ---
Type "t"
Sleep 2.2s

# --- clear the search to see the whole list (still timestamped) ---
Ctrl+U
Sleep 1.8s
Type "t"
Sleep 700ms

# --- filter by tool name ---
Type "amp"
Sleep 1.6s
Down
Sleep 800ms

# --- Enter prints a cwd-restoring resume command (the finale) ---
Enter
Sleep 3.0s
