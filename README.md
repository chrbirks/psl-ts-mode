# psl-ts-mode - Emacs major mode for PSL (Property Specification Language)

A [tree-sitter](https://tree-sitter.github.io/) based Emacs major mode for
**PSL - the Property Specification Language (IEEE 1850)**. The focus is the
**VHDL flavor** of PSL (not Verilog or SystemVerilog), edited in standalone
`.psl` files.

PSL is a formal-verification language for describing temporal assertions about
hardware designs. It is organized in four layers - Boolean, Temporal (FL),
SERE, and Verification - and packaged in verification units (`vunit`, `vmode`,
`vprop`, `vpkg`).

## Example

```psl
vunit fifo_props (fifo_rtl) {

  default clock is rising_edge(clk);

  property no_overflow_underflow is
    always (not (overflow and underflow));

  property req_grant is
    always (req -> eventually! grant);

  sequence two_valid is {valid; valid};

  property handshake is
    {req; ack} |=> {data_valid[*2]};

  assert no_overflow_underflow report "FIFO overflow/underflow";
  assert req_grant;
  assert handshake @ rising_edge(clk);

  cover {req; ack; data_valid};
  assume always (reset -> next (not valid));
  restrict {reset[*3]};
  fairness grant;
}
```

## Features

For `.psl` files:

- **Syntax highlighting** - verification units, directives
  (`assert`/`assume`/`cover`/`restrict`/`fairness`), temporal/FL operators
  (including parameterized `next[N]`, `next_event(b)(p)`, `forall`),
  SERE operators (including `union`, strong `{..}!`), built-in functions,
  VHDL slice expressions (`downto`/`to`), comments, strings, and numbers.
  Keywords are recognized in any case (`assert`, `ASSERT`, `Assert`), as PSL
  inherits VHDL's case-insensitivity.
- **Indentation** - verification-unit bodies, braced SEREs, statement
  continuation lines, and parameter lists, controlled by
  `psl-ts-mode-indent-offset`.
- **Navigation** - `imenu` and `treesit` defun navigation for verification
  units, properties, sequences, and endpoints.
- **Diagnostics** - optional [Flycheck](https://www.flycheck.org/) integration,
  see [Diagnostics](#diagnostics) below.

## Requirements

- Emacs **29.1+** built with tree-sitter support - check with
  `(treesit-available-p)`.
- A **C compiler** (used once, to build the grammar).

## Installation

### 1. Put the mode on your `load-path`

```elisp
(add-to-list 'load-path "/path/to/psl-ts-mode")
(require 'psl-ts-mode)
```

Or with `use-package`:

```elisp
(use-package psl-ts-mode
  :ensure (:host github :repo "chrbirks/psl-ts-mode")
  :commands (psl-ts-mode-install-grammar)
  :mode "\\.psl\\'")
```

### 2. Install the tree-sitter grammar (once)

The grammar ships in this repository under `tree-sitter-psl/` (the generated
`src/` is committed, so no Node/tree-sitter CLI is required to install it).

For a local checkout, point the grammar source at it and install:

```elisp
(setq psl-ts-mode-grammar-source
      (list "/path/to/psl-ts-mode/tree-sitter-psl" nil "src"))
(psl-ts-mode-install-grammar)
```

When installing from the published repository, the default
`psl-ts-mode-grammar-source` already points at the GitHub repo, so just run:

```
M-x psl-ts-mode-install-grammar
```

Confirm with `(treesit-ready-p 'psl)` ⇒ `t`, then open any `.psl` file.

### Troubleshooting: almost nothing is highlighted

If only comments and strings are coloured and everything else is plain, the
installed grammar is older than the mode.  The grammar and `psl-ts-mode.el`
are versioned together, and tree-sitter rejects an entire query when a single
node type in it is unknown, so an out-of-date grammar costs you keywords,
names, operators and numbers all at once.  The mode warns about this on
startup; the fix is:

```
M-x psl-ts-mode-install-grammar
```

then **restart Emacs** — a grammar already loaded into a running Emacs is not
replaced by reinstalling it.

Highlighting also depends on `treesit-font-lock-level` (default `3`):

| Level | Adds                                                       |
|-------|------------------------------------------------------------|
| 1     | comments, strings                                          |
| 2     | keywords, declaration names, directive labels              |
| 3     | built-in functions, temporal/SERE operators, numbers       |
| 4     | Boolean/arithmetic operators, brackets, delimiters         |

If you see only comments and strings *and* no warning, you are on level 1;
`(setq treesit-font-lock-level 3)` (or `4`) will fix that.  Plain signal
references stay unhighlighted at every level — there is no way to tell an HDL
signal from any other identifier without seeing the design.

## More examples

Example files covering advanced constructs:

| File                                                         | Demonstrates                                                                                                                                                                                                                 |
|--------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`examples/fifo.psl`](examples/fifo.psl)                     | Default clock, invariants, fill-level bounds, req/ack handshake, `\|=>`, `report` strings                                                                                                                                    |
| [`examples/axi_handshake.psl`](examples/axi_handshake.psl)   | `\|->`, `\|=>`, `next_event(b)(p)`, counted `next[N]`, `eventually!`, clocked `@` properties                                                                                                                                 |
| [`examples/fsm.psl`](examples/fsm.psl)                       | Named sequences, fusion `:`, `[=]`/`[->]`/`[*]` with `to` ranges, `within`, `abort`                                                                                                                                          |
| [`examples/all_constructs.psl`](examples/all_constructs.psl) | Dense: `vunit`/`vmode`/`vprop`/`vpkg`, `endpoint`, parameterized `next` + full `next_event` family, `forall`, all SERE ops incl. `union` + strong `{..}!`, VHDL slices `downto`/`to`, all literal forms, both comment styles |

## Customization

| Variable                     | Default     | Meaning                                                                   |
|------------------------------|-------------|---------------------------------------------------------------------------|
| `psl-ts-mode-indent-offset`  | `2`         | Spaces per indentation step.                                              |
| `psl-ts-mode-grammar-source` | GitHub repo | `(URL REVISION SOURCE-DIR)` passed to `treesit-install-language-grammar`. |

## Repository layout

```
psl-ts-mode.el            the Emacs major mode
psl-ts-mode-flycheck.el   optional Flycheck diagnostics
psl-ts-mode-test.el       ERT test suite
examples/sample.psl       example PSL buffer
examples/errors/          files with deliberate errors, for the checker
tree-sitter-psl/
  grammar.js              the PSL grammar
  src/                    generated parser (committed)
  queries/highlights.scm  editor-agnostic highlight queries
  test/corpus/            tree-sitter corpus tests
```

## Development

Build and test the grammar (requires the `tree-sitter` CLI):

```sh
cd tree-sitter-psl
tree-sitter generate
tree-sitter test                       # corpus tests in test/corpus/
tree-sitter parse ../examples/sample.psl
```

Run the Emacs test suite (install the grammar first):

```sh
emacs -batch -L . -l ert -l psl-ts-mode.el -l psl-ts-mode-test.el \
  -f ert-run-tests-batch-and-exit
```

Tests that need the grammar are skipped when it is not installed.  To run
against a locally built grammar without installing it, build a shared library
next to the generated parser and point `treesit-extra-load-path` at it:

```sh
cc -shared -fPIC -O2 -I tree-sitter-psl/src \
  tree-sitter-psl/src/parser.c -o tree-sitter-psl/src/libtree-sitter-psl.so
emacs -batch -L . \
  --eval "(setq treesit-extra-load-path '(\"$PWD/tree-sitter-psl/src\"))" \
  -l ert -l psl-ts-mode.el -l psl-ts-mode-test.el \
  -f ert-run-tests-batch-and-exit
```

## Diagnostics

`psl-ts-mode-flycheck.el` provides optional [Flycheck](https://www.flycheck.org/)
diagnostics when Flycheck is installed.  It loads automatically — no extra
configuration required.

### Always-on AST lint (`psl-treesit` checker)

Runs synchronously on the live tree-sitter AST, requires no external tool:

- **Syntax errors** — any `ERROR` or missing node in the parse tree is reported
  at `error` level.
- **Unclocked directives** — `assert`/`assume`/`cover`/`restrict` directives
  with no inline `@ clock` expression and no preceding `default clock is …` in
  the same scope are reported at `warning` level.  GHDL requires all PSL
  assertions to be clocked.
- **Undeclared names** — *opt-in*, off by default.  With
  `psl-ts-mode-check-undeclared-names` set to `t`, a directive whose argument
  is a bare identifier that names no property/sequence/endpoint declared in
  the same unit is reported at `warning` level.  This is off by default
  because `assert some_signal;` is perfectly valid PSL — a Boolean is an FL
  property — and this checker cannot see the design's signals.  Units using
  `inherit` are skipped entirely.

### Optional GHDL semantic check (`psl-ghdl` checker)

Runs `ghdl -s -fpsl` when `psl-ts-mode-ghdl-design-files` is non-nil.
Configure per project via `.dir-locals.el`:

```elisp
((psl-ts-mode
  . ((psl-ts-mode-ghdl-design-files . ("../src/dut.vhd"))
     (psl-ts-mode-ghdl-std          . "08"))))
```

| Variable                             | Default  | Meaning                                                    |
|--------------------------------------|----------|------------------------------------------------------------|
| `flycheck-psl-ghdl-executable`       | `"ghdl"` | Path to the GHDL binary (set by Flycheck).                 |
| `psl-ts-mode-ghdl-std`               | `"08"`   | VHDL standard: `87`, `93`, `02`, `08` or `19`.             |
| `psl-ts-mode-ghdl-design-files`      | `nil`    | VHDL files to analyze alongside the `.psl`.                |
| `psl-ts-mode-check-undeclared-names` | `nil`    | Enable the opt-in undeclared-name warning described above. |

`-s` (parse plus full semantic analysis) is used rather than `-a`: it reports
the same undeclared signals, missing clocks and type errors, but skips code
generation, so it leaves no `work-obj*.cf` in your source tree — and `ghdl -a`
in fact aborts on a standalone vunit file with `cannot handle
IIR_KIND_VUNIT_DECLARATION`.

**Which `--std` values work:** vunit files need `08` or later.  Under `87`,
`93` or `02` GHDL does not recognize `vunit` at all and reports *missing
entity, architecture, package or configuration* on line 1.

**VHDL-2019 (`--std=19`)** is accepted by GHDL's command line and passed
through unchanged, so `(setq psl-ts-mode-ghdl-std "19")` works as far as this
mode is concerned.  Whether it runs depends on your GHDL build: most packages
ship prebuilt `std`/`ieee` libraries for v87, v93 and v08 only, and with no
v19 libraries every check fails immediately with

```
ghdl:warning: ieee library directory '/usr/lib/ghdl/ieee/v19/' not found
ghdl:error: cannot find "std" library
```

Check for a `v19` directory alongside the others in GHDL's library path
(`/usr/lib/ghdl/ieee/` on most Linux distributions) before selecting it; if
there is none, build the VHDL-2019 libraries yourself or stay on `08`.  Note
also that GHDL's VHDL-2019 support is partial and unrelated to PSL: the PSL
layer itself is the same under `08` and `19`.

**Other GHDL limitations:** GHDL can only check PSL that is bound to a VHDL
design (signals, ports, clocks must be resolvable).  Standalone `.psl` files
without a design context will produce unresolved-identifier errors.  GHDL also
requires all assertions to be clocked and repetition ranges to be static
integer literals.

## Not yet supported

- PSL embedded inside VHDL (`-- psl ...` comments, inline `vunit` in `.vhd`).
- Verilog / SystemVerilog flavors of PSL.
- LSP / completion integration.
- The single-letter LTL operator spellings (`X`, `F`, `G`, `U`, `W`).  The
  VHDL flavor spells these `next`, `eventually!`, `always`, `until` and
  `before`; leaving the aliases out keeps `X`/`F`/`G` usable as signal names.
- `ended` is the only built-in that takes a sequence argument; the other
  built-ins accept Boolean arguments only.

## License

GPL-3.0
