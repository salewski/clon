;;; sheet.lisp --- Sheet handling for Clon

;; Copyright (C) 2008 Didier Verna

;; Author:        Didier Verna <didier@lrde.epita.fr>
;; Maintainer:    Didier Verna <didier@lrde.epita.fr>
;; Created:       Sun Nov 30 16:20:55 2008
;; Last Revision: Sun Nov 30 16:20:55 2008

;; This file is part of Clon.

;; Clon is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2 of the License, or
;; (at your option) any later version.

;; Clon is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.


;;; Commentary:

;; Contents management by FCM version 0.1.


;;; Code:

(in-package :clon)
(in-readtable :clon)


;; ==========================================================================
;; The Sheet Class
;; ==========================================================================

(defclass sheet ()
  ((output-stream :documentation "The sheet's output stream."
		  :type stream
		  :reader output-stream
		  :initarg :output-stream)
   (line-width :documentation "The sheet's line width."
	       :type (integer 1)
	       :reader line-width
	       :initarg :line-width)
   (last-action :documentation "The last action performed on the sheet."
		:type symbol
		:accessor last-action
		:initform :none))
  (:documentation "The SHEET class.
This class implements the notion of sheet for printing Clon help."))



;; ==========================================================================
;; Sheet Processing
;; ==========================================================================

(defmacro within-group (sheet &body body)
  `(progn ,@body))

(defun newline (sheet)
  (terpri (output-stream sheet)))

(defun maybe-newline (sheet)
  "Output a newline to SHEET if needed."
  (ecase (last-action sheet)
    ((:none #+():open-group)
     (values))
    ((:put-header #+():put-string #+():put-option #+():close-group)
     (newline sheet))))

(defun output-char (sheet char)
  (assert (and (char/= char #\newline) (char/= char #\tab)))
  (princ char (output-stream sheet)))

(defun output-string (sheet string)
  (princ string (output-stream sheet)))

(defun output-header (sheet pathname minus-pack plus-pack postfix)
  (output-string sheet "Usage: ")
  (output-string sheet pathname)
  (when minus-pack
    (output-string sheet " [")
    (output-char sheet #\-)
    (output-string sheet minus-pack)
    (output-char sheet #\]))
  (when plus-pack
    (output-string sheet " [")
    (output-char sheet #\+)
    (output-string sheet plus-pack)
    (output-char sheet #\]))
  (output-string sheet " [")
  (output-string sheet "OPTIONS")
  (output-char sheet #\])
  (when postfix
    (output-char sheet #\space)
    (output-string sheet postfix))
  (newline sheet)
  (setf (last-action sheet) :put-header))



;; ==========================================================================
;; Sheet Instance Creation
;; ==========================================================================

(defun make-sheet (&key output-stream line-width search-path theme)
  "Make a new SHEET."
  (declare (ignore search-path theme))
  (unless line-width
    ;; #### PORTME.
    (handler-case
	(with-winsize winsize ()
	  (sb-posix:ioctl (stream-file-stream output-stream :output)
			  +tiocgwinsz+
			  winsize)
	  (setq line-width (winsize-ws-col winsize)))
      (sb-posix:syscall-error (error)
	;; ENOTTY error should remain silent, but no the others.
	(unless (= (sb-posix:syscall-errno error) sb-posix:enotty)
	  (let (*print-escape*) (print-object error *error-output*)))
	(setq line-width 80))))
  ;; See the --clon-line-width option specification
  (assert (typep line-width '(integer 1)))
  (funcall #'make-instance 'sheet
	   :output-stream output-stream :line-width line-width))


;;; sheet.lisp ends here
