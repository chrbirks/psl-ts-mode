/**
 * @file PSL (Property Specification Language, IEEE 1850) grammar for tree-sitter.
 * @author emacs-psl-mode
 * @license GPL-3.0
 *
 * Focuses on the VHDL flavor of PSL for standalone `.psl` files. The Boolean
 * layer borrows VHDL expression syntax; this grammar implements a pragmatic
 * subset sufficient for editor syntax highlighting, indentation and navigation
 * rather than a fully conformant front-end.
 *
 * PSL inherits VHDL's case-insensitivity, so every keyword below is built with
 * the `kw`/`kws` helpers, which produce a case-insensitive token aliased back
 * to its canonical lower-case spelling. Node names in the resulting tree are
 * therefore always lower case, whatever the source used.
 */

/* eslint-disable arrow-parens */
/* eslint-disable camelcase */
/* eslint-disable-next-line spaced-comment */
/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

// Operator precedence, lowest to highest. PSL temporal/SERE operators bind
// looser than the VHDL-flavored Boolean expression operators.
const PREC = {
  logical_impl: 1,  // -> <-> (FL logical implication / equivalence)
  suffix_impl: 1,   // |->  |=>
  abort: 2,         // abort / async_abort / sync_abort
  until: 3,         // until / before
  or: 4,            // logical or / nor
  and: 5,           // logical and / nand
  not: 6,           // not
  equality: 7,      // = /= < <= > >=
  add: 8,           // + - &
  mul: 9,           // * / mod rem
  unary: 10,        // unary - +
  power: 11,        // **
  sere_or: 4,       // | within SERE
  sere_and: 5,      // & && within SERE
  sere_concat: 3,   // ; :
};

// Lexical precedence of keyword tokens over `identifier`. Because the keywords
// are regexes rather than string literals, tree-sitter cannot apply its keyword
// extraction optimization, so they need an explicit edge over the word token.
const KEYWORD_PREC = 1;

module.exports = grammar({
  name: 'psl',

  extras: $ => [
    /\s/,
    $.comment,
  ],

  word: $ => $.identifier,

  conflicts: $ => [
    [$._fl_property, $._sere],
    [$._fl_property, $.paren_expression],
    [$._fl_property, $.clocked_sere],
  ],

  rules: {
    source_file: $ => repeat($._verification_item),

    // ----------------------------------------------------------------- comments
    comment: _ => token(choice(
      seq('--', /.*/),
      seq('/*', /[^*]*\*+([^/*][^*]*\*+)*/, '/'),
    )),

    // ------------------------------------------------------- verification units
    _verification_item: $ => choice(
      $.verification_unit,
      $._directive,
      $.declaration,
      $.default_clock,
    ),

    verification_unit: $ => seq(
      field('kind', kws('vunit', 'vmode', 'vprop', 'vpkg')),
      field('name', $.identifier),
      optional($.hdl_unit_binding),
      '{',
      repeat($._vunit_item),
      '}',
      optional(';'),
    ),

    // The HDL design unit a verification unit is bound to: `vunit u (dut) {..}`.
    // Unrelated to `inherit_declaration` below.
    hdl_unit_binding: $ => seq(
      '(',
      field('hdl_unit', sep1($._name, ',')),
      ')',
    ),

    _vunit_item: $ => choice(
      $._directive,
      $.declaration,
      $.default_clock,
      $.inherit_declaration,
      $.override_declaration,
    ),

    // Inherit_Spec ::= [nontransitive] inherit vunit_Name {, vunit_Name} ;
    inherit_declaration: $ => seq(
      optional(kw('nontransitive')),
      kw('inherit'),
      sep1($._name, ','),
      ';',
    ),

    // Override_Spec ::= override Name_List ;
    override_declaration: $ => seq(
      kw('override'),
      sep1($._name, ','),
      ';',
    ),

    // ----------------------------------------------------------- default clock
    default_clock: $ => seq(
      kw('default'), kw('clock'),
      kw('is'),
      field('clock', $._clock_expr),
      ';',
    ),

    _clock_expr: $ => $._boolean,

    // -------------------------------------------------------------- directives
    _directive: $ => choice(
      $.assert_directive,
      $.assume_directive,
      $.cover_directive,
      $.restrict_directive,
      $.fairness_directive,
    ),

    // PSL_Directive ::= [ Label : ] Verification_Directive
    _directive_label: $ => seq(field('label', $.identifier), ':'),

    assert_directive: $ => seq(
      optional($._directive_label),
      kw('assert'),
      field('property', $._property),
      optional($.report_clause),
      optional($.severity_clause),
      ';',
    ),

    assume_directive: $ => seq(
      optional($._directive_label),
      kws('assume', 'assume_guarantee'),
      field('property', $._property),
      ';',
    ),

    // The directive argument is a single sequence: a braced SERE, a clocked
    // braced SERE, or a sequence name/boolean. A bare top-level `a ; b`
    // concatenation is not used here, and allowing it would make the
    // terminating `;` ambiguous with a following directive label.
    _directive_sequence: $ => choice(
      $.braced_sere,
      $.clocked_sere,
      $._boolean,
    ),

    cover_directive: $ => seq(
      optional($._directive_label),
      kw('cover'),
      field('sequence', $._directive_sequence),
      optional($.report_clause),
      ';',
    ),

    restrict_directive: $ => seq(
      optional($._directive_label),
      choice(kw('restrict'), kw('restrict!')),
      field('sequence', $._directive_sequence),
      ';',
    ),

    // Two distinct forms: the weak/strong-modified `fairness B` and the
    // separate `strong_fairness B, B` keyword (IEEE 1850 §7).
    fairness_directive: $ => seq(
      optional($._directive_label),
      choice(
        seq(
          optional(kws('strong', 'weak')),
          kw('fairness'),
          $._boolean,
          optional(seq(',', $._boolean)),
        ),
        seq(
          kw('strong_fairness'),
          $._boolean, ',', $._boolean,
        ),
      ),
      ';',
    ),

    report_clause: $ => seq(kw('report'), $.string_literal),

    // VHDL severity clause, accepted by GHDL on PSL assertions.
    severity_clause: $ => seq(
      kw('severity'),
      field('level', kws('note', 'warning', 'error', 'failure')),
    ),

    // ----------------------------------------------------------- declarations
    declaration: $ => choice(
      $.property_declaration,
      $.sequence_declaration,
      $.endpoint_declaration,
    ),

    property_declaration: $ => seq(
      kw('property'),
      field('name', $.identifier),
      optional($.formal_parameter_list),
      kw('is'),
      field('definition', $._property),
      ';',
    ),

    sequence_declaration: $ => seq(
      kw('sequence'),
      field('name', $.identifier),
      optional($.formal_parameter_list),
      kw('is'),
      field('definition', $._sere),
      ';',
    ),

    endpoint_declaration: $ => seq(
      kw('endpoint'),
      field('name', $.identifier),
      optional($.formal_parameter_list),
      kw('is'),
      field('definition', $._sere),
      ';',
    ),

    formal_parameter_list: $ => seq(
      '(',
      sep1($.formal_parameter, ';'),
      ')',
    ),

    // NOTE: because `word: $ => $.identifier`, every type-class keyword below
    // (bit, bitvector, numeric, string, ...) becomes globally reserved and can
    // no longer be lexed as an identifier anywhere in a .psl file. These are
    // VHDL type names rather than typical signal names, so the impact is small.
    formal_parameter: $ => seq(
      optional(kws('const', 'mutable')),
      optional(kws('boolean', 'bit', 'bitvector', 'numeric', 'string',
                   'property', 'sequence', 'hdltype')),
      sep1($.identifier, ','),
    ),

    // -------------------------------------------------------------- properties
    _property: $ => choice(
      $._fl_property,
      $.clocked_property,
      $.replicated_property,
    ),

    clocked_property: $ => prec.left(seq(
      $._fl_property,
      '@',
      $._clock_expr,
    )),

    // forall replicated property
    replicated_property: $ => prec.right(seq(
      kw('forall'),
      field('param', $.identifier),
      optional(seq(kw('in'), $._value_set)),
      ':',
      field('property', $._property),
    )),

    _value_set: $ => choice(
      seq('{', sep1($._value_range, ','), '}'),
      $._boolean,
    ),

    _value_range: $ => choice(
      seq($._number, kw('to'), $._number),
      $._boolean,
    ),

    _fl_property: $ => choice(
      $._boolean,
      $.braced_sere,
      $.unary_temporal,
      $.next_event_property,
      $.binary_temporal,
      $.logical_implication,
      $.suffix_implication,
      $.abort_property,
      $.paren_property,
      $.strong_sequence,
    ),

    // NOTE: a braced SERE {..} IS a valid FL property in PSL; sequences may
    // appear as bare properties, as suffix-implication antecedents, and in
    // cover/restrict directives.

    paren_property: $ => seq('(', $._property, ')'),

    logical_implication: $ => prec.right(PREC.logical_impl, seq(
      field('left', $._fl_property),
      field('operator', choice('->', '<->')),
      field('right', $._fl_property),
    )),

    // Parameterized next/next_a/next_e with optional count: next[N] p
    temporal_count: $ => seq('[', $._count, ']'),

    unary_temporal: $ => prec.right(PREC.until, seq(
      field('operator', $.temporal_unary_op),
      optional($.temporal_count),
      field('operand', $._fl_property),
    )),

    // The single-letter LTL spellings (X, F, G, U, W) are deliberately absent:
    // `word: $ => $.identifier` would reserve them globally, and `X`/`F`/`G`
    // are plausible HDL signal names. The VHDL flavor spells these
    // `next`/`eventually!`/`always`/`until`/`before`.
    temporal_unary_op: _ => kws(
      'always', 'never',
      'next', 'next!',
      'next_a', 'next_a!', 'next_e', 'next_e!',
      'eventually!',
    ),

    // next_event family: next_event(b)(p), next_event_a(b)[k](p), etc.
    next_event_property: $ => prec.right(seq(
      field('operator', kws(
        'next_event', 'next_event!',
        'next_event_a', 'next_event_a!',
        'next_event_e', 'next_event_e!',
      )),
      '(',
      field('event', $._boolean),
      ')',
      optional($.temporal_count),
      '(',
      field('operand', $._fl_property),
      ')',
    )),

    binary_temporal: $ => prec.left(PREC.until, seq(
      field('left', $._fl_property),
      field('operator', $.temporal_binary_op),
      field('right', $._fl_property),
    )),

    temporal_binary_op: _ => kws(
      'until', 'until!', 'until_', 'until_!',
      'before', 'before!', 'before_', 'before_!',
    ),

    suffix_implication: $ => prec.right(PREC.suffix_impl, seq(
      field('antecedent', $._sere),
      field('operator', choice('|->', '|=>')),
      field('consequent', choice($._fl_property, $.braced_sere)),
    )),

    abort_property: $ => prec.left(PREC.abort, seq(
      field('property', $._fl_property),
      field('operator', kws('abort', 'async_abort', 'sync_abort')),
      field('condition', $._boolean),
    )),

    // Strong sequence: {..}!
    strong_sequence: $ => prec(1, seq($.braced_sere, '!')),

    // -------------------------------------------------------------------- SEREs
    _sere: $ => choice(
      $._boolean,
      $.braced_sere,
      $.sere_concat,
      $.sere_or,
      $.sere_union,
      $.sere_and,
      $.sere_within,
      $.sere_repetition,
      $.clocked_sere,
    ),

    // Kept visible (rather than hidden behind a leading underscore) so that
    // editors have a node to anchor indentation of multi-line `{ .. }` on.
    braced_sere: $ => seq('{', sep1($._sere, ';'), '}'),

    clocked_sere: $ => prec.left(seq($.braced_sere, '@', $._clock_expr)),

    sere_concat: $ => prec.left(PREC.sere_concat, seq(
      $._sere, choice(';', ':'), $._sere,
    )),

    sere_or: $ => prec.left(PREC.sere_or, seq($._sere, '|', $._sere)),

    sere_union: $ => prec.left(PREC.sere_or, seq($._sere, kw('union'), $._sere)),

    sere_and: $ => prec.left(PREC.sere_and, seq(
      $._sere, choice('&', '&&'), $._sere,
    )),

    sere_within: $ => prec.left(PREC.sere_or, seq(
      $._sere, kw('within'), $._sere,
    )),

    sere_repetition: $ => prec(PREC.unary, seq(
      $._sere,
      $.repeat_count,
    )),

    repeat_count: $ => choice(
      seq('[*', optional($._count), ']'),
      seq('[+', ']'),
      seq('[=', $._count, ']'),
      seq('[->', optional($._count), ']'),
    ),

    // A count is any statically-evaluable expression, e.g. a literal or a
    // `const` formal parameter: next[n], valid[*2 to depth].
    _count: $ => choice(
      $._boolean,
      seq($._boolean, kw('to'), choice($._boolean, kw('inf'))),
    ),

    // ----------------------------------------- Boolean layer (VHDL expressions)
    _boolean: $ => choice(
      $.binary_expression,
      $.unary_expression,
      $.builtin_call,
      $.paren_expression,
      $._primary,
    ),

    paren_expression: $ => seq('(', $._boolean, ')'),

    unary_expression: $ => prec(PREC.not, seq(
      field('operator', choice(kw('not'), '-', '+', kw('abs'))),
      field('operand', $._boolean),
    )),

    binary_expression: $ => {
      const table = [
        [PREC.or, choice(kw('or'), kw('nor'), kw('xor'), kw('xnor'), '||')],
        [PREC.and, choice(kw('and'), kw('nand'), '&&')],
        [PREC.equality, choice('=', '/=', '<', '<=', '>', '>=', '==')],
        [PREC.add, choice('+', '-', '&')],
        [PREC.mul, choice('*', '/', kw('mod'), kw('rem'))],
        [PREC.power, '**'],
      ];
      return choice(...table.map(([precedence, operator]) =>
        prec.left(precedence, seq(
          field('left', $._boolean),
          field('operator', operator),
          field('right', $._boolean),
        ))));
    },

    // `ended` takes a Sequence argument, so a braced SERE is accepted here
    // alongside Boolean arguments: both `ended(seq_name)` and `ended({a;b})`
    // parse.
    builtin_call: $ => seq(
      field('function', $.builtin_function),
      '(',
      sep1(choice($._boolean, $.braced_sere), ','),
      ')',
    ),

    builtin_function: _ => kws(
      'prev', 'stable', 'rose', 'fell', 'ended',
      'countones', 'onehot', 'onehot0', 'isunknown',
      'nondet', 'nondet_vector',
    ),

    _primary: $ => choice(
      $._name,
      $._number,
      $.bit_string_literal,
      $.character_literal,
      $.string_literal,
      $.boolean_literal,
    ),

    // --------------------------------------------------------------- names
    _name: $ => choice(
      $.identifier,
      $.selected_name,
      $.indexed_name,
      $.attribute_name,
    ),

    selected_name: $ => prec.left(seq($._name, '.', $.identifier)),

    // VHDL slices: sig(3 downto 0) or sig(0 to 3) or multi-dim sig(i, j)
    indexed_name: $ => prec.left(seq(
      $._name, '(', sep1(choice($.range_constraint, $._boolean), ','), ')',
    )),

    range_constraint: $ => seq(
      $._boolean, kws('to', 'downto'), $._boolean,
    ),

    attribute_name: $ => prec.left(seq(
      $._name, "'", $.identifier,
      optional(seq('(', sep1($._boolean, ','), ')')),
    )),

    // --------------------------------------------------------------- literals
    _number: $ => choice($.integer, $.real, $.based_literal),

    integer: _ => token(/[0-9][0-9_]*/),

    real: _ => token(/[0-9][0-9_]*\.[0-9][0-9_]*([eE][+-]?[0-9]+)?/),

    based_literal: _ => token(
      /[0-9]+#[0-9a-fA-F][0-9a-fA-F_]*(\.[0-9a-fA-F_]+)?#([eE][+-]?[0-9]+)?/,
    ),

    bit_string_literal: _ => token(
      /[bBoOxXdD]?"[0-9a-fA-F_]*"/,
    ),

    character_literal: _ => token(/'[^']'/),

    string_literal: _ => token(/"([^"\\]|\\.|"")*"/),

    boolean_literal: _ => kws('true', 'false'),

    identifier: _ => /[a-zA-Z][a-zA-Z0-9_]*|\\[^\\]+\\/,
  },
});

/**
 * Creates a rule matching one or more `rule` separated by `separator`.
 * @param {RuleOrLiteral} rule
 * @param {RuleOrLiteral} separator
 * @returns {SeqRule}
 */
function sep1(rule, separator) {
  return seq(rule, repeat(seq(separator, rule)));
}

/**
 * Creates a case-insensitive keyword token that still appears in the tree
 * under its canonical (lower-case) spelling, so that editor queries can match
 * on the literal keyword regardless of how it was written in the source.
 * @param {string} word canonical lower-case spelling
 * @returns {AliasRule}
 */
function kw(word) {
  const pattern = word
    .split('')
    .map(c => (/[a-z]/.test(c) ? `[${c}${c.toUpperCase()}]` : c.replace(/[.*+?^${}()|[\]\\!]/g, '\\$&')))
    .join('');
  return alias(token(prec(KEYWORD_PREC, new RegExp(pattern))), word);
}

/**
 * `choice` over `kw` for each of the given keywords.
 * @param {...string} words
 * @returns {ChoiceRule}
 */
function kws(...words) {
  return choice(...words.map(kw));
}
