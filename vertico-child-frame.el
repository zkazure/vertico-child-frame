;;; vertico-child-frame.el --- Display Vertico in a native child frame -*- lexical-binding: t -*-

;; Copyright (C) 2026 Kazure Zheng

;; Author: Kazure Zheng <kazurezheng@gmail.com>
;; Maintainer: Kazure Zheng <kazurezheng@gmail.com>
;; URL: https://github.com/zkazure/vertico-child-frame
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (vertico "1.0"))
;; Keywords: convenience, matching, frames

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

;; `vertico-child-frame' displays the Vertico completion UI inside a
;; native Emacs child frame with zero external dependencies beyond
;; `vertico' itself.
;;
;; Compared to `vertico-posframe' and `vertico-buffer-frame', it is
;; designed around:
;; - Persistent per-depth child-frame pooling and geometry caching to
;;   avoid frame recreation, flicker, and compositor round-trips.
;; - First-class recursive minibuffer support (e.g., nested Embark
;;   actions), with cascading offsets and automatic stack restoration.
;; - Long-path stability via `truncate-lines', `auto-hscroll-mode'
;;   set to `current-line', and fixed-height defaults.
;; - Accurate `vertico--window-width' reporting so Marginalia
;;   annotations, truncation, `vertico-grid', and `vertico-flat' align
;;   to the child frame rather than the hidden minibuffer.
;; - Clean `vertico-multiform-mode' integration and automatic fallback
;;   on TTY frames or undersized parent frames.
;;
;; Quick start:
;;   (vertico-child-frame-mode 1)
;;
;; Or via `vertico-multiform-mode':
;;   (require 'vertico-child-frame)
;;   (setq vertico-multiform-commands '((t child-frame)))
;;   (vertico-multiform-mode 1)

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'vertico)

(defvar vertico--candidates)
(defvar vertico--count-ov)
(defvar vertico--input)
(defvar vertico--scroll)
(defvar vertico-multiform--display-modes)
(defvar vertico-multiform-map)
(defvar vertico-multiform-mode)

(declare-function vertico--command-p "vertico")
(declare-function vertico--exhibit "vertico")
(declare-function vertico--update "vertico")
(declare-function vertico--window-width "vertico")
(declare-function vertico-multiform--toggle "vertico-multiform")

;;;; Customization

(defgroup vertico-child-frame nil
  "Display Vertico in a native child frame."
  :group 'vertico
  :prefix "vertico-child-frame-")

(defface vertico-child-frame
  '((t :inherit default))
  "Face used for the child-frame background, foreground, and font."
  :group 'vertico-child-frame)

(defface vertico-child-frame-border
  '((((class color) (min-colors 88) (background dark))
     :background "#505050")
    (((class color) (min-colors 88) (background light))
     :background "#c0c0c0")
    (t :background "gray"))
  "Face whose background specifies the child-frame border color."
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-golden-ratio-scale 1.0
  "Scale factor applied to default golden-ratio child-frame dimensions.
A value of 1.0 uses a frame one golden-ratio step smaller than the
largest golden rectangle fitting in the parent frame.  Values at or
above 1.618 use the full fitting golden rectangle."
  :type 'number
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-width nil
  "Width of the Vertico child frame.
If nil, default to the golden-ratio width for the parent frame (matching
`vertico-buffer-frame') and optionally widen to fit candidates per
`vertico-child-frame-width-resize', capped to the target window width
when using `window-*' or `other-window-*' poshandlers.  A float in
\(0.0, 1.0] specifies a fraction of the parent frame pixel width.  An
integer specifies the width in columns.  A function is called with the
parent frame and must return pixel width."
  :type '(choice (const :tag "Auto (golden-ratio + content adaptive)" nil)
                 (float :tag "Fraction of parent frame")
                 (integer :tag "Columns")
                 (function :tag "Function returning pixel width"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-width-resize 'grow-only
  "How child-frame width adapts to candidate content when width is nil.
- `grow-only': start at golden-ratio width and widen to fit rendered
  or visible candidates (up to 90% of parent width, `:max-width', or the
  target-window bound) without shrinking below the golden-ratio floor.
- t: dynamically widen and shrink to match current candidates (down to
  `:min-width' or 30 columns, falling back to golden-ratio width when no
  candidates are present).
- nil: disable content measurement and use fixed golden-ratio width."
  :type '(choice (const :tag "Grow only (golden-ratio floor)" grow-only)
                 (const :tag "Grow and shrink" t)
                 (const :tag "Fixed (golden-ratio width)" nil))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-min-width nil
  "Minimum child-frame width, or nil for no minimum.
An integer specifies columns; a float in (0.0, 1.0] specifies a fraction
of the parent frame pixel width."
  :type '(choice (const :tag "None" nil)
                 (float :tag "Fraction of parent frame")
                 (integer :tag "Columns"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-max-width nil
  "Maximum child-frame width, or nil for no maximum.
An integer specifies columns; a float in (0.0, 1.0] specifies a fraction
of the parent frame pixel width."
  :type '(choice (const :tag "None" nil)
                 (float :tag "Fraction of parent frame")
                 (integer :tag "Columns"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-height nil
  "Explicit height of the Vertico child frame, or nil to size automatically.
When nil, height is determined by `vertico-count' and
`vertico-child-frame-resize'.  When non-nil, it overrides dynamic
resizing: an integer specifies lines, a float in (0.0, 1.0] specifies a
fraction of the parent frame pixel height, and a function is called with
\(PARENT LINES) and must return pixel height."
  :type '(choice (const :tag "Automatic (from vertico-count / resize)" nil)
                 (float :tag "Fraction of parent frame")
                 (integer :tag "Lines")
                 (function :tag "Function returning pixel height"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-resize 'golden-ratio
  "How the child frame resizes vertically during a completion session.
Only applies when `vertico-child-frame-height' is nil.
If `golden-ratio', use the golden-ratio height matching
`vertico-buffer-frame' and adjust `vertico-count' to fit.
If nil, use a fixed height determined by `vertico-count'.
If t, grow and shrink to fit the currently displayed lines.
If `grow-only', only expand vertically during the session."
  :type '(choice (const :tag "Golden ratio (vertico-buffer-frame default)"
                        golden-ratio)
                 (const :tag "Fixed (vertico-count lines)" nil)
                 (const :tag "Grow and shrink" t)
                 (const :tag "Grow only" grow-only))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-min-height nil
  "Minimum child-frame height, or nil for 1 line.
An integer specifies lines; a float in (0.0, 1.0] specifies a fraction
of the parent frame pixel height."
  :type '(choice (const :tag "None" nil)
                 (float :tag "Fraction of parent frame")
                 (integer :tag "Lines"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-max-height nil
  "Maximum child-frame height, or nil for no maximum.
A float in (0.0, 1.0] specifies a fraction of the parent frame pixel
height.  An integer specifies the maximum number of lines."
  :type '(choice (const :tag "None" nil)
                 (float :tag "Fraction of parent frame")
                 (integer :tag "Lines"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-size-function #'vertico-child-frame-get-size
  "Function returning sizing properties for the Vertico child frame.
It is called with no arguments and must return a plist supporting
`:width', `:height', `:min-width', `:max-width', `:min-height', and
`:max-height', matching `vertico-posframe-size-function'."
  :type 'function
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-poshandler
  #'vertico-child-frame-poshandler-frame-center
  "Function or symbol computing child-frame position relative to parent.
It may be a short symbol (such as `frame-center', `window-top-center',
or `point-bottom-left-corner'), a poshandler function taking three
arguments (PARENT WIDTH HEIGHT) and returning a cons cell (X . Y) in
pixels relative to PARENT."
  :type '(choice
          (const :tag "Frame center (vertico-buffer-frame default)"
                 vertico-child-frame-poshandler-frame-center)
          (const :tag "Frame top center (command palette)"
                 vertico-child-frame-poshandler-frame-top-center)
          (const :tag "Frame bottom center"
                 vertico-child-frame-poshandler-frame-bottom-center)
          (const :tag "Frame top left corner"
                 vertico-child-frame-poshandler-frame-top-left-corner)
          (const :tag "Frame top right corner"
                 vertico-child-frame-poshandler-frame-top-right-corner)
          (const :tag "Frame bottom left corner"
                 vertico-child-frame-poshandler-frame-bottom-left-corner)
          (const :tag "Frame bottom right corner"
                 vertico-child-frame-poshandler-frame-bottom-right-corner)
          (const :tag "Frame top left or right (avoid active window)"
                 vertico-child-frame-poshandler-frame-top-left-or-right-other-corner)
          (const :tag "Window center"
                 vertico-child-frame-poshandler-window-center)
          (const :tag "Window top center"
                 vertico-child-frame-poshandler-window-top-center)
          (const :tag "Window top left corner"
                 vertico-child-frame-poshandler-window-top-left-corner)
          (const :tag "Window top right corner"
                 vertico-child-frame-poshandler-window-top-right-corner)
          (const :tag "Window bottom center"
                 vertico-child-frame-poshandler-window-bottom-center)
          (const :tag "Window bottom left corner"
                 vertico-child-frame-poshandler-window-bottom-left-corner)
          (const :tag "Window bottom right corner"
                 vertico-child-frame-poshandler-window-bottom-right-corner)
          (const :tag "Other window center"
                 vertico-child-frame-poshandler-other-window-center)
          (const :tag "Other window top center"
                 vertico-child-frame-poshandler-other-window-top-center)
          (const :tag "Other window top left corner"
                 vertico-child-frame-poshandler-other-window-top-left-corner)
          (const :tag "Other window top right corner"
                 vertico-child-frame-poshandler-other-window-top-right-corner)
          (const :tag "Other window bottom center"
                 vertico-child-frame-poshandler-other-window-bottom-center)
          (const :tag "Other window bottom left corner"
                 vertico-child-frame-poshandler-other-window-bottom-left-corner)
          (const :tag "Other window bottom right corner"
                 vertico-child-frame-poshandler-other-window-bottom-right-corner)
          (const :tag "Point bottom left corner"
                 vertico-child-frame-poshandler-point-bottom-left-corner)
          (const :tag "Point top left corner"
                 vertico-child-frame-poshandler-point-top-left-corner)
          (const :tag "Point bottom left corner (upward)"
                 vertico-child-frame-poshandler-point-bottom-left-corner-upward)
          (const :tag "Point window center"
                 vertico-child-frame-poshandler-point-window-center)
          (const :tag "Point frame center"
                 vertico-child-frame-poshandler-point-frame-center)
          (symbol :tag "Short poshandler symbol")
          (function :tag "Custom poshandler"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-offset '(0 . 0)
  "Additional pixel offset (DX . DY) added after poshandler placement."
  :type '(cons (integer :tag "Horizontal")
               (integer :tag "Vertical"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-top-offset nil
  "Vertical top offset for top-center poshandlers.
If nil, use the vertical value of `vertico-child-frame-margin'.
A float in [0.0, 1.0) specifies a fraction of parent or window height.
An integer specifies pixels."
  :type '(choice (const :tag "Use vertical margin" nil)
                 (float :tag "Fraction of height")
                 (integer :tag "Pixels"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-bottom-offset nil
  "Vertical bottom offset for bottom-center poshandlers.
If nil, use the vertical value of `vertico-child-frame-margin'.
A float in [0.0, 1.0) specifies a fraction of parent or window height.
An integer specifies pixels."
  :type '(choice (const :tag "Use vertical margin" nil)
                 (float :tag "Fraction of height")
                 (integer :tag "Pixels"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-margin '(0 . 0)
  "Minimum horizontal and vertical margin from parent frame edges in pixels."
  :type '(cons (integer :tag "Horizontal")
               (integer :tag "Vertical"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-bottom-respect-mode-line t
  "When non-nil, bottom poshandlers clear the mode-line and minibuffer.
Only applies when `vertico-child-frame-bottom-offset' is nil."
  :type 'boolean
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-recursive-offset '(24 . 24)
  "Pixel offset (DX . DY) applied per recursive minibuffer level."
  :type '(cons (integer :tag "Horizontal")
               (integer :tag "Vertical"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-font nil
  "Font name for the child frame, or nil to inherit from face or parent."
  :type '(choice (const :tag "Inherit" nil)
                 (string :tag "Font"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-alpha nil
  "Opacity for the child frame, or nil for opaque/inherited.
An integer from 0 to 100 sets `alpha-background' (background-only
transparency).  A cons cell (ACTIVE . INACTIVE) sets `alpha'."
  :type '(choice (const :tag "Opaque / inherit" nil)
                 (integer :tag "Background opacity (0-100)")
                 (cons (integer :tag "Active")
                       (integer :tag "Inactive")))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-border-width 1
  "Width of the child-frame border in pixels."
  :type 'integer
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-internal-border-width 0
  "Width of the child-frame internal border (padding) in pixels."
  :type 'integer
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-left-fringe 8
  "Width of the child-frame left fringe in pixels."
  :type 'integer
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-right-fringe 8
  "Width of the child-frame right fringe in pixels."
  :type 'integer
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-mode-line-format nil
  "Value of `mode-line-format' inside the Vertico child frame."
  :type 'sexp
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-header-line-format nil
  "Value of `header-line-format' inside the Vertico child frame."
  :type 'sexp
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-hide-minibuffer t
  "When non-nil, hide the prompt inside the parent minibuffer window."
  :type 'boolean
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-truncate-lines 'auto
  "How long lines are handled inside the child frame.
If `auto', truncate lines while the prompt and input fit within 80% of
the child-frame width, and wrap automatically when input grows longer.
If nil, always wrap long lines.  If t, always truncate long lines."
  :type '(choice (const :tag "Auto-wrap long input" auto)
                 (const :tag "Always wrap" nil)
                 (const :tag "Always truncate" t))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-min-parent-width 40
  "Minimum parent frame width in columns required to show a child frame."
  :type 'integer
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-min-parent-height 10
  "Minimum parent frame height in lines required to show a child frame."
  :type 'integer
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-fallback-mode nil
  "Optional Vertico display minor mode to enable when child frames cannot be used.
For example, `vertico-buffer-mode' or `vertico-flat-mode'."
  :type '(choice (const :tag "Standard minibuffer" nil)
                 (symbol :tag "Minor mode symbol"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-prewarm t
  "When non-nil, pre-create a hidden depth-1 child frame while idle.
This avoids first-popup `make-frame' and face-realization latency."
  :type 'boolean
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-parameters nil
  "Extra frame parameters merged when creating Vertico child frames."
  :type '(alist :key-type symbol :value-type sexp)
  :group 'vertico-child-frame)

;;;; Internal state

(defconst vertico-child-frame--default-parameters
  '((no-accept-focus . t)
    (no-focus-on-map . t)
    (min-width . t)
    (min-height . t)
    (border-width . 0)
    (outer-border-width . 0)
    (vertical-scroll-bars . nil)
    (horizontal-scroll-bars . nil)
    (menu-bar-lines . 0)
    (tool-bar-lines . 0)
    (tab-bar-lines . 0)
    (no-other-frame . t)
    (unsplittable . t)
    (undecorated . t)
    (no-special-glyphs . t)
    (desktop-dont-save . t)
    (inhibit-double-buffering . nil)
    (skip-taskbar . t)
    (user-position . t)
    (user-size . t))
  "Default frame parameters for Vertico child frames.")

(defvar vertico-child-frame--pool nil
  "Alist mapping minibuffer recursion depth to pooled child frames.")

(defvar vertico-child-frame--active-frames nil
  "Alist mapping active recursion depth to its visible child frame.")

(defvar vertico-child-frame--active-buffers nil
  "List of minibuffer buffers currently displayed in a child frame.")

(defvar vertico-child-frame--resizing nil
  "Non-nil while programmatically resizing or repositioning a child frame.")

(defvar-local vertico-child-frame--active nil
  "Non-nil when the current minibuffer is displayed in a child frame.")

(defvar-local vertico-child-frame--frame nil
  "Child frame assigned to the current minibuffer session.")

(defvar-local vertico-child-frame--window nil
  "Root window of the child frame for the current minibuffer session.")

(defvar-local vertico-child-frame--depth nil
  "Minibuffer recursion depth for the current child-frame session.")

(defvar-local vertico-child-frame--parent nil
  "Parent frame for the current child-frame session.")

(defconst vertico-child-frame--golden-ratio (/ (+ 1.0 (sqrt 5.0)) 2.0)
  "Golden ratio used for default child-frame dimensions.")

(defconst vertico-child-frame--auto-width-max-ratio 0.9
  "Maximum auto-width fraction of parent width so a margin remains.")

(defconst vertico-child-frame--tty-cell-aspect 2.0
  "Assumed height-to-width visual aspect ratio of a TTY character cell.")

(defvar vertico-child-frame--in-redisplay nil
  "Non-nil while executing inside `pre-redisplay-functions'.")

(defvar vertico-child-frame--exhibiting nil
  "Non-nil while re-exhibiting Vertico after an auto-width growth.")

(defvar vertico-child-frame--warmup-timer nil
  "Idle timer scheduled for child-frame pre-warming.")

(defvar-local vertico-child-frame--content-width-cache nil
  "Cached content-width entry `(KEY . PIXELS)' for reuse.")

(defvar-local vertico-child-frame--max-height-seen 0
  "Maximum line count observed so far in `grow-only' resize mode.")

(defvar-local vertico-child-frame--max-width-seen 0
  "Maximum text width in pixels observed in `grow-only' width mode.")

(defvar-local vertico-child-frame--orig-vertico-count nil
  "Original `vertico-count' value before child-frame setup.")

(defvar-local vertico-child-frame--orig-vertico-count-local nil
  "Non-nil if `vertico-count' was buffer-local before setup.")

(defvar-local vertico-child-frame--last-lines nil
  "Last candidate line count passed to `vertico-child-frame--resize'.")

(defvar-local vertico-child-frame--saved-cursor nil
  "Saved `cursor-in-non-selected-windows' value before setup.")

(defvar-local vertico-child-frame--init-timer nil
  "Idle timer ensuring initial candidate exhibition after frame mapping.")

(defvar-local vertico-child-frame--fallback-active nil
  "Fallback mode symbol activated for the current session, if any.")

(defvar-local vertico-child-frame--orig-truncate-lines nil
  "Original `truncate-lines' value before child-frame setup.")

(defvar-local vertico-child-frame--orig-word-wrap nil
  "Original `word-wrap' value before child-frame setup.")

(defvar-local vertico-child-frame--orig-auto-hscroll nil
  "Original `auto-hscroll-mode' value before child-frame setup.")

(defvar-local vertico-child-frame--orig-resize-mini nil
  "Original `resize-mini-windows' value before child-frame setup.")

(defvar-local vertico-child-frame--orig-mode-line nil
  "Original `mode-line-format' value before child-frame setup.")

(defvar-local vertico-child-frame--orig-header-line nil
  "Original `header-line-format' value before child-frame setup.")

(defvar-local vertico-child-frame--orig-tab-line nil
  "Original `tab-line-format' value before child-frame setup.")

;;;; Support detection and fallback

(defun vertico-child-frame--tty-p (&optional frame)
  "Return non-nil if FRAME is a non-graphical (TTY) frame."
  (not (display-graphic-p frame)))

(defun vertico-child-frame--supported-p (&optional frame)
  "Return non-nil if child frames are supported on FRAME."
  (or (display-graphic-p frame)
      (and (or (featurep 'tty-child-frames)
               (and (boundp 'tty-child-frames)
                    (symbol-value 'tty-child-frames)))
           (or (null frame) (frame-live-p frame))
           (not (null (tty-type frame))))))

(defun vertico-child-frame--can-display-p (parent)
  "Return non-nil if PARENT can host a Vertico child frame."
  (and (frame-live-p parent)
       (vertico-child-frame--supported-p parent)
       (>= (frame-width parent) vertico-child-frame-min-parent-width)
       (>= (frame-height parent) vertico-child-frame-min-parent-height)))

(defun vertico-child-frame--deactivate-fallback ()
  "Disable the temporary fallback mode activated for this session."
  (remove-hook 'minibuffer-exit-hook
               #'vertico-child-frame--deactivate-fallback :local)
  (when (and vertico-child-frame--fallback-active
             (fboundp vertico-child-frame--fallback-active))
    (let ((mode vertico-child-frame--fallback-active))
      (setq vertico-child-frame--fallback-active nil)
      (ignore-errors (funcall mode -1)))))

(defun vertico-child-frame--activate-fallback ()
  "Activate `vertico-child-frame-fallback-mode' for this session if configured."
  (when-let* ((mode vertico-child-frame-fallback-mode)
              ((fboundp mode))
              ((not vertico-child-frame--fallback-active))
              ((not (and (boundp mode) (symbol-value mode)))))
    (setq vertico-child-frame--fallback-active mode)
    (funcall mode 1)
    (add-hook 'minibuffer-exit-hook
              #'vertico-child-frame--deactivate-fallback nil :local)))

(defun vertico-child-frame--before-setup (&rest _args)
  "Activate fallback display mode before `vertico--setup' dispatches."
  (when (and (bound-and-true-p vertico-child-frame-mode)
             (minibufferp))
    (let* ((mbwin (or (active-minibuffer-window) (selected-window)))
           (parent (and (window-live-p mbwin) (window-frame mbwin))))
      (unless (vertico-child-frame--can-display-p parent)
        (setq vertico-child-frame--active nil)
        (vertico-child-frame--activate-fallback)))))

;;;; Geometry and poshandlers

(defun vertico-child-frame--resolve-bound (spec parent-px unit-px default-px)
  "Resolve bound SPEC against PARENT-PX, UNIT-PX, and DEFAULT-PX."
  (cond
   ((and (floatp spec) (<= spec 1.0) (> spec 0.0))
    (round (* parent-px spec)))
   ((integerp spec)
    (* (max 1 spec) unit-px))
   (t default-px)))

(defun vertico-child-frame--scale-tty-px (px unit)
  "Scale pixel distance PX to TTY character cells using cell size UNIT."
  (if (or (not (numberp px)) (zerop px))
      0
    (let ((mag (max 1 (round (/ (float (abs px)) unit)))))
      (if (< px 0) (- mag) mag))))

(defun vertico-child-frame--tty-border-width ()
  "Return TTY child-frame border width in character cells (0 or 1)."
  (if (or (and (integerp vertico-child-frame-border-width)
               (> vertico-child-frame-border-width 0))
          (and (integerp vertico-child-frame-internal-border-width)
               (> vertico-child-frame-internal-border-width 0)))
      1
    0))

(defun vertico-child-frame--margin (&optional parent)
  "Return horizontal and vertical margin (MX . MY) for PARENT."
  (let ((mx (max 0 (or (car-safe vertico-child-frame-margin) 0)))
        (my (max 0 (or (cdr-safe vertico-child-frame-margin) 0))))
    (if (vertico-child-frame--tty-p parent)
        (cons (vertico-child-frame--scale-tty-px mx 10)
              (vertico-child-frame--scale-tty-px my 20))
      (cons mx my))))

(defun vertico-child-frame--chrome-size (&optional parent)
  "Return outer frame chrome (WIDTH . HEIGHT) on PARENT."
  (if (vertico-child-frame--tty-p parent)
      (let ((border (vertico-child-frame--tty-border-width)))
        (cons (* 2 border) (* 2 border)))
    (let ((border (max 0 (if (and (integerp vertico-child-frame-border-width)
                                  (> vertico-child-frame-border-width 0))
                             vertico-child-frame-border-width
                           (or vertico-child-frame-internal-border-width 0)))))
      (cons (+ (max 0 vertico-child-frame-left-fringe)
               (max 0 vertico-child-frame-right-fringe)
               (* 2 border))
            (* 2 border)))))

(defun vertico-child-frame-get-size ()
  "Return the default sizing plist for `vertico-child-frame-size-function'."
  (list :width vertico-child-frame-width
        :height vertico-child-frame-height
        :min-width vertico-child-frame-min-width
        :max-width vertico-child-frame-max-width
        :min-height vertico-child-frame-min-height
        :max-height vertico-child-frame-max-height))

(defun vertico-child-frame--size-option (size-plist key fallback)
  "Read KEY from SIZE-PLIST if present, otherwise return FALLBACK."
  (if (and size-plist (plist-member size-plist key))
      (plist-get size-plist key)
    fallback))

(defun vertico-child-frame--target-window-max-width (parent)
  "Return pixel width of target window on PARENT when narrower than PARENT."
  (let* ((fn (vertico-child-frame--resolve-poshandler
              vertico-child-frame-poshandler))
         (win (cond
               ((memq fn '(vertico-child-frame-poshandler-window-center
                           vertico-child-frame-poshandler-window-top-center
                           vertico-child-frame-poshandler-window-top-left-corner
                           vertico-child-frame-poshandler-window-top-right-corner
                           vertico-child-frame-poshandler-window-bottom-center
                           vertico-child-frame-poshandler-window-bottom-left-corner
                           vertico-child-frame-poshandler-window-bottom-right-corner))
                (vertico-child-frame--selected-window parent))
               ((memq fn '(vertico-child-frame-poshandler-other-window-center
                           vertico-child-frame-poshandler-other-window-top-center
                           vertico-child-frame-poshandler-other-window-top-left-corner
                           vertico-child-frame-poshandler-other-window-top-right-corner
                           vertico-child-frame-poshandler-other-window-bottom-center
                           vertico-child-frame-poshandler-other-window-bottom-left-corner
                           vertico-child-frame-poshandler-other-window-bottom-right-corner))
                (or (vertico-child-frame--other-window parent)
                    (vertico-child-frame--selected-window parent))))))
    (when (window-live-p win)
      (pcase-let ((`(,left ,_top ,right ,_bottom) (window-pixel-edges win)))
        (let ((win-w (- right left)))
          (when (< win-w (frame-pixel-width parent))
            win-w))))))

(defun vertico-child-frame--golden-pixel-size (parent)
  "Return golden-ratio child-frame dimensions in pixels for PARENT."
  (let* ((cw (max 1 (frame-char-width parent)))
         (lh (max 1 (frame-char-height parent)))
         (pw (max cw (frame-pixel-width parent)))
         (ph (max lh (frame-pixel-height parent)))
         (tty-p (vertico-child-frame--tty-p parent))
         (aspect (if tty-p vertico-child-frame--tty-cell-aspect 1.0))
         (eff-ph (if tty-p (* ph aspect) ph))
         (parent-ratio (/ (float pw) eff-ph))
         (golden-w (if (> parent-ratio vertico-child-frame--golden-ratio)
                       (* eff-ph vertico-child-frame--golden-ratio)
                     pw))
         (golden-h (if (> parent-ratio vertico-child-frame--golden-ratio)
                       ph
                     (if tty-p
                         (/ pw vertico-child-frame--golden-ratio aspect)
                       (/ pw vertico-child-frame--golden-ratio))))
         (scale-num (if (numberp vertico-child-frame-golden-ratio-scale)
                        (float vertico-child-frame-golden-ratio-scale)
                      1.0))
         (scale (min 1.0
                     (max 0.0
                          (/ (max 0.0 scale-num)
                             vertico-child-frame--golden-ratio)))))
    (cons (max cw (round (* golden-w scale)))
          (max lh (round (* golden-h scale))))))

(defun vertico-child-frame--visible-candidates ()
  "Return the currently visible Vertico candidates as a list of strings."
  (when (and (boundp 'vertico--candidates)
             (listp vertico--candidates)
             vertico--candidates)
    (let* ((scroll (if (boundp 'vertico--scroll) (or vertico--scroll 0) 0))
           (count (if (boundp 'vertico-count) (or vertico-count 10) 10))
           (total (length vertico--candidates))
           (start (max 0 (min scroll total)))
           (end (min total (+ start (max 1 count)))))
      (when (< start end)
        (cl-subseq vertico--candidates start end)))))

(defun vertico-child-frame--content-pixel-width (parent &optional cap-px)
  "Return widest visible candidate pixel width on PARENT, or nil.
CAP-PX bounds measurement so redundant layout passes can be skipped."
  (let* ((rendered (and (boundp 'vertico--candidates-ov)
                        (overlayp vertico--candidates-ov)
                        (overlay-get vertico--candidates-ov 'before-string)))
         (cands (and (boundp 'vertico--candidates) vertico--candidates))
         (scroll (if (boundp 'vertico--scroll) (or vertico--scroll 0) 0))
         (count (if (boundp 'vertico-count) (or vertico-count 10) 10))
         (parent-cw (max 1 (frame-char-width parent)))
         (child-cw (if (frame-live-p vertico-child-frame--frame)
                       (max 1 (frame-char-width vertico-child-frame--frame))
                     parent-cw))
         (cached vertico-child-frame--content-width-cache)
         (k (car cached)))
    (if (and cached
             (eq (nth 0 k) rendered)
             (eq (nth 1 k) cands)
             (eql (nth 2 k) scroll)
             (eql (nth 3 k) count)
             (eql (nth 4 k) parent-cw)
             (eql (nth 5 k) child-cw))
        (cdr cached)
      (let (widths rendered-px)
        (when (and (stringp rendered) (string-match-p "\n" rendered))
          (when-let* ((px (ignore-errors (string-pixel-width rendered))))
            (setq rendered-px px)
            (push px widths)))
        (unless (and cap-px rendered-px (>= rendered-px cap-px))
          (let* ((visible (vertico-child-frame--visible-candidates))
                 (text (and visible
                            (mapconcat (lambda (cand)
                                         (if (stringp cand) cand ""))
                                       visible "\n"))))
            (when (and text (> (length text) 0))
              (when-let* ((px (ignore-errors (string-pixel-width text))))
                (push px widths)))))
        (let ((result (when widths
                        (round (* (apply #'max widths)
                                  (/ (float child-cw) parent-cw))))))
          (setq vertico-child-frame--content-width-cache
                (cons (list rendered cands scroll count parent-cw child-cw)
                      result))
          result)))))

(defun vertico-child-frame--resolve-width (parent &optional size-plist)
  "Compute child-frame text width in pixels for PARENT using SIZE-PLIST."
  (let* ((cw (max 1 (frame-char-width parent)))
         (pw (max cw (frame-pixel-width parent)))
         (chrome-w (car (vertico-child-frame--chrome-size parent)))
         (margin-x (car (vertico-child-frame--margin parent)))
         (avail-w (if (> pw (* 2 margin-x)) (- pw (* 2 margin-x)) pw))
         (max-parent-px (max cw (- avail-w chrome-w)))
         (spec (vertico-child-frame--size-option
                size-plist :width vertico-child-frame-width))
         (min-spec (vertico-child-frame--size-option
                    size-plist :min-width vertico-child-frame-min-width))
         (max-spec (vertico-child-frame--size-option
                    size-plist :max-width vertico-child-frame-max-width))
         (win-w (and (null spec)
                     (vertico-child-frame--target-window-max-width parent)))
         (win-cap (when win-w
                    (max cw (- win-w (* 2 margin-x) chrome-w))))
         (min-px (vertico-child-frame--resolve-bound min-spec pw cw cw))
         (max-px (vertico-child-frame--resolve-bound
                  max-spec pw cw max-parent-px))
         (upper (max cw (min max-px max-parent-px)))
         (effective-upper (if win-cap (min upper win-cap) upper))
         (lower (min min-px effective-upper))
         (golden-w (car (vertico-child-frame--golden-pixel-size parent)))
         (base-w (max lower (min effective-upper golden-w)))
         (auto-upper
          (if (or max-spec win-cap)
              effective-upper
            (max base-w
                 (min effective-upper
                      (floor (* max-parent-px
                                vertico-child-frame--auto-width-max-ratio))))))
         (hit-cap (and (null spec)
                       (eq vertico-child-frame-width-resize 'grow-only)
                       (> auto-upper 0)
                       (>= vertico-child-frame--max-width-seen auto-upper)))
         (content-px (when (and (null spec)
                                vertico-child-frame-width-resize
                                (not hit-cap))
                       (vertico-child-frame--content-pixel-width
                        parent auto-upper)))
         (raw-px
          (cond
           ((functionp spec) (round (funcall spec parent)))
           ((and (floatp spec) (<= spec 1.0) (> spec 0.0))
            (round (* pw spec)))
           ((integerp spec) (* (max 1 spec) cw))
           (content-px
            (let ((padded (+ content-px (* 6 cw))))
              (if (eq vertico-child-frame-width-resize 'grow-only)
                  (let ((target (max base-w (min auto-upper padded))))
                    (setq vertico-child-frame--max-width-seen
                          (max vertico-child-frame--max-width-seen target)))
                (let ((shrink-floor
                       (if min-spec lower (min effective-upper (* 30 cw)))))
                  (max shrink-floor (min auto-upper padded))))))
           ((and (eq vertico-child-frame-width-resize 'grow-only)
                 (> vertico-child-frame--max-width-seen 0))
            (min auto-upper (max base-w vertico-child-frame--max-width-seen)))
           (t base-w))))
    (max lower (min effective-upper raw-px))))

(defun vertico-child-frame--prompt-width ()
  "Return display width in columns of the minibuffer prompt and input."
  (if (minibufferp)
      (string-width (buffer-substring-no-properties (point-min) (point-max)))
    0))

(defun vertico-child-frame--update-truncation (&optional win)
  "Update `truncate-lines' and horizontal scroll for child-frame WIN."
  (let* ((cols (max 1 (cond
                       ((window-live-p win) (window-width win))
                       ((frame-live-p vertico-child-frame--parent)
                        (/ (vertico-child-frame--resolve-width
                            vertico-child-frame--parent)
                           (max 1 (frame-char-width
                                   vertico-child-frame--parent))))
                       (t 80))))
         (desired (if (eq vertico-child-frame-truncate-lines 'auto)
                      (< (vertico-child-frame--prompt-width) (* 0.8 cols))
                    vertico-child-frame-truncate-lines)))
    (setq-local truncate-lines desired)
    (unless desired
      (setq-local word-wrap nil)
      (when (window-live-p win)
        (set-window-hscroll win 0)))))

(defun vertico-child-frame--prompt-lines (parent width-px)
  "Return visual line count of the minibuffer prompt on PARENT at WIDTH-PX."
  (if (or (not (minibufferp)) truncate-lines)
      1
    (let* ((cols (max 1 (/ width-px (max 1 (frame-char-width parent)))))
           (text (buffer-substring-no-properties (point-min) (point-max)))
           (lines (split-string text "\n"))
           (total 0))
      (dolist (line lines)
        (setq total (+ total (max 1 (ceiling (max 1 (1+ (string-width line))) cols)))))
      (max 1 total))))

(defun vertico-child-frame--resolve-height
    (parent lines &optional prompt-lines size-plist)
  "Compute child-frame height on PARENT for LINES using SIZE-PLIST.
PROMPT-LINES counts wrapped prompt lines."
  (let* ((lh (max 1 (frame-char-height parent)))
         (ph (max lh (frame-pixel-height parent)))
         (chrome-h (cdr (vertico-child-frame--chrome-size parent)))
         (margin-y (cdr (vertico-child-frame--margin parent)))
         (avail-h (if (> ph (* 2 margin-y)) (- ph (* 2 margin-y)) ph))
         (max-parent-px (max lh (- avail-h chrome-h)))
         (pl (max 1 (or prompt-lines 1)))
         (prompt-plus-lines (max 1 (+ pl lines)))
         (hspec (vertico-child-frame--size-option
                 size-plist :height vertico-child-frame-height))
         (min-spec (vertico-child-frame--size-option
                    size-plist :min-height vertico-child-frame-min-height))
         (max-spec (vertico-child-frame--size-option
                    size-plist :max-height vertico-child-frame-max-height))
         (raw-px
          (cond
           ((functionp hspec) (round (funcall hspec parent lines)))
           ((and (floatp hspec) (<= hspec 1.0) (> hspec 0.0))
            (round (* ph hspec)))
           ((integerp hspec) (* (max 1 hspec) lh))
           (t
            (pcase vertico-child-frame-resize
              ('golden-ratio
               (cdr (vertico-child-frame--golden-pixel-size parent)))
              ('nil (* (max 1 (+ pl vertico-count)) lh))
              ('grow-only
               (* (setq vertico-child-frame--max-height-seen
                        (max vertico-child-frame--max-height-seen
                             prompt-plus-lines))
                  lh))
              (_ (* prompt-plus-lines lh))))))
         (min-px (vertico-child-frame--resolve-bound min-spec ph lh lh))
         (max-px (min max-parent-px
                      (vertico-child-frame--resolve-bound
                       max-spec ph lh max-parent-px)))
         (upper (max lh max-px))
         (lower (min min-px upper)))
    (max lower (min upper raw-px))))

(defun vertico-child-frame--sync-vertico-count
    (parent height prompt-lines &optional size-plist)
  "Adjust buffer-local `vertico-count' on PARENT for HEIGHT and PROMPT-LINES.
Uses SIZE-PLIST to check whether an explicit height was configured."
  (when (and (minibufferp) (frame-live-p parent))
    (let ((hspec (vertico-child-frame--size-option
                  size-plist :height vertico-child-frame-height)))
      (when (or hspec (eq vertico-child-frame-resize 'golden-ratio))
        (let* ((lh (max 1 (frame-char-height parent)))
               (pl (max 1 (or prompt-lines 1)))
               (target (max 1 (- (/ height lh) pl 1))))
          (unless (= vertico-count target)
            (setq-local vertico-count target)))))))

(defun vertico-child-frame--clamp-coord (coord size parent-size margin)
  "Clamp COORD of SIZE within PARENT-SIZE respecting MARGIN."
  (let* ((eff-margin (if (>= parent-size (+ size (* 2 margin))) margin 0))
         (max-coord (max eff-margin (- parent-size size eff-margin))))
    (max eff-margin (min max-coord coord))))

(defun vertico-child-frame--clamp-position (parent x y width height)
  "Clamp (X, Y) for child frame of WIDTH by HEIGHT within PARENT."
  (pcase-let ((`(,mx . ,my) (vertico-child-frame--margin parent))
              (pw (frame-pixel-width parent))
              (ph (frame-pixel-height parent)))
    (cons (vertico-child-frame--clamp-coord x width pw mx)
          (vertico-child-frame--clamp-coord y height ph my))))

(defun vertico-child-frame--resolve-offset (offset dim &optional parent)
  "Resolve OFFSET against pixel dimension DIM on PARENT."
  (cond
   ((null offset) (cdr (vertico-child-frame--margin parent)))
   ((and (floatp offset) (< offset 1.0) (>= offset 0.0))
    (round (* dim offset)))
   ((vertico-child-frame--tty-p parent)
    (vertico-child-frame--scale-tty-px offset 20))
   (t (round offset))))

(defun vertico-child-frame--selected-window (parent)
  "Return the selected window if it belongs to PARENT."
  (let ((win (minibuffer-selected-window)))
    (when (and (window-live-p win) (eq (window-frame win) parent))
      win)))

(defun vertico-child-frame--selected-window-edges (parent)
  "Return pixel edges of the selected window if it belongs to PARENT."
  (when-let* ((win (vertico-child-frame--selected-window parent)))
    (window-pixel-edges win)))

(defun vertico-child-frame--other-window (parent)
  "Return another regular window on PARENT, or nil."
  (let ((selected (minibuffer-selected-window)))
    (cl-loop for win in (window-list parent 'no-minibuf selected)
             when (and (not (eq win selected))
                       (window-live-p win)
                       (not (window-minibuffer-p win))
                       (not (window-parameter win 'no-other-window)))
             return win)))

(defun vertico-child-frame--other-window-edges (parent)
  "Return pixel edges of another regular window on PARENT, or nil."
  (when-let* ((win (vertico-child-frame--other-window parent)))
    (window-pixel-edges win)))

(defun vertico-child-frame--window-mode-line-height (win)
  "Return the mode-line pixel height of WIN, or 0."
  (if (and (window-live-p win) (fboundp 'window-mode-line-height))
      (window-mode-line-height win)
    0))

(defun vertico-child-frame--frame-bottom-inset (parent)
  "Return bottom inset in pixels on PARENT for bottom-aligned poshandlers."
  (if vertico-child-frame-bottom-offset
      (vertico-child-frame--resolve-offset
       vertico-child-frame-bottom-offset (frame-pixel-height parent) parent)
    (+ (cdr (vertico-child-frame--margin parent))
       (if vertico-child-frame-bottom-respect-mode-line
           (+ (let ((mb (minibuffer-window parent)))
                (if (and (window-live-p mb) (eq (window-frame mb) parent))
                    (window-pixel-height mb)
                  0))
              (vertico-child-frame--window-mode-line-height
               (vertico-child-frame--selected-window parent)))
         0))))

(defun vertico-child-frame--window-bottom-inset (win win-h)
  "Return bottom inset in pixels on WIN of pixel height WIN-H."
  (let ((parent (and (window-live-p win) (window-frame win))))
    (if vertico-child-frame-bottom-offset
        (vertico-child-frame--resolve-offset
         vertico-child-frame-bottom-offset win-h parent)
      (+ (cdr (vertico-child-frame--margin parent))
         (if vertico-child-frame-bottom-respect-mode-line
             (vertico-child-frame--window-mode-line-height win)
           0)))))

(defun vertico-child-frame--position-in-edges (anchor edges width height &optional win)
  "Compute (X . Y) for ANCHOR in pixel EDGES of WIN for WIDTH by HEIGHT."
  (let ((parent (and (window-live-p win) (window-frame win))))
    (pcase-let ((`(,left ,top ,right ,bottom) edges)
                (`(,mx . ,my) (vertico-child-frame--margin parent)))
      (pcase anchor
        ('center
         (cons (+ left (round (/ (- (- right left) width) 2.0)))
               (+ top (round (/ (- (- bottom top) height) 2.0)))))
        ('top-center
         (let ((win-w (- right left))
               (win-h (- bottom top)))
           (cons (+ left (round (/ (- win-w width) 2.0)))
                 (+ top (vertico-child-frame--resolve-offset
                         vertico-child-frame-top-offset win-h parent)))))
        ('top-left-corner (cons (+ left mx) (+ top my)))
        ('top-right-corner (cons (- right width mx) (+ top my)))
        ('bottom-center
         (cons (+ left (round (/ (- (- right left) width) 2.0)))
               (- bottom height
                  (vertico-child-frame--window-bottom-inset win (- bottom top)))))
        ('bottom-left-corner
         (cons (+ left mx)
               (- bottom height
                  (vertico-child-frame--window-bottom-inset win (- bottom top)))))
        ('bottom-right-corner
         (cons (- right width mx)
               (- bottom height
                  (vertico-child-frame--window-bottom-inset win (- bottom top)))))))))

(defun vertico-child-frame--point-pixel-position (parent)
  "Return (X Y LINE-HEIGHT) in pixels for point in selected window on PARENT."
  (let ((win (minibuffer-selected-window)))
    (when (and (window-live-p win) (eq (window-frame win) parent))
      (when-let* ((posn (posn-at-point (window-point win) win))
                  (xy (posn-x-y posn)))
        (pcase-let ((`(,in-left ,in-top ,_in-right ,_in-bottom)
                     (window-inside-pixel-edges win)))
          (let* ((obj-wh (posn-object-width-height posn))
                 (lh (max 1 (or (cdr obj-wh) (frame-char-height parent)))))
            (list (+ in-left (car xy))
                  (+ in-top (cdr xy))
                  lh)))))))

(defun vertico-child-frame--point-y-below-or-above (parent py lh height)
  "Return Y below PY (with line height LH) or above if HEIGHT overflows PARENT."
  (let ((my (cdr (vertico-child-frame--margin parent)))
        (ph (frame-pixel-height parent)))
    (if (and (> (+ py lh height my) ph)
             (>= (- py height) my))
        (- py height)
      (+ py lh))))

(defun vertico-child-frame-poshandler-frame-top-center (parent width _height)
  "Position child frame of WIDTH at top center of PARENT."
  (let ((x (round (/ (- (frame-pixel-width parent) width) 2.0)))
        (y (vertico-child-frame--resolve-offset
            vertico-child-frame-top-offset
            (frame-pixel-height parent)
            parent)))
    (cons x y)))

(defalias 'vertico-child-frame-poshandler-top-center
  #'vertico-child-frame-poshandler-frame-top-center)

(defun vertico-child-frame-poshandler-frame-center (parent width height)
  "Position child frame of WIDTH by HEIGHT at center of PARENT."
  (cons (round (/ (- (frame-pixel-width parent) width) 2.0))
        (round (/ (- (frame-pixel-height parent) height) 2.0))))

(defalias 'vertico-child-frame-poshandler-center
  #'vertico-child-frame-poshandler-frame-center)

(defun vertico-child-frame-poshandler-frame-bottom-center (parent width height)
  "Position child frame of WIDTH by HEIGHT near bottom center of PARENT."
  (cons (round (/ (- (frame-pixel-width parent) width) 2.0))
        (- (frame-pixel-height parent)
           height
           (vertico-child-frame--frame-bottom-inset parent))))

(defalias 'vertico-child-frame-poshandler-bottom-center
  #'vertico-child-frame-poshandler-frame-bottom-center)

(defun vertico-child-frame-poshandler-frame-top-left-corner (parent _width _height)
  "Position child frame at the top-left corner of PARENT within margins."
  (vertico-child-frame--margin parent))

(defun vertico-child-frame-poshandler-frame-top-right-corner (parent width _height)
  "Position child frame of WIDTH at the top-right corner of PARENT."
  (pcase-let ((`(,mx . ,my) (vertico-child-frame--margin parent)))
    (cons (- (frame-pixel-width parent) width mx) my)))

(defun vertico-child-frame-poshandler-frame-bottom-left-corner (parent _width height)
  "Position child frame of HEIGHT at the bottom-left corner of PARENT."
  (cons (car (vertico-child-frame--margin parent))
        (- (frame-pixel-height parent)
           height
           (vertico-child-frame--frame-bottom-inset parent))))

(defun vertico-child-frame-poshandler-frame-bottom-right-corner (parent width height)
  "Position child frame of WIDTH by HEIGHT at bottom-right corner of PARENT."
  (cons (- (frame-pixel-width parent) width
           (car (vertico-child-frame--margin parent)))
        (- (frame-pixel-height parent)
           height
           (vertico-child-frame--frame-bottom-inset parent))))

(defun vertico-child-frame-poshandler-frame-top-left-or-right-other-corner
    (parent width height)
  "Position child frame of WIDTH by HEIGHT at top corner opposite active window.
Uses PARENT top-right when the selected window is on the left half,
otherwise top-left."
  (let ((edges (vertico-child-frame--selected-window-edges parent)))
    (if (and edges
             (< (/ (+ (nth 0 edges) (nth 2 edges)) 2.0)
                (/ (frame-pixel-width parent) 2.0)))
        (vertico-child-frame-poshandler-frame-top-right-corner parent width height)
      (vertico-child-frame-poshandler-frame-top-left-corner parent width height))))

(defun vertico-child-frame-poshandler-window-center (parent width height)
  "Position child frame of WIDTH by HEIGHT at center of selected window.
Falls back to PARENT center if no selected window belongs to PARENT."
  (if-let* ((win (vertico-child-frame--selected-window parent)))
      (vertico-child-frame--position-in-edges
       'center (window-pixel-edges win) width height win)
    (vertico-child-frame-poshandler-frame-center parent width height)))

(defun vertico-child-frame-poshandler-window-top-center (parent width height)
  "Position child frame of WIDTH by HEIGHT at top center of selected window.
Falls back to PARENT top center if no selected window belongs to PARENT."
  (if-let* ((win (vertico-child-frame--selected-window parent)))
      (vertico-child-frame--position-in-edges
       'top-center (window-pixel-edges win) width height win)
    (vertico-child-frame-poshandler-frame-top-center parent width height)))

(defun vertico-child-frame-poshandler-window-top-left-corner (parent width height)
  "Position child frame of WIDTH by HEIGHT at top-left of selected window.
Falls back to PARENT top-left if no selected window belongs to PARENT."
  (if-let* ((win (vertico-child-frame--selected-window parent)))
      (vertico-child-frame--position-in-edges
       'top-left-corner (window-pixel-edges win) width height win)
    (vertico-child-frame-poshandler-frame-top-left-corner parent width height)))

(defun vertico-child-frame-poshandler-window-top-right-corner (parent width height)
  "Position child frame of WIDTH by HEIGHT at top-right of selected window.
Falls back to PARENT top-right if no selected window belongs to PARENT."
  (if-let* ((win (vertico-child-frame--selected-window parent)))
      (vertico-child-frame--position-in-edges
       'top-right-corner (window-pixel-edges win) width height win)
    (vertico-child-frame-poshandler-frame-top-right-corner parent width height)))

(defun vertico-child-frame-poshandler-window-bottom-center (parent width height)
  "Position child frame of WIDTH by HEIGHT at bottom center of selected window.
Falls back to PARENT bottom center if no selected window belongs to PARENT."
  (if-let* ((win (vertico-child-frame--selected-window parent)))
      (vertico-child-frame--position-in-edges
       'bottom-center (window-pixel-edges win) width height win)
    (vertico-child-frame-poshandler-frame-bottom-center parent width height)))

(defun vertico-child-frame-poshandler-window-bottom-left-corner (parent width height)
  "Position child frame of WIDTH by HEIGHT at bottom-left of selected window.
Falls back to PARENT bottom-left if no selected window belongs to PARENT."
  (if-let* ((win (vertico-child-frame--selected-window parent)))
      (vertico-child-frame--position-in-edges
       'bottom-left-corner (window-pixel-edges win) width height win)
    (vertico-child-frame-poshandler-frame-bottom-left-corner parent width height)))

(defun vertico-child-frame-poshandler-window-bottom-right-corner (parent width height)
  "Position child frame of WIDTH by HEIGHT at bottom-right of selected window.
Falls back to PARENT bottom-right if no selected window belongs to PARENT."
  (if-let* ((win (vertico-child-frame--selected-window parent)))
      (vertico-child-frame--position-in-edges
       'bottom-right-corner (window-pixel-edges win) width height win)
    (vertico-child-frame-poshandler-frame-bottom-right-corner parent width height)))

(defun vertico-child-frame-poshandler-other-window-center (parent width height)
  "Position child frame of WIDTH by HEIGHT at center of another window.
Falls back to selected window center on PARENT if only one window exists."
  (if-let* ((win (vertico-child-frame--other-window parent)))
      (vertico-child-frame--position-in-edges
       'center (window-pixel-edges win) width height win)
    (vertico-child-frame-poshandler-window-center parent width height)))

(defun vertico-child-frame-poshandler-other-window-top-center (parent width height)
  "Position child frame of WIDTH by HEIGHT at top center of another window.
Falls back to selected window top center on PARENT if none exists."
  (if-let* ((win (vertico-child-frame--other-window parent)))
      (vertico-child-frame--position-in-edges
       'top-center (window-pixel-edges win) width height win)
    (vertico-child-frame-poshandler-window-top-center parent width height)))

(defun vertico-child-frame-poshandler-other-window-top-left-corner
    (parent width height)
  "Position child frame of WIDTH by HEIGHT at top-left of another window.
Falls back to selected window top-left on PARENT if none exists."
  (if-let* ((win (vertico-child-frame--other-window parent)))
      (vertico-child-frame--position-in-edges
       'top-left-corner (window-pixel-edges win) width height win)
    (vertico-child-frame-poshandler-window-top-left-corner parent width height)))

(defun vertico-child-frame-poshandler-other-window-top-right-corner
    (parent width height)
  "Position child frame of WIDTH by HEIGHT at top-right of another window.
Falls back to selected window top-right on PARENT if none exists."
  (if-let* ((win (vertico-child-frame--other-window parent)))
      (vertico-child-frame--position-in-edges
       'top-right-corner (window-pixel-edges win) width height win)
    (vertico-child-frame-poshandler-window-top-right-corner parent width height)))

(defun vertico-child-frame-poshandler-other-window-bottom-center
    (parent width height)
  "Position child frame of WIDTH by HEIGHT at bottom center of another window.
Falls back to selected window bottom center on PARENT if none exists."
  (if-let* ((win (vertico-child-frame--other-window parent)))
      (vertico-child-frame--position-in-edges
       'bottom-center (window-pixel-edges win) width height win)
    (vertico-child-frame-poshandler-window-bottom-center parent width height)))

(defun vertico-child-frame-poshandler-other-window-bottom-left-corner
    (parent width height)
  "Position child frame of WIDTH by HEIGHT at bottom-left of another window.
Falls back to selected window bottom-left on PARENT if none exists."
  (if-let* ((win (vertico-child-frame--other-window parent)))
      (vertico-child-frame--position-in-edges
       'bottom-left-corner (window-pixel-edges win) width height win)
    (vertico-child-frame-poshandler-window-bottom-left-corner parent width height)))

(defun vertico-child-frame-poshandler-other-window-bottom-right-corner
    (parent width height)
  "Position child frame of WIDTH by HEIGHT at bottom-right of another window.
Falls back to selected window bottom-right on PARENT if none exists."
  (if-let* ((win (vertico-child-frame--other-window parent)))
      (vertico-child-frame--position-in-edges
       'bottom-right-corner (window-pixel-edges win) width height win)
    (vertico-child-frame-poshandler-window-bottom-right-corner parent width height)))

(defun vertico-child-frame-poshandler-point-bottom-left-corner (parent width height)
  "Position child frame of WIDTH by HEIGHT below point, flipping upward if needed.
Falls back to window center on PARENT if point position is unavailable."
  (if-let* ((pt (vertico-child-frame--point-pixel-position parent)))
      (pcase-let ((`(,px ,py ,lh) pt))
        (cons px (vertico-child-frame--point-y-below-or-above parent py lh height)))
    (vertico-child-frame-poshandler-window-center parent width height)))

(defun vertico-child-frame-poshandler-point-top-left-corner (parent width height)
  "Position child frame of WIDTH by HEIGHT with its top-left at point.
Falls back to window center on PARENT if point position is unavailable."
  (if-let* ((pt (vertico-child-frame--point-pixel-position parent)))
      (cons (nth 0 pt) (nth 1 pt))
    (vertico-child-frame-poshandler-window-center parent width height)))

(defun vertico-child-frame-poshandler-point-bottom-left-corner-upward
    (parent width height)
  "Position child frame of WIDTH by HEIGHT above point.
Falls back to window center on PARENT if point position is unavailable."
  (if-let* ((pt (vertico-child-frame--point-pixel-position parent)))
      (cons (nth 0 pt) (- (nth 1 pt) height))
    (vertico-child-frame-poshandler-window-center parent width height)))

(defun vertico-child-frame-poshandler-point-window-center (parent width height)
  "Position child frame of WIDTH by HEIGHT at point Y and window center X.
Falls back to window center on PARENT if point position is unavailable."
  (if-let* ((pt (vertico-child-frame--point-pixel-position parent))
            (edges (vertico-child-frame--selected-window-edges parent)))
      (pcase-let ((`(,_px ,py ,lh) pt)
                  (`(,left ,_top ,right ,_bottom) edges))
        (cons (+ left (round (/ (- (- right left) width) 2.0)))
              (vertico-child-frame--point-y-below-or-above parent py lh height)))
    (vertico-child-frame-poshandler-window-center parent width height)))

(defun vertico-child-frame-poshandler-point-frame-center (parent width height)
  "Position child frame of WIDTH by HEIGHT at point Y and PARENT center X.
Falls back to PARENT center if point position is unavailable."
  (if-let* ((pt (vertico-child-frame--point-pixel-position parent)))
      (pcase-let ((`(,_px ,py ,lh) pt))
        (cons (round (/ (- (frame-pixel-width parent) width) 2.0))
              (vertico-child-frame--point-y-below-or-above parent py lh height)))
    (vertico-child-frame-poshandler-frame-center parent width height)))

(defconst vertico-child-frame--poshandler-alist
  '((frame-top-center . vertico-child-frame-poshandler-frame-top-center)
    (frame-center . vertico-child-frame-poshandler-frame-center)
    (frame-bottom-center . vertico-child-frame-poshandler-frame-bottom-center)
    (frame-top-left-corner . vertico-child-frame-poshandler-frame-top-left-corner)
    (frame-top-right-corner . vertico-child-frame-poshandler-frame-top-right-corner)
    (frame-bottom-left-corner
     . vertico-child-frame-poshandler-frame-bottom-left-corner)
    (frame-bottom-right-corner
     . vertico-child-frame-poshandler-frame-bottom-right-corner)
    (frame-top-left-or-right-other-corner
     . vertico-child-frame-poshandler-frame-top-left-or-right-other-corner)
    (window-center . vertico-child-frame-poshandler-window-center)
    (window-top-center . vertico-child-frame-poshandler-window-top-center)
    (window-top-left-corner . vertico-child-frame-poshandler-window-top-left-corner)
    (window-top-right-corner
     . vertico-child-frame-poshandler-window-top-right-corner)
    (window-bottom-center . vertico-child-frame-poshandler-window-bottom-center)
    (window-bottom-left-corner
     . vertico-child-frame-poshandler-window-bottom-left-corner)
    (window-bottom-right-corner
     . vertico-child-frame-poshandler-window-bottom-right-corner)
    (other-window-center . vertico-child-frame-poshandler-other-window-center)
    (other-window-top-center . vertico-child-frame-poshandler-other-window-top-center)
    (other-window-top-left-corner
     . vertico-child-frame-poshandler-other-window-top-left-corner)
    (other-window-top-right-corner
     . vertico-child-frame-poshandler-other-window-top-right-corner)
    (other-window-bottom-center
     . vertico-child-frame-poshandler-other-window-bottom-center)
    (other-window-bottom-left-corner
     . vertico-child-frame-poshandler-other-window-bottom-left-corner)
    (other-window-bottom-right-corner
     . vertico-child-frame-poshandler-other-window-bottom-right-corner)
    (point-bottom-left-corner
     . vertico-child-frame-poshandler-point-bottom-left-corner)
    (point-top-left-corner . vertico-child-frame-poshandler-point-top-left-corner)
    (point-bottom-left-corner-upward
     . vertico-child-frame-poshandler-point-bottom-left-corner-upward)
    (point-window-center . vertico-child-frame-poshandler-point-window-center)
    (point-frame-center . vertico-child-frame-poshandler-point-frame-center))
  "Mapping from short poshandler symbols to poshandler functions.")

(defun vertico-child-frame--resolve-poshandler (spec)
  "Resolve poshandler SPEC (symbol or function) to a callable function."
  (or (and (symbolp spec) (alist-get spec vertico-child-frame--poshandler-alist))
      (and (functionp spec) spec)
      #'vertico-child-frame-poshandler-frame-center))

(defun vertico-child-frame--compute-geometry (parent lines depth)
  "Compute (X Y WIDTH HEIGHT) for child frame on PARENT with LINES at DEPTH."
  (let* ((size-plist (when (functionp vertico-child-frame-size-function)
                       (funcall vertico-child-frame-size-function)))
         (width (vertico-child-frame--resolve-width parent size-plist))
         (prompt-lines (vertico-child-frame--prompt-lines parent width))
         (height (vertico-child-frame--resolve-height
                  parent lines prompt-lines size-plist))
         (chrome (vertico-child-frame--chrome-size parent))
         (outer-w (+ width (car chrome)))
         (outer-h (+ height (cdr chrome)))
         (fn (vertico-child-frame--resolve-poshandler vertico-child-frame-poshandler))
         (pos (funcall fn parent outer-w outer-h))
         (tty-p (vertico-child-frame--tty-p parent))
         (raw-ox (car vertico-child-frame-offset))
         (raw-oy (cdr vertico-child-frame-offset))
         (ox (if tty-p (vertico-child-frame--scale-tty-px raw-ox 10) raw-ox))
         (oy (if tty-p (vertico-child-frame--scale-tty-px raw-oy 20) raw-oy))
         (level (max 0 (1- (or depth 1))))
         (raw-rx (car vertico-child-frame-recursive-offset))
         (raw-ry (cdr vertico-child-frame-recursive-offset))
         (dx (* level (if tty-p (vertico-child-frame--scale-tty-px raw-rx 10) raw-rx)))
         (dy (* level (if tty-p (vertico-child-frame--scale-tty-px raw-ry 20) raw-ry)))
         (clamped (vertico-child-frame--clamp-position
                   parent (+ (car pos) ox dx) (+ (cdr pos) oy dy)
                   outer-w outer-h)))
    (list (car clamped) (cdr clamped) width height)))

;;;; Frame pool and styling

(defun vertico-child-frame--scratch-buffer ()
  "Return the hidden scratch buffer parked in inactive pooled frames."
  (let ((buf (get-buffer-create " *vertico-child-frame*")))
    (with-current-buffer buf
      (unless (eq major-mode 'fundamental-mode)
        (fundamental-mode))
      (setq-local mode-line-format nil
                  header-line-format nil
                  tab-line-format nil))
    buf))

(defun vertico-child-frame--face-attribute (face attr &optional frame)
  "Return ATTR of FACE on FRAME, ignoring unspecified values."
  (let ((val (face-attribute face attr (and (framep frame) frame) t)))
    (unless (or (eq val 'unspecified)
                (equal val "unspecified-bg")
                (equal val "unspecified-fg"))
      val)))

(defun vertico-child-frame--appearance-spec (parent)
  "Return resolved appearance attribute list for child frames on PARENT."
  (let* ((tty-p (vertico-child-frame--tty-p parent))
         (font (unless tty-p
                 (or vertico-child-frame-font
                     (vertico-child-frame--face-attribute
                      'vertico-child-frame :font parent)
                     (frame-parameter parent 'font))))
         (bg (or (vertico-child-frame--face-attribute
                  'vertico-child-frame :background parent)
                 (vertico-child-frame--face-attribute
                  'default :background parent)))
         (fg (or (vertico-child-frame--face-attribute
                  'vertico-child-frame :foreground parent)
                 (vertico-child-frame--face-attribute
                  'default :foreground parent)))
         (border-bg (vertico-child-frame--face-attribute
                     'vertico-child-frame-border :background parent))
         (ib-bg (if (and (integerp vertico-child-frame-border-width)
                         (zerop vertico-child-frame-border-width)
                         border-bg)
                    border-bg
                  bg))
         (alpha-bg (unless tty-p
                     (if (integerp vertico-child-frame-alpha)
                         vertico-child-frame-alpha
                       (alist-get 'alpha-background
                                  vertico-child-frame-parameters))))
         (alpha-pair (unless tty-p
                       (if (consp vertico-child-frame-alpha)
                           vertico-child-frame-alpha
                         (alist-get 'alpha vertico-child-frame-parameters))))
         (tty-bw (and tty-p (vertico-child-frame--tty-border-width)))
         (use-ib (and (integerp vertico-child-frame-border-width)
                      (zerop vertico-child-frame-border-width)
                      (integerp vertico-child-frame-internal-border-width)
                      (> vertico-child-frame-internal-border-width 0)))
         (border-width (if tty-p
                           (unless use-ib tty-bw)
                         (unless use-ib vertico-child-frame-border-width)))
         (ib-width (if tty-p
                       (if use-ib tty-bw 0)
                     vertico-child-frame-internal-border-width))
         (lf (if tty-p 0 vertico-child-frame-left-fringe))
         (rf (if tty-p 0 vertico-child-frame-right-fringe)))
    (list font bg fg border-bg ib-bg alpha-bg alpha-pair border-width
          ib-width lf rf)))

(defun vertico-child-frame--sync-appearance (frame parent)
  "Synchronize FRAME fonts, colors, borders, alpha, and fringes from PARENT."
  (let* ((tty-p (vertico-child-frame--tty-p parent))
         (sig (vertico-child-frame--appearance-spec parent))
         (cached (frame-parameter frame 'vertico-child-frame--appearance)))
    (unless (equal sig cached)
      (pcase-let*
          ((`(,font ,bg ,fg ,border-bg ,ib-bg ,alpha-bg ,alpha-pair
              ,border-width ,ib-width ,lf ,rf)
            sig)
           (params (delq nil
                         (append
                          (list (when font (cons 'font font))
                                (when bg (cons 'background-color bg))
                                (when fg (cons 'foreground-color fg))
                                (cons 'child-frame-border-width border-width)
                                (cons 'internal-border-width ib-width))
                          (unless tty-p
                            (list (cons 'alpha-background alpha-bg)
                                  (cons 'alpha alpha-pair))))))
           (changed-params
            (cl-remove-if
             (lambda (pair)
               (equal (cdr pair) (frame-parameter frame (car pair))))
             params))
           (border-changed
            (and border-bg (facep 'child-frame-border)
                 (or (null cached)
                     (not (equal border-bg (nth 3 cached))))))
           (ib-changed
            (and ib-bg (facep 'internal-border)
                 (or (null cached)
                     (not (equal ib-bg (nth 4 cached))))))
           (fringe-changed
            (and (not tty-p)
                 (or (null cached)
                     (not (eql lf (nth 9 cached)))
                     (not (eql rf (nth 10 cached)))))))
        (let ((frame-inhibit-implied-resize t)
              (inhibit-redisplay t))
          (when changed-params
            (modify-frame-parameters frame changed-params))
          (when border-changed
            (set-face-background 'child-frame-border border-bg frame))
          (when ib-changed
            (set-face-background 'internal-border ib-bg frame))
          (when fringe-changed
            (when-let* ((win (frame-root-window frame))
                        ((window-live-p win)))
              (set-window-fringes win lf rf)))
          (set-frame-parameter frame 'vertico-child-frame--appearance sig))))))

(defun vertico-child-frame--configure-window (win)
  "Configure child-frame root window WIN to suppress extraneous chrome."
  (when (window-live-p win)
    (set-window-parameter win 'no-other-window t)
    (set-window-parameter win 'no-delete-other-windows t)))

(defun vertico-child-frame--acquire-frame (parent depth)
  "Return a reusable child frame on PARENT for minibuffer DEPTH."
  (let* ((entry (assq depth vertico-child-frame--pool))
         (frame (cdr entry)))
    (unless (and (frame-live-p frame)
                 (eq (frame-parent frame) parent)
                 (window-live-p (frame-root-window frame)))
      (when (frame-live-p frame)
        (ignore-errors (delete-frame frame)))
      (setq frame
            (pcase-let*
                ((tty-p (vertico-child-frame--tty-p parent))
                 (`(,font ,bg ,fg ,_border-bg ,_ib-bg ,alpha-bg ,alpha-pair
                    ,border-width ,ib-width ,lf ,rf)
                  (vertico-child-frame--appearance-spec parent))
                 (init-px (vertico-child-frame--golden-pixel-size parent))
                 (init-cols (max 20 (round (/ (float (car init-px))
                                              (max 1 (frame-char-width parent))))))
                 (init-rows (max 10 (round (/ (float (cdr init-px))
                                              (max 1 (frame-char-height parent))))))
                 (init-params
                  (delq nil
                        (append
                         (list (cons 'parent-frame parent)
                               (cons 'minibuffer (minibuffer-window parent))
                               '(visibility . nil)
                               (cons 'width init-cols)
                               (cons 'height init-rows)
                               (when font (cons 'font font))
                               (when bg (cons 'background-color bg))
                               (when fg (cons 'foreground-color fg))
                               (cons 'child-frame-border-width border-width)
                               (cons 'internal-border-width ib-width))
                         (unless tty-p
                           (list (cons 'alpha-background alpha-bg)
                                 (cons 'alpha alpha-pair)
                                 (cons 'left-fringe lf)
                                 (cons 'right-fringe rf))))))
                 (frame-inhibit-implied-resize t))
              (make-frame
               (append init-params
                       vertico-child-frame--default-parameters
                       vertico-child-frame-parameters))))
      (let ((root (frame-root-window frame)))
        (vertico-child-frame--configure-window root)
        (vertico-child-frame--set-window-buffer
         root (vertico-child-frame--scratch-buffer)))
      (if entry
          (setcdr entry frame)
        (push (cons depth frame) vertico-child-frame--pool)))
    (vertico-child-frame--sync-appearance frame parent)
    (vertico-child-frame--configure-window (frame-root-window frame))
    frame))

(defun vertico-child-frame--apply-geometry (frame geometry)
  "Apply GEOMETRY (X Y WIDTH HEIGHT) to FRAME if changed."
  (pcase-let* ((`(,x ,y ,width ,height) geometry)
               (cached (frame-parameter frame 'vertico-child-frame--geometry))
               (size-changed (not (equal (cddr geometry) (cddr cached))))
               (pos-changed (or (not (equal (list x y)
                                            (list (car cached) (cadr cached))))
                                (not (equal (frame-position frame)
                                            (cons x y))))))
    (when (or size-changed pos-changed)
      (let ((frame-resize-pixelwise t)
            (frame-inhibit-implied-resize t)
            (window-min-height 1)
            (window-min-width 1)
            (inhibit-redisplay t)
            (vertico-child-frame--resizing t))
        (when size-changed
          (set-frame-size frame width height t))
        (when pos-changed
          (modify-frame-parameters frame `((left . (+ ,x))
                                           (top . (+ ,y))
                                           (user-position . t)))
          (set-frame-position frame x y))
        (set-frame-parameter frame 'vertico-child-frame--geometry geometry)))))

(defun vertico-child-frame--on-delete-frame (deleted)
  "Delete any pooled child frames whose parent is DELETED."
  (let (remaining)
    (dolist (entry vertico-child-frame--pool)
      (let ((child (cdr entry)))
        (if (and (frame-live-p child)
                 (eq (frame-parent child) deleted))
            (ignore-errors (delete-frame child))
          (when (frame-live-p child)
            (push entry remaining)))))
    (setq vertico-child-frame--pool (nreverse remaining))
    (setq vertico-child-frame--active-frames
          (cl-remove-if-not (lambda (entry) (frame-live-p (cdr entry)))
                            vertico-child-frame--active-frames))))

;;;###autoload
(defun vertico-child-frame-warmup ()
  "Pre-create a hidden depth-1 child frame for faster first display.
Return non-nil when a child frame was pre-created."
  (interactive)
  (let ((parent (selected-frame)))
    (when (and (frame-live-p parent)
               (not (frame-parameter parent 'parent-frame))
               (eq (frame-visible-p parent) t)
               (vertico-child-frame--can-display-p parent))
      (let ((entry (assq 1 vertico-child-frame--pool)))
        (unless (and (frame-live-p (cdr entry))
                     (eq (frame-parent (cdr entry)) parent))
          (vertico-child-frame--acquire-frame parent 1)
          t)))))

(defun vertico-child-frame--maybe-warmup ()
  "Pre-warm a child frame when idle if pre-warming is enabled."
  (when (timerp vertico-child-frame--warmup-timer)
    (cancel-timer vertico-child-frame--warmup-timer)
    (setq vertico-child-frame--warmup-timer nil))
  (remove-hook 'window-setup-hook #'vertico-child-frame--maybe-warmup)
  (when (and vertico-child-frame-prewarm
             (or (bound-and-true-p vertico-child-frame-mode)
                 (bound-and-true-p vertico-multiform-mode)))
    (ignore-errors (vertico-child-frame-warmup))))

(defun vertico-child-frame--schedule-warmup ()
  "Schedule background idle pre-warming of a depth-1 child frame."
  (when (and vertico-child-frame-prewarm
             (not noninteractive)
             (null vertico-child-frame--warmup-timer))
    (add-hook 'server-after-make-frame-hook #'vertico-child-frame--maybe-warmup)
    (if after-init-time
        (setq vertico-child-frame--warmup-timer
              (run-with-idle-timer 0.3 nil #'vertico-child-frame--maybe-warmup))
      (add-hook 'window-setup-hook #'vertico-child-frame--maybe-warmup))))

;;;###autoload
(defun vertico-child-frame-cleanup ()
  "Delete all pooled Vertico child frames."
  (interactive)
  (when (timerp vertico-child-frame--warmup-timer)
    (cancel-timer vertico-child-frame--warmup-timer)
    (setq vertico-child-frame--warmup-timer nil))
  (remove-hook 'window-setup-hook #'vertico-child-frame--maybe-warmup)
  (remove-hook 'server-after-make-frame-hook #'vertico-child-frame--maybe-warmup)
  (dolist (entry vertico-child-frame--pool)
    (when (frame-live-p (cdr entry))
      (ignore-errors (delete-frame (cdr entry)))))
  (setq vertico-child-frame--pool nil
        vertico-child-frame--active-frames nil
        vertico-child-frame--active-buffers nil))

;;;; Session lifecycle

(defun vertico-child-frame--hide-minibuffer (mbwin)
  "Collapse and scroll away the prompt in parent minibuffer window MBWIN."
  (when (and vertico-child-frame-hide-minibuffer
             (window-live-p mbwin))
    (when (> (window-pixel-height mbwin) (frame-char-height (window-frame mbwin)))
      (ignore-errors
        (window-resize mbwin (- (window-pixel-height mbwin)) nil nil 'pixelwise)))
    (set-window-vscroll mbwin 100)))

(defun vertico-child-frame--update-cursor ()
  "Mirror the active minibuffer cursor inside the child frame."
  (let* ((mbwin (active-minibuffer-window))
         (new (and (eq (selected-window) mbwin)
                   (if (memq cursor-type '(nil t)) 'box cursor-type))))
    (unless (eq new cursor-in-non-selected-windows)
      (setq-local cursor-in-non-selected-windows new))))

(defun vertico-child-frame--set-window-buffer (win buf)
  "Display BUF in WIN while keeping WIN dedicated afterward."
  (when (window-live-p win)
    (set-window-dedicated-p win nil)
    (set-window-buffer win buf)
    (set-window-dedicated-p win t)))

(defun vertico-child-frame--redisplay (win)
  "Synchronize child-frame WIN point, wrapping, and hidden minibuffer."
  (when vertico-child-frame--active
    (let ((vertico-child-frame--in-redisplay t)
          (mbwin (active-minibuffer-window))
          (cwin vertico-child-frame--window))
      (when (and (window-live-p mbwin)
                 (eq (window-buffer mbwin) (current-buffer)))
        (vertico-child-frame--hide-minibuffer mbwin))
      (when (or (null win) (eq win cwin))
        (vertico-child-frame--update-cursor)
        (vertico-child-frame--update-truncation cwin)
        (vertico-child-frame--resize
         (or vertico-child-frame--last-lines vertico-count))
        (when (and (window-live-p cwin)
                   (eq (window-buffer cwin) (current-buffer)))
          (set-window-point cwin (point)))))))

(defun vertico-child-frame--on-window-size-change (frame)
  "Adapt active child frames after FRAME or its parent is resized."
  (when (and (not vertico-child-frame--resizing)
             vertico-child-frame--active-buffers)
    (let ((vertico-child-frame--resizing t))
      (setq vertico-child-frame--active-buffers
            (cl-remove-if-not #'buffer-live-p vertico-child-frame--active-buffers))
      (dolist (buf vertico-child-frame--active-buffers)
        (with-current-buffer buf
          (when (and vertico-child-frame--active
                     (frame-live-p vertico-child-frame--frame)
                     (frame-live-p vertico-child-frame--parent))
            (cond
             ((eq frame vertico-child-frame--parent)
              (setq vertico-child-frame--max-width-seen 0
                    vertico-child-frame--content-width-cache nil)
              (set-frame-parameter vertico-child-frame--frame
                                   'vertico-child-frame--geometry nil)
              (vertico-child-frame--resize
               (or vertico-child-frame--last-lines vertico-count))
              (vertico-child-frame--update-truncation vertico-child-frame--window)
              (vertico-child-frame--resize
               (or vertico-child-frame--last-lines vertico-count))
              (when-let* ((mbwin (active-minibuffer-window))
                          ((eq buf (window-buffer mbwin)))
                          ((fboundp 'vertico--exhibit)))
                (vertico--exhibit)))
             ((eq frame vertico-child-frame--frame)
              (set-frame-parameter vertico-child-frame--frame
                                   'vertico-child-frame--geometry nil)
              (vertico-child-frame--resize
               (or vertico-child-frame--last-lines vertico-count))))))))))

(defun vertico-child-frame--resize (height)
  "Resize the active Vertico child frame for HEIGHT candidate lines."
  (when (and vertico-child-frame--active
             (frame-live-p vertico-child-frame--frame)
             (frame-live-p vertico-child-frame--parent))
    (setq vertico-child-frame--last-lines height)
    (let* ((cached (frame-parameter vertico-child-frame--frame
                                    'vertico-child-frame--geometry))
           (prev-width (nth 2 cached))
           (size-plist (when (functionp vertico-child-frame-size-function)
                         (funcall vertico-child-frame-size-function)))
           (geometry (vertico-child-frame--compute-geometry
                      vertico-child-frame--parent
                      height
                      vertico-child-frame--depth))
           (width (nth 2 geometry))
           (pixel-h (nth 3 geometry))
           (prompt-lines (vertico-child-frame--prompt-lines
                          vertico-child-frame--parent width)))
      (vertico-child-frame--apply-geometry vertico-child-frame--frame geometry)
      (vertico-child-frame--sync-vertico-count
       vertico-child-frame--parent pixel-h prompt-lines size-plist)
      (when (and prev-width
                 (not (= prev-width width))
                 (not vertico-child-frame--in-redisplay)
                 (not vertico-child-frame--exhibiting)
                 (fboundp 'vertico--exhibit))
        (let ((vertico-child-frame--exhibiting t))
          (vertico--exhibit))))))

;;;###autoload
(defun vertico-child-frame-set-poshandler (poshandler)
  "Select POSHANDLER interactively and use it for child-frame placement.
Updates `vertico-child-frame-poshandler' and repositions any active
child frame immediately."
  (interactive
   (list
    (let* ((names (mapcar (lambda (entry) (symbol-name (car entry)))
                          vertico-child-frame--poshandler-alist))
           (choice (completing-read "Vertico child-frame position: " names nil t)))
      (alist-get (intern choice) vertico-child-frame--poshandler-alist))))
  (setq vertico-child-frame-poshandler poshandler)
  (when vertico-child-frame--active
    (vertico-child-frame--resize (or vertico-child-frame--last-lines vertico-count))))

(defun vertico-child-frame--ensure-initial-exhibit (buf)
  "Re-run initial Vertico exhibit for BUF if frame events aborted it."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (setq vertico-child-frame--init-timer nil)
      (when (and vertico-child-frame--active
                 (boundp 'vertico--input)
                 (eq vertico--input t)
                 (minibufferp)
                 (when-let* ((mbwin (active-minibuffer-window))
                             ((window-live-p mbwin)))
                   (eq buf (window-buffer mbwin))))
        (with-local-quit
          (let ((buffer-undo-list t))
            (when (fboundp 'vertico--update)
              (vertico--update))
            (when (fboundp 'vertico--exhibit)
              (vertico--exhibit))))))))

(defun vertico-child-frame--setup ()
  "Set up the Vertico child frame for the current minibuffer session."
  (when (minibufferp)
    (let* ((mbwin (or (active-minibuffer-window) (selected-window)))
           (parent (and (window-live-p mbwin) (window-frame mbwin))))
      (if (not (vertico-child-frame--can-display-p parent))
          (progn
            (setq vertico-child-frame--active nil)
            (vertico-child-frame--activate-fallback))
        (let* ((depth (max 1 (minibuffer-depth)))
               (frame (vertico-child-frame--acquire-frame parent depth))
               (win (frame-root-window frame)))
          (when (timerp vertico-child-frame--init-timer)
            (cancel-timer vertico-child-frame--init-timer))
          (setq vertico-child-frame--active t
                vertico-child-frame--frame frame
                vertico-child-frame--window win
                vertico-child-frame--depth depth
                vertico-child-frame--parent parent
                vertico-child-frame--max-height-seen 0
                vertico-child-frame--max-width-seen 0
                vertico-child-frame--content-width-cache nil
                vertico-child-frame--last-lines vertico-count
                vertico-child-frame--orig-vertico-count vertico-count
                vertico-child-frame--orig-vertico-count-local
                (local-variable-p 'vertico-count)
                vertico-child-frame--saved-cursor cursor-in-non-selected-windows
                vertico-child-frame--init-timer nil
                vertico-child-frame--orig-truncate-lines truncate-lines
                vertico-child-frame--orig-word-wrap word-wrap
                vertico-child-frame--orig-auto-hscroll auto-hscroll-mode
                vertico-child-frame--orig-resize-mini resize-mini-windows
                vertico-child-frame--orig-mode-line mode-line-format
                vertico-child-frame--orig-header-line header-line-format
                vertico-child-frame--orig-tab-line tab-line-format)
          (setq-local auto-hscroll-mode 'current-line
                      resize-mini-windows nil
                      mode-line-format vertico-child-frame-mode-line-format
                      header-line-format vertico-child-frame-header-line-format
                      tab-line-format nil)
          (vertico-child-frame--update-truncation)
          (vertico-child-frame--set-window-buffer win (current-buffer))
          (when (overlayp vertico--candidates-ov)
            (overlay-put vertico--candidates-ov 'window win))
          (when (and (boundp 'vertico--count-ov) (overlayp vertico--count-ov))
            (overlay-put vertico--count-ov 'window win))
          (vertico-child-frame--hide-minibuffer mbwin)
          (let* ((size-plist (when (functionp vertico-child-frame-size-function)
                               (funcall vertico-child-frame-size-function)))
                 (geometry (vertico-child-frame--compute-geometry
                            parent vertico-count depth))
                 (prev-trunc truncate-lines))
            (vertico-child-frame--apply-geometry frame geometry)
            (vertico-child-frame--update-truncation win)
            (unless (eq prev-trunc truncate-lines)
              (setq geometry (vertico-child-frame--compute-geometry
                              parent vertico-count depth))
              (vertico-child-frame--apply-geometry frame geometry))
            (vertico-child-frame--sync-vertico-count
             parent (nth 3 geometry)
             (vertico-child-frame--prompt-lines parent (nth 2 geometry))
             size-plist)
            (setq vertico-child-frame--last-lines vertico-count)
            (cl-pushnew (current-buffer) vertico-child-frame--active-buffers :test #'eq)
            (setq vertico-child-frame--active-frames
                  (cons (cons depth frame)
                        (assq-delete-all depth vertico-child-frame--active-frames)))
            (make-frame-visible frame)
            (raise-frame frame)
            ;; Re-verify after mapping only if GTK/WM shifted the frame.
            (unless (equal (frame-position frame)
                           (cons (car geometry) (cadr geometry)))
              (vertico-child-frame--apply-geometry frame geometry)))
          (vertico-child-frame--update-cursor)
          (when (window-live-p win)
            (set-window-point win (point)))
          (add-hook 'pre-redisplay-functions #'vertico-child-frame--redisplay 90 :local)
          (add-hook 'minibuffer-exit-hook #'vertico-child-frame--teardown nil :local)
          (setq vertico-child-frame--init-timer
                (run-with-idle-timer
                 0 nil #'vertico-child-frame--ensure-initial-exhibit
                 (current-buffer))))))))

(defun vertico-child-frame--teardown ()
  "Tear down the child frame for the current minibuffer session."
  (when vertico-child-frame--active
    (let ((frame vertico-child-frame--frame)
          (win vertico-child-frame--window)
          (depth vertico-child-frame--depth)
          (parent vertico-child-frame--parent)
          (init-timer vertico-child-frame--init-timer)
          (mbwin (active-minibuffer-window)))
      (setq vertico-child-frame--active nil
            vertico-child-frame--frame nil
            vertico-child-frame--window nil
            vertico-child-frame--depth nil
            vertico-child-frame--parent nil
            vertico-child-frame--init-timer nil
            vertico-child-frame--max-width-seen 0
            vertico-child-frame--content-width-cache nil
            vertico-child-frame--active-buffers
            (delq (current-buffer) vertico-child-frame--active-buffers))
      (when (timerp init-timer)
        (cancel-timer init-timer))
      (remove-hook 'pre-redisplay-functions #'vertico-child-frame--redisplay :local)
      (remove-hook 'minibuffer-exit-hook #'vertico-child-frame--teardown :local)
      (when (overlayp vertico--candidates-ov)
        (overlay-put vertico--candidates-ov 'window nil)
        (overlay-put vertico--candidates-ov 'before-string nil)
        (overlay-put vertico--candidates-ov 'after-string nil))
      (when (and (boundp 'vertico--count-ov) (overlayp vertico--count-ov))
        (overlay-put vertico--count-ov 'window nil)
        (overlay-put vertico--count-ov 'before-string nil)
        (overlay-put vertico--count-ov 'after-string nil))
      (if vertico-child-frame--orig-vertico-count-local
          (setq-local vertico-count vertico-child-frame--orig-vertico-count)
        (kill-local-variable 'vertico-count))
      (setq-local cursor-in-non-selected-windows vertico-child-frame--saved-cursor
                  truncate-lines vertico-child-frame--orig-truncate-lines
                  word-wrap vertico-child-frame--orig-word-wrap
                  auto-hscroll-mode vertico-child-frame--orig-auto-hscroll
                  resize-mini-windows vertico-child-frame--orig-resize-mini
                  mode-line-format vertico-child-frame--orig-mode-line
                  header-line-format vertico-child-frame--orig-header-line
                  tab-line-format vertico-child-frame--orig-tab-line)
      (when (window-live-p mbwin)
        (ignore-errors (set-window-vscroll mbwin 0)))
      (when (window-live-p win)
        (ignore-errors
          (set-window-dedicated-p win nil)
          (set-window-buffer win (vertico-child-frame--scratch-buffer))))
      (when (frame-live-p frame)
        (ignore-errors (make-frame-invisible frame t)))
      (when (and (frame-live-p parent)
                 (vertico-child-frame--tty-p parent)
                 (framep parent))
        (ignore-errors (redraw-frame parent)))
      (setq vertico-child-frame--active-frames
            (assq-delete-all depth vertico-child-frame--active-frames))
      (when-let* ((outer (cdar vertico-child-frame--active-frames))
                  ((frame-live-p outer)))
        (ignore-errors
          (make-frame-visible outer)
          (raise-frame outer))))))

(defun vertico-child-frame--window-width (orig-fn &rest args)
  "Return the child-frame window width when active, else call ORIG-FN with ARGS."
  (if (and vertico-child-frame--active
           (window-live-p vertico-child-frame--window))
      (window-width vertico-child-frame--window)
    (apply orig-fn args)))

;;;; Minor mode and Vertico integration

;;;###autoload
(define-minor-mode vertico-child-frame-mode
  "Display Vertico completion candidates inside a native child frame."
  :global t
  :group 'vertico-child-frame
  (if vertico-child-frame-mode
      (progn
        (advice-add #'vertico--window-width :around
                    #'vertico-child-frame--window-width)
        (add-hook 'delete-frame-functions #'vertico-child-frame--on-delete-frame)
        (add-hook 'window-size-change-functions
                  #'vertico-child-frame--on-window-size-change)
        (vertico-child-frame--schedule-warmup)
        (when (and (minibufferp) (bound-and-true-p vertico--input))
          (vertico-child-frame--setup)
          (when (fboundp 'vertico--exhibit)
            (vertico--exhibit))))
    (advice-remove #'vertico--window-width #'vertico-child-frame--window-width)
    (remove-hook 'delete-frame-functions #'vertico-child-frame--on-delete-frame)
    (remove-hook 'window-size-change-functions
                 #'vertico-child-frame--on-window-size-change)
    (if (and (minibufferp) (bound-and-true-p vertico--input))
        (let ((was-active vertico-child-frame--active))
          (vertico-child-frame--teardown)
          (vertico-child-frame--deactivate-fallback)
          (when (and was-active (fboundp 'vertico--exhibit))
            (vertico--exhibit)))
      (if (bound-and-true-p vertico-multiform-mode)
          (progn
            (dolist (entry vertico-child-frame--pool)
              (when (frame-live-p (cdr entry))
                (ignore-errors (make-frame-invisible (cdr entry) t))))
            (setq vertico-child-frame--active-frames nil
                  vertico-child-frame--active-buffers nil))
        (vertico-child-frame-cleanup)))))

(advice-add #'vertico--setup :before #'vertico-child-frame--before-setup
            '((depth . 90)))

(cl-defmethod vertico--setup :after (&context (vertico-child-frame-mode (eql t)))
  "Set up the child frame when VERTICO-CHILD-FRAME-MODE is active."
  (vertico-child-frame--setup))

(cl-defmethod vertico--resize-window (height &context (vertico-child-frame-mode (eql t)))
  "Resize the child frame for HEIGHT lines when VERTICO-CHILD-FRAME-MODE is on."
  (if vertico-child-frame--active
      (vertico-child-frame--resize height)
    (cl-call-next-method height)))

(defun vertico-multiform-child-frame ()
  "Toggle the child-frame display mode in the current minibuffer."
  (interactive)
  (vertico-multiform--toggle 'vertico-child-frame-mode))

(put 'vertico-multiform-child-frame 'completion-predicate #'vertico--command-p)

(with-eval-after-load 'vertico-multiform
  (when (boundp 'vertico-multiform--display-modes)
    (cl-pushnew 'vertico-child-frame-mode vertico-multiform--display-modes))
  (when (and (boundp 'vertico-multiform-map)
             (keymapp vertico-multiform-map)
             (not (lookup-key vertico-multiform-map (kbd "M-C"))))
    (define-key vertico-multiform-map (kbd "M-C") #'vertico-multiform-child-frame))
  (vertico-child-frame--schedule-warmup))

(provide 'vertico-child-frame)
;;; vertico-child-frame.el ends here
