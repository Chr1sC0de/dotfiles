; extends

; Recipe bodies include shell injections, which otherwise override Just's
; interpolation captures (for example inside a quoted shell string).
((value
  (identifier) @variable)
  (#has-ancestor? @variable interpolation)
  (#set! priority 110))

(interpolation
  [
    "{{"
    "}}"
  ] @punctuation.bracket
  (#set! priority 110))
