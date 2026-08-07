; extends

(assignment
  left: (identifier) @identifier
  right: (string
    (string_content) @injection.content)
  (#match? @identifier ".+_bash_*.*")
  (#set! injection.language "bash"))

(assignment
  left: (identifier) @identifier
  right: (string
    ((string_content)
      (interpolation)*)+ @injection.content)
  (#match? @identifier ".*sql*.*")
  (#set! injection.language "sql"))

(call
  function: [
    (identifier) @identifier
    (attribute
      attribute: (identifier) @identifier)
  ]
  arguments: (argument_list
    (string
      ((string_content)
        (interpolation)*)+ @injection.content))
  (#match? @identifier ".*sql.*")
  (#set! injection.language "sql"))

(keyword_argument
  name: (identifier) @identifier
  value: (lambda
    body: (parenthesized_expression
      (string
        ((string_content)
          (interpolation)*)+ @injection.content)))
  (#match? @identifier ".*sql.*")
  (#set! injection.language "sql"))
