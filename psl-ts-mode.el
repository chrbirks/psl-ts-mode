;;; psl-ts-mode.el --- Major mode for IEEE 1850 PSL using tree-sitter -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Christian Birk Sørensen

;; Author: Christian Birk Sørensen
;; Maintainer: Christian Birk Sørensen
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: languages, tools, hardware, verification
;; URL: https://github.com/chrbirks/emacs-psl-mode

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; A major mode for editing PSL (Property Specification Language, IEEE
;; 1850) source files, based on the built-in tree-sitter support of
;; Emacs 29+ (`treesit').  The focus is the VHDL flavor of PSL in
;; standalone \".psl\" files.
;;
;; Features: syntax highlighting, indentation, and imenu/navigation for
;; verification units, properties and sequences.
;;
;; Setup:
;;
;;   The tree-sitter grammar must be installed once.  With the grammar
;;   source registered (see `psl-ts-mode-grammar-source'), run:
;;
;;     M-x psl-ts-mode-install-grammar
;;
;;   Then open any file with the \".psl\" extension.

;;; Code:

(require 'treesit)

(eval-when-compile
  (require 'rx))

(declare-function treesit-parser-create "treesit.c")
(declare-function treesit-node-type "treesit.c")
(declare-function treesit-node-child-by-field-name "treesit.c")

(defgroup psl-ts nil
  "Major mode for PSL (Property Specification Language) using tree-sitter."
  :group 'languages
  :prefix "psl-ts-mode-")

(defcustom psl-ts-mode-indent-offset 2
  "Number of spaces for each indentation step in `psl-ts-mode'."
  :type 'integer
  :safe #'integerp
  :group 'psl-ts)

(defcustom psl-ts-mode-grammar-source
  '("https://github.com/chrbirks/emacs-psl-mode"
    nil "tree-sitter-psl/src")
  "Source specification for the PSL tree-sitter grammar.
A list of (URL REVISION SOURCE-DIR) suitable for
`treesit-language-source-alist'.  When developing locally, set the URL
to the path of the local checkout of this repository."
  :type '(list (string :tag "URL or local path")
               (choice (const :tag "Default revision" nil) string)
               (choice (const :tag "Default source dir" nil) string))
  :group 'psl-ts)

;;;###autoload
(defun psl-ts-mode-install-grammar ()
  "Install the PSL tree-sitter grammar.
Uses `psl-ts-mode-grammar-source' as the grammar location."
  (interactive)
  (let ((treesit-language-source-alist
         (cons (cons 'psl psl-ts-mode-grammar-source)
               (bound-and-true-p treesit-language-source-alist))))
    (treesit-install-language-grammar 'psl)))

;;;; Font lock

(defvar psl-ts-mode--keywords
  '("vunit" "vmode" "vprop" "vpkg"
    "property" "sequence" "endpoint"
    "default" "clock" "is" "report"
    "strong" "weak"
    "const" "boolean" "hdltype"
    "within" "to" "downto" "inf"
    "forall" "in" "union")
  "PSL keywords for tree-sitter font-locking.")

(defvar psl-ts-mode--directives
  '("assert" "assume" "assume_guarantee" "cover"
    "restrict" "restrict!" "fairness")
  "PSL verification directives for tree-sitter font-locking.")

(defvar psl-ts-mode--operators
  '("and" "or" "nand" "nor" "xor" "xnor" "not"
    "mod" "rem" "abs"
    "=" "/=" "<" "<=" ">" ">=" "=="
    "+" "-" "*" "/" "**" "&" "&&" "||" "@")
  "Boolean and arithmetic operators for tree-sitter font-locking.")

(defvar psl-ts-mode--temporal-operators
  '("->" "<->" "|->" "|=>"
    "abort" "async_abort" "sync_abort")
  "Temporal and SERE operators for tree-sitter font-locking.")

(defvar psl-ts-mode--font-lock-settings
  (treesit-font-lock-rules
   :language 'psl
   :feature 'comment
   '((comment) @font-lock-comment-face)

   :language 'psl
   :feature 'string
   '([(string_literal) (character_literal) (bit_string_literal)]
     @font-lock-string-face)

   :language 'psl
   :feature 'keyword
   `([,@psl-ts-mode--keywords] @font-lock-keyword-face
     ([,@psl-ts-mode--directives] @font-lock-keyword-face))

   :language 'psl
   :feature 'definition
   '((verification_unit name: (identifier) @font-lock-type-face)
     (property_declaration name: (identifier) @font-lock-function-name-face)
     (sequence_declaration name: (identifier) @font-lock-function-name-face)
     (endpoint_declaration name: (identifier) @font-lock-function-name-face))

   :language 'psl
   :feature 'builtin
   '((builtin_function) @font-lock-builtin-face
     (boolean_literal) @font-lock-constant-face)

   :language 'psl
   :feature 'temporal
   `((temporal_unary_op) @font-lock-keyword-face
     (temporal_binary_op) @font-lock-keyword-face
     (next_event_property operator: _ @font-lock-keyword-face)
     ([,@psl-ts-mode--temporal-operators] @font-lock-keyword-face))

   :language 'psl
   :feature 'number
   '([(integer) (real) (based_literal)] @font-lock-number-face)

   :language 'psl
   :feature 'operator
   `([,@psl-ts-mode--operators] @font-lock-operator-face)

   :language 'psl
   :feature 'bracket
   '((["(" ")" "{" "}" "[*" "[+" "[=" "[->" "]"]) @font-lock-bracket-face)

   :language 'psl
   :feature 'delimiter
   '(([";" "," ":" "." "'"]) @font-lock-delimiter-face))
  "Tree-sitter font-lock settings for `psl-ts-mode'.")

;;;; Indentation

(defun psl-ts-mode--indent-rules ()
  "Return the tree-sitter indentation rules for `psl-ts-mode'."
  (let ((offset psl-ts-mode-indent-offset))
    `((psl
       ((node-is "}") parent-bol 0)
       ((node-is ")") parent-bol 0)
       ((parent-is "verification_unit") parent-bol ,offset)
       ((parent-is "inherit_clause") parent-bol ,offset)
       ((parent-is "actual_parameter_list") parent-bol ,offset)
       ((parent-is "formal_parameter_list") parent-bol ,offset)
       ((parent-is "source_file") column-0 0)
       (catch-all parent-bol 0)))))

;;;; Imenu / navigation

(defun psl-ts-mode--defun-name (node)
  "Return the name of verification unit, property or sequence NODE."
  (treesit-node-text
   (treesit-node-child-by-field-name node "name")
   t))

;;;; Mode

;;;###autoload
(define-derived-mode psl-ts-mode prog-mode "PSL"
  "Major mode for editing IEEE 1850 PSL (Property Specification Language) files.

\\{psl-ts-mode-map}"
  :group 'psl-ts
  (when (treesit-ready-p 'psl)
    (treesit-parser-create 'psl)

    ;; Comments.
    (setq-local comment-start "-- ")
    (setq-local comment-end "")
    (setq-local comment-start-skip (rx (or "--" "/*") (* (syntax whitespace))))

    ;; Font lock.
    (setq-local treesit-font-lock-settings psl-ts-mode--font-lock-settings)
    (setq-local treesit-font-lock-feature-list
                '((comment string)
                  (keyword definition)
                  (builtin temporal number)
                  (operator bracket delimiter)))

    ;; Indentation.
    (setq-local treesit-simple-indent-rules (psl-ts-mode--indent-rules))

    ;; Navigation.
    (setq-local treesit-defun-type-regexp
                (rx (or "verification_unit"
                        "property_declaration"
                        "sequence_declaration"
                        "endpoint_declaration")))
    (setq-local treesit-defun-name-function #'psl-ts-mode--defun-name)
    (setq-local treesit-simple-imenu-settings
                '(("Unit" "\\`verification_unit\\'" nil nil)
                  ("Property" "\\`property_declaration\\'" nil nil)
                  ("Sequence" "\\`sequence_declaration\\'" nil nil)
                  ("Endpoint" "\\`endpoint_declaration\\'" nil nil)))

    (treesit-major-mode-setup)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.psl\\'" . psl-ts-mode))

(provide 'psl-ts-mode)
;;; psl-ts-mode.el ends here
