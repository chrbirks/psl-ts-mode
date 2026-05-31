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
;;     directives that GHDL cannot check without a clock context.
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
(defvar psl-ts-mode--clocked-directive-types)

;;;; Project config

(defcustom psl-ts-mode-ghdl-std "08"
  "VHDL standard passed to GHDL via --std=.  Common values: \"93\", \"08\"."
  :type 'string
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

(defcustom psl-ts-mode-ghdl-top-entity nil
  "Top-level entity name for GHDL (optional, not yet used)."
  :type '(choice (const :tag "None" nil) string)
  :safe (lambda (v) (or (null v) (stringp v)))
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
Checks: tree-sitter ERROR/missing nodes (error level) and unclocked
PSL directives (warning level)."
  (let* ((root (treesit-buffer-root-node))
         errors)
    ;; Syntax errors: ERROR nodes and missing nodes
    (dolist (node (or (treesit-search-subtree
                       root
                       (lambda (n)
                         (or (string= (treesit-node-type n) "ERROR")
                             (treesit-node-check n 'missing)))
                       nil t)
                      nil))
      (let ((lc (psl-ts-mode--pos-to-line-col (treesit-node-start node))))
        (push (flycheck-error-new-at
               (car lc) (cdr lc) 'error
               (if (treesit-node-check node 'missing)
                   (format "Missing %s" (treesit-node-type node))
                 "Syntax error")
               :checker checker)
              errors)))
    ;; Unclocked directives
    (dolist (node (or (treesit-search-subtree
                       root
                       (lambda (n)
                         (member (treesit-node-type n)
                                 psl-ts-mode--clocked-directive-types))
                       nil t)
                      nil))
      (unless (psl-ts-mode--directive-clocked-p node)
        (let ((lc (psl-ts-mode--pos-to-line-col (treesit-node-start node))))
          (push (flycheck-error-new-at
                 (car lc) (cdr lc) 'warning
                 (concat "Directive is not clocked; GHDL requires a clock. "
                         "Add `default clock is ...' to the enclosing unit "
                         "or append `@ clock' to this directive.")
                 :checker checker)
                errors))))
    errors))

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
warnings for unclocked directives.  No external tool required."
  :start #'psl-ts-mode--flycheck-treesit-start
  :modes '(psl-ts-mode)
  :next-checkers '((warning . psl-ghdl)))

(add-to-list 'flycheck-checkers 'psl-treesit)

;;;; Checker B: psl-ghdl

(defun psl-ts-mode--ghdl-design-args ()
  "Return expanded paths for `psl-ts-mode-ghdl-design-files'."
  (mapcar #'expand-file-name psl-ts-mode-ghdl-design-files))

(flycheck-define-checker psl-ghdl
  "Check PSL semantics using GHDL.
Requires `psl-ts-mode-ghdl-design-files' to be set.  GHDL analyzes
all design files alongside the current buffer file."
  :command ("ghdl"  ; override path via M-x customize flycheck-psl-ghdl-executable
            "-a"
            (eval (concat "--std=" psl-ts-mode-ghdl-std))
            "-fpsl"
            (eval (psl-ts-mode--ghdl-design-args))
            source-inplace)
  :error-patterns
  ((error   line-start (file-name) ":" line ":" column ":error: "   (message) line-end)
   (error   line-start (file-name) ":" line ":" column ": error: "  (message) line-end)
   (warning line-start (file-name) ":" line ":" column ":warning: " (message) line-end)
   (warning line-start (file-name) ":" line ":" column ": warning: "(message) line-end))
  :modes (psl-ts-mode)
  :enabled (lambda () (not (null psl-ts-mode-ghdl-design-files)))
  :predicate (lambda () (not (null psl-ts-mode-ghdl-design-files))))

(provide 'psl-ts-mode-flycheck)
;;; psl-ts-mode-flycheck.el ends here
