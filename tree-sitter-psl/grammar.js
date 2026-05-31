/**
 * @file PSL (Property Specification Language, IEEE 1850) grammar for tree-sitter.
 * @author emacs-psl-mode
 * @license GPL-3.0
 *
 * Focuses on the VHDL flavor of PSL for standalone `.psl` files. The Boolean
 * layer borrows VHDL expression syntax; this grammar implements a pragmatic
 * subset sufficient for editor syntax highlighting, indentation and navigation
 * rather than a fully conformant front-end.
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
      field('kind', choice('vunit', 'vmode', 'vprop', 'vpkg')),
      field('name', $.identifier),
      optional($.inherit_clause),
      '{',
      repeat($._vunit_item),
      '}',
      optional(';'),
    ),

    inherit_clause: $ => seq(
      '(',
      field('hdl_unit', sep1($._name, ',')),
      ')',
    ),

    _vunit_item: $ => choice(
      $._directive,
      $.declaration,
      $.default_clock,
      $.verification_unit,
    ),

    // ----------------------------------------------------------- default clock
    default_clock: $ => seq(
      'default', 'clock',
      'is',
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

    assert_directive: $ => seq(
      'assert',
      field('property', $._property),
      optional($.report_clause),
      ';',
    ),

    assume_directive: $ => seq(
      choice('assume', 'assume_guarantee'),
      field('property', $._property),
      ';',
    ),

    cover_directive: $ => seq(
      'cover',
      field('sequence', $._sere),
      optional($.report_clause),
      ';',
    ),

    restrict_directive: $ => seq(
      choice('restrict', 'restrict!'),
      field('sequence', $._sere),
      ';',
    ),

    fairness_directive: $ => seq(
      optional(choice('strong', 'weak')),
      'fairness',
      $._boolean,
      optional(seq(',', $._boolean)),
      ';',
    ),

    report_clause: $ => seq('report', $.string_literal),

    // ----------------------------------------------------------- declarations
    declaration: $ => choice(
      $.property_declaration,
      $.sequence_declaration,
      $.endpoint_declaration,
    ),

    property_declaration: $ => seq(
      'property',
      field('name', $.identifier),
      optional($.formal_parameter_list),
      'is',
      field('definition', $._property),
      ';',
    ),

    sequence_declaration: $ => seq(
      'sequence',
      field('name', $.identifier),
      optional($.formal_parameter_list),
      'is',
      field('definition', $._sere),
      ';',
    ),

    endpoint_declaration: $ => seq(
      'endpoint',
      field('name', $.identifier),
      optional($.formal_parameter_list),
      'is',
      field('definition', $._sere),
      ';',
    ),

    formal_parameter_list: $ => seq(
      '(',
      sep1($.formal_parameter, ';'),
      ')',
    ),

    formal_parameter: $ => seq(
      choice('const', 'boolean', 'property', 'sequence', 'hdltype'),
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
      'forall',
      field('param', $.identifier),
      optional(seq('in', $._value_set)),
      ':',
      field('property', $._property),
    )),

    _value_set: $ => choice(
      seq('{', sep1($._value_range, ','), '}'),
      $._boolean,
    ),

    _value_range: $ => choice(
      seq($._number, 'to', $._number),
      $._boolean,
    ),

    _fl_property: $ => choice(
      $._boolean,
      $._braced_sere,
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

    temporal_unary_op: _ => choice(
      'always', 'never',
      'next', 'next!',
      'next_a', 'next_a!', 'next_e', 'next_e!',
      'eventually!',
      'X', 'X!', 'F', 'G',
    ),

    // next_event family: next_event(b)(p), next_event_a(b)[k](p), etc.
    next_event_property: $ => prec.right(seq(
      field('operator', choice(
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

    temporal_binary_op: _ => choice(
      'until', 'until!', 'until_', 'until_!',
      'before', 'before!', 'before_', 'before_!',
      'U', 'W',
    ),

    suffix_implication: $ => prec.right(PREC.suffix_impl, seq(
      field('antecedent', $._sere),
      field('operator', choice('|->', '|=>')),
      field('consequent', choice($._fl_property, $._braced_sere)),
    )),

    abort_property: $ => prec.left(PREC.abort, seq(
      field('property', $._fl_property),
      field('operator', choice('abort', 'async_abort', 'sync_abort')),
      field('condition', $._boolean),
    )),

    // Strong sequence: {..}!
    strong_sequence: $ => prec(1, seq($._braced_sere, '!')),

    // -------------------------------------------------------------------- SEREs
    _sere: $ => choice(
      $._boolean,
      $._braced_sere,
      $.sere_concat,
      $.sere_or,
      $.sere_union,
      $.sere_and,
      $.sere_within,
      $.sere_repetition,
      $.clocked_sere,
    ),

    _braced_sere: $ => seq('{', sep1($._sere, ';'), '}'),

    clocked_sere: $ => prec.left(seq($._braced_sere, '@', $._clock_expr)),

    sere_concat: $ => prec.left(PREC.sere_concat, seq(
      $._sere, choice(';', ':'), $._sere,
    )),

    sere_or: $ => prec.left(PREC.sere_or, seq($._sere, '|', $._sere)),

    sere_union: $ => prec.left(PREC.sere_or, seq($._sere, 'union', $._sere)),

    sere_and: $ => prec.left(PREC.sere_and, seq(
      $._sere, choice('&', '&&'), $._sere,
    )),

    sere_within: $ => prec.left(PREC.sere_or, seq(
      $._sere, 'within', $._sere,
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

    _count: $ => choice(
      $._number,
      seq($._number, 'to', $._number),
      seq($._number, 'to', 'inf'),
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
      field('operator', choice('not', '-', '+', 'abs')),
      field('operand', $._boolean),
    )),

    binary_expression: $ => {
      const table = [
        [PREC.or, choice('or', 'nor', 'xor', 'xnor', '||')],
        [PREC.and, choice('and', 'nand', '&&')],
        [PREC.equality, choice('=', '/=', '<', '<=', '>', '>=', '==')],
        [PREC.add, choice('+', '-', '&')],
        [PREC.mul, choice('*', '/', 'mod', 'rem')],
        [PREC.power, '**'],
      ];
      return choice(...table.map(([precedence, operator]) =>
        prec.left(precedence, seq(
          field('left', $._boolean),
          field('operator', operator),
          field('right', $._boolean),
        ))));
    },

    builtin_call: $ => seq(
      field('function', $.builtin_function),
      '(',
      sep1($._boolean, ','),
      ')',
    ),

    builtin_function: _ => choice(
      'prev', 'stable', 'rose', 'fell',
      'countones', 'onehot', 'onehot0', 'isunknown', 'nondet',
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

    range_constraint: $ => seq($._boolean, choice('to', 'downto'), $._boolean),

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

    boolean_literal: _ => choice('true', 'false'),

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
