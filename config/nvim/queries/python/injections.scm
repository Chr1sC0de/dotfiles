; extends

(assignment
  left: (identifier) @name
  right: (string
    (string_content) @injection.content)
  (#match? @name ".+_bash_*.*")
  (#set! injection.language "bash"))

(assignment
  left: (identifier) @name
  right: (string
    (string_content) @injection.content)
  (#match? @name ".*sql*.*")
  (#set! injection.language "sql"))

(call
  function: [
    (identifier) @name
    (attribute
      attribute: (identifier) @name)
  ]
  arguments: (argument_list
    (string
      (string_start)
      (string_content) @injection.content
      (string_end)))
  (#match? @name ".*sql.*")
  (#set! injection.language "sql"))

(keyword_argument
  name: (identifier) @name
  (lambda
    (string
      (string_content) @injection.content))
  (#match? @name ".*sql.*")
  (#set! injection.language "sql"))
