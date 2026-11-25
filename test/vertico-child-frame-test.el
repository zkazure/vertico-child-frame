;;; vertico-child-frame-test.el --- ERT tests for vertico-child-frame -*- lexical-binding: t -*-

(require 'ert)
(require 'cl-lib)
(require 'vertico)
(require 'vertico-multiform)
(require 'vertico-child-frame)

;;;; Mock frame/window helpers

(defvar vcf-test--active nil
  "Non-nil when mocked GUI primitives are active inside a test body.")

(cl-defstruct vcf-test-frame
  id parent root-window pixel-w pixel-h char-w char-h
  cols rows visible raised live params pos size)

(cl-defstruct vcf-test-win
  frame buffer point dedicated width height pixel-h mode-line-h
  vscroll hscroll edges inside-edges params)

(defmacro vcf-test-with-mock-gui (&rest body)
  "Evaluate BODY with mocked GUI frames, windows, and display primitives."
  (declare (indent 0) (debug t))
  `(let* ((native-comp-enable-subr-trampolines nil)
          (next-id 1)
          (vcf-test--point-xy '(150 . 100))
          (vcf-test--point-lh 20)
          (vcf-test--string-pixel-width-fn nil)
          (parent-win (make-vcf-test-win
                       :buffer (current-buffer)
                       :point 1
                       :width 120
                       :height 40
                       :pixel-h 800
                       :edges '(0 0 1200 800)
                       :inside-edges '(0 0 1200 800)))
          (parent-frame (make-vcf-test-frame
                         :id 0
                         :pixel-w 1200
                         :pixel-h 800
                         :char-w 10
                         :char-h 20
                         :cols 120
                         :rows 40
                         :visible t
                         :live t
                         :root-window parent-win
                         :params '((font . "Monospace-12"))))
          (mb-win (make-vcf-test-win
                   :frame parent-frame
                   :buffer (current-buffer)
                   :width 120
                   :height 1
                   :pixel-h 20
                   :vscroll 0
                   :edges '(0 780 1200 800)))
          (make-frame-calls 0)
          (resize-calls 0)
          (move-calls 0)
          (modify-params-calls 0)
          (set-face-calls 0)
          (all-frames (list parent-frame))
          (mock-window-list (list parent-win))
          (orig-display-graphic-p (symbol-function 'display-graphic-p))
          (orig-frame-live-p (symbol-function 'frame-live-p))
          (orig-frame-visible-p (symbol-function 'frame-visible-p))
          (orig-frame-parent (symbol-function 'frame-parent))
          (orig-frame-root-window (symbol-function 'frame-root-window))
          (orig-frame-pixel-width (symbol-function 'frame-pixel-width))
          (orig-frame-pixel-height (symbol-function 'frame-pixel-height))
          (orig-frame-char-width (symbol-function 'frame-char-width))
          (orig-frame-char-height (symbol-function 'frame-char-height))
          (orig-frame-width (symbol-function 'frame-width))
          (orig-frame-height (symbol-function 'frame-height))
          (orig-frame-parameter (symbol-function 'frame-parameter))
          (orig-frame-position (symbol-function 'frame-position))
          (orig-set-frame-parameter (symbol-function 'set-frame-parameter))
          (orig-modify-frame-parameters (symbol-function 'modify-frame-parameters))
          (orig-window-live-p (symbol-function 'window-live-p))
          (orig-window-frame (symbol-function 'window-frame))
          (orig-window-buffer (symbol-function 'window-buffer))
          (orig-set-window-buffer (symbol-function 'set-window-buffer))
          (orig-set-window-dedicated-p (symbol-function 'set-window-dedicated-p))
          (orig-window-dedicated-p (symbol-function 'window-dedicated-p))
          (orig-set-window-parameter (symbol-function 'set-window-parameter))
          (orig-window-parameter (symbol-function 'window-parameter))
          (orig-window-list (symbol-function 'window-list))
          (orig-window-minibuffer-p (symbol-function 'window-minibuffer-p))
          (orig-set-window-fringes (symbol-function 'set-window-fringes))
          (orig-set-window-point (symbol-function 'set-window-point))
          (orig-set-window-vscroll (symbol-function 'set-window-vscroll))
          (orig-set-window-hscroll (symbol-function 'set-window-hscroll))
          (orig-window-width (symbol-function 'window-width))
          (orig-window-pixel-height (symbol-function 'window-pixel-height))
          (orig-window-mode-line-height (symbol-function 'window-mode-line-height))
          (orig-string-pixel-width (symbol-function 'string-pixel-width))
          (orig-window-pixel-edges (symbol-function 'window-pixel-edges))
          (orig-window-inside-pixel-edges (symbol-function 'window-inside-pixel-edges))
          (orig-window-point (symbol-function 'window-point))
          (orig-posn-at-point (symbol-function 'posn-at-point))
          (orig-set-face-background (symbol-function 'set-face-background))
          (orig-minibuffer-window (symbol-function 'minibuffer-window))
          (orig-active-minibuffer-window (symbol-function 'active-minibuffer-window))
          (orig-minibuffer-selected-window (symbol-function 'minibuffer-selected-window))
          (orig-selected-window (symbol-function 'selected-window))
          (orig-window-resize (symbol-function 'window-resize)))
     (setf (vcf-test-win-frame parent-win) parent-frame)
     (let ((vcf-test--active nil))
       (cl-letf*
         (((symbol-function 'display-graphic-p)
           (lambda (&optional f)
             (if vcf-test--active t (funcall orig-display-graphic-p f))))
          ((symbol-function 'frame-live-p)
           (lambda (f)
             (if (vcf-test-frame-p f)
                 (vcf-test-frame-live f)
               (funcall orig-frame-live-p f))))
          ((symbol-function 'frame-visible-p)
           (lambda (&optional f)
             (let ((target (or f parent-frame)))
               (if (vcf-test-frame-p target)
                   (vcf-test-frame-visible target)
                 (funcall orig-frame-visible-p f)))))
          ((symbol-function 'frame-parent)
           (lambda (f)
             (if (vcf-test-frame-p f)
                 (vcf-test-frame-parent f)
               (funcall orig-frame-parent f))))
          ((symbol-function 'frame-root-window)
           (lambda (f)
             (if (vcf-test-frame-p f)
                 (vcf-test-frame-root-window f)
               (funcall orig-frame-root-window f))))
          ((symbol-function 'frame-pixel-width)
           (lambda (&optional f)
             (if (vcf-test-frame-p f)
                 (vcf-test-frame-pixel-w f)
               (funcall orig-frame-pixel-width f))))
          ((symbol-function 'frame-pixel-height)
           (lambda (&optional f)
             (if (vcf-test-frame-p f)
                 (vcf-test-frame-pixel-h f)
               (funcall orig-frame-pixel-height f))))
          ((symbol-function 'frame-char-width)
           (lambda (&optional f)
             (if (vcf-test-frame-p f)
                 (vcf-test-frame-char-w f)
               (funcall orig-frame-char-width f))))
          ((symbol-function 'frame-char-height)
           (lambda (&optional f)
             (if (vcf-test-frame-p f)
                 (vcf-test-frame-char-h f)
               (funcall orig-frame-char-height f))))
          ((symbol-function 'frame-width)
           (lambda (&optional f)
             (if (vcf-test-frame-p f)
                 (vcf-test-frame-cols f)
               (funcall orig-frame-width f))))
          ((symbol-function 'frame-height)
           (lambda (&optional f)
             (if (vcf-test-frame-p f)
                 (vcf-test-frame-rows f)
               (funcall orig-frame-height f))))
          ((symbol-function 'frame-parameter)
           (lambda (f param)
             (if (vcf-test-frame-p f)
                 (alist-get param (vcf-test-frame-params f))
               (funcall orig-frame-parameter f param))))
          ((symbol-function 'frame-position)
           (lambda (&optional f)
             (if (vcf-test-frame-p f)
                 (or (vcf-test-frame-pos f) '(0 . 0))
               (funcall orig-frame-position f))))
          ((symbol-function 'set-frame-parameter)
           (lambda (f param val)
             (if (vcf-test-frame-p f)
                 (progn
                   (setf (alist-get param (vcf-test-frame-params f)) val)
                   val)
               (funcall orig-set-frame-parameter f param val))))
          ((symbol-function 'modify-frame-parameters)
           (lambda (f alist)
             (if (vcf-test-frame-p f)
                 (progn
                   (cl-incf modify-params-calls)
                   (dolist (pair alist)
                     (setf (alist-get (car pair) (vcf-test-frame-params f))
                           (cdr pair))))
               (funcall orig-modify-frame-parameters f alist))))
          ((symbol-function 'make-frame)
           (lambda (&optional params)
             (cl-incf make-frame-calls)
             (let* ((pf (alist-get 'parent-frame params))
                    (cw (if (vcf-test-frame-p pf) (vcf-test-frame-char-w pf) 10))
                    (ch (if (vcf-test-frame-p pf) (vcf-test-frame-char-h pf) 20))
                    (cols (max 1 (or (alist-get 'width params) 72)))
                    (rows (max 1 (or (alist-get 'height params) 11)))
                    (pw (* cols cw))
                    (ph (* rows ch))
                    (w (make-vcf-test-win :width cols :height rows :pixel-h ph))
                    (f (make-vcf-test-frame
                        :id next-id
                        :parent (alist-get 'parent-frame params)
                        :root-window w
                        :pixel-w pw
                        :pixel-h ph
                        :char-w cw
                        :char-h ch
                        :cols cols
                        :rows rows
                        :visible (alist-get 'visibility params)
                        :live t
                        :params (copy-alist params))))
               (cl-incf next-id)
               (setf (vcf-test-win-frame w) f)
               (push f all-frames)
               f)))
          ((symbol-function 'delete-frame)
           (lambda (&optional f _force)
             (when (vcf-test-frame-p f)
               (setf (vcf-test-frame-live f) nil
                     (vcf-test-frame-visible f) nil))))
          ((symbol-function 'make-frame-visible)
           (lambda (&optional f)
             (when (vcf-test-frame-p f)
               (setf (vcf-test-frame-visible f) t))))
          ((symbol-function 'make-frame-invisible)
           (lambda (&optional f _force)
             (when (vcf-test-frame-p f)
               (setf (vcf-test-frame-visible f) nil
                     (vcf-test-frame-raised f) nil))))
          ((symbol-function 'raise-frame)
           (lambda (&optional f)
             (when (vcf-test-frame-p f)
               (setf (vcf-test-frame-raised f) t))))
          ((symbol-function 'set-frame-size)
           (lambda (f w h &optional _pixelwise)
             (cl-incf resize-calls)
             (when (vcf-test-frame-p f)
               (setf (vcf-test-frame-pixel-w f) w
                     (vcf-test-frame-pixel-h f) h
                     (vcf-test-frame-size f) (cons w h))
               (when-let* ((rw (vcf-test-frame-root-window f)))
                 (setf (vcf-test-win-width rw)
                       (max 1 (/ w (max 1 (vcf-test-frame-char-w f))))
                       (vcf-test-win-height rw)
                       (max 1 (/ h (max 1 (vcf-test-frame-char-h f))))
                       (vcf-test-win-pixel-h rw) h)))))
          ((symbol-function 'set-frame-position)
           (lambda (f x y)
             (cl-incf move-calls)
             (when (vcf-test-frame-p f)
               (setf (vcf-test-frame-pos f) (cons x y)))))
          ((symbol-function 'set-face-background)
           (lambda (face color &optional frame)
             (if (vcf-test-frame-p frame)
                 (progn
                   (cl-incf set-face-calls)
                   (setf (alist-get (intern (format "face-%s" face))
                                    (vcf-test-frame-params frame))
                         color))
               (funcall orig-set-face-background face color frame))))
          ((symbol-function 'window-live-p)
           (lambda (w)
             (if (vcf-test-win-p w) t (funcall orig-window-live-p w))))
          ((symbol-function 'window-frame)
           (lambda (&optional w)
             (if (vcf-test-win-p w)
                 (vcf-test-win-frame w)
               (funcall orig-window-frame w))))
          ((symbol-function 'window-buffer)
           (lambda (&optional w)
             (if (vcf-test-win-p w)
                 (vcf-test-win-buffer w)
               (funcall orig-window-buffer w))))
          ((symbol-function 'set-window-buffer)
           (lambda (w buf &optional keep)
             (if (vcf-test-win-p w)
                 (setf (vcf-test-win-buffer w) buf)
               (funcall orig-set-window-buffer w buf keep))))
          ((symbol-function 'set-window-dedicated-p)
           (lambda (w flag)
             (if (vcf-test-win-p w)
                 (setf (vcf-test-win-dedicated w) flag)
               (funcall orig-set-window-dedicated-p w flag))))
          ((symbol-function 'window-dedicated-p)
           (lambda (&optional w)
             (if (vcf-test-win-p w)
                 (vcf-test-win-dedicated w)
               (funcall orig-window-dedicated-p w))))
          ((symbol-function 'set-window-parameter)
           (lambda (w p v)
             (if (vcf-test-win-p w)
                 (setf (alist-get p (vcf-test-win-params w)) v)
               (funcall orig-set-window-parameter w p v))))
          ((symbol-function 'window-parameter)
           (lambda (w p)
             (if (vcf-test-win-p w)
                 (alist-get p (vcf-test-win-params w))
               (funcall orig-window-parameter w p))))
          ((symbol-function 'window-list)
           (lambda (&optional frame minibuf window)
             (if (and vcf-test--active (vcf-test-frame-p frame))
                 mock-window-list
               (funcall orig-window-list frame minibuf window))))
          ((symbol-function 'window-minibuffer-p)
           (lambda (&optional w)
             (if (vcf-test-win-p w)
                 (eq w mb-win)
               (funcall orig-window-minibuffer-p w))))
          ((symbol-function 'set-window-fringes)
           (lambda (w &rest args)
             (unless (vcf-test-win-p w)
               (apply orig-set-window-fringes w args))))
          ((symbol-function 'set-window-point)
           (lambda (w pt)
             (if (vcf-test-win-p w)
                 (setf (vcf-test-win-point w) pt)
               (funcall orig-set-window-point w pt))))
          ((symbol-function 'set-window-vscroll)
           (lambda (w v &optional p)
             (if (vcf-test-win-p w)
                 (setf (vcf-test-win-vscroll w) v)
               (funcall orig-set-window-vscroll w v p))))
          ((symbol-function 'set-window-hscroll)
           (lambda (w h)
             (if (vcf-test-win-p w)
                 (setf (vcf-test-win-hscroll w) h)
               (funcall orig-set-window-hscroll w h))))
          ((symbol-function 'window-width)
           (lambda (&optional w)
             (cond
              ((vcf-test-win-p w) (vcf-test-win-width w))
              (vcf-test--active 120)
              (t (funcall orig-window-width w)))))
          ((symbol-function 'window-pixel-height)
           (lambda (&optional w)
             (if (vcf-test-win-p w)
                 (vcf-test-win-pixel-h w)
               (funcall orig-window-pixel-height w))))
          ((symbol-function 'window-mode-line-height)
           (lambda (&optional w)
             (if (vcf-test-win-p w)
                 (or (vcf-test-win-mode-line-h w) 0)
               (funcall orig-window-mode-line-height w))))
          ((symbol-function 'string-pixel-width)
           (lambda (str &rest _args)
             (if (and vcf-test--active vcf-test--string-pixel-width-fn)
                 (funcall vcf-test--string-pixel-width-fn str)
               (funcall orig-string-pixel-width str))))
          ((symbol-function 'window-pixel-edges)
           (lambda (&optional w)
             (if (vcf-test-win-p w)
                 (vcf-test-win-edges w)
               (funcall orig-window-pixel-edges w))))
          ((symbol-function 'window-inside-pixel-edges)
           (lambda (&optional w)
             (if (vcf-test-win-p w)
                 (or (vcf-test-win-inside-edges w) (vcf-test-win-edges w))
               (funcall orig-window-inside-pixel-edges w))))
          ((symbol-function 'window-point)
           (lambda (&optional w)
             (if (vcf-test-win-p w)
                 (or (vcf-test-win-point w) 1)
               (funcall orig-window-point w))))
          ((symbol-function 'posn-at-point)
           (lambda (&optional pos w)
             (if (vcf-test-win-p w)
                 (when vcf-test--point-xy
                   (list w 1 vcf-test--point-xy 0 nil 1 nil nil nil
                         (cons 10 vcf-test--point-lh)))
               (funcall orig-posn-at-point pos w))))
          ((symbol-function 'minibuffer-window)
           (lambda (&optional f)
             (if vcf-test--active mb-win (funcall orig-minibuffer-window f))))
          ((symbol-function 'active-minibuffer-window)
           (lambda ()
             (if vcf-test--active mb-win (funcall orig-active-minibuffer-window))))
          ((symbol-function 'minibuffer-selected-window)
           (lambda ()
             (if vcf-test--active parent-win (funcall orig-minibuffer-selected-window))))
          ((symbol-function 'selected-window)
           (lambda ()
             (if vcf-test--active mb-win (funcall orig-selected-window))))
          ((symbol-function 'window-resize)
           (lambda (w &rest args)
             (unless (vcf-test-win-p w)
               (apply orig-window-resize w args)))))
       (unwind-protect
           (let ((vcf-test--active t))
             ,@body)
         (vertico-child-frame-cleanup))))))

;;;; Geometry tests

(ert-deftest vcf-test-resolve-width-variants ()
  (vcf-test-with-mock-gui
    (let ((vertico-child-frame-margin '(16 . 16))
          (vertico-child-frame-min-width 50)
          (vertico-child-frame-max-width 120))
      ;; Float fraction: 0.6 * 1200 = 720
      (let ((vertico-child-frame-width 0.6))
        (should (= (vertico-child-frame--resolve-width parent-frame) 720)))
      ;; Fixed columns: 80 * 10 = 800
      (let ((vertico-child-frame-width 80))
        (should (= (vertico-child-frame--resolve-width parent-frame) 800)))
      ;; Function spec
      (let ((vertico-child-frame-width (lambda (f) (/ (frame-pixel-width f) 2))))
        (should (= (vertico-child-frame--resolve-width parent-frame) 600)))
      ;; Clamped to min-width (50 * 10 = 500)
      (let ((vertico-child-frame-width 0.1))
        (should (= (vertico-child-frame--resolve-width parent-frame) 500)))
      ;; Clamped to parent width minus margins & chrome (1200 - 32 - 18 = 1150)
      (let ((vertico-child-frame-width 200)
            (vertico-child-frame-max-width nil))
        (should (= (vertico-child-frame--resolve-width parent-frame) 1150)))
      ;; Without chrome (fringes 0, border 0), full 1200 - 32 = 1168 is available
      (let ((vertico-child-frame-width 200)
            (vertico-child-frame-max-width nil)
            (vertico-child-frame-left-fringe 0)
            (vertico-child-frame-right-fringe 0)
            (vertico-child-frame-border-width 0))
        (should (= (vertico-child-frame--resolve-width parent-frame) 1168)))
      ;; Float min-width / max-width bounds
      (let ((vertico-child-frame-min-width 0.3)
            (vertico-child-frame-max-width 0.8))
        (let ((vertico-child-frame-width 0.1))
          (should (= (vertico-child-frame--resolve-width parent-frame) 360)))
        (let ((vertico-child-frame-width 0.95))
          (should (= (vertico-child-frame--resolve-width parent-frame) 960)))))))

(ert-deftest vcf-test-resolve-height-modes ()
  (vcf-test-with-mock-gui
    (with-temp-buffer
      (let ((vertico-count 10)
            (vertico-child-frame-height nil)
            (vertico-child-frame-min-height nil)
            (vertico-child-frame-max-height 0.5)
            (vertico-child-frame-margin '(16 . 16)))
        ;; Fixed height: (1 + 10) * 20 = 220
        (let ((vertico-child-frame-resize nil))
          (should (= (vertico-child-frame--resolve-height parent-frame 3) 220))
          (should (= (vertico-child-frame--resolve-height parent-frame 10) 220)))
        ;; Dynamic grow & shrink
        (let ((vertico-child-frame-resize t))
          (should (= (vertico-child-frame--resolve-height parent-frame 3) 80))
          (should (= (vertico-child-frame--resolve-height parent-frame 7) 160))
          (should (= (vertico-child-frame--resolve-height parent-frame 2) 60)))
        ;; Grow-only
        (let ((vertico-child-frame-resize 'grow-only))
          (setq vertico-child-frame--max-height-seen 0)
          (should (= (vertico-child-frame--resolve-height parent-frame 3) 80))
          (should (= (vertico-child-frame--resolve-height parent-frame 7) 160))
          (should (= (vertico-child-frame--resolve-height parent-frame 2) 160)))
        ;; Min/max height clamping (integers & floats)
        (let ((vertico-child-frame-resize t)
              (vertico-child-frame-min-height 4)
              (vertico-child-frame-max-height 8))
          (should (= (vertico-child-frame--resolve-height parent-frame 0) 80))
          (should (= (vertico-child-frame--resolve-height parent-frame 20) 160)))
        (let ((vertico-child-frame-resize t)
              (vertico-child-frame-min-height 0.2)
              (vertico-child-frame-max-height 0.4))
          (should (= (vertico-child-frame--resolve-height parent-frame 0) 160))
          (should (= (vertico-child-frame--resolve-height parent-frame 30) 320)))
        ;; Explicit vertico-child-frame-height (int lines, float fraction, function)
        (let ((vertico-child-frame-max-height nil))
          (let ((vertico-child-frame-height 12))
            (should (= (vertico-child-frame--resolve-height parent-frame 2) 240)))
          (let ((vertico-child-frame-height 0.25))
            (should (= (vertico-child-frame--resolve-height parent-frame 2) 200)))
          (let ((vertico-child-frame-height (lambda (_p lines) (* (+ 2 lines) 20))))
            (should (= (vertico-child-frame--resolve-height parent-frame 4) 120))))))))

(ert-deftest vcf-test-poshandlers-and-clamping ()
  (vcf-test-with-mock-gui
    (let ((vertico-child-frame-top-offset nil)
          (vertico-child-frame-bottom-offset nil)
          (vertico-child-frame-margin '(16 . 16))
          (vertico-child-frame-offset '(0 . 0))
          (vertico-child-frame-recursive-offset '(24 . 24)))
      ;; Symmetric nil defaults match margin (16px from top and 16px from bottom)
      (let ((vertico-child-frame-bottom-respect-mode-line nil))
        (should (equal (vertico-child-frame-poshandler-frame-top-center parent-frame 720 220)
                       '(240 . 16)))
        (should (equal (vertico-child-frame-poshandler-top-center parent-frame 720 220)
                       '(240 . 16)))
        (should (equal (vertico-child-frame-poshandler-frame-center parent-frame 720 220)
                       '(240 . 290)))
        (should (equal (vertico-child-frame-poshandler-center parent-frame 720 220)
                       '(240 . 290)))
        (should (equal (vertico-child-frame-poshandler-frame-bottom-center parent-frame 720 220)
                       '(240 . 564)))
        (should (equal (vertico-child-frame-poshandler-bottom-center parent-frame 720 220)
                       '(240 . 564))))
      ;; Explicit float offsets
      (let ((vertico-child-frame-top-offset 0.12)
            (vertico-child-frame-bottom-offset 0.06))
        (should (equal (vertico-child-frame-poshandler-frame-top-center parent-frame 720 220)
                       '(240 . 96)))
        (should (equal (vertico-child-frame-poshandler-frame-bottom-center parent-frame 720 220)
                       '(240 . 532))))
      (let ((vertico-child-frame-bottom-respect-mode-line nil))
        (should (equal (vertico-child-frame-poshandler-frame-top-left-corner parent-frame 400 200)
                       '(16 . 16)))
        (should (equal (vertico-child-frame-poshandler-frame-top-right-corner parent-frame 400 200)
                       '(784 . 16)))
        (should (equal (vertico-child-frame-poshandler-frame-bottom-left-corner parent-frame 400 200)
                       '(16 . 584)))
        (should (equal (vertico-child-frame-poshandler-frame-bottom-right-corner parent-frame 400 200)
                       '(784 . 584))))
      ;; Top-left-or-right-other-corner adapts to selected window side
      (setf (vcf-test-win-edges parent-win) '(0 0 500 800))
      (should (equal (vertico-child-frame-poshandler-frame-top-left-or-right-other-corner
                      parent-frame 400 200)
                     '(784 . 16)))
      (setf (vcf-test-win-edges parent-win) '(700 0 1200 800))
      (should (equal (vertico-child-frame-poshandler-frame-top-left-or-right-other-corner
                      parent-frame 400 200)
                     '(16 . 16)))
      ;; Window-relative poshandlers on sub-window (100, 50) -> (900, 650)
      (setf (vcf-test-win-edges parent-win) '(100 50 900 650))
      (should (equal (vertico-child-frame-poshandler-window-center parent-frame 400 200)
                     '(300 . 250)))
      (should (equal (vertico-child-frame-poshandler-window-top-center parent-frame 400 200)
                     '(300 . 66)))
      (should (equal (vertico-child-frame-poshandler-window-top-left-corner parent-frame 400 200)
                     '(116 . 66)))
      (should (equal (vertico-child-frame-poshandler-window-top-right-corner parent-frame 400 200)
                     '(484 . 66)))
      (should (equal (vertico-child-frame-poshandler-window-bottom-center parent-frame 400 200)
                     '(300 . 434)))
      (should (equal (vertico-child-frame-poshandler-window-bottom-left-corner parent-frame 400 200)
                     '(116 . 434)))
      (should (equal (vertico-child-frame-poshandler-window-bottom-right-corner parent-frame 400 200)
                     '(484 . 434)))
      ;; Geometry accounts for outer chrome (18x2 with default fringes=8, border=1)
      ;; ensuring identical left/right and top/bottom outer pixel gaps.
      (let ((vertico-child-frame-width 0.6)
            (vertico-child-frame-resize nil)
            (vertico-child-frame-bottom-respect-mode-line nil)
            (vertico-count 10))
        (let* ((vertico-child-frame-poshandler 'frame-top-center)
               (top-geom (vertico-child-frame--compute-geometry parent-frame 10 1))
               (top-rec (vertico-child-frame--compute-geometry parent-frame 10 2))
               (vertico-child-frame-poshandler 'frame-bottom-center)
               (bot-geom (vertico-child-frame--compute-geometry parent-frame 10 1)))
          ;; outer-w = 720 + 18 = 738 -> left=231, right=1200-231-738=231
          ;; outer-h = 220 + 2 = 222 -> top=16, bottom=800-562-222=16
          (should (equal top-geom '(231 16 720 220)))
          (should (equal bot-geom '(231 562 720 220)))
          (should (equal top-rec '(255 40 720 220)))))
      ;; Clamping keeps child frame inside parent margins
      (should (equal (vertico-child-frame--clamp-position parent-frame -50 900 720 220)
                     '(16 . 564))))))

(ert-deftest vcf-test-point-poshandlers-and-shorthand ()
  (vcf-test-with-mock-gui
    (let ((vertico-child-frame-margin '(16 . 16))
          (vertico-child-frame-offset '(0 . 0))
          (vertico-child-frame-recursive-offset '(24 . 24)))
      (setf (vcf-test-win-edges parent-win) '(100 50 900 750)
            (vcf-test-win-inside-edges parent-win) '(100 50 900 750))
      ;; Point at (100+150=250, 50+100=150), lh=20
      (should (equal (vertico-child-frame-poshandler-point-bottom-left-corner
                      parent-frame 400 200)
                     '(250 . 170)))
      (should (equal (vertico-child-frame-poshandler-point-top-left-corner
                      parent-frame 400 200)
                     '(250 . 150)))
      (should (equal (vertico-child-frame-poshandler-point-bottom-left-corner-upward
                      parent-frame 400 100)
                     '(250 . 50)))
      (should (equal (vertico-child-frame-poshandler-point-window-center
                      parent-frame 400 200)
                     '(300 . 170)))
      (should (equal (vertico-child-frame-poshandler-point-frame-center
                      parent-frame 400 200)
                     '(400 . 170)))
      ;; Flip upward automatically when near bottom of parent frame (py = 600+50 = 650)
      (setq vcf-test--point-xy '(150 . 600))
      (should (equal (vertico-child-frame-poshandler-point-bottom-left-corner
                      parent-frame 400 200)
                     '(250 . 450)))
      ;; Fallback to window-center / frame-center when posn-at-point returns nil
      (setq vcf-test--point-xy nil)
      (should (equal (vertico-child-frame-poshandler-point-bottom-left-corner
                      parent-frame 400 200)
                     '(300 . 300)))
      (should (equal (vertico-child-frame-poshandler-point-frame-center
                      parent-frame 400 200)
                     '(400 . 300)))
      ;; Short symbolic poshandler + global pixel offset (outer-w=418, outer-h=222)
      (let ((vertico-child-frame-poshandler 'frame-bottom-right-corner)
            (vertico-child-frame-width 40)
            (vertico-child-frame-min-width nil)
            (vertico-child-frame-resize nil)
            (vertico-child-frame-bottom-respect-mode-line nil)
            (vertico-count 10)
            (vertico-child-frame-offset '(-10 . -20)))
        (should (equal (vertico-child-frame--compute-geometry parent-frame 10 1)
                       '(756 542 400 220))))
      ;; Interactive poshandler switcher updates live session immediately
      (vertico-child-frame-mode 1)
      (unwind-protect
          (cl-letf (((symbol-function 'minibufferp) (lambda (&optional _b _l) t))
                    ((symbol-function 'minibuffer-depth) (lambda () 1)))
            (with-temp-buffer
              (setf (vcf-test-win-buffer mb-win) (current-buffer))
              (let ((vertico-child-frame-poshandler 'frame-top-center)
                    (vertico-child-frame-width 0.6)
                    (vertico-child-frame-resize nil)
                    (vertico-child-frame-bottom-respect-mode-line nil))
                (vertico--setup)
                (vertico-child-frame-set-poshandler
                 #'vertico-child-frame-poshandler-frame-bottom-right-corner)
                (should (eq vertico-child-frame-poshandler
                            #'vertico-child-frame-poshandler-frame-bottom-right-corner))
                (should (equal (vcf-test-frame-pos vertico-child-frame--frame)
                               '(446 . 562)))
                (run-hooks 'minibuffer-exit-hook))))
        (vertico-child-frame-mode -1)))))

(ert-deftest vcf-test-appearance-options ()
  (vcf-test-with-mock-gui
    (let ((vertico-child-frame-font "JetBrains Mono-13")
          (vertico-child-frame-alpha 92)
          (vertico-child-frame-border-width 2)
          (vertico-child-frame-internal-border-width 8)
          (vertico-child-frame-mode-line-format '(" ML"))
          (vertico-child-frame-header-line-format '(" HL")))
      (vertico-child-frame-mode 1)
      (unwind-protect
          (cl-letf (((symbol-function 'minibufferp) (lambda (&optional _b _l) t))
                    ((symbol-function 'minibuffer-depth) (lambda () 1)))
            (with-temp-buffer
              (setf (vcf-test-win-buffer mb-win) (current-buffer))
              (vertico--setup)
              (let ((f vertico-child-frame--frame))
                (should (equal (frame-parameter f 'font) "JetBrains Mono-13"))
                (should (= (frame-parameter f 'alpha-background) 92))
                (should (= (frame-parameter f 'child-frame-border-width) 2))
                (should (= (frame-parameter f 'internal-border-width) 8))
                (should (equal mode-line-format '(" ML")))
                (should (equal header-line-format '(" HL")))
                ;; internal-border uses child frame background rather than border-bg
                (should (equal (frame-parameter f 'face-internal-border)
                               (frame-parameter f 'background-color)))
                (should-not (equal (frame-parameter f 'face-internal-border)
                                   (frame-parameter f 'face-child-frame-border))))
              (run-hooks 'minibuffer-exit-hook))
            ;; Cons alpha sets `alpha' parameter
            (let ((vertico-child-frame-alpha '(95 . 85)))
              (with-temp-buffer
                (setf (vcf-test-win-buffer mb-win) (current-buffer))
                (vertico--setup)
                (let ((f vertico-child-frame--frame))
                  (should (equal (frame-parameter f 'alpha) '(95 . 85)))
                  (should-not (frame-parameter f 'alpha-background)))
                (run-hooks 'minibuffer-exit-hook))))
        (vertico-child-frame-mode -1)))))

(ert-deftest vcf-test-other-window-poshandlers ()
  (vcf-test-with-mock-gui
    (let ((vertico-child-frame-top-offset nil)
          (vertico-child-frame-bottom-offset nil)
          (vertico-child-frame-margin '(16 . 16))
          (vertico-child-frame-offset '(0 . 0))
          (vertico-child-frame-recursive-offset '(24 . 24))
          (sidebar-win (make-vcf-test-win
                        :frame parent-frame
                        :width 20
                        :height 40
                        :pixel-h 800
                        :edges '(0 0 200 800)
                        :params '((no-other-window . t))))
          (other-win (make-vcf-test-win
                      :frame parent-frame
                      :width 60
                      :height 30
                      :pixel-h 600
                      :edges '(600 100 1200 700))))
      (setf (vcf-test-win-edges parent-win) '(0 0 600 800))
      ;; With sidebar (no-other-window), mb-win, and other-win in window-list,
      ;; other-window-* skips parent-win, mb-win, and sidebar-win.
      ;; Top/bottom gaps are symmetric (16px from top=100, 16px from bottom=700).
      (setq mock-window-list (list parent-win mb-win sidebar-win other-win))
      (should (equal (vertico-child-frame-poshandler-other-window-center
                      parent-frame 300 200)
                     '(750 . 300)))
      (should (equal (vertico-child-frame-poshandler-other-window-top-center
                      parent-frame 300 200)
                     '(750 . 116)))
      (should (equal (vertico-child-frame-poshandler-other-window-top-left-corner
                      parent-frame 300 200)
                     '(616 . 116)))
      (should (equal (vertico-child-frame-poshandler-other-window-top-right-corner
                      parent-frame 300 200)
                     '(884 . 116)))
      (should (equal (vertico-child-frame-poshandler-other-window-bottom-center
                      parent-frame 300 200)
                     '(750 . 484)))
      (should (equal (vertico-child-frame-poshandler-other-window-bottom-left-corner
                      parent-frame 300 200)
                     '(616 . 484)))
      (should (equal (vertico-child-frame-poshandler-other-window-bottom-right-corner
                      parent-frame 300 200)
                     '(884 . 484)))
      ;; Symbolic shorthand resolves via --compute-geometry (outer-w=318, outer-h=202)
      (let ((vertico-child-frame-poshandler 'other-window-center)
            (vertico-child-frame-width 30)
            (vertico-child-frame-min-width nil)
            (vertico-child-frame-resize nil)
            (vertico-count 9))
        (should (equal (vertico-child-frame--compute-geometry parent-frame 9 1)
                       '(741 299 300 200))))
      ;; Single-window frame falls back to window-* (selected window)
      (setq mock-window-list (list parent-win))
      (should (equal (vertico-child-frame-poshandler-other-window-center
                      parent-frame 300 200)
                     '(150 . 300)))
      (should (equal (vertico-child-frame-poshandler-other-window-top-center
                      parent-frame 300 200)
                     '(150 . 16)))
      (should (equal (vertico-child-frame-poshandler-other-window-top-left-corner
                      parent-frame 300 200)
                     '(16 . 16)))
      (should (equal (vertico-child-frame-poshandler-other-window-top-right-corner
                      parent-frame 300 200)
                     '(284 . 16)))
      (should (equal (vertico-child-frame-poshandler-other-window-bottom-center
                      parent-frame 300 200)
                     '(150 . 584)))
      (should (equal (vertico-child-frame-poshandler-other-window-bottom-left-corner
                      parent-frame 300 200)
                     '(16 . 584)))
      (should (equal (vertico-child-frame-poshandler-other-window-bottom-right-corner
                      parent-frame 300 200)
                     '(284 . 584))))))

;;;; Fallback tests

(ert-deftest vcf-test-tty-and-fallback-mode ()
  ;; In batch mode (no mocked GUI), display-graphic-p is nil.
  (should-not (vertico-child-frame--supported-p))
  (let ((fallback-state nil))
    (cl-letf (((symbol-function 'vcf-test-dummy-fallback)
               (lambda (&optional arg)
                 (setq fallback-state (and arg (> arg 0))))))
      (defvar vcf-test-dummy-fallback nil)
      (let ((vertico-child-frame-fallback-mode 'vcf-test-dummy-fallback)
            (vertico-stub--resize-called nil))
        (vertico-child-frame-mode 1)
        (unwind-protect
            (with-temp-buffer
              (cl-letf (((symbol-function 'minibufferp) (lambda (&optional _b _l) t))
                        ((symbol-function 'active-minibuffer-window) (lambda () (selected-window)))
                        ((symbol-function 'minibuffer-depth) (lambda () 1)))
                (vertico--setup)
                (should-not vertico-child-frame--active)
                (should fallback-state)
                ;; Resize delegates to Vertico's next method when inactive
                (vertico--resize-window 5)
                (should (= vertico-stub--resize-called 5))
                (run-hooks 'minibuffer-exit-hook)
                (should-not fallback-state)))
          (vertico-child-frame-mode -1))))))

(defvar vcf-test--cl-fb-mode nil
  "Mock fallback minor-mode variable used in `cl-defmethod' dispatch test.")
(defvar vcf-test--cl-fb-activate-count 0)
(defvar vcf-test--cl-fb-setup-count 0)

(defun vcf-test--cl-fb-mode (&optional arg)
  "Toggle mock fallback mode `vcf-test--cl-fb-mode' according to ARG."
  (let ((enable (if (numberp arg) (> arg 0) (not vcf-test--cl-fb-mode))))
    (when enable
      (cl-incf vcf-test--cl-fb-activate-count))
    (setq vcf-test--cl-fb-mode enable)))

(cl-defmethod vertico--setup :after (&context (vcf-test--cl-fb-mode (eql t)))
  (cl-incf vcf-test--cl-fb-setup-count))

(ert-deftest vcf-test-tty-child-frames-support-and-geometry ()
  "Verify Emacs 31+ `tty-child-frames' detection, cell geometry, and lifecycle."
  (vcf-test-with-mock-gui
    (let ((tty-feature t)
          (tty-term "xterm-256color")
          (fringe-calls 0)
          (orig-featurep (symbol-function 'featurep))
          (orig-tty-type (symbol-function 'tty-type)))
      (setf (vcf-test-frame-char-w parent-frame) 1
            (vcf-test-frame-char-h parent-frame) 1
            (vcf-test-frame-pixel-w parent-frame) 120
            (vcf-test-frame-pixel-h parent-frame) 40
            (vcf-test-frame-cols parent-frame) 120
            (vcf-test-frame-rows parent-frame) 40
            (vcf-test-frame-params parent-frame) nil
            (vcf-test-win-pixel-h mb-win) 1
            (vcf-test-win-edges parent-win) '(0 0 120 40)
            (vcf-test-win-inside-edges parent-win) '(0 0 120 40))
      (cl-letf (((symbol-function 'display-graphic-p) (lambda (&optional _f) nil))
                ((symbol-function 'featurep)
                 (lambda (feat &optional sub)
                   (if (eq feat 'tty-child-frames)
                       tty-feature
                     (funcall orig-featurep feat sub))))
                ((symbol-function 'tty-type)
                 (lambda (&optional f)
                   (if (or (null f) (vcf-test-frame-p f))
                       tty-term
                     (funcall orig-tty-type f))))
                ((symbol-function 'set-window-fringes)
                 (lambda (&rest _args) (cl-incf fringe-calls))))
        ;; Feature + live tty-type detection matrix
        (should (vertico-child-frame--supported-p parent-frame))
        (setq tty-term nil)
        (should-not (vertico-child-frame--supported-p parent-frame))
        (setq tty-term "xterm-256color"
              tty-feature nil)
        (should-not (vertico-child-frame--supported-p parent-frame))
        (setq tty-feature t)
        ;; Chrome omits fringes on TTY and clamps border to 1 cell
        (let ((vertico-child-frame-border-width 1)
              (vertico-child-frame-left-fringe 8)
              (vertico-child-frame-right-fringe 8))
          (should (equal (vertico-child-frame--chrome-size parent-frame) '(2 . 2))))
        (let ((vertico-child-frame-border-width 0)
              (vertico-child-frame-internal-border-width 0))
          (should (equal (vertico-child-frame--chrome-size parent-frame) '(0 . 0))))
        ;; Golden ratio respects 2:1 TTY cell aspect on 120x40 and 80x24
        (let ((vertico-child-frame-golden-ratio-scale 1.0))
          (should (equal (vertico-child-frame--golden-pixel-size parent-frame)
                         '(74 . 23)))
          (let ((small-tty (make-vcf-test-frame
                            :id 88 :pixel-w 80 :pixel-h 24
                            :char-w 1 :char-h 1 :cols 80 :rows 24 :live t)))
            (should (equal (vertico-child-frame--golden-pixel-size small-tty)
                           '(48 . 15)))))
        ;; Margin, offset, and recursive-offset scale from GUI px to TTY cells
        (let ((vertico-child-frame-width 40)
              (vertico-child-frame-min-width nil)
              (vertico-child-frame-resize nil)
              (vertico-count 10)
              (vertico-child-frame-border-width 1)
              (vertico-child-frame-margin '(16 . 16))
              (vertico-child-frame-offset '(0 . 0))
              (vertico-child-frame-recursive-offset '(24 . 24)))
          (let ((vertico-child-frame-poshandler 'frame-top-left-corner))
            (should (equal (vertico-child-frame--compute-geometry parent-frame 10 1)
                           '(2 1 40 11))))
          (let ((vertico-child-frame-poshandler 'frame-center))
            (should (equal (vertico-child-frame--compute-geometry parent-frame 10 1)
                           '(39 14 40 11)))
            (should (equal (vertico-child-frame--compute-geometry parent-frame 10 2)
                           '(41 15 40 11)))
            (let ((vertico-child-frame-offset '(-10 . -20)))
              (should (equal (vertico-child-frame--compute-geometry parent-frame 10 1)
                             '(38 13 40 11))))))
        ;; Full TTY setup, recursive minibuffer, and teardown lifecycle
        (let ((vertico-child-frame-font "Monospace-12")
              (vertico-child-frame-alpha 90)
              (vertico-child-frame-border-width 2)
              (vertico-child-frame-internal-border-width 8)
              (vertico-child-frame-left-fringe 8)
              (vertico-child-frame-right-fringe 8)
              (vertico-child-frame-recursive-offset '(24 . 24))
              (depth 1)
              (buf1 (generate-new-buffer " *tty-mb1*"))
              (buf2 (generate-new-buffer " *tty-mb2*")))
          (vertico-child-frame-mode 1)
          (unwind-protect
              (cl-letf (((symbol-function 'minibufferp) (lambda (&optional _b _l) t))
                        ((symbol-function 'minibuffer-depth) (lambda () depth)))
                (with-current-buffer buf1
                  (setf (vcf-test-win-buffer mb-win) buf1)
                  (vertico--setup)
                  (should vertico-child-frame--active)
                  (let ((f1 vertico-child-frame--frame))
                    (should (= make-frame-calls 1))
                    (should (= fringe-calls 0))
                    (should-not (frame-parameter f1 'font))
                    (should-not (frame-parameter f1 'alpha))
                    (should-not (frame-parameter f1 'alpha-background))
                    (should-not (frame-parameter f1 'left-fringe))
                    (should-not (frame-parameter f1 'right-fringe))
                    (should (= (frame-parameter f1 'child-frame-border-width) 1))
                    (should (= (frame-parameter f1 'internal-border-width) 0))
                    (setq depth 2)
                    (with-current-buffer buf2
                      (setf (vcf-test-win-buffer mb-win) buf2)
                      (vertico--setup)
                      (let ((f2 vertico-child-frame--frame))
                        (should (= make-frame-calls 2))
                        (should (equal (vcf-test-frame-pos f2)
                                       (cons (+ (car (vcf-test-frame-pos f1)) 2)
                                             (+ (cdr (vcf-test-frame-pos f1)) 1))))
                        (setf (vcf-test-frame-raised f1) nil)
                        (run-hooks 'minibuffer-exit-hook)
                        (should-not (vcf-test-frame-visible f2))
                        (should (vcf-test-frame-visible f1))
                        (should (vcf-test-frame-raised f1))))
                    (setq depth 1)
                    (setf (vcf-test-win-buffer mb-win) buf1)
                    (run-hooks 'minibuffer-exit-hook)
                    (should-not (vcf-test-frame-visible f1)))))
            (when (buffer-live-p buf1) (kill-buffer buf1))
            (when (buffer-live-p buf2) (kill-buffer buf2))
            (vertico-child-frame-mode -1)))))))

(ert-deftest vcf-test-fallback-dispatches-vertico-setup ()
  "Verify fallback mode activates before `vertico--setup' method dispatch."
  (should-not (vertico-child-frame--supported-p))
  (let ((vertico-child-frame-fallback-mode #'vcf-test--cl-fb-mode)
        (vcf-test--cl-fb-mode nil)
        (vcf-test--cl-fb-activate-count 0)
        (vcf-test--cl-fb-setup-count 0))
    ;; 1. Global mode: fallback activates once before cl-defmethod :after runs
    (vertico-child-frame-mode 1)
    (unwind-protect
        (with-temp-buffer
          (cl-letf (((symbol-function 'minibufferp) (lambda (&optional _b _l) t))
                    ((symbol-function 'active-minibuffer-window)
                     (lambda () (selected-window)))
                    ((symbol-function 'minibuffer-depth) (lambda () 1)))
            (vertico--setup)
            (should-not vertico-child-frame--active)
            (should vcf-test--cl-fb-mode)
            (should (= vcf-test--cl-fb-activate-count 1))
            (should (= vcf-test--cl-fb-setup-count 1))
            (run-hooks 'minibuffer-exit-hook)
            (should-not vcf-test--cl-fb-mode)))
      (vertico-child-frame-mode -1))
    ;; 2. Multiform-style :around advice enabling vertico-child-frame-mode dynamically
    (setq vcf-test--cl-fb-activate-count 0
          vcf-test--cl-fb-setup-count 0)
    (let ((multiform-around
           (lambda (orig &rest args)
             (vertico-child-frame-mode 1)
             (add-hook 'minibuffer-exit-hook
                       (lambda () (vertico-child-frame-mode -1))
                       nil :local)
             (apply orig args))))
      (advice-add #'vertico--setup :around multiform-around)
      (unwind-protect
          (with-temp-buffer
            (cl-letf (((symbol-function 'minibufferp) (lambda (&optional _b _l) t))
                      ((symbol-function 'active-minibuffer-window)
                       (lambda () (selected-window)))
                      ((symbol-function 'minibuffer-depth) (lambda () 1)))
              (vertico--setup)
              (should vcf-test--cl-fb-mode)
              (should (= vcf-test--cl-fb-activate-count 1))
              (should (= vcf-test--cl-fb-setup-count 1))
              (run-hooks 'minibuffer-exit-hook)
              (should-not vcf-test--cl-fb-mode)))
        (advice-remove #'vertico--setup multiform-around)
        (vertico-child-frame-mode -1)))
    ;; 3. Recursive minibuffer preserves outer fallback ownership until depth 1 exits
    (setq vcf-test--cl-fb-activate-count 0
          vcf-test--cl-fb-setup-count 0)
    (vertico-child-frame-mode 1)
    (unwind-protect
        (let ((buf1 (generate-new-buffer " *fb-mb1*"))
              (buf2 (generate-new-buffer " *fb-mb2*")))
          (unwind-protect
              (cl-letf (((symbol-function 'minibufferp) (lambda (&optional _b _l) t))
                        ((symbol-function 'active-minibuffer-window)
                         (lambda () (selected-window))))
                (with-current-buffer buf1
                  (vertico--setup)
                  (should vcf-test--cl-fb-mode)
                  (should (eq vertico-child-frame--fallback-active
                              #'vcf-test--cl-fb-mode))
                  (with-current-buffer buf2
                    (vertico--setup)
                    (should vcf-test--cl-fb-mode)
                    (should-not vertico-child-frame--fallback-active)
                    (run-hooks 'minibuffer-exit-hook)
                    (should vcf-test--cl-fb-mode))
                  (should vcf-test--cl-fb-mode)
                  (run-hooks 'minibuffer-exit-hook)
                  (should-not vcf-test--cl-fb-mode)))
            (when (buffer-live-p buf1) (kill-buffer buf1))
            (when (buffer-live-p buf2) (kill-buffer buf2))))
      (vertico-child-frame-mode -1))))

;;;; Lifecycle, pooling, recursive minibuffers, and multiform tests

(ert-deftest vcf-test-pool-reuse-and-geometry-cache ()
  (vcf-test-with-mock-gui
    (vertico-child-frame-mode 1)
    (unwind-protect
        (cl-letf (((symbol-function 'minibufferp) (lambda (&optional _b _l) t))
                  ((symbol-function 'minibuffer-depth) (lambda () 1)))
          ;; Session 1
          (with-temp-buffer
            (setf (vcf-test-win-buffer mb-win) (current-buffer))
            (vertico--setup)
            (should vertico-child-frame--active)
            (should (= make-frame-calls 1))
            (should (vcf-test-frame-visible vertico-child-frame--frame))
            (should (eq (overlay-get vertico--candidates-ov 'window)
                        vertico-child-frame--window))
            (should (eq (overlay-get vertico--count-ov 'window)
                        vertico-child-frame--window))
            ;; Long path settings
            (should truncate-lines)
            (should (eq auto-hscroll-mode 'current-line))
            (should-not resize-mini-windows)
            ;; Window width advice reports child-frame width (74 cols for 0.62 * 1200 vs 120)
            (should (= (vertico--window-width) 74))
            ;; Calling resize with identical height hits geometry cache
            (let ((prev-resizes resize-calls)
                  (prev-moves move-calls))
              (vertico--resize-window 5)
              (should (= resize-calls prev-resizes))
              (should (= move-calls prev-moves)))
            (let ((frame-1 vertico-child-frame--frame))
              (run-hooks 'minibuffer-exit-hook)
              ;; Idempotent second teardown is a safe no-op
              (vertico-child-frame--teardown)
              (should-not vertico-child-frame--active)
              (should-not (vcf-test-frame-visible frame-1))
              (should-not (overlay-get vertico--candidates-ov 'window))
              (should (= (vertico--window-width) 120))))
          ;; Session 2 reuses pooled frame (no second make-frame)
          (with-temp-buffer
            (setf (vcf-test-win-buffer mb-win) (current-buffer))
            (vertico--setup)
            (should (= make-frame-calls 1))
            (should (vcf-test-frame-visible vertico-child-frame--frame))
            (run-hooks 'minibuffer-exit-hook))
          ;; Parent-frame switch recreates pooled frame cleanly
          (let ((other-parent (make-vcf-test-frame
                               :id 99
                               :pixel-w 1200
                               :pixel-h 800
                               :char-w 10
                               :char-h 20
                               :cols 120
                               :rows 40
                               :visible t
                               :live t
                               :root-window parent-win
                               :params '((font . "Monospace-12")))))
            (setf (vcf-test-win-frame mb-win) other-parent)
            (with-temp-buffer
              (setf (vcf-test-win-buffer mb-win) (current-buffer))
              (vertico--setup)
              (should (= make-frame-calls 2))
              (should (eq (frame-parent vertico-child-frame--frame) other-parent))
              (run-hooks 'minibuffer-exit-hook))
            (setf (vcf-test-win-frame mb-win) parent-frame)))
      (vertico-child-frame-mode -1))
    ;; Cleanup deleted pooled frames
    (should-not vertico-child-frame--pool)))

(ert-deftest vcf-test-recursive-minibuffer-stack ()
  (vcf-test-with-mock-gui
    (vertico-child-frame-mode 1)
    (unwind-protect
        (let ((depth 1)
              (buf1 (generate-new-buffer " *mb1*"))
              (buf2 (generate-new-buffer " *mb2*")))
          (unwind-protect
              (cl-letf (((symbol-function 'minibufferp) (lambda (&optional _b _l) t))
                        ((symbol-function 'minibuffer-depth) (lambda () depth)))
                (with-current-buffer buf1
                  (setf (vcf-test-win-buffer mb-win) buf1)
                  (vertico--setup)
                  (let ((f1 vertico-child-frame--frame))
                    (should (= make-frame-calls 1))
                    ;; Enter recursive minibuffer (depth 2)
                    (setq depth 2)
                    (with-current-buffer buf2
                      (setf (vcf-test-win-buffer mb-win) buf2)
                      (vertico--setup)
                      (let ((f2 vertico-child-frame--frame))
                        (should (= make-frame-calls 2))
                        (should-not (eq f1 f2))
                        (should (vcf-test-frame-visible f1))
                        (should (vcf-test-frame-visible f2))
                        ;; Depth 2 is shifted by recursive-offset
                        (should (equal (vcf-test-frame-pos f2)
                                       (cons (+ (car (vcf-test-frame-pos f1)) 24)
                                             (+ (cdr (vcf-test-frame-pos f1)) 24))))
                        ;; Exit depth 2 -> hides f2, re-raises f1
                        (setf (vcf-test-frame-raised f1) nil)
                        (run-hooks 'minibuffer-exit-hook)
                        (should-not (vcf-test-frame-visible f2))
                        (should (vcf-test-frame-visible f1))
                        (should (vcf-test-frame-raised f1))))
                    ;; Exit depth 1
                    (setq depth 1)
                    (setf (vcf-test-win-buffer mb-win) buf1)
                    (run-hooks 'minibuffer-exit-hook)
                    (should-not (vcf-test-frame-visible f1)))))
            (kill-buffer buf1)
            (kill-buffer buf2)))
      (vertico-child-frame-mode -1))))

(ert-deftest vcf-test-parent-delete-and-multiform ()
  (vcf-test-with-mock-gui
    ;; Multiform registration
    (should (memq 'vertico-child-frame-mode vertico-multiform--display-modes))
    (should (fboundp 'vertico-multiform-child-frame))
    (should (eq (lookup-key vertico-multiform-map (kbd "M-C"))
                #'vertico-multiform-child-frame))
    ;; Parent frame deletion cleans up child frames
    (vertico-child-frame-mode 1)
    (unwind-protect
        (cl-letf (((symbol-function 'minibufferp) (lambda (&optional _b _l) t))
                  ((symbol-function 'minibuffer-depth) (lambda () 1)))
          (with-temp-buffer
            (setf (vcf-test-win-buffer mb-win) (current-buffer))
            (vertico--setup)
            (let ((child vertico-child-frame--frame))
              (run-hooks 'minibuffer-exit-hook)
              (should (vcf-test-frame-live child))
              (vertico-child-frame--on-delete-frame parent-frame)
              (should-not (vcf-test-frame-live child))
              (should-not vertico-child-frame--pool))))
      (vertico-child-frame-mode -1))))

(ert-deftest vcf-test-auto-wrap-and-fixed-width ()
  (vcf-test-with-mock-gui
    (let ((vertico-count 5)
          (vertico-child-frame-width 0.6)
          (vertico-child-frame-min-width 50)
          (vertico-child-frame-max-width 120)
          (vertico-child-frame-max-height nil)
          (vertico-child-frame-resize nil))
      ;; 'auto keeps truncate-lines t for short prompts, wraps long input
      ;; without widening the child frame, and expands height for wrapped lines
      (vertico-child-frame-mode 1)
      (unwind-protect
          (cl-letf (((symbol-function 'minibufferp) (lambda (&optional _b _l) t))
                    ((symbol-function 'minibuffer-depth) (lambda () 1)))
            (with-temp-buffer
              (insert "Find file: foo")
              (setf (vcf-test-win-buffer mb-win) (current-buffer))
              (vertico--setup)
              (let ((f vertico-child-frame--frame)
                    (w vertico-child-frame--window))
                (should truncate-lines)
                (should (= (frame-pixel-width f) 720))
                (should (= (frame-pixel-height f) 120))
                ;; Insert long ASCII input (> 80% of 72 cols = 57.6 cols)
                (setf (vcf-test-win-hscroll w) 25)
                (insert (make-string 140 ?a))
                (vertico-child-frame--redisplay w)
                (should-not truncate-lines)
                (should (= (vcf-test-win-hscroll w) 0))
                ;; Width remains strictly locked at 720px; height grows for 3 wrapped lines
                (should (= (frame-pixel-width f) 720))
                (should (= (frame-pixel-height f) 160))
                ;; Deleting back to short input re-enables truncate-lines
                (erase-buffer)
                (insert "short")
                (vertico-child-frame--redisplay w)
                (should truncate-lines)
                (should (= (frame-pixel-height f) 120))
                ;; CJK double-width characters trigger wrapping via string-width
                (erase-buffer)
                (insert (make-string 35 ?中))
                (vertico-child-frame--redisplay w)
                (should-not truncate-lines))
              (run-hooks 'minibuffer-exit-hook))
            ;; Explicit nil (always wrap) and t (always truncate)
            (let ((vertico-child-frame-truncate-lines nil))
              (with-temp-buffer
                (insert "hi")
                (setf (vcf-test-win-buffer mb-win) (current-buffer))
                (vertico--setup)
                (should-not truncate-lines)
                (run-hooks 'minibuffer-exit-hook)))
            (let ((vertico-child-frame-truncate-lines t))
              (with-temp-buffer
                (insert (make-string 140 ?x))
                (setf (vcf-test-win-buffer mb-win) (current-buffer))
                (vertico--setup)
                (should truncate-lines)
                (run-hooks 'minibuffer-exit-hook))))
        (vertico-child-frame-mode -1)))))

(ert-deftest vcf-test-parent-resize-adaptation ()
  (vcf-test-with-mock-gui
    (let ((vertico-child-frame-width 0.6)
          (vertico-child-frame-min-width 20)
          (vertico-child-frame-max-width 120)
          (vertico-child-frame-poshandler 'frame-top-center)
          (vertico-child-frame-top-offset 0.12)
          (vertico-stub--exhibit-called nil))
      (vertico-child-frame-mode 1)
      (unwind-protect
          (cl-letf (((symbol-function 'minibufferp) (lambda (&optional _b _l) t))
                    ((symbol-function 'minibuffer-depth) (lambda () 1)))
            (with-temp-buffer
              (setf (vcf-test-win-buffer mb-win) (current-buffer))
              (vertico--setup)
              (let ((f vertico-child-frame--frame))
                ;; Initial parent 1200x800 -> child text width 720, outer 738 -> pos (231 . 96)
                (should (= (frame-pixel-width f) 720))
                (should (equal (vcf-test-frame-pos f) '(231 . 96)))
                ;; Resize parent app window to 800x600
                (setf (vcf-test-frame-pixel-w parent-frame) 800
                      (vcf-test-frame-pixel-h parent-frame) 600
                      (vcf-test-frame-cols parent-frame) 80
                      (vcf-test-frame-rows parent-frame) 30)
                (setq vertico-stub--exhibit-called nil)
                (vertico-child-frame--on-window-size-change parent-frame)
                (should (= (frame-pixel-width f) 480))
                (should (equal (vcf-test-frame-pos f) '(151 . 72)))
                (should vertico-stub--exhibit-called)
                ;; External drift on child frame itself is snapped back to 480px
                (setf (vcf-test-frame-pixel-w f) 999)
                (vertico-child-frame--on-window-size-change f)
                (should (= (frame-pixel-width f) 480)))
              (run-hooks 'minibuffer-exit-hook)))
        (vertico-child-frame-mode -1)))))

(ert-deftest vcf-test-wm-position-drift-recovery ()
  (vcf-test-with-mock-gui
    ;; Default frame parameters advertise user-position & user-size for WMs.
    (should (eq (alist-get 'user-position vertico-child-frame--default-parameters) t))
    (should (eq (alist-get 'user-size vertico-child-frame--default-parameters) t))
    (let ((vertico-child-frame-width 0.6)
          (vertico-child-frame-margin '(16 . 16))
          (vertico-child-frame-poshandler 'frame-top-center)
          (vertico-child-frame-top-offset nil))
      ;; Simulate a WM/GTK centering the frame when make-frame-visible runs.
      (let ((orig-visible (symbol-function 'make-frame-visible)))
        (cl-letf (((symbol-function 'make-frame-visible)
                   (lambda (&optional f)
                     (funcall orig-visible f)
                     (when (vcf-test-frame-p f)
                       (setf (vcf-test-frame-pos f) '(231 . 289))))))
          (vertico-child-frame-mode 1)
          (unwind-protect
              (cl-letf (((symbol-function 'minibufferp) (lambda (&optional _b _l) t))
                        ((symbol-function 'minibuffer-depth) (lambda () 1)))
                (with-temp-buffer
                  (setf (vcf-test-win-buffer mb-win) (current-buffer))
                  (vertico--setup)
                  ;; Post-map verification snaps it back from (231 . 289) to (231 . 16)
                  (should (equal (frame-position vertico-child-frame--frame)
                                 '(231 . 16)))
                  (should (equal (frame-parameter vertico-child-frame--frame 'left)
                                 '(+ 231)))
                  (should (equal (frame-parameter vertico-child-frame--frame 'top)
                                 '(+ 16)))
                  (run-hooks 'minibuffer-exit-hook)))
            (vertico-child-frame-mode -1)))))))

(ert-deftest vcf-test-posframe-parity-and-size-function ()
  (vcf-test-with-mock-gui
    ;; With posframe-style overrides (margin '(0 . 0), resize nil -> 10 lines,
    ;; width nil -> golden-ratio 742px, bottom-respect-mode-line t),
    ;; top/bottom corners align flush / clear mode-line & minibuffer.
    (setf (vcf-test-win-mode-line-h parent-win) 22)
    (let ((vertico-count 10)
          (vertico-child-frame-resize nil))
      ;; Frame top-center flush at y=0, width = 742 -> x = 220
      (let ((vertico-child-frame-poshandler 'frame-top-center))
        (should (equal (vertico-child-frame--compute-geometry parent-frame 10 1)
                       '(220 0 742 220))))
      ;; Frame top-left-corner flush at (0 . 0)
      (let ((vertico-child-frame-poshandler 'frame-top-left-corner))
        (should (equal (vertico-child-frame--compute-geometry parent-frame 10 1)
                       '(0 0 742 220))))
      ;; Frame bottom-center clears minibuffer (20) + mode-line (22) = 42px
      ;; outer-h = 222 -> y = 800 - 222 - 42 = 536
      (let ((vertico-child-frame-poshandler 'frame-bottom-center))
        (should (equal (vertico-child-frame--compute-geometry parent-frame 10 1)
                       '(220 536 742 220))))
      ;; Frame bottom-right-corner clears mode-line + minibuffer and sits flush right
      (let ((vertico-child-frame-poshandler 'frame-bottom-right-corner))
        (should (equal (vertico-child-frame--compute-geometry parent-frame 10 1)
                       '(440 536 742 220))))
      ;; Window bottom-center clears that window's mode-line (22px)
      (setf (vcf-test-win-edges parent-win) '(100 50 900 650))
      (let ((vertico-child-frame-poshandler 'window-bottom-center))
        (should (equal (vertico-child-frame--compute-geometry parent-frame 10 1)
                       '(120 406 742 220))))
      ;; Narrow other-window caps auto-width so it fits inside that split
      (let ((other-win (make-vcf-test-win
                        :frame parent-frame
                        :width 50
                        :height 30
                        :pixel-h 600
                        :mode-line-h 24
                        :edges '(600 100 1100 700))))
        (setf (vcf-test-win-edges parent-win) '(0 0 600 800))
        (setq mock-window-list (list parent-win other-win))
        (let ((vertico-child-frame-poshandler 'other-window-bottom-center))
          ;; other-win width = 500, chrome-w = 18 -> text-w = 482, outer-w = 500
          ;; y = 700 - 222 (outer-h) - 24 (mode-line) = 454
          (should (equal (vertico-child-frame--compute-geometry parent-frame 10 1)
                         '(600 454 482 220)))))
      ;; Custom vertico-child-frame-size-function plist overrides sizing options
      (let ((vertico-child-frame-poshandler 'frame-center)
            (vertico-child-frame-size-function
             (lambda ()
               (list :width 60
                     :height 8
                     :min-width 40
                     :max-width 90
                     :min-height 4
                     :max-height 12))))
        ;; width=600 (outer=618), height=160 (outer=162) -> (291, 319)
        (should (equal (vertico-child-frame--compute-geometry parent-frame 20 1)
                       '(291 319 600 160)))))))

(ert-deftest vcf-test-content-adaptive-width ()
  "Test `vertico-buffer-frame' golden-ratio defaults and `string-pixel-width' auto-width."
  (vcf-test-with-mock-gui
    ;; Verify vertico-buffer-frame parity defaults
    (should (eq (default-value 'vertico-child-frame-poshandler)
                #'vertico-child-frame-poshandler-frame-center))
    (should (eq (default-value 'vertico-child-frame-resize) 'golden-ratio))
    (should (= (default-value 'vertico-child-frame-golden-ratio-scale) 1.0))
    (let* ((vertico-child-frame-width nil)
           (vertico-child-frame-min-width nil)
           (vertico-child-frame-max-width nil)
           (vertico-child-frame-height nil)
           (vertico-child-frame-resize 'golden-ratio)
           (vertico-child-frame-width-resize 'grow-only)
           (vertico-child-frame-golden-ratio-scale 1.0)
           (vertico-child-frame-margin '(0 . 0))
           (vertico-child-frame-poshandler #'vertico-child-frame-poshandler-frame-center)
           (vertico-child-frame-border-width 1)
           (vertico-child-frame-left-fringe 8)
           (vertico-child-frame-right-fringe 8)
           (vertico-child-frame-min-parent-width 40)
           (vertico-child-frame-recursive-offset '(24 . 24))
           (vertico-child-frame-offset '(0 . 0))
           (vertico-child-frame-truncate-lines 'auto)
           (vertico-count 10)
           (orig-make-frame (symbol-function 'make-frame))
           (created-frames nil))
      ;; Golden-ratio geometry on 1200x800 and 1920x1080
      (should (equal (vertico-child-frame--compute-geometry parent-frame 10 1)
                     '(220 170 742 458)))
      (let ((wide-parent (make-vcf-test-frame
                          :id 50
                          :pixel-w 1920
                          :pixel-h 1080
                          :char-w 10
                          :char-h 20
                          :cols 192
                          :rows 54
                          :visible t
                          :live t
                          :root-window parent-win)))
        (should (equal (vertico-child-frame--compute-geometry wide-parent 10 1)
                       '(411 206 1080 667))))
      (let ((vertico-child-frame-golden-ratio-scale 1.7))
        (should (equal (vertico-child-frame--compute-geometry parent-frame 10 1)
                       '(0 28 1182 742))))
      ;; Full session setup: non-zero initial frame, synced vertico-count,
      ;; empty candidates do not collapse to a tiny square, teardown restores state.
      (cl-letf (((symbol-function 'minibufferp) (lambda (&optional _b _l) t))
                ((symbol-function 'minibuffer-depth) (lambda () 1))
                ((symbol-function 'make-frame)
                 (lambda (&optional params)
                   (let ((f (funcall orig-make-frame params)))
                     (push f created-frames)
                     f))))
        (vertico-child-frame-mode 1)
        (unwind-protect
            (with-temp-buffer
              (insert "Node: ")
              (setf (vcf-test-win-buffer mb-win) (current-buffer))
              (vertico--setup)
              (let ((f vertico-child-frame--frame)
                    (w vertico-child-frame--window))
                (should (= (length created-frames) 1))
                ;; Initial frame created with non-zero golden-ratio cols/rows
                (should (>= (alist-get 'width (vcf-test-frame-params f)) 20))
                (should (>= (alist-get 'height (vcf-test-frame-params f)) 10))
                ;; vertico-count auto-fitted to golden-ratio height (458/20 - 2 = 20)
                (should (= vertico-count 20))
                ;; Simulate empty candidate state during early redisplay
                (overlay-put vertico--candidates-ov 'before-string #(" " 0 1 (cursor t)))
                (overlay-put vertico--count-ov 'before-string "0/0 ")
                (setq vertico--candidates nil)
                (vertico-child-frame--redisplay w)
                (should (= (frame-pixel-width f) 742))
                (should (= (frame-pixel-height f) 458))
                (should (equal (frame-position f) '(220 . 170))))
              (run-hooks 'minibuffer-exit-hook)
              ;; Teardown restores vertico-count and clears overlay strings
              (should (= vertico-count 10))
              (should-not (overlay-get vertico--candidates-ov 'before-string))
              (should-not (overlay-get vertico--count-ov 'before-string)))
          (vertico-child-frame-mode -1)))
      ;; Content-adaptive width via safe `string-pixel-width'
      (setq vcf-test--string-pixel-width-fn
            (lambda (str)
              (* 10 (apply #'max 0 (mapcar #'string-width
                                           (split-string str "\n"))))))
      (let* ((vertico--candidates-ov (make-overlay 1 1))
             (vertico--candidates nil)
             (vertico--scroll 0)
             (child-win (make-vcf-test-win :width 59 :height 22 :pixel-h 440))
             (child-frame (make-vcf-test-frame
                           :id 60
                           :parent parent-frame
                           :root-window child-win
                           :cols 59
                           :rows 22
                           :pixel-w 590
                           :pixel-h 440
                           :char-w 10
                           :char-h 20
                           :live t))
             (buf (generate-new-buffer " *vcf-adaptive-test*")))
        (setf (vcf-test-win-frame child-win) child-frame)
        (unwind-protect
            (with-current-buffer buf
              (insert "1/2053 Node: ")
              (setq vertico-child-frame--active t
                    vertico-child-frame--frame child-frame
                    vertico-child-frame--window child-win
                    vertico-child-frame--parent parent-frame
                    vertico-child-frame--depth 1
                    vertico-child-frame--max-height-seen 0
                    vertico-child-frame--max-width-seen 0)
              (push buf vertico-child-frame--active-buffers)
              (setf (vcf-test-win-buffer child-win) buf)
              ;; 950x800 frame -> golden-w = 587
              (setf (vcf-test-frame-pixel-w parent-frame) 950
                    (vcf-test-frame-cols parent-frame) 95
                    (vcf-test-frame-pixel-h parent-frame) 800
                    (vcf-test-frame-rows parent-frame) 40
                    (vcf-test-win-edges parent-win) '(0 0 950 800))
              ;; Empty overlay (" ") stays at golden-w = 587
              (overlay-put vertico--candidates-ov 'before-string " ")
              (should (= (nth 2 (vertico-child-frame--compute-geometry parent-frame 10 1))
                         587))
              ;; Wide candidate (80 chars = 800px) in `vertico--candidates' even when
              ;; `before-string' is clipped (58 chars = 580px) grows up to 90% max (838px)
              (overlay-put vertico--candidates-ov 'before-string
                           (concat " \n" (make-string 58 ?a)))
              (setq vertico--candidates (list (make-string 80 ?a)))
              (should (= (nth 2 (vertico-child-frame--compute-geometry parent-frame 10 1))
                         838))
              ;; Test fresh session with 70-char candidate (700 + 60 = 760 < 838)
              (setq vertico-child-frame--max-width-seen 0)
              (overlay-put vertico--candidates-ov 'before-string
                           (concat " \n" (make-string 50 ?b)))
              (setq vertico--candidates (list (make-string 70 ?b)))
              (should (= (nth 2 (vertico-child-frame--compute-geometry parent-frame 10 1))
                         760))
              ;; Narrower candidates (40 chars = 400px) keep 760 under `grow-only'
              (overlay-put vertico--candidates-ov 'before-string
                           (concat " \n" (make-string 40 ?c)))
              (setq vertico--candidates (list (make-string 40 ?c)))
              (should (= (nth 2 (vertico-child-frame--compute-geometry parent-frame 10 1))
                         760))
              ;; Under `t' mode, shrinks to 400 + 60 = 460 and respects 30-col (300px) floor
              (let ((vertico-child-frame-width-resize t))
                (should (= (nth 2 (vertico-child-frame--compute-geometry parent-frame 10 1))
                           460))
                (overlay-put vertico--candidates-ov 'before-string
                             (concat " \n" (make-string 10 ?d)))
                (setq vertico--candidates (list (make-string 10 ?d)))
                (should (= (nth 2 (vertico-child-frame--compute-geometry parent-frame 10 1))
                           300)))
              ;; `vertico-child-frame-width-resize' nil stays at golden-w = 587
              (let ((vertico-child-frame-width-resize nil))
                (setq vertico--candidates (list (make-string 70 ?e)))
                (should (= (nth 2 (vertico-child-frame--compute-geometry parent-frame 10 1))
                           587)))
              ;; Explicit width (55 cols = 550px) overrides content measurement
              (let ((vertico-child-frame-width 55))
                (should (= (nth 2 (vertico-child-frame--compute-geometry parent-frame 10 1))
                           550)))
              ;; `other-window-*' caps wide content (800px) to split window width (482px)
              (let ((other-win (make-vcf-test-win
                                :frame parent-frame
                                :width 50
                                :height 30
                                :pixel-h 600
                                :mode-line-h 24
                                :edges '(1420 0 1920 1000)))
                    (vertico-child-frame-poshandler 'other-window-center)
                    (vertico-child-frame-width-resize t))
                (setf (vcf-test-frame-pixel-w parent-frame) 1920
                      (vcf-test-frame-cols parent-frame) 192
                      (vcf-test-win-edges parent-win) '(0 0 1420 1000))
                (setq mock-window-list (list parent-win other-win))
                (overlay-put vertico--candidates-ov 'before-string
                             (concat " \n" (make-string 80 ?f)))
                (setq vertico--candidates (list (make-string 80 ?f)))
                (should (= (nth 2 (vertico-child-frame--compute-geometry parent-frame 10 1))
                           482))
                (overlay-put vertico--candidates-ov 'before-string
                             (concat " \n" (make-string 30 ?g)))
                (setq vertico--candidates (list (make-string 30 ?g)))
                (should (= (nth 2 (vertico-child-frame--compute-geometry parent-frame 10 1))
                           360)))
              ;; Parent resize resets `--max-width-seen' so widening expands child frame
              (setq mock-window-list (list parent-win)
                    vertico-child-frame--max-width-seen 0)
              (overlay-put vertico--candidates-ov 'before-string
                           (concat " \n" (make-string 70 ?h)))
              (setq vertico--candidates (list (make-string 70 ?h)))
              (setf (vcf-test-frame-pixel-w parent-frame) 800
                    (vcf-test-frame-cols parent-frame) 80
                    (vcf-test-win-edges parent-win) '(0 0 800 800))
              ;; floor(782 * 0.9) = 703
              (should (= (nth 2 (vertico-child-frame--compute-geometry parent-frame 10 1))
                         703))
              (setf (vcf-test-frame-pixel-w parent-frame) 1200
                    (vcf-test-frame-cols parent-frame) 120
                    (vcf-test-win-edges parent-win) '(0 0 1200 800))
              (vertico-child-frame--on-window-size-change parent-frame)
              (should (= (nth 2 (vertico-child-frame--compute-geometry parent-frame 10 1))
                         760)))
          (setq vertico-child-frame--active-buffers
                (delq buf vertico-child-frame--active-buffers))
          (delete-overlay vertico--candidates-ov)
          (when (buffer-live-p buf) (kill-buffer buf)))))))

(ert-deftest vcf-test-performance-caching-and-warmup ()
  "Test appearance caching, width memoization, warmup, and multiform pooling."
  (vcf-test-with-mock-gui
    ;; 1. Pre-warm creates 1 hidden depth-1 pooled frame; first setup reuses it
    (cl-letf (((symbol-function 'selected-frame) (lambda () parent-frame))
              ((symbol-function 'minibufferp) (lambda (&optional _b _l) t))
              ((symbol-function 'minibuffer-depth) (lambda () 1)))
      (should (vertico-child-frame-warmup))
      (should (= make-frame-calls 1))
      (should (= (length vertico-child-frame--pool) 1))
      (should-not (vcf-test-frame-visible (cdar vertico-child-frame--pool)))
      (vertico-child-frame-mode 1)
      (unwind-protect
          (progn
            (with-temp-buffer
              (setf (vcf-test-win-buffer mb-win) (current-buffer))
              (vertico--setup)
              (should (= make-frame-calls 1))
              (should (eq vertico-child-frame--frame
                          (cdar vertico-child-frame--pool)))
              (run-hooks 'minibuffer-exit-hook))
            ;; 2. Session 2 with unchanged appearance does 0 modify-frame-parameters
            ;; and 0 set-face-background calls, and hits geometry cache too.
            (let ((before-m modify-params-calls)
                  (before-f set-face-calls))
              (with-temp-buffer
                (setf (vcf-test-win-buffer mb-win) (current-buffer))
                (vertico--setup)
                (should (= make-frame-calls 1))
                (should (= modify-params-calls before-m))
                (should (= set-face-calls before-f))
                ;; Direct sync-appearance with unchanged settings is a full no-op
                (vertico-child-frame--sync-appearance
                 vertico-child-frame--frame parent-frame)
                (should (= modify-params-calls before-m))
                (should (= set-face-calls before-f))
                ;; Changing only alpha updates alpha-background without re-sending font
                (let ((sent-alists nil)
                      (orig-mod (symbol-function 'modify-frame-parameters)))
                  (cl-letf (((symbol-function 'modify-frame-parameters)
                             (lambda (f alist)
                               (push alist sent-alists)
                               (funcall orig-mod f alist))))
                    (let ((vertico-child-frame-alpha 85))
                      (vertico-child-frame--sync-appearance
                       vertico-child-frame--frame parent-frame)))
                  (should (= (length sent-alists) 1))
                  (should (equal (assq 'alpha-background (car sent-alists))
                                 '(alpha-background . 85)))
                  (should-not (assq 'font (car sent-alists))))
                (run-hooks 'minibuffer-exit-hook))))
        (vertico-child-frame-mode -1)))
    ;; 3. Width memoization + window-filtered redisplay + grow-only cap short-circuit
    (let ((spw-calls 0)
          (vertico-child-frame-width nil)
          (vertico-child-frame-width-resize 'grow-only)
          (vertico-child-frame-resize 'golden-ratio)
          (vertico-child-frame-margin '(0 . 0)))
      (setq vcf-test--string-pixel-width-fn
            (lambda (str)
              (cl-incf spw-calls)
              (* 10 (apply #'max 0 (mapcar #'string-width
                                           (split-string str "\n"))))))
      (let* ((vertico--candidates-ov (make-overlay 1 1))
             (vertico--candidates (list (make-string 76 ?a)))
             (vertico--scroll 0)
             (resize-invocations 0)
             (buf (generate-new-buffer " *vcf-cache-test*"))
             (child-win (make-vcf-test-win :width 74 :height 22 :pixel-h 458))
             (child-frame (make-vcf-test-frame
                           :id 70
                           :parent parent-frame
                           :root-window child-win
                           :cols 74
                           :rows 22
                           :pixel-w 742
                           :pixel-h 458
                           :char-w 10
                           :char-h 20
                           :live t)))
        (setf (vcf-test-win-frame child-win) child-frame)
        (unwind-protect
            (with-current-buffer buf
              (insert "Find: ")
              (setq vertico-child-frame--active t
                    vertico-child-frame--frame child-frame
                    vertico-child-frame--window child-win
                    vertico-child-frame--parent parent-frame
                    vertico-child-frame--depth 1
                    vertico-child-frame--max-width-seen 0
                    vertico-child-frame--content-width-cache nil)
              (setf (vcf-test-win-buffer child-win) buf)
              (setf (vcf-test-win-buffer mb-win) buf)
              ;; Redisplay called on mb-win skips resize completely
              (cl-letf (((symbol-function 'vertico-child-frame--resize)
                         (lambda (_h) (cl-incf resize-invocations))))
                (vertico-child-frame--redisplay mb-win)
                (should (= resize-invocations 0))
                (vertico-child-frame--redisplay child-win)
                (should (= resize-invocations 1)))
              ;; Repeated compute-geometry calls with same rendered + candidates hit cache
              (overlay-put vertico--candidates-ov 'before-string
                           (concat " \n" (make-string 50 ?a)))
              (setq spw-calls 0)
              (should (= (nth 2 (vertico-child-frame--compute-geometry parent-frame 10 1))
                         820))
              (should (= spw-calls 2))
              (vertico-child-frame--compute-geometry parent-frame 10 1)
              (vertico-child-frame--compute-geometry parent-frame 10 1)
              (should (= spw-calls 2))
              ;; Once grow-only hits auto-upper (floor(1182*0.9) = 1063),
              ;; new candidates skip string-pixel-width altogether
              (overlay-put vertico--candidates-ov 'before-string
                           (concat " \n" (make-string 120 ?x)))
              (should (= (nth 2 (vertico-child-frame--compute-geometry parent-frame 10 1))
                         1063))
              (setq spw-calls 0)
              (overlay-put vertico--candidates-ov 'before-string
                           (concat " \n" (make-string 40 ?y)))
              (setq vertico--candidates (list (make-string 40 ?y)))
              (should (= (nth 2 (vertico-child-frame--compute-geometry parent-frame 10 1))
                         1063))
              (should (= spw-calls 0)))
          (delete-overlay vertico--candidates-ov)
          (when (buffer-live-p buf) (kill-buffer buf)))))
    ;; 4. `vertico-multiform-mode' keeps pooled child frame across sessions
    (let ((vertico-multiform-mode t)
          (before-make make-frame-calls))
      (cl-letf (((symbol-function 'minibufferp) (lambda (&optional _b _l) t))
                ((symbol-function 'minibuffer-depth) (lambda () 1)))
        (vertico-child-frame-mode 1)
        (with-temp-buffer
          (setf (vcf-test-win-buffer mb-win) (current-buffer))
          (vertico--setup)
          (run-hooks 'minibuffer-exit-hook))
        (vertico-child-frame-mode -1)
        ;; Pool retained while multiform mode is active
        (should (= (length vertico-child-frame--pool) 1))
        (should (vcf-test-frame-live (cdar vertico-child-frame--pool)))
        (should-not (vcf-test-frame-visible (cdar vertico-child-frame--pool)))
        ;; Next multiform session reuses the parked frame without make-frame
        (let ((calls-after-first make-frame-calls))
          (vertico-child-frame-mode 1)
          (with-temp-buffer
            (setf (vcf-test-win-buffer mb-win) (current-buffer))
            (vertico--setup)
            (should (= make-frame-calls calls-after-first))
            (run-hooks 'minibuffer-exit-hook))
          (vertico-child-frame-mode -1)
          (should (>= calls-after-first before-make))))
      ;; Without multiform mode, disabling deletes pool as usual
      (setq vertico-multiform-mode nil)
      (vertico-child-frame-mode -1)
      (should-not vertico-child-frame--pool))))

(ert-deftest vcf-test-initial-exhibit-recovery ()
  "Verify initial exhibit recovery runs only when `vertico--input' stays `t'."
  (vcf-test-with-mock-gui
    (vertico-child-frame-mode 1)
    (unwind-protect
        (cl-letf (((symbol-function 'minibufferp) (lambda (&optional _b _l) t))
                  ((symbol-function 'minibuffer-depth) (lambda () 1)))
          ;; 1. When `vertico--input' is still `t' (aborted initial exhibit),
          ;; recovery calls `vertico--update' non-interruptibly and `vertico--exhibit'.
          (with-temp-buffer
            (let ((buf (current-buffer))
                  (timer nil))
              (unwind-protect
                  (progn
                    (setf (vcf-test-win-buffer mb-win) buf)
                    (vertico--setup)
                    (setq timer vertico-child-frame--init-timer)
                    (should (timerp timer))
                    (should (memq timer timer-idle-list))
                    (setq vertico-stub--update-called nil
                          vertico-stub--exhibit-called nil)
                    (vertico-child-frame--ensure-initial-exhibit buf)
                    (should (eq vertico-stub--update-called 'sync))
                    (should vertico-stub--exhibit-called)
                    (should-not vertico-child-frame--init-timer)
                    ;; 2. When `vertico--input' is already computed as a cons cell,
                    ;; recovery is a no-op.
                    (setq vertico--input '("foo" . 3)
                          vertico-stub--update-called nil
                          vertico-stub--exhibit-called nil)
                    (vertico-child-frame--ensure-initial-exhibit buf)
                    (should-not vertico-stub--update-called)
                    (should-not vertico-stub--exhibit-called)
                    (should-not vertico-child-frame--init-timer))
                (when (timerp timer)
                  (cancel-timer timer))
                (run-hooks 'minibuffer-exit-hook))))
          ;; 3. Teardown cancels the scheduled idle timer and clears it;
          ;; running recovery afterward or on a killed buffer is a no-op.
          (let ((dead-buf (generate-new-buffer " *vcf-init-dead*"))
                (timer nil))
            (unwind-protect
                (with-current-buffer dead-buf
                  (setf (vcf-test-win-buffer mb-win) dead-buf)
                  (vertico--setup)
                  (setq timer vertico-child-frame--init-timer)
                  (should (timerp timer))
                  (should (memq timer timer-idle-list))
                  (run-hooks 'minibuffer-exit-hook)
                  (should-not vertico-child-frame--init-timer)
                  (should-not (memq timer timer-idle-list))
                  (setq vertico-stub--update-called nil
                        vertico-stub--exhibit-called nil)
                  (vertico-child-frame--ensure-initial-exhibit dead-buf)
                  (should-not vertico-stub--update-called)
                  (should-not vertico-stub--exhibit-called))
              (when (timerp timer)
                (cancel-timer timer))
              (when (buffer-live-p dead-buf)
                (kill-buffer dead-buf)))
            (setq vertico-stub--update-called nil
                  vertico-stub--exhibit-called nil)
            (vertico-child-frame--ensure-initial-exhibit dead-buf)
            (should-not vertico-stub--update-called)
            (should-not vertico-stub--exhibit-called)))
      (vertico-child-frame-mode -1))))

(provide 'vertico-child-frame-test)
;;; vertico-child-frame-test.el ends here
