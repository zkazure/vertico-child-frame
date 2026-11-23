;;; vertico-multiform.el --- Minimal vertico-multiform stub for testing -*- lexical-binding: t -*-

(defvar vertico-multiform--display-modes nil)
(defvar vertico-multiform-map (make-sparse-keymap))
(defvar vertico-multiform-stub--toggled nil)

(defun vertico-multiform--toggle (mode)
  "Toggle MODE stub."
  (setq vertico-multiform-stub--toggled mode)
  (funcall mode (if (symbol-value mode) -1 1)))

(provide 'vertico-multiform)
;;; vertico-multiform.el ends here
