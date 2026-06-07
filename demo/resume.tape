# VHS tape for the `resume` feature showcase GIF.
#
#   render:  DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/Cellar/x265/4.1/lib \
#              vhs demo/resume.tape
#
# The hidden setup block points HOME at a freshly generated tree of synthetic
# sessions (demo/make-fixtures.mjs) so the demo shows all nine supported tools
# without touching any real session history.
#
# The interactive picker leads (it's the star), and the CLI flags follow.
#
# Picker keys shown: type-to-filter, ↑/↓ move, Tab expand preview,
# Ctrl+A cycle agent, Ctrl+T toggle exact timestamps, Ctrl+U clear,
# Enter copy-to-clipboard + print + exit.

Output demo/resume.gif

Set Shell "bash"
Set FontSize 18
Set Width 1320
Set Height 760
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 90ms
Set Framerate 30

# --- hidden setup: build clean fixture data, put real `resume` on PATH ---
# This environment exports NO_COLOR / FORCE_COLOR=0; clear them so the picker
# renders its blue branding and cyan legend in the recording.
Hide
Type 'export PATH="/Users/helge/.nvm/versions/node/v22.22.3/bin:$PATH"'
Enter
Type 'unset NO_COLOR CLICOLOR CLICOLOR_FORCE FORCE_COLOR; export TERM=xterm-256color'
Enter
Type 'cd /Users/helge/code/resume'
Enter
Type 'shopt -s expand_aliases; alias resume="node /Users/helge/code/resume/dist/resume.mjs"'
Enter
Type 'export HOME="/Users/helge/code/resume/demo/home"'
Enter
Type 'node demo/make-fixtures.mjs "$HOME"'
Enter
Type 'clear'
Enter
Show

# --- open the searchable picker: every tool in one list ---
Type "resume"
Sleep 500ms
Enter
Sleep 2.4s

# --- type-to-filter across tool, title, cwd, id and preview ---
Type "login"
Sleep 2.2s

# --- move the selection; the details panel follows ---
Down
Sleep 600ms
Down
Sleep 1.2s

# --- Tab expands the preview panel for the selected session ---
Tab
Sleep 2.2s
Tab
Sleep 800ms

# --- Ctrl+T toggles the exact yyyy-mm-dd hh:mm:ss timestamp column ---
Ctrl+T
Sleep 2.2s
Ctrl+T
Sleep 700ms

# --- clear the query to see the whole list again ---
Ctrl+U
Sleep 1.8s

# --- Ctrl+A cycles the agent filter: all → Claude → Codex → Amp → … ---
Ctrl+A
Sleep 1.4s
Ctrl+A
Sleep 1.4s
Ctrl+A
Sleep 1.6s

# --- now filtered to a single agent; move to the session we want ---
Down
Sleep 800ms

# --- Enter copies the cwd-restoring resume command and prints it ---
Enter
Sleep 2.6s
Type "clear"
Enter
Sleep 400ms

# --- the help screen: usage and keybindings ---
Type "resume --help"
Sleep 500ms
Enter
Sleep 2.6s
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

# --- copy a resume command straight to the clipboard by id prefix (finale) ---
Type "resume --copy 7f3a9c21"
Sleep 500ms
Enter
Sleep 3.0s
