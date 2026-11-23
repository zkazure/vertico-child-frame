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
  frame buffer point dedicated width height pixel-h vscroll edges inside-edges params)

(defmacro vcf-test-with-mock-gui (&rest body)
  "Evaluate BODY with mocked GUI frames, windows, and display primitives."
  (declare (indent 0) (debug t))
  `(let* ((native-comp-enable-subr-trampolines nil)
          (next-id 1)
          (vcf-test--point-xy '(150 . 100))
          (vcf-test--point-lh 20)
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
          (all-frames (list parent-frame))
          (orig-display-graphic-p (symbol-function 'display-graphic-p))
          (orig-frame-live-p (symbol-function 'frame-live-p))
          (orig-frame-parent (symbol-function 'frame-parent))
          (orig-frame-root-window (symbol-function 'frame-root-window))
          (orig-frame-pixel-width (symbol-function 'frame-pixel-width))
          (orig-frame-pixel-height (symbol-function 'frame-pixel-height))
          (orig-frame-char-width (symbol-function 'frame-char-width))
          (orig-frame-char-height (symbol-function 'frame-char-height))
          (orig-frame-width (symbol-function 'frame-width))
          (orig-frame-height (symbol-function 'frame-height))
          (orig-frame-parameter (symbol-function 'frame-parameter))
          (orig-set-frame-parameter (symbol-function 'set-frame-parameter))
          (orig-modify-frame-parameters (symbol-function 'modify-frame-parameters))
          (orig-window-live-p (symbol-function 'window-live-p))
          (orig-window-frame (symbol-function 'window-frame))
          (orig-window-buffer (symbol-function 'window-buffer))
          (orig-set-window-buffer (symbol-function 'set-window-buffer))
          (orig-set-window-dedicated-p (symbol-function 'set-window-dedicated-p))
          (orig-window-dedicated-p (symbol-function 'window-dedicated-p))
          (orig-set-window-parameter (symbol-function 'set-window-parameter))
          (orig-set-window-fringes (symbol-function 'set-window-fringes))
          (orig-set-window-point (symbol-function 'set-window-point))
          (orig-set-window-vscroll (symbol-function 'set-window-vscroll))
          (orig-window-width (symbol-function 'window-width))
          (orig-window-pixel-height (symbol-function 'window-pixel-height))
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
                 (dolist (pair alist)
                   (setf (alist-get (car pair) (vcf-test-frame-params f))
                         (cdr pair)))
               (funcall orig-modify-frame-parameters f alist))))
          ((symbol-function 'make-frame)
           (lambda (&optional params)
             (cl-incf make-frame-calls)
             (let* ((cw 10)
                    (ch 20)
                    (w (make-vcf-test-win :width 72 :height 11 :pixel-h 220))
                    (f (make-vcf-test-frame
                        :id next-id
                        :parent (alist-get 'parent-frame params)
                        :root-window w
                        :pixel-w 720
                        :pixel-h 220
                        :char-w cw
                        :char-h ch
                        :cols 72
                        :rows 11
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
                 (setf (alist-get (intern (format "face-%s" face))
                                  (vcf-test-frame-params frame))
                       color)
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
      ;; Clamped to parent width minus margins (1200 - 32 = 1168)
      (let ((vertico-child-frame-width 200)
            (vertico-child-frame-max-width nil))
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
    (let ((vertico-child-frame-top-offset 0.12)
          (vertico-child-frame-bottom-offset 0.06)
          (vertico-child-frame-margin '(16 . 16))
          (vertico-child-frame-offset '(0 . 0))
          (vertico-child-frame-recursive-offset '(24 . 24)))
      ;; Frame-relative poshandlers (+ legacy aliases)
      (should (equal (vertico-child-frame-poshandler-frame-top-center parent-frame 720 220)
                     '(240 . 96)))
      (should (equal (vertico-child-frame-poshandler-top-center parent-frame 720 220)
                     '(240 . 96)))
      (should (equal (vertico-child-frame-poshandler-frame-center parent-frame 720 220)
                     '(240 . 290)))
      (should (equal (vertico-child-frame-poshandler-center parent-frame 720 220)
                     '(240 . 290)))
      (should (equal (vertico-child-frame-poshandler-frame-bottom-center parent-frame 720 220)
                     '(240 . 532)))
      (should (equal (vertico-child-frame-poshandler-bottom-center parent-frame 720 220)
                     '(240 . 532)))
      (should (equal (vertico-child-frame-poshandler-frame-top-left-corner parent-frame 400 200)
                     '(16 . 16)))
      (should (equal (vertico-child-frame-poshandler-frame-top-right-corner parent-frame 400 200)
                     '(784 . 16)))
      (should (equal (vertico-child-frame-poshandler-frame-bottom-left-corner parent-frame 400 200)
                     '(16 . 584)))
      (should (equal (vertico-child-frame-poshandler-frame-bottom-right-corner parent-frame 400 200)
                     '(784 . 584)))
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
                     '(300 . 122)))
      (should (equal (vertico-child-frame-poshandler-window-top-left-corner parent-frame 400 200)
                     '(100 . 50)))
      (should (equal (vertico-child-frame-poshandler-window-top-right-corner parent-frame 400 200)
                     '(500 . 50)))
      (should (equal (vertico-child-frame-poshandler-window-bottom-center parent-frame 400 200)
                     '(300 . 450)))
      (should (equal (vertico-child-frame-poshandler-window-bottom-left-corner parent-frame 400 200)
                     '(100 . 450)))
      (should (equal (vertico-child-frame-poshandler-window-bottom-right-corner parent-frame 400 200)
                     '(500 . 450)))
      ;; Recursive depth offset
      (let ((vertico-child-frame-poshandler #'vertico-child-frame-poshandler-frame-top-center)
            (vertico-child-frame-width 0.6)
            (vertico-child-frame-resize nil)
            (vertico-count 10))
        (should (equal (vertico-child-frame--compute-geometry parent-frame 10 1)
                       '(240 96 720 220)))
        (should (equal (vertico-child-frame--compute-geometry parent-frame 10 2)
                       '(264 120 720 220))))
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
      ;; Short symbolic poshandler + global pixel offset
      (let ((vertico-child-frame-poshandler 'frame-bottom-right-corner)
            (vertico-child-frame-width 40)
            (vertico-child-frame-min-width nil)
            (vertico-child-frame-resize nil)
            (vertico-count 10)
            (vertico-child-frame-offset '(-10 . -20)))
        (should (equal (vertico-child-frame--compute-geometry parent-frame 10 1)
                       '(774 544 400 220))))
      ;; Interactive poshandler switcher updates live session immediately
      (vertico-child-frame-mode 1)
      (unwind-protect
          (cl-letf (((symbol-function 'minibufferp) (lambda (&optional _b _l) t))
                    ((symbol-function 'minibuffer-depth) (lambda () 1)))
            (with-temp-buffer
              (setf (vcf-test-win-buffer mb-win) (current-buffer))
              (let ((vertico-child-frame-poshandler 'frame-top-center))
                (vertico--setup)
                (vertico-child-frame-set-poshandler
                 #'vertico-child-frame-poshandler-frame-bottom-right-corner)
                (should (eq vertico-child-frame-poshandler
                            #'vertico-child-frame-poshandler-frame-bottom-right-corner))
                (should (equal (vcf-test-frame-pos vertico-child-frame--frame)
                               '(464 . 564)))
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
            ;; Window width advice reports child-frame width (72 vs 120)
            (should (= (vertico--window-width) 72))
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

(provide 'vertico-child-frame-test)
;;; vertico-child-frame-test.el ends here
