;;; lispobj.lisp --- read-from-string options for Clon

;; Copyright (C) 2008 Didier Verna

;; Author:        Didier Verna <didier@lrde.epita.fr>
;; Maintainer:    Didier Verna <didier@lrde.epita.fr>
;; Created:       Thu Nov 27 18:04:15 2008
;; Last Revision: Thu Nov 27 18:04:15 2008

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
;; The LispObj Option Class
;; ==========================================================================

(defoption lispobj ()
  ((typespec :documentation "A type specifier the option's value should satisfy."
	     :initform t
	     :initarg :typespec
	     :reader typespec))
  (:documentation "The LISPOBJ class.
This class implements read-from-string options."))


;; -------------------
;; Conversion protocol
;; -------------------

;; Value check subprotocol
(defmethod check-value ((lispobj lispobj) value)
  "Check that VALUE is valid for LISPOBJ."
  (if (typep value (typespec lispobj))
      value
      (error 'invalid-value
	     :option lispobj
	     :value value
	     :comment (format nil "Value must satisfy ~A." (typespec lispobj)))))

(defmethod convert ((lispobj lispobj) argument)
  "Return the evaluation of ARGUMENT string."
  (multiple-value-bind (value position) (read-from-string argument)
    (cond ((< position (length argument))
	   (error 'invalid-argument
		  :option lispobj
		  :argument argument
		  :comment (format nil "Cannot parse argument ~S." argument)))
	  ((typep value (typespec lispobj))
	   value)
	  (t
	   (error 'invalid-argument
		  :option lispobj
		  :argument argument
		  :comment (format nil "Argument ~S must evaluate to ~A."
			     argument (typespec lispobj)))))))



;; ==========================================================================
;; LispObj Instance Creation
;; ==========================================================================

(defun make-lispobj (&rest keys
		     &key short-name long-name description
			  argument-name argument-type
			  env-var
			  typespec fallback-value default-value
			  nullablep)
  "Make a new lispobj option.
- SHORT-NAME is the option's short name (without the dash).
  It defaults to nil.
- LONG-NAME is the option's long name (without the double-dash).
  It defaults to nil.
- DESCRIPTION is the option's description appearing in help strings.
  It defaults to nil.
- ARGUMENT-NAME is the option's argument name appearing in help strings.
- ARGUMENT-TYPE is one of :required, :mandatory or :optional (:required and
  :mandatory are synonyms).
  It defaults to :optional.
- ENV-VAR is the option's associated environment variable.
  It defaults to nil.
- TYPESPEC is a type specifier the option's value should satisfy.
- FALLBACK-VALUE is the option's fallback value (for missing optional
  arguments), if any.
- DEFAULT-VALUE is the option's default value, if any.
- NULLABLEP indicates whether this option accepts nil as a value."
  (declare (ignore short-name long-name description
		   argument-name argument-type
		   env-var
		   typespec fallback-value default-value
		   nullablep))
  (apply #'make-instance 'lispobj keys))

(defun make-internal-lispobj (long-name description
			       &rest keys
			       &key argument-name argument-type
				    env-var
				    typespec fallback-value default-value
				    nullablep)
  "Make a new internal (Clon-specific) string option.
- LONG-NAME is the option's long-name, minus the 'clon-' prefix.
  (Internal options don't have short names.)
- DESCRIPTION is the options's description.
- ARGUMENT-NAME is the option's argument name appearing in help strings.
- ARGUMENT-TYPE is one of :required, :mandatory or :optional (:required and
  :mandatory are synonyms).
  It defaults to :optional.
- ENV-VAR is the option's associated environment variable, minus the 'CLON_'
  prefix. It defaults to nil.
- TYPESPEC is a type specifier the option's value should satisfy.
- FALLBACK-VALUE is the option's fallback value (for missing optional
  arguments), if any.
- DEFAULT-VALUE is the option's default value, if any.
- NULLABLEP indicates whether this option accepts nil as a value."
  (declare (ignore argument-name argument-type
		   env-var
		   typespec fallback-value default-value
		   nullablep))
  (apply #'make-instance 'lispobj
	 :long-name long-name
	 :description description
	 :internal t
	 keys))


;;; lispobj.lisp ends here