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
- **Indentation** - verification-unit bodies and parameter lists, controlled by
  `psl-ts-mode-indent-offset`.
- **Navigation** - `imenu` and `treesit` defun navigation for verification
  units, properties, sequences, and endpoints.

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
psl-ts-mode-test.el       ERT test suite
examples/sample.psl       example PSL buffer
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

## Diagnostics

`psl-ts-mode-flycheck.el` provides optional [Flycheck](https://www.flycheck.org/)
diagnostics when Flycheck is installed.  It loads automatically — no extra
configuration required.

### Always-on AST lint (`psl-treesit` checker)

Runs synchronously on the live tree-sitter AST, requires no external tool:

- **Syntax errors** — any `ERROR` or missing node in the parse tree is reported
  at `error` level.
- **Unclocked directives** — `assert`/`assume`/`cover`/`restrict` directives
  that have no `default clock is …` in the enclosing unit and no inline
  `@ clock` expression are reported at `warning` level.  GHDL requires all
  PSL assertions to be clocked.

### Optional GHDL semantic check (`psl-ghdl` checker)

Runs `ghdl -a -fpsl` when `psl-ts-mode-ghdl-design-files` is non-nil.
Configure per project via `.dir-locals.el`:

```elisp
((psl-ts-mode
  . ((psl-ts-mode-ghdl-design-files . ("../src/dut.vhd"))
     (psl-ts-mode-ghdl-std          . "08"))))
```

| Variable                          | Default  | Meaning                                      |
|-----------------------------------|----------|----------------------------------------------|
| `flycheck-psl-ghdl-executable`    | `"ghdl"` | Path to the GHDL binary (set by Flycheck).   |
| `psl-ts-mode-ghdl-std`            | `"08"`   | VHDL standard (`"93"`, `"08"`, …).           |
| `psl-ts-mode-ghdl-design-files`   | `nil`    | VHDL files to analyze alongside the `.psl`.  |
| `psl-ts-mode-ghdl-top-entity`     | `nil`    | Top entity name (not yet used).              |

**GHDL limitations:** GHDL can only check PSL that is bound to a VHDL design
(signals, ports, clocks must be resolvable).  Standalone `.psl` files without
a design context will produce unresolved-identifier errors.  GHDL also requires
all assertions to be clocked and repetition ranges to be static integer
literals.

## Not yet supported

- PSL embedded inside VHDL (`-- psl ...` comments, inline `vunit` in `.vhd`).
- Verilog / SystemVerilog flavors of PSL.
- LSP / completion integration.

## License

GPL-3.0
