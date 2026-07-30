; extends

; bash
(string
  (string_content) @injection.content
  (#match? @injection.content "#!/.*bash")
  (#set! injection.language "bash"))

(assignment
  left: (identifier) @script
  right: (string
    (string_content) @injection.content)
  (#match? @script ".+_bash_*.*")
  (#set! injection.language "bash"))

; sql
(string
  (string_content) @injection.content
  (#match? @injection.content "--sql")
  (#set! injection.language "sql"))

(assignment
  left: (identifier) @script
  right: (string
    (string_content) @injection.content)
  (#match? @script ".*_sql_*.*")
  (#set! injection.language "sql"))

; jinja
(assignment
  left: (identifier) @script
  right: (string
    (string_content) @injection.content)
  (#match? @script ".+_jinja_*.*")
  (#set! injection.language "jinja"))

; python
(string
  (string_content) @injection.content
  (#match? @injection.content "#!/.*python")
  (#set! injection.language "python"))

(assignment
  left: (identifier) @script
  right: (string
    (string_content) @injection.content)
  (#match? @script ".+_python_*.*")
  (#set! injection.language "python"))

(call
  function: (attribute
    object: (identifier)
    attribute: (identifier) @method)
  arguments: (argument_list
    (string
      (string_start)
      (string_content) @injection.content
      (string_end)))
  (#match? @method "sql")
  (#set! injection.language "sql"))
