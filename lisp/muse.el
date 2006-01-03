;;; muse.el --- an authoring and publishing tool for Emacs

;; Copyright (C) 2004, 2005 Free Software Foundation, Inc.

;; Emacs Lisp Archive Entry
;; Filename: muse.el
;; Version: 3.02.5
;; Date: Sat 17-Dec-2005
;; Keywords: hypermedia
;; Author: John Wiegley (johnw AT gnu DOT org)
;; Maintainer: Michael Olson (mwolson AT gnu DOT org)
;; Description: An authoring and publishing tool for Emacs
;; URL: http://www.mwolson.org/projects/MuseMode.html
;; Compatibility: Emacs21 XEmacs21 Emacs22

;; This file is not part of GNU Emacs.

;; This is free software; you can redistribute it and/or modify it under
;; the terms of the GNU General Public License as published by the Free
;; Software Foundation; either version 2, or (at your option) any later
;; version.
;;
;; This is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
;; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
;; for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; Muse is a tool for easily authoring and publishing documents.  It
;; allows for rapid prototyping of hyperlinked text, which may then be
;; exported to multiple output formats -- such as HTML, LaTeX,
;; Texinfo, etc.

;; The markup rules used by Muse are intended to be very friendly to
;; people familiar with Emacs.  See the included manual for more
;; information.

;;; Contributors:

;;; Code:

(defvar muse-version "3.02.5"
  "The version of Muse currently loaded")

(defun muse-version (&optional insert)
  "Display the version of Muse that is currently loaded.
If INSERT is non-nil, insert the text instead of displaying it."
  (interactive "P")
  (if insert
      (insert muse-version)
    (message muse-version)))

(defgroup muse nil
  "Options controlling the behavior of Muse.
The markup used by Muse is intended to be very friendly to people
familiar with Emacs."
  :group 'hypermedia)

(defvar muse-under-windows-p (memq system-type '(ms-dos windows-nt)))

(require 'wid-edit)
(require 'muse-regexps)

;; Default file extension

(eval-when-compile
  (defvar muse-ignored-extensions))

(defvar muse-ignored-extensions-regexp nil
  "A regexp of extensions to omit from the ending of a Muse page name.
This is autogenerated from `muse-ignored-extensions'.")

(defun muse-update-file-extension (sym val)
  "Update the value of `muse-file-extension'."
  (when (and (boundp sym) (symbol-value sym))
    ;; remove old auto-mode-alist association
    (setq auto-mode-alist
          (delete (cons (concat "\\." (symbol-value sym) "\\'")
                        'muse-mode-choose-mode)
                  auto-mode-alist)))
  (set sym val)
  ;; associate .muse with muse-mode
  (when val
    (add-to-list 'auto-mode-alist
                 (cons (concat "\\." val "\\'")
                       'muse-mode-choose-mode)))
  (when (fboundp 'muse-update-ignored-extensions-regexp)
    (muse-update-ignored-extensions-regexp
     'muse-ignored-extensions muse-ignored-extensions)))

(defcustom muse-file-extension "muse"
  "File extension of Muse files.  Omit the period at the beginning."
  :type '(choice
          (const :tag "None" nil)
          (string))
  :set 'muse-update-file-extension
  :group 'muse)

(defun muse-update-ignored-extensions-regexp (sym val)
  "Update the value of `muse-ignored-extensions-regexp'."
  (set sym val)
  (if val
      (setq muse-ignored-extensions-regexp
            (concat "\\.\\("
                    (regexp-quote (or muse-file-extension "")) "\\|"
                    (mapconcat 'identity val "\\|")
                    "\\)\\'"))
    (setq muse-ignored-extensions-regexp
          (if muse-file-extension
              (concat "\\.\\(" muse-file-extension "\\)\\'")
            nil))))

(defcustom muse-ignored-extensions '("bz2" "gz" "[Zz]")
  "A list of extensions to omit from the ending of a Muse page name.
These are regexps.

Don't put a period at the beginning of each extension unless you
understand that it is part of a regexp."
  :type '(repeat (regexp :tag "Extension"))
  :set 'muse-update-ignored-extensions-regexp
  :group 'muse)

;; URL protocols

(require 'muse-protocols)

;;; Return an list of known wiki names and the files they represent.

(defsubst muse-delete-file-if-exists (file)
  (when (file-exists-p file)
    (delete-file file)
    (message "Removed %s" file)))

(defsubst muse-time-less-p (t1 t2)
  "Say whether time T1 is less than time T2."
  (or (< (car t1) (car t2))
      (and (= (car t1) (car t2))
           (< (nth 1 t1) (nth 1 t2)))))

(eval-when-compile
  (defvar muse-publishing-current-file nil))

(defun muse-current-file ()
  "Return the name of the currently visited or published file."
  (or (and (boundp 'muse-publishing-current-file)
           muse-publishing-current-file)
      (buffer-file-name)
      (concat default-directory (buffer-name))))

(defun muse-page-name (&optional name)
  "Return the canonical form of a Muse page name.
All this means is that certain extensions, like .gz, are removed."
  (save-match-data
    (unless (and name (not (string= name "")))
      (setq name (muse-current-file)))
    (if name
        (let ((page (file-name-nondirectory name)))
          (if (and muse-ignored-extensions-regexp
                   (string-match muse-ignored-extensions-regexp page))
              (replace-match "" t t page)
            page)))))

(defun muse-eval-lisp (form)
  "Evaluate the given form and return the result as a string."
  (require 'pp)
  (save-match-data
    (condition-case err
        (let ((object (eval (read form))))
          (cond
           ((stringp object) object)
           ((and (listp object)
                 (not (eq object nil)))
            (let ((string (pp-to-string object)))
              (substring string 0 (1- (length string)))))
           ((numberp object)
            (number-to-string object))
           ((eq object nil) "")
           (t
            (pp-to-string object))))
      (error
       (if (fboundp 'display-warning)
           (display-warning 'muse
                            (format "%s: Error evaluating %s: %s"
                                    (muse-page-name) form err)
                            (if (featurep 'xemacs)
                                'warning
                              :warning))
         (message "%s: Error evaluating %s: %s"
                  (muse-page-name) form err))
       "<!--INVALID LISP CODE-->"))))

(defmacro muse-with-temp-buffer (&rest body)
  "Create a temporary buffer, and evaluate BODY there like `progn'.
See also `with-temp-file' and `with-output-to-string'.
Unlike `with-temp-buffer', this will never attempt to save the temp buffer.
It is meant to be used along with `insert-file-contents'."
  (let ((temp-buffer (make-symbol "temp-buffer")))
    `(let ((,temp-buffer (generate-new-buffer " *muse-temp*")))
       (unwind-protect
           (if debug-on-error
               (with-current-buffer ,temp-buffer
                 ,@body)
             (condition-case err
                 (with-current-buffer ,temp-buffer
                   ,@body)
               (error
                (cond
                 ((and (boundp 'muse-batch-publishing-p)
                       muse-batch-publishing-p)
                  (message "%s: Error occured: %s"
                           (muse-page-name) err)
                  (backtrace))
                 ((fboundp 'display-warning)
                  (display-warning
                   'muse (format (concat "An error occurred while publishing"
                                         " %s: %s\n\nSet debug-on-error to"
                                         " `t' if you would like a backtrace.")
                                 (muse-page-name) err)
                   (if (featurep 'xemacs)
                       'warning
                     :warning)))
                 (t
                  (message (concat "An error occurred while publishing"
                                   " %s: %s\n\nSet debug-on-error to"
                                   " `t' if you would like a backtrace.")
                           (muse-page-name) err))))))
         (when (buffer-live-p ,temp-buffer)
           (with-current-buffer ,temp-buffer
             (set-buffer-modified-p nil))
           (unless debug-on-error (kill-buffer ,temp-buffer)))))))
(put 'muse-with-temp-buffer 'lisp-indent-function 0)
(put 'muse-with-temp-buffer 'edebug-form-spec '(body))

;; The following code was extracted from cl

(defun muse-const-expr-p (x)
  (cond ((consp x)
         (or (eq (car x) 'quote)
             (and (memq (car x) '(function function*))
                  (or (symbolp (nth 1 x))
                      (and (eq (and (consp (nth 1 x))
                                    (car (nth 1 x))) 'lambda) 'func)))))
        ((symbolp x) (and (memq x '(nil t)) t))
        (t t)))

(put 'muse-assertion-failed 'error-conditions '(error))
(put 'muse-assertion-failed 'error-message "Assertion failed")

(defun muse-list* (arg &rest rest)
  "Return a new list with specified args as elements, cons'd to last arg.
Thus, `(list* A B C D)' is equivalent to `(nconc (list A B C) D)', or to
`(cons A (cons B (cons C D)))'."
  (cond ((not rest) arg)
        ((not (cdr rest)) (cons arg (car rest)))
        (t (let* ((n (length rest))
                  (copy (copy-sequence rest))
                  (last (nthcdr (- n 2) copy)))
             (setcdr last (car (cdr last)))
             (cons arg copy)))))

(defmacro muse-assert (form &optional show-args string &rest args)
  "Verify that FORM returns non-nil; signal an error if not.
Second arg SHOW-ARGS means to include arguments of FORM in message.
Other args STRING and ARGS... are arguments to be passed to `error'.
They are not evaluated unless the assertion fails.  If STRING is
omitted, a default message listing FORM itself is used."
  (let ((sargs
         (and show-args
              (delq nil (mapcar
                         (function
                          (lambda (x)
                            (and (not (muse-const-expr-p x)) x)))
                         (cdr form))))))
    (list 'progn
          (list 'or form
                (if string
                    (muse-list* 'error string (append sargs args))
                  (list 'signal '(quote muse-assertion-failed)
                        (muse-list* 'list (list 'quote form) sargs))))
          nil)))

;; Compatibility functions

(defun muse-looking-back (regexp &optional limit)
  (if (fboundp 'looking-back)
      (looking-back regexp limit)
    (save-excursion
      (re-search-backward (concat "\\(?:" regexp "\\)\\=") limit t))))

(defun muse-line-end-position (&optional n)
  (if (fboundp 'line-end-position)
      (line-end-position n)
    (save-excursion (end-of-line n) (point))))

(defun muse-line-beginning-position (&optional n)
  (if (fboundp 'line-beginning-position)
      (line-beginning-position n)
    (save-excursion (beginning-of-line n) (point))))

(defun muse-match-string-no-properties (num &optional string)
  (if (fboundp 'match-string-no-properties)
      (match-string-no-properties num string)
    (match-string num string)))

(defun muse-replace-regexp-in-string (regexp replacement text &optional fixedcase literal)
  "Replace REGEXP with REPLACEMENT in TEXT.
If fourth arg FIXEDCASE is non-nil, do not alter case of replacement text.
If fifth arg LITERAL is non-nil, insert REPLACEMENT literally."
  (cond
   ((fboundp 'replace-regexp-in-string)
    (replace-regexp-in-string regexp replacement text fixedcase literal))
   ((fboundp 'replace-in-string)
    (replace-in-string text regexp replacement literal))
   (t (while (string-match regexp text)
        (setq text (replace-match replacement fixedcase literal text)))
      text)))

(defun muse-add-to-invisibility-spec (element)
  "Add ELEMENT to `buffer-invisibility-spec'.
See documentation for `buffer-invisibility-spec' for the kind of elements
that can be added."
  (if (fboundp 'add-to-invisibility-spec)
      (add-to-invisibility-spec element)
    (if (eq buffer-invisibility-spec t)
        (setq buffer-invisibility-spec (list t)))
    (setq buffer-invisibility-spec
          (cons element buffer-invisibility-spec))))

(defun muse-read-directory-name (prompt &optional dir default-dirname mustmatch initial)
  "Read directory name - see `read-file-name' for details."
  (if (fboundp 'read-directory-name)
      (read-directory-name prompt dir default-dirname mustmatch initial)
    (unless dir
      (setq dir default-directory))
    (read-file-name prompt dir (or default-dirname
                                   (if initial (expand-file-name initial dir)
                                     dir))
                    mustmatch initial)))

;; Widget compatibility functions

(defun muse-widget-type-value-create (widget)
  "Convert and instantiate the value of the :type attribute of WIDGET.
Store the newly created widget in the :children attribute.

The value of the :type attribute should be an unconverted widget type."
  (let ((value (widget-get widget :value))
        (type (widget-get widget :type)))
    (widget-put widget :children
                (list (widget-create-child-value widget
                                                 (widget-convert type)
                                                 value)))))

(defun muse-widget-child-value-get (widget)
  "Get the value of the first member of :children in WIDGET."
  (widget-value (car (widget-get widget :children))))

(defun muse-widget-type-match (widget value)
  "Non-nil if the :type value of WIDGET matches VALUE.

The value of the :type attribute should be an unconverted widget type."
  (widget-apply (widget-convert (widget-get widget :type)) :match value))

;; Link-handling functions and variables

(defun muse-link-escape (text)
  "Escape characters in TEXT that conflict with the explicit link
regexp."
  (if text
      (progn
        (muse-replace-regexp-in-string "\\[" "%5B" text t t)
        (muse-replace-regexp-in-string "\\]" "%5D" text t t)
        text)
    ""))

(defun muse-link-unescape (text)
  "Un-escape characters in TEXT that conflict with the explicit
link regexp."
  (if text
      (progn
        (muse-replace-regexp-in-string "%5B" "[" text t t)
        (muse-replace-regexp-in-string "%5D" "]" text t t)
        text)
    ""))

(defun muse-handle-url (&optional string)
  "If STRING or point has a URL, match and return it."
  (if (if string (string-match muse-url-regexp string)
        (looking-at muse-url-regexp))
      (match-string 0 string)))

(defcustom muse-implicit-link-functions '(muse-handle-url)
  "A list of functions to handle an implicit link.
An implicit link is one that is not surrounded by brackets.

By default, Muse handles URLs only.
If you want to handle WikiWords, load muse-wiki.el."
  :type 'hook
  :options '(muse-handle-url)
  :group 'muse)

(defun muse-handle-implicit-link (&optional link)
  "Handle implicit links.  If LINK is not specified, look at point.
An implicit link is one that is not surrounded by brackets.
By default, Muse handles URLs only.
If you want to handle WikiWords, load muse-wiki.el.

This function modifies the match data so that match 1 is the
link.  Match 2 will usually be nil, unless the description is
embedded in the text of the buffer.

The match data is restored after each unsuccessful handler
function call.  If LINK is specified, only restore at very end.

This behavior is needed because the part of the buffer that
`muse-implicit-link-regexp' matches must be narrowed to the part
that is an accepted link."
  (let ((funcs muse-implicit-link-functions)
        (res nil)
        (data (match-data t)))
    (while funcs
      (setq res (funcall (car funcs) link))
      (if res
          (setq funcs nil)
        (unless link (set-match-data data))
        (setq funcs (cdr funcs))))
    (when link (set-match-data data))
    res))

(defcustom muse-explicit-link-functions nil
  "A list of functions to handle an explicit link.
An explicit link is one [[like][this]] or [[this]]."
  :type 'hook
  :group 'muse)

(defun muse-handle-explicit-link (&optional link)
  "Handle explicit links.  If LINK is not specified, look at point.
An explicit link is one that looks [[like][this]] or [[this]].

This function modifies the match data so that match 1 is the link
and match 2 is the description.  Perhaps someday match 3 might be
the text to use for the alt element of an <a> or <img> tag.

The match data is saved.  If no handlers are able to process
LINK, return LINK (if specified) or the 1st match string.  If
LINK is not specified, it is assumed that Muse has matched
against `muse-explicit-link-regexp' before calling this
function."
  (let ((funcs muse-explicit-link-functions)
        (res nil))
    (save-match-data
      (while funcs
        (setq res (funcall (car funcs) link))
        (if res
            (setq funcs nil)
          (setq funcs (cdr funcs)))))
    (muse-link-unescape
     (if res
         res
       (or link (match-string 1))))))

(provide 'muse)

;;; muse.el ends here
