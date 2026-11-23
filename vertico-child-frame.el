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
(require 'vertico)

(defvar vertico--count-ov)
(defvar vertico-multiform--display-modes)
(defvar vertico-multiform-map)

(declare-function vertico--command-p "vertico")
(declare-function vertico--exhibit "vertico")
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

(defcustom vertico-child-frame-width 0.6
  "Width of the Vertico child frame.
A float in (0.0, 1.0] specifies a fraction of the parent frame pixel
width.  An integer greater than 1 specifies the width in columns.  A
function is called with the parent frame and must return pixel width."
  :type '(choice (float :tag "Fraction of parent frame")
                 (integer :tag "Columns")
                 (function :tag "Function returning pixel width"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-min-width 50
  "Minimum child-frame width in columns, or nil for no minimum."
  :type '(choice (const :tag "None" nil)
                 (integer :tag "Columns"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-max-width 120
  "Maximum child-frame width in columns, or nil for no maximum."
  :type '(choice (const :tag "None" nil)
                 (integer :tag "Columns"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-resize nil
  "How the child frame resizes vertically during a completion session.
If nil, use a fixed height determined by `vertico-count'.
If t, grow and shrink to fit the currently displayed lines.
If `grow-only', only expand vertically during the session."
  :type '(choice (const :tag "Fixed height" nil)
                 (const :tag "Grow and shrink" t)
                 (const :tag "Grow only" grow-only))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-min-height nil
  "Minimum child-frame height in lines, or nil for 1 line."
  :type '(choice (const :tag "None" nil)
                 (integer :tag "Lines"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-max-height 0.5
  "Maximum child-frame height.
A float in (0.0, 1.0] specifies a fraction of the parent frame pixel
height.  An integer specifies the maximum number of lines."
  :type '(choice (const :tag "None" nil)
                 (float :tag "Fraction of parent frame")
                 (integer :tag "Lines"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-poshandler
  #'vertico-child-frame-poshandler-top-center
  "Function computing child-frame position relative to its parent frame.
It is called with three arguments (PARENT WIDTH HEIGHT) and must return
a cons cell (X . Y) in pixels relative to PARENT."
  :type '(choice
          (const :tag "Top center (command palette)"
                 vertico-child-frame-poshandler-top-center)
          (const :tag "Frame center"
                 vertico-child-frame-poshandler-center)
          (const :tag "Bottom center"
                 vertico-child-frame-poshandler-bottom-center)
          (const :tag "Selected window top center"
                 vertico-child-frame-poshandler-window-top-center)
          (const :tag "Selected window center"
                 vertico-child-frame-poshandler-window-center)
          (function :tag "Custom poshandler"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-top-offset 0.12
  "Vertical top offset for top-aligned poshandlers.
A float in [0.0, 1.0) specifies a fraction of parent or window height.
An integer specifies pixels."
  :type '(choice (float :tag "Fraction of height")
                 (integer :tag "Pixels"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-bottom-offset 0.06
  "Vertical bottom offset for `vertico-child-frame-poshandler-bottom-center'.
A float in [0.0, 1.0) specifies a fraction of parent height.
An integer specifies pixels."
  :type '(choice (float :tag "Fraction of height")
                 (integer :tag "Pixels"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-margin '(16 . 16)
  "Minimum horizontal and vertical margin from parent frame edges in pixels."
  :type '(cons (integer :tag "Horizontal")
               (integer :tag "Vertical"))
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-recursive-offset '(24 . 24)
  "Pixel offset (DX . DY) applied per recursive minibuffer level."
  :type '(cons (integer :tag "Horizontal")
               (integer :tag "Vertical"))
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

(defcustom vertico-child-frame-hide-minibuffer t
  "When non-nil, hide the prompt inside the parent minibuffer window."
  :type 'boolean
  :group 'vertico-child-frame)

(defcustom vertico-child-frame-truncate-lines t
  "When non-nil, truncate long lines inside the child frame."
  :type 'boolean
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
    (skip-taskbar . t))
  "Default frame parameters for Vertico child frames.")

(defvar vertico-child-frame--pool nil
  "Alist mapping minibuffer recursion depth to pooled child frames.")

(defvar vertico-child-frame--active-frames nil
  "Alist mapping active recursion depth to its visible child frame.")

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

(defvar-local vertico-child-frame--max-height-seen 0
  "Maximum line count observed so far in `grow-only' resize mode.")

(defvar-local vertico-child-frame--saved-cursor nil
  "Saved `cursor-in-non-selected-windows' value before setup.")

(defvar-local vertico-child-frame--fallback-active nil
  "Fallback mode symbol activated for the current session, if any.")

(defvar-local vertico-child-frame--orig-truncate-lines nil
  "Original `truncate-lines' value before child-frame setup.")

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

(defun vertico-child-frame--supported-p (&optional frame)
  "Return non-nil if child frames are supported on FRAME."
  (or (display-graphic-p frame)
      (and (boundp 'tty-child-frames)
           (symbol-value 'tty-child-frames))))

(defun vertico-child-frame--can-display-p (parent)
  "Return non-nil if PARENT can host a Vertico child frame."
  (and (frame-live-p parent)
       (vertico-child-frame--supported-p parent)
       (>= (frame-width parent) vertico-child-frame-min-parent-width)
       (>= (frame-height parent) vertico-child-frame-min-parent-height)))

(defun vertico-child-frame--deactivate-fallback ()
  "Disable the temporary fallback mode activated for this session."
  (when (and vertico-child-frame--fallback-active
             (fboundp vertico-child-frame--fallback-active))
    (let ((mode vertico-child-frame--fallback-active))
      (setq vertico-child-frame--fallback-active nil)
      (ignore-errors (funcall mode -1)))))

(defun vertico-child-frame--activate-fallback ()
  "Activate `vertico-child-frame-fallback-mode' for this session if configured."
  (when-let* ((mode vertico-child-frame-fallback-mode)
              ((fboundp mode))
              ((not (and (boundp mode) (symbol-value mode)))))
    (setq vertico-child-frame--fallback-active mode)
    (funcall mode 1)
    (add-hook 'minibuffer-exit-hook
              #'vertico-child-frame--deactivate-fallback nil :local)))

;;;; Geometry and poshandlers

(defun vertico-child-frame--resolve-width (parent)
  "Compute child-frame text width in pixels for PARENT."
  (let* ((cw (max 1 (frame-char-width parent)))
         (pw (max cw (frame-pixel-width parent)))
         (margin-x (max 0 (car vertico-child-frame-margin)))
         (max-parent-px (max cw (- pw (* 2 margin-x))))
         (spec vertico-child-frame-width)
         (raw-px
          (cond
           ((functionp spec) (round (funcall spec parent)))
           ((and (numberp spec) (<= spec 1.0) (> spec 0.0))
            (round (* pw spec)))
           ((integerp spec) (* spec cw))
           (t (round (* pw 0.6)))))
         (min-px (if (integerp vertico-child-frame-min-width)
                     (* vertico-child-frame-min-width cw)
                   cw))
         (max-px (if (integerp vertico-child-frame-max-width)
                     (* vertico-child-frame-max-width cw)
                   max-parent-px))
         (upper (max cw (min max-px max-parent-px)))
         (lower (min min-px upper)))
    (max lower (min upper raw-px))))

(defun vertico-child-frame--resolve-height (parent lines)
  "Compute child-frame text height in pixels on PARENT for LINES candidates."
  (let* ((lh (max 1 (frame-char-height parent)))
         (ph (max lh (frame-pixel-height parent)))
         (margin-y (max 0 (cdr vertico-child-frame-margin)))
         (max-parent-px (max lh (- ph (* 2 margin-y))))
         (prompt-plus-lines (max 1 (1+ lines)))
         (target-lines
          (pcase vertico-child-frame-resize
            ('nil (max 1 (1+ vertico-count)))
            ('grow-only
             (setq vertico-child-frame--max-height-seen
                   (max vertico-child-frame--max-height-seen prompt-plus-lines)))
            (_ prompt-plus-lines)))
         (min-lines (if (integerp vertico-child-frame-min-height)
                        (max 1 vertico-child-frame-min-height)
                      1))
         (max-px
          (cond
           ((and (numberp vertico-child-frame-max-height)
                 (<= vertico-child-frame-max-height 1.0)
                 (> vertico-child-frame-max-height 0.0))
            (min max-parent-px (round (* ph vertico-child-frame-max-height))))
           ((integerp vertico-child-frame-max-height)
            (min max-parent-px (* (max 1 vertico-child-frame-max-height) lh)))
           (t max-parent-px)))
         (min-px (min (* min-lines lh) (max lh max-px)))
         (raw-px (* target-lines lh)))
    (max min-px (min (max lh max-px) raw-px))))

(defun vertico-child-frame--clamp-coord (coord size parent-size margin)
  "Clamp COORD of SIZE within PARENT-SIZE respecting MARGIN."
  (let* ((eff-margin (if (>= parent-size (+ size (* 2 margin))) margin 0))
         (max-coord (max eff-margin (- parent-size size eff-margin))))
    (max eff-margin (min max-coord coord))))

(defun vertico-child-frame--clamp-position (parent x y width height)
  "Clamp (X, Y) for child frame of WIDTH by HEIGHT within PARENT."
  (let ((mx (max 0 (car vertico-child-frame-margin)))
        (my (max 0 (cdr vertico-child-frame-margin)))
        (pw (frame-pixel-width parent))
        (ph (frame-pixel-height parent)))
    (cons (vertico-child-frame--clamp-coord x width pw mx)
          (vertico-child-frame--clamp-coord y height ph my))))

(defun vertico-child-frame--resolve-offset (offset dim)
  "Resolve OFFSET against pixel dimension DIM."
  (if (and (numberp offset) (< offset 1.0) (>= offset 0.0))
      (round (* dim offset))
    (round offset)))

(defun vertico-child-frame-poshandler-top-center (parent width _height)
  "Position child frame of WIDTH at top center of PARENT."
  (let ((x (round (/ (- (frame-pixel-width parent) width) 2.0)))
        (y (vertico-child-frame--resolve-offset
            vertico-child-frame-top-offset
            (frame-pixel-height parent))))
    (cons x y)))

(defun vertico-child-frame-poshandler-center (parent width height)
  "Position child frame of WIDTH by HEIGHT at center of PARENT."
  (cons (round (/ (- (frame-pixel-width parent) width) 2.0))
        (round (/ (- (frame-pixel-height parent) height) 2.0))))

(defun vertico-child-frame-poshandler-bottom-center (parent width height)
  "Position child frame of WIDTH by HEIGHT near bottom center of PARENT."
  (let* ((ph (frame-pixel-height parent))
         (offset (vertico-child-frame--resolve-offset
                  vertico-child-frame-bottom-offset ph))
         (x (round (/ (- (frame-pixel-width parent) width) 2.0)))
         (y (- ph height offset)))
    (cons x y)))

(defun vertico-child-frame-poshandler-window-top-center (parent width height)
  "Position child frame of WIDTH by HEIGHT at top center of selected window.
Falls back to PARENT top center if no selected window belongs to PARENT."
  (let ((win (minibuffer-selected-window)))
    (if (and (window-live-p win) (eq (window-frame win) parent))
        (pcase-let ((`(,left ,top ,right ,bottom) (window-pixel-edges win)))
          (let* ((win-w (- right left))
                 (win-h (- bottom top))
                 (x (+ left (round (/ (- win-w width) 2.0))))
                 (y (+ top (vertico-child-frame--resolve-offset
                            vertico-child-frame-top-offset win-h))))
            (cons x y)))
      (vertico-child-frame-poshandler-top-center parent width height))))

(defun vertico-child-frame-poshandler-window-center (parent width height)
  "Position child frame of WIDTH by HEIGHT at center of selected window.
Falls back to PARENT center if no selected window belongs to PARENT."
  (let ((win (minibuffer-selected-window)))
    (if (and (window-live-p win) (eq (window-frame win) parent))
        (pcase-let ((`(,left ,top ,right ,bottom) (window-pixel-edges win)))
          (cons (+ left (round (/ (- (- right left) width) 2.0)))
                (+ top (round (/ (- (- bottom top) height) 2.0)))))
      (vertico-child-frame-poshandler-center parent width height))))

(defun vertico-child-frame--compute-geometry (parent lines depth)
  "Compute (X Y WIDTH HEIGHT) for child frame on PARENT with LINES at DEPTH."
  (let* ((width (vertico-child-frame--resolve-width parent))
         (height (vertico-child-frame--resolve-height parent lines))
         (pos (funcall vertico-child-frame-poshandler parent width height))
         (level (max 0 (1- (or depth 1))))
         (dx (* level (car vertico-child-frame-recursive-offset)))
         (dy (* level (cdr vertico-child-frame-recursive-offset)))
         (clamped (vertico-child-frame--clamp-position
                   parent (+ (car pos) dx) (+ (cdr pos) dy) width height)))
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
  "Return ATTR of FACE on FRAME, ignoring `unspecified'."
  (let ((val (face-attribute face attr frame t)))
    (unless (eq val 'unspecified) val)))

(defun vertico-child-frame--sync-appearance (frame parent)
  "Synchronize FRAME fonts, colors, borders, and fringes from PARENT."
  (let* ((font (or (vertico-child-frame--face-attribute 'vertico-child-frame :font)
                   (frame-parameter parent 'font)))
         (bg (or (vertico-child-frame--face-attribute 'vertico-child-frame :background)
                 (vertico-child-frame--face-attribute 'default :background parent)))
         (fg (or (vertico-child-frame--face-attribute 'vertico-child-frame :foreground)
                 (vertico-child-frame--face-attribute 'default :foreground parent)))
         (border-bg (vertico-child-frame--face-attribute
                     'vertico-child-frame-border :background))
         (params (delq nil
                       (list (when font (cons 'font font))
                             (when bg (cons 'background-color bg))
                             (when fg (cons 'foreground-color fg))
                             (cons 'child-frame-border-width
                                   vertico-child-frame-border-width)
                             (cons 'internal-border-width
                                   vertico-child-frame-internal-border-width)))))
    (modify-frame-parameters frame params)
    (when border-bg
      (dolist (face '(child-frame-border internal-border))
        (when (facep face)
          (set-face-background face border-bg frame))))
    (when-let* ((win (frame-root-window frame))
                ((window-live-p win)))
      (set-window-fringes win
                          vertico-child-frame-left-fringe
                          vertico-child-frame-right-fringe))))

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
            (make-frame
             `((parent-frame . ,parent)
               (minibuffer . ,(minibuffer-window parent))
               (visibility . nil)
               (width . 0)
               (height . 0)
               ,@vertico-child-frame--default-parameters
               ,@vertico-child-frame-parameters)))
      (if entry
          (setcdr entry frame)
        (push (cons depth frame) vertico-child-frame--pool)))
    (vertico-child-frame--sync-appearance frame parent)
    (vertico-child-frame--configure-window (frame-root-window frame))
    frame))

(defun vertico-child-frame--apply-geometry (frame geometry)
  "Apply GEOMETRY (X Y WIDTH HEIGHT) to FRAME if changed."
  (unless (equal geometry (frame-parameter frame 'vertico-child-frame--geometry))
    (pcase-let ((`(,x ,y ,width ,height) geometry))
      (let ((frame-resize-pixelwise t))
        (set-frame-size frame width height t)
        (set-frame-position frame x y)
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
(defun vertico-child-frame-cleanup ()
  "Delete all pooled Vertico child frames."
  (interactive)
  (dolist (entry vertico-child-frame--pool)
    (when (frame-live-p (cdr entry))
      (ignore-errors (delete-frame (cdr entry)))))
  (setq vertico-child-frame--pool nil
        vertico-child-frame--active-frames nil))

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

(defun vertico-child-frame--redisplay (_win)
  "Synchronize child-frame point, cursor, and hidden minibuffer before redisplay."
  (when vertico-child-frame--active
    (let ((mbwin (active-minibuffer-window))
          (win vertico-child-frame--window))
      (when (and (window-live-p mbwin)
                 (eq (window-buffer mbwin) (current-buffer)))
        (vertico-child-frame--hide-minibuffer mbwin))
      (vertico-child-frame--update-cursor)
      (when (and (window-live-p win)
                 (eq (window-buffer win) (current-buffer)))
        (set-window-point win (point))))))

(defun vertico-child-frame--resize (height)
  "Resize the active Vertico child frame for HEIGHT candidate lines."
  (when (and vertico-child-frame--active
             (frame-live-p vertico-child-frame--frame)
             (frame-live-p vertico-child-frame--parent))
    (let ((geometry (vertico-child-frame--compute-geometry
                     vertico-child-frame--parent
                     height
                     vertico-child-frame--depth)))
      (vertico-child-frame--apply-geometry vertico-child-frame--frame geometry))))

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
               (win (frame-root-window frame))
               (geometry (vertico-child-frame--compute-geometry
                          parent vertico-count depth)))
          (setq vertico-child-frame--active t
                vertico-child-frame--frame frame
                vertico-child-frame--window win
                vertico-child-frame--depth depth
                vertico-child-frame--parent parent
                vertico-child-frame--max-height-seen 0
                vertico-child-frame--saved-cursor cursor-in-non-selected-windows
                vertico-child-frame--orig-truncate-lines truncate-lines
                vertico-child-frame--orig-auto-hscroll auto-hscroll-mode
                vertico-child-frame--orig-resize-mini resize-mini-windows
                vertico-child-frame--orig-mode-line mode-line-format
                vertico-child-frame--orig-header-line header-line-format
                vertico-child-frame--orig-tab-line tab-line-format)
          (setq-local truncate-lines vertico-child-frame-truncate-lines
                      auto-hscroll-mode 'current-line
                      resize-mini-windows nil
                      mode-line-format nil
                      header-line-format nil
                      tab-line-format nil)
          (vertico-child-frame--set-window-buffer win (current-buffer))
          (when (overlayp vertico--candidates-ov)
            (overlay-put vertico--candidates-ov 'window win))
          (when (and (boundp 'vertico--count-ov) (overlayp vertico--count-ov))
            (overlay-put vertico--count-ov 'window win))
          (vertico-child-frame--hide-minibuffer mbwin)
          (vertico-child-frame--apply-geometry frame geometry)
          (setq vertico-child-frame--active-frames
                (cons (cons depth frame)
                      (assq-delete-all depth vertico-child-frame--active-frames)))
          (make-frame-visible frame)
          (raise-frame frame)
          (vertico-child-frame--update-cursor)
          (when (window-live-p win)
            (set-window-point win (point)))
          (add-hook 'pre-redisplay-functions #'vertico-child-frame--redisplay nil :local)
          (add-hook 'minibuffer-exit-hook #'vertico-child-frame--teardown nil :local))))))

(defun vertico-child-frame--teardown ()
  "Tear down the child frame for the current minibuffer session."
  (when vertico-child-frame--active
    (let ((frame vertico-child-frame--frame)
          (win vertico-child-frame--window)
          (depth vertico-child-frame--depth)
          (mbwin (active-minibuffer-window)))
      (setq vertico-child-frame--active nil
            vertico-child-frame--frame nil
            vertico-child-frame--window nil
            vertico-child-frame--depth nil
            vertico-child-frame--parent nil)
      (remove-hook 'pre-redisplay-functions #'vertico-child-frame--redisplay :local)
      (remove-hook 'minibuffer-exit-hook #'vertico-child-frame--teardown :local)
      (when (overlayp vertico--candidates-ov)
        (overlay-put vertico--candidates-ov 'window nil))
      (when (and (boundp 'vertico--count-ov) (overlayp vertico--count-ov))
        (overlay-put vertico--count-ov 'window nil))
      (setq-local cursor-in-non-selected-windows vertico-child-frame--saved-cursor
                  truncate-lines vertico-child-frame--orig-truncate-lines
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
        (when (and (minibufferp) (bound-and-true-p vertico--input))
          (vertico-child-frame--setup)
          (when (fboundp 'vertico--exhibit)
            (vertico--exhibit))))
    (advice-remove #'vertico--window-width #'vertico-child-frame--window-width)
    (remove-hook 'delete-frame-functions #'vertico-child-frame--on-delete-frame)
    (if (and (minibufferp) (bound-and-true-p vertico--input))
        (progn
          (vertico-child-frame--teardown)
          (vertico-child-frame--deactivate-fallback)
          (when (fboundp 'vertico--exhibit)
            (vertico--exhibit)))
      (vertico-child-frame-cleanup))))

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
    (define-key vertico-multiform-map (kbd "M-C") #'vertico-multiform-child-frame)))

(provide 'vertico-child-frame)
;;; vertico-child-frame.el ends here
