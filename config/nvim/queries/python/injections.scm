; extends

; Recognize Bash scripts independently of the surrounding assignment or call.
((string
  (string_start) .
  (string_content) @injection.content .
  (string_end))
  (#match? @injection.content "^[ \t\r\n]*#![ \t]*(/bin/bash|/usr/bin/bash|/usr/bin/env[ \t]+bash)([ \t\r\n]|$)")
  (#set! injection.language "bash")
  (#set! injection.include-children))

(assignment
  left: (identifier) @identifier
  right: (string
    (string_content) @injection.content)
  (#match? @identifier ".+_bash_*.*")
  (#set! injection.language "bash"))

((string
  (string_start)
  (string_content) @marker @injection.content
  [
    (string_content) @injection.content
    (interpolation) @injection.content
  ]*
  (string_end))
  (#match? @marker "/[*][[:space:]]*[dD][uU][cC][kK][dD][bB][sS][qQ][lL][[:space:]]*[*]/")
  (#set! injection.language "duckdbsql")
  (#set! injection.include-children))
