; extends

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
