;;; psl-ts-mode-flycheck.el --- Flycheck diagnostics for psl-ts-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Christian Birk Sørensen

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; Optional Flycheck integration for `psl-ts-mode'.  Loaded automatically
;; when Flycheck is present (via `with-eval-after-load' in psl-ts-mode.el).
;;
;; Two checkers are registered for `psl-ts-mode', chained in order:
;;
;;   `psl-treesit' — always-on AST lint using the live tree-sitter tree.
;;     Detects syntax errors (ERROR/missing nodes) and reports unclocked
;;     directives that GHDL cannot check without a clock context.  With
;;     `psl-ts-mode-check-undeclared-names' enabled it additionally warns on
;;     directives that reference an undeclared property/sequence/endpoint
;;     name (skipped for units that use `inherit', since this checker has no
;;     visibility into names from outside the current file).
;;
;;   `psl-ghdl' — optional semantic check via GHDL.
;;     Runs only when `psl-ts-mode-ghdl-design-files' is configured.
;;     Configure per project via .dir-locals.el:
;;
;;       ((psl-ts-mode
;;         . ((psl-ts-mode-ghdl-design-files . ("../src/dut.vhd"))
;;            (psl-ts-mode-ghdl-std . "08"))))

;;; Code:

(require 'flycheck)
(require 'treesit)

;; psl-ts-mode is guaranteed loaded at runtime (checker only runs in psl-ts-mode
;; buffers), but declare its symbols so the byte-compiler doesn't warn.
(declare-function psl-ts-mode--find-ancestor "psl-ts-mode" (node type))
(declare-function psl-ts-mode--directive-clocked-p "psl-ts-mode" (directive))
(declare-function psl-ts-mode--collect-subtree "psl-ts-mode" (node predicate))
(declare-function psl-ts-mode--directive-target "psl-ts-mode" (directive))
(declare-function psl-ts-mode--directive-scope "psl-ts-mode" (node))
(declare-function psl-ts-mode--scope-has-inherit-p "psl-ts-mode" (scope))
(declare-function psl-ts-mode--scope-declared-names "psl-ts-mode" (scope))
(declare-function psl-ts-mode--name-declared-p "psl-ts-mode" (name names))
(defvar psl-ts-mode--clocked-directive-types)

;;;; Project config

(defconst psl-ts-mode-ghdl-standards '("87" "93" "02" "08" "19")
  "VHDL standards GHDL accepts for its --std= option.")

(defcustom psl-ts-mode-ghdl-std "08"
  "VHDL standard passed to GHDL via --std=.

Standalone PSL vunit files need \"08\" or later; under \"87\"/\"93\"/\"02\"
GHDL does not recognize `vunit' and reports \"missing entity,
architecture, package or configuration\".

\"19\" (VHDL-2019) is a valid GHDL option, but most GHDL packages ship
prebuilt std/ieee libraries for v87/v93/v08 only, in which case every
check fails with \"cannot find \\=\"std\\=\" library\".  Check for a v19
directory alongside the others in GHDL's library path before selecting
it."
  :type `(choice ,@(mapcar (lambda (s) `(const ,s))
                           psl-ts-mode-ghdl-standards)
                 (string :tag "Other"))
  :safe #'stringp
  :group 'psl-ts)

(defcustom psl-ts-mode-ghdl-design-files nil
  "List of VHDL design files for GHDL semantic checking.
When non-nil the `psl-ghdl' checker is enabled.  All paths are
expanded relative to the buffer's default directory.  Set this
per project via .dir-locals.el:

  ((psl-ts-mode
    . ((psl-ts-mode-ghdl-design-files . (\"../src/dut.vhd\")))))"
  :type '(repeat file)
  :safe (lambda (v) (and (listp v) (seq-every-p #'stringp v)))
  :group 'psl-ts)

(defcustom psl-ts-mode-check-undeclared-names nil
  "When non-nil, warn about directives naming an undeclared property.

A bare identifier after `assert'/`cover'/... is ambiguous: it may name a
property, sequence or endpoint declared in the same unit, but `assert b;'
where B is an HDL signal is equally valid PSL, and this checker has no
visibility into the design's signals.  The check therefore reports every
directive on a signal, so it is off by default.  Turn it on in projects
where directives always reference declared names."
  :type 'boolean
  :safe #'booleanp
  :group 'psl-ts)

;;;; AST lint

(defun psl-ts-mode--pos-to-line-col (pos)
  "Return (LINE . COLUMN) for buffer position POS, both 1-indexed."
  (save-excursion
    (goto-char pos)
    (cons (line-number-at-pos) (1+ (current-column)))))

(defun psl-ts-mode--ast-lint (checker)
  "Return a list of `flycheck-error' objects for the current buffer.
CHECKER is the Flycheck checker symbol attached to each error.
Checks: tree-sitter ERROR/missing nodes (error level), unclocked PSL
directives (warning level), and — when
`psl-ts-mode-check-undeclared-names' is non-nil — directives that
reference an undeclared property/sequence/endpoint name by a bare
identifier (warning level)."
  (let* ((root (treesit-buffer-root-node))
         ;; Declared-name sets are memoized per scope (keyed on the scope
         ;; node's start position) so a unit with many directives is walked
         ;; once rather than once per directive.
         (scope-names (make-hash-table :test #'eql))
         errors)
    ;; Syntax errors: ERROR nodes and missing nodes
    (dolist (node (psl-ts-mode--collect-subtree
                   root
                   (lambda (n)
                     (or (string= (treesit-node-type n) "ERROR")
                         (treesit-node-check n 'missing)))))
      (let ((lc (psl-ts-mode--pos-to-line-col (treesit-node-start node))))
        (push (flycheck-error-new-at
               (car lc) (cdr lc) 'error
               (if (treesit-node-check node 'missing)
                   (format "Missing %s" (treesit-node-type node))
                 "Syntax error")
               :checker checker)
              errors)))
    ;; Per-directive checks
    (dolist (node (psl-ts-mode--collect-subtree
                   root
                   (lambda (n)
                     (member (treesit-node-type n)
                             psl-ts-mode--clocked-directive-types))))
      ;; Unclocked directives
      (unless (psl-ts-mode--directive-clocked-p node)
        (let ((lc (psl-ts-mode--pos-to-line-col (treesit-node-start node))))
          (push (flycheck-error-new-at
                 (car lc) (cdr lc) 'warning
                 (concat "Directive is not clocked; GHDL requires a clock. "
                         "Add `default clock is ...' to the enclosing unit "
                         "or append `@ clock' to this directive.")
                 :checker checker)
                errors)))
      ;; Undeclared property/sequence/endpoint references.  Only checked when
      ;; the directive's target is a bare identifier (a name reference, not a
      ;; larger expression), and skipped entirely for any verification_unit
      ;; that uses `inherit', since inherited names can't be resolved from a
      ;; single standalone .psl file.
      (when psl-ts-mode-check-undeclared-names
        (let ((target (psl-ts-mode--directive-target node)))
          (when (and target (string= (treesit-node-type target) "identifier"))
            (let* ((scope (psl-ts-mode--directive-scope node))
                   (key (treesit-node-start scope)))
              (unless (psl-ts-mode--scope-has-inherit-p scope)
                (let ((names (or (gethash key scope-names)
                                 (puthash key
                                          (psl-ts-mode--scope-declared-names scope)
                                          scope-names)))
                      (name (treesit-node-text target t)))
                  (unless (psl-ts-mode--name-declared-p name names)
                    (let ((lc (psl-ts-mode--pos-to-line-col
                               (treesit-node-start target))))
                      (push (flycheck-error-new-at
                             (car lc) (cdr lc) 'warning
                             (format "`%s' is not declared in this verification unit (typo, missing declaration, or an HDL signal)"
                                     name)
                             :checker checker)
                            errors))))))))))
    (nreverse errors)))

;;;; Checker A: psl-treesit

(defun psl-ts-mode--flycheck-treesit-start (checker callback)
  "Start function for the `psl-treesit' Flycheck checker.
CHECKER and CALLBACK follow the Flycheck generic-checker protocol."
  (condition-case err
      (funcall callback 'finished (psl-ts-mode--ast-lint checker))
    (error (funcall callback 'errored (error-message-string err)))))

(flycheck-define-generic-checker 'psl-treesit
  "Check PSL using the tree-sitter AST.
Reports syntax errors from ERROR/missing nodes and GHDL-compatibility
warnings for unclocked directives, plus — when
`psl-ts-mode-check-undeclared-names' is enabled — warnings for
directives that reference an undeclared property/sequence/endpoint
name.  No external tool required."
  :start #'psl-ts-mode--flycheck-treesit-start
  :modes '(psl-ts-mode)
  ;; Without the grammar there is no parse tree to lint, and asking for the
  ;; root node would signal and make Flycheck disable the checker outright.
  :predicate (lambda () (treesit-ready-p 'psl t))
  :next-checkers '((warning . psl-ghdl)))

(add-to-list 'flycheck-checkers 'psl-treesit)

;;;; Checker B: psl-ghdl

(defun psl-ts-mode--ghdl-design-args ()
  "Return expanded paths for `psl-ts-mode-ghdl-design-files'."
  (mapcar #'expand-file-name psl-ts-mode-ghdl-design-files))

(defun psl-ts-mode--ghdl-error-filter (errors)
  "Sanitize ERRORS and give GHDL's location-less diagnostics a line.
Driver-level messages such as `cannot find \"std\" library' name no file
and no line, and Flycheck drops errors without a line number, so they
are pinned to line 0 rather than disappearing into a \"suspicious\"
status.  `flycheck-sanitize-errors' is the filter Flycheck would apply
by default and is kept."
  (flycheck-fill-empty-line-numbers (flycheck-sanitize-errors errors)))

(flycheck-define-checker psl-ghdl
  "Check PSL semantics using GHDL.
Requires `psl-ts-mode-ghdl-design-files' to be set.  GHDL analyzes all
design files alongside the current buffer file, so PSL that references
the design's signals, ports and clocks can be resolved.

Uses `ghdl -s' rather than `ghdl -a': -s runs the parser and full
semantic analysis (undeclared signals, missing clocks, type errors) but
no code generation, so it leaves no work library behind in the source
tree.  `ghdl -a' additionally tries to translate the unit, which fails
outright on a standalone vunit file (\"cannot handle
IIR_KIND_VUNIT_DECLARATION\")."
  :command ("ghdl"  ; override path via M-x customize flycheck-psl-ghdl-executable
            "-s"
            (eval (concat "--std=" psl-ts-mode-ghdl-std))
            "-fpsl"
            (eval (psl-ts-mode--ghdl-design-args))
            source-inplace)
  :error-patterns
  ((error   line-start (file-name) ":" line ":" column ":error: "   (message) line-end)
   (error   line-start (file-name) ":" line ":" column ": error: "  (message) line-end)
   (warning line-start (file-name) ":" line ":" column ":warning: " (message) line-end)
   (warning line-start (file-name) ":" line ":" column ": warning: "(message) line-end)
   ;; Driver-level diagnostics carry no source location, e.g. the
   ;; "cannot find \"std\" library" that a --std= without prebuilt
   ;; libraries produces.  Without these, GHDL's non-zero exit would
   ;; leave Flycheck in its opaque "suspicious" state instead.  GHDL
   ;; prefixes them with argv[0], which Flycheck invokes as an absolute
   ;; path, hence the leading wildcard.
   (error   line-start (zero-or-more not-newline) "ghdl:error: "
            (message) line-end)
   (warning line-start (zero-or-more not-newline) "ghdl:warning: "
            (message) line-end))
  :error-filter psl-ts-mode--ghdl-error-filter
  :modes (psl-ts-mode)
  ;; `:enabled' is consulted once per buffer, `:predicate' on every check;
  ;; the design-file list can be set by .dir-locals.el after the first check,
  ;; so the predicate is the one that matters here.
  :predicate (lambda () (not (null psl-ts-mode-ghdl-design-files))))

(provide 'psl-ts-mode-flycheck)
;;; psl-ts-mode-flycheck.el ends here
