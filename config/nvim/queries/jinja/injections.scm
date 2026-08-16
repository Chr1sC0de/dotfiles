; extends

((content) @injection.content
  (#inject-lang-jinja!)
  (#set! injection.combined)
  (#set! injection.include-children))
