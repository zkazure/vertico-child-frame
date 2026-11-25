;;; vertico.el --- Minimal Vertico stub for offline testing -*- lexical-binding: t -*-

(require 'cl-lib)

(defvar vertico-count 10)
(defvar vertico-resize nil)
(defvar-local vertico--input nil)
(defvar-local vertico--candidates nil)
(defvar-local vertico--scroll 0)
(defvar-local vertico--candidates-ov nil)
(defvar-local vertico--count-ov nil)
(defvar vertico-stub--resize-called nil)
(defvar vertico-stub--exhibit-called nil)
(defvar vertico-stub--update-called nil)

(cl-defgeneric vertico--setup ()
  "Setup completion UI."
  (setq-local vertico--input t
              vertico--candidates-ov (make-overlay (point-max) (point-max))
              vertico--count-ov (make-overlay (point-min) (point-min))))

(cl-defgeneric vertico--display-candidates (lines)
  "Display candidate LINES."
  (vertico--resize-window (length lines)))

(cl-defgeneric vertico--resize-window (height)
  "Resize minibuffer window to HEIGHT."
  (setq vertico-stub--resize-called height))

(defun vertico--window-width ()
  "Return window width."
  (window-width))

(defun vertico--update (&optional interruptible)
  "Update completion state, optionally INTERRUPTIBLE."
  (setq vertico-stub--update-called (if interruptible 'interruptible 'sync)))

(defun vertico--exhibit ()
  "Exhibit candidates."
  (setq vertico-stub--exhibit-called t))

(defun vertico--command-p (_sym _buf)
  "Command predicate stub."
  t)

(provide 'vertico)
;;; vertico.el ends here
