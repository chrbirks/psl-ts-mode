; Highlight queries for tree-sitter-psl (PSL / IEEE 1850, VHDL flavor).

; Comments and strings
(comment) @comment
(string_literal) @string
(character_literal) @string
(bit_string_literal) @string

; Numbers and constants
(integer) @number
(real) @number
(based_literal) @number
(boolean_literal) @constant.builtin

; Verification-unit and directive keywords
[
  "vunit" "vmode" "vprop" "vpkg"
  "assert" "assume" "assume_guarantee" "cover"
  "restrict" "restrict!" "fairness"
  "property" "sequence" "endpoint"
  "default" "clock" "is" "report"
  "strong" "weak"
  "const" "boolean" "hdltype"
  "within" "to" "downto" "inf"
  "forall" "in" "union"
] @keyword

; Temporal (FL) and SERE operators
(temporal_unary_op) @keyword.operator
(temporal_binary_op) @keyword.operator
(next_event_property operator: _ @keyword.operator)
[
  "->" "<->" "|->" "|=>"
  "abort" "async_abort" "sync_abort"
] @keyword.operator

; Boolean / arithmetic operators
[
  "and" "or" "nand" "nor" "xor" "xnor" "not"
  "mod" "rem" "abs"
  "=" "/=" "<" "<=" ">" ">=" "=="
  "+" "-" "*" "/" "**" "&" "&&" "||"
  "@"
] @operator

; Built-in functions
(builtin_function) @function.builtin

; Definitions
(verification_unit name: (identifier) @type)
(property_declaration name: (identifier) @function)
(sequence_declaration name: (identifier) @function)
(endpoint_declaration name: (identifier) @function)

; Punctuation
[ "(" ")" "{" "}" "[" "[*" "[+" "[=" "[->" "]" ] @punctuation.bracket
[ ";" "," ":" "." "'" ] @punctuation.delimiter

(identifier) @variable
