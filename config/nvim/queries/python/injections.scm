; extends

(assignment
  left: (identifier) @script
  right: (string
    (string_content) @injection.content)
  (#match? @script ".+_bash_*.*")
  (#set! injection.language "bash"))

(assignment
  left: (identifier) @script
  right: (string
    (string_content) @injection.content)
  (#match? @script ".*_sql_*.*")
  (#set! injection.language "sql"))

(call
  function: [
    (identifier) @method
    (attribute
      attribute: (identifier) @method)
  ]
  arguments: (argument_list
    (string
      (string_start)
      (string_content) @injection.content
      (string_end)))
  (#match? @method ".*sql.*")
  (#set! injection.language "sql"))
