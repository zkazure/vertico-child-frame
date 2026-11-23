EMACS ?= emacs
VERTICO_DIR ?=

ifeq ($(strip $(VERTICO_DIR)),)
LOAD_FLAGS = -L . -L test/stubs
else
LOAD_FLAGS = -L . -L $(VERTICO_DIR)
endif

BATCH = $(EMACS) -Q --batch $(LOAD_FLAGS)

.PHONY: all compile lint test check clean

all: check

compile:
	$(BATCH) --eval "(setq byte-compile-error-on-warn t)" -f batch-byte-compile vertico-child-frame.el

lint:
	$(BATCH) --eval "(progn \
	  (require 'checkdoc) \
	  (let ((checkdoc-diagnostic-buffer \"*checkdoc-warnings*\")) \
	    (checkdoc-file \"vertico-child-frame.el\") \
	    (when-let* ((buf (get-buffer checkdoc-diagnostic-buffer))) \
	      (with-current-buffer buf \
	        (when (> (buffer-size) 0) \
	          (princ (buffer-string)) \
	          (error \"checkdoc reported warnings\"))))) \
	  (when (require 'package-lint nil t) \
	    (let ((issues (package-lint-buffer (find-file-noselect \"vertico-child-frame.el\")))) \
	      (when issues \
	        (dolist (issue issues) \
	          (princ (format \"%S\n\" issue))) \
	        (error \"package-lint reported issues\")))))"

test:
	$(BATCH) -l test/vertico-child-frame-test.el -f ert-run-tests-batch-and-exit

check: compile lint test

clean:
	rm -f *.elc test/*.elc test/stubs/*.elc
