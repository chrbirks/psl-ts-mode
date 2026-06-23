;;; psl-ts-mode-test.el --- Tests for psl-ts-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Christian Birk Sørensen

;; This file is not part of GNU Emacs.

;;; Commentary:

;; ERT tests for `psl-ts-mode'.  Require that the PSL tree-sitter
;; grammar has been installed (see `psl-ts-mode-install-grammar').
;;
;; Run with:
;;
;;   emacs -batch -l ert -l psl-ts-mode.el -l psl-ts-mode-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'treesit)
(require 'psl-ts-mode)

(defmacro psl-ts-test--with-buffer (content &rest body)
  "Run BODY in a `psl-ts-mode' buffer containing CONTENT."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,content)
     (psl-ts-mode)
     (goto-char (point-min))
     ,@body))

(ert-deftest psl-ts-test-grammar-available ()
  "The PSL grammar should be installed for the tests to run."
  (should (treesit-ready-p 'psl)))

(ert-deftest psl-ts-test-mode-activates ()
  "Opening PSL content should select `psl-ts-mode' and create a parser."
  (skip-unless (treesit-ready-p 'psl))
  (psl-ts-test--with-buffer "assert always a;\n"
    (should (eq major-mode 'psl-ts-mode))
    (should (treesit-parser-list))))

(ert-deftest psl-ts-test-parses-without-error ()
  "A representative buffer should parse with no ERROR nodes."
  (skip-unless (treesit-ready-p 'psl))
  (psl-ts-test--with-buffer
      (concat "vunit u (top) {\n"
              "  default clock is rising_edge(clk);\n"
              "  property p is always (req -> eventually! grant);\n"
              "  sequence s is {req; ack};\n"
              "  assert p report \"oops\";\n"
              "  cover {req; ack; grant};\n"
              "  assume always (reset -> next (not valid));\n"
              "  restrict {reset[*3]};\n"
              "  fairness grant;\n"
              "}\n")
    (let ((root (treesit-buffer-root-node)))
      (should-not (treesit-search-subtree root "ERROR" nil nil))
      (should-not (treesit-node-check root 'has-error)))))

(ert-deftest psl-ts-test-font-lock-keyword ()
  "Directive and temporal keywords should be fontified."
  (skip-unless (treesit-ready-p 'psl))
  (psl-ts-test--with-buffer "assert always req;\n"
    (font-lock-ensure)
    ;; "assert" keyword.
    (should (eq (face-at-point) 'font-lock-keyword-face))
    ;; "always" temporal operator.
    (goto-char (point-min))
    (search-forward "always")
    (should (eq (get-text-property (- (point) 1) 'face)
                'font-lock-keyword-face))))

(ert-deftest psl-ts-test-font-lock-comment-and-string ()
  "Comments and strings should be fontified."
  (skip-unless (treesit-ready-p 'psl))
  (psl-ts-test--with-buffer "-- a comment\nassert a report \"hi\";\n"
    (font-lock-ensure)
    (goto-char (point-min))
    (should (eq (face-at-point) 'font-lock-comment-face))
    (goto-char (point-min))
    (search-forward "\"hi\"")
    (should (eq (get-text-property (- (point) 2) 'face)
                'font-lock-string-face))))

(ert-deftest psl-ts-test-indentation ()
  "Verification-unit bodies should indent by `psl-ts-mode-indent-offset'."
  (skip-unless (treesit-ready-p 'psl))
  (psl-ts-test--with-buffer
      "vunit u (top) {\nassert a;\n}\n"
    (let ((psl-ts-mode-indent-offset 2))
      (setq-local treesit-simple-indent-rules (psl-ts-mode--indent-rules))
      (indent-region (point-min) (point-max))
      (goto-char (point-min))
      (forward-line 1)
      (should (equal (current-indentation) 2))
      (forward-line 1)
      (should (equal (current-indentation) 0)))))

(ert-deftest psl-ts-test-imenu-defun-name ()
  "The defun-name function should return verification-unit names."
  (skip-unless (treesit-ready-p 'psl))
  (psl-ts-test--with-buffer "vunit my_unit (top) {\n  assert a;\n}\n"
    (let* ((root (treesit-buffer-root-node))
           (unit (treesit-search-subtree root "verification_unit")))
      (should (equal (psl-ts-mode--defun-name unit) "my_unit")))))

(ert-deftest psl-ts-test-spec-additions-parse-clean ()
  "New IEEE 1850 constructs should parse with no ERROR nodes."
  (skip-unless (treesit-ready-p 'psl))
  (psl-ts-test--with-buffer
      (concat "vunit u {\n"
              "  nontransitive inherit base1, base2;\n"
              "  override sig1, sig2;\n"
              "  property p (mutable boolean b; bit x; bitvector v;\n"
              "              numeric n; string s) is always b;\n"
              "  chk_req: assert always (req -> ended(seq)) report \"x\";\n"
              "  cov_lbl: cover {a; b};\n"
              "  strong_fairness a, b;\n"
              "  assert always nondet_vector(2, x);\n"
              "}\n")
    (let ((root (treesit-buffer-root-node)))
      (should-not (treesit-node-check root 'has-error)))))

(ert-deftest psl-ts-test-directive-label-font-lock ()
  "A directive label should be fontified with the variable-name face."
  (skip-unless (treesit-ready-p 'psl))
  (psl-ts-test--with-buffer "chk_req: assert always req;\n"
    (font-lock-ensure)
    (goto-char (point-min))
    (should (eq (face-at-point) 'font-lock-variable-name-face))))

(ert-deftest psl-ts-test-example-files-parse-clean ()
  "Every file in examples/ should parse with zero ERROR nodes."
  (skip-unless (treesit-ready-p 'psl))
  (let ((examples-dir (expand-file-name
                       "examples"
                       (file-name-directory
                        (or load-file-name buffer-file-name default-directory)))))
    (dolist (psl-file (directory-files examples-dir t "\\.psl\\'"))
      (with-temp-buffer
        (insert-file-contents psl-file)
        (psl-ts-mode)
        (let ((root (treesit-buffer-root-node)))
          (should-not
           (treesit-node-check root 'has-error)))))))

;;;; AST lint helper tests (no Flycheck or external tools required)

(ert-deftest psl-ts-test-directive-clocked-with-default-clock ()
  "A directive inside a vunit that has `default clock' is considered clocked."
  (skip-unless (treesit-ready-p 'psl))
  (psl-ts-test--with-buffer
      "vunit u (top) {\n  default clock is rising_edge(clk);\n  assert always req;\n}\n"
    (let* ((root (treesit-buffer-root-node))
           (dir (treesit-search-subtree
                 root
                 (lambda (n) (string= (treesit-node-type n) "assert_directive")))))
      (should dir)
      (should (psl-ts-mode--directive-clocked-p dir)))))

(ert-deftest psl-ts-test-directive-unclocked-without-default-clock ()
  "A directive inside a vunit without `default clock' is not clocked."
  (skip-unless (treesit-ready-p 'psl))
  (psl-ts-test--with-buffer
      "vunit u (top) {\n  assert always req;\n}\n"
    (let* ((root (treesit-buffer-root-node))
           (dir (treesit-search-subtree
                 root
                 (lambda (n) (string= (treesit-node-type n) "assert_directive")))))
      (should dir)
      (should-not (psl-ts-mode--directive-clocked-p dir)))))

(ert-deftest psl-ts-test-directive-clocked-inline ()
  "A directive whose property is directly a clocked_property is considered clocked."
  (skip-unless (treesit-ready-p 'psl))
  (psl-ts-test--with-buffer
      "vunit u (top) {\n  assert (req -> next ack) @ rising_edge(clk);\n}\n"
    (let* ((root (treesit-buffer-root-node))
           (dir (treesit-search-subtree
                 root
                 (lambda (n) (string= (treesit-node-type n) "assert_directive")))))
      (should dir)
      (should (psl-ts-mode--directive-clocked-p dir)))))

(ert-deftest psl-ts-test-syntax-error-produces-error-node ()
  "A buffer with a syntax error should have an ERROR node in the tree."
  (skip-unless (treesit-ready-p 'psl))
  (psl-ts-test--with-buffer
      "vunit u (top) {\n  assert $$$INVALID;\n}\n"
    (let ((root (treesit-buffer-root-node)))
      (should (treesit-node-check root 'has-error)))))

(ert-deftest psl-ts-test-undeclared-reference-flagged ()
  "A bare directive reference to an undeclared name is not in scope's names."
  (skip-unless (treesit-ready-p 'psl))
  (psl-ts-test--with-buffer
      "vunit u (top) {\n  property p1 is always true;\n  assert p2;\n}\n"
    (let* ((root (treesit-buffer-root-node))
           (dir (treesit-search-subtree
                 root
                 (lambda (n) (string= (treesit-node-type n) "assert_directive"))))
           (target (psl-ts-mode--directive-target dir))
           (scope (psl-ts-mode--directive-scope dir))
           (names (psl-ts-mode--scope-declared-names scope)))
      (should (string= (treesit-node-text target t) "p2"))
      (should-not (psl-ts-mode--scope-has-inherit-p scope))
      (should-not (gethash "p2" names))
      (should (gethash "p1" names)))))

(ert-deftest psl-ts-test-declared-reference-not-flagged ()
  "A bare directive reference to a declared name is in scope's names."
  (skip-unless (treesit-ready-p 'psl))
  (psl-ts-test--with-buffer
      "vunit u (top) {\n  property p1 is always true;\n  assert p1;\n}\n"
    (let* ((root (treesit-buffer-root-node))
           (dir (treesit-search-subtree
                 root
                 (lambda (n) (string= (treesit-node-type n) "assert_directive"))))
           (target (psl-ts-mode--directive-target dir))
           (scope (psl-ts-mode--directive-scope dir)))
      (should (gethash (treesit-node-text target t)
                        (psl-ts-mode--scope-declared-names scope))))))

(ert-deftest psl-ts-test-inherit-skips-undeclared-check ()
  "A verification_unit using `inherit' is detected so the check can bail out."
  (skip-unless (treesit-ready-p 'psl))
  (psl-ts-test--with-buffer
      "vunit u (top) {\n  inherit other_unit;\n  assert p2;\n}\n"
    (let* ((root (treesit-buffer-root-node))
           (dir (treesit-search-subtree
                 root
                 (lambda (n) (string= (treesit-node-type n) "assert_directive"))))
           (scope (psl-ts-mode--directive-scope dir)))
      (should (psl-ts-mode--scope-has-inherit-p scope)))))

(ert-deftest psl-ts-test-top-level-directive-scope ()
  "A directive outside any verification_unit scopes to the buffer root."
  (skip-unless (treesit-ready-p 'psl))
  (psl-ts-test--with-buffer
      "property p1 is always true;\nassert p2;\n"
    (let* ((root (treesit-buffer-root-node))
           (dir (treesit-search-subtree
                 root
                 (lambda (n) (string= (treesit-node-type n) "assert_directive"))))
           (scope (psl-ts-mode--directive-scope dir)))
      (should (treesit-node-eq scope root))
      (should-not (psl-ts-mode--scope-has-inherit-p scope))
      (should (gethash "p1" (psl-ts-mode--scope-declared-names scope)))
      (should-not (gethash "p2" (psl-ts-mode--scope-declared-names scope))))))

(provide 'psl-ts-mode-test)
;;; psl-ts-mode-test.el ends here
