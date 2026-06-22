;;; Directory Local Variables            -*- no-byte-compile: t -*-
;;; For more information see (info "(emacs) Directory Variables")

;; Point the grammar installer at this checkout instead of the default
;; GitHub URL (which clones `main' and can lag behind `develop').  See
;; `psl-ts-mode-grammar-source' in psl-ts-mode.el.
((psl-ts-mode
  . ((eval . (setq-local
              psl-ts-mode-grammar-source
              (list (locate-dominating-file default-directory ".dir-locals.el")
                    nil
                    "tree-sitter-psl/src"))))))
