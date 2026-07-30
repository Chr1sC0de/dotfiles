; extends

(paragraph
  (inline) @injection.content
  (#match? @injection.content "^::: mermaid")
  (#offset! @injection.content 1 0 0 0)
  (#set! injection.language "mermaid"))
