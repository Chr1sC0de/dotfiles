; extends

(string
  (string_content) @injection.content
  (#match? @injection.content "#!/.*bash")
  (#set! injection.language "bash"))

(assignment
  left: (identifier) @script
  right: (string
    (string_content) @injection.content)
  (#match? @script ".+_bash_script|.+_bash_cmd")
  (#set! injection.language "bash"))
