;;; context.lisp --- Context management for Clon

;; Copyright (C) 2008 Didier Verna

;; Author:        Didier Verna <didier@lrde.epita.fr>
;; Maintainer:    Didier Verna <didier@lrde.epita.fr>
;; Created:       Tue Jul  1 16:08:02 2008
;; Last Revision: Tue Jul  1 16:08:02 2008

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


;; ============================================================================
;; The Command-Line Items
;; ============================================================================

(defstruct cmdline-option
  name ;; the option's name as used on the cmdline
  option ;; the corresponding option object
  value ;; the converted option's cmdline value
  )

(define-condition cmdline-junk-error (cmdline-error)
  ((item ;; inherited from the CMDLINE-ERROR condition
    :documentation "The piece of junk appearing on the command-line."
    :initarg :junk
    :reader junk))
  (:report (lambda (error stream)
	     (format stream "Junk on the command-line: ~S." (junk error))))
  (:documentation "An error related to a command-line piece of junk."))

(define-condition unknown-cmdline-option-error (cmdline-error)
  ((item ;; inherited from the CMDLINE-ERROR condition
    :documentation "The option's name as it appears on the command-line."
    :initarg :name
    :reader name)
   (argument :documentation "The option's command-line argument."
	     :initarg :argument
	     :reader argument))
  (:report (lambda (error stream)
	     (format stream
		     "Unknown command-line option ~S~@[ with argument ~S~]."
		     (name error)
		     (argument error))))
  (:documentation "An error related to an unknown command-line option."))


;; ============================================================================
;; The Context Class
;; ============================================================================

;; #### FIXME: make final
(defclass context ()
  ((synopsis :documentation "The program synopsis."
	     :type synopsis
	     :initarg :synopsis
	     :reader synopsis)
   (progname :documentation
	     "The program name, as it appears on the command-line."
	     :type string
	     :reader progname)
   (cmdline-items :documentation "The items on the command-line."
	  :type list
	  :accessor cmdline-items)
   (remainder :documentation "The non-Clon part of the command-line."
	      :type list
	      :reader remainder)
   (error-handler :documentation
		  "The behavior to adopt on errors at command-line parsing time."
		  :type symbol
		  :initarg :error-handler
		  :initform :quit
		  :reader error-handler)
   (getopt-error-handler
    :documentation
    "The default behavior to adopt on errors in the getopt family of functions."
    :type symbol
    :initarg :getopt-error-handler
    :initform :quit
    :reader getopt-error-handler))
  (:default-initargs
      ;; #### FIXME: SBCL specific
      :cmdline sb-ext:*posix-argv*)
  (:documentation "The CONTEXT class.
This class represents the associatiion of a synopsis and a set of command-line
options based on it."))

(defmethod initialize-instance :before ((context context) &key synopsis)
  "Ensure that SYNOPSIS is sealed."
  (unless (sealedp synopsis)
    (error "Initializing context ~A: synopsis ~A not sealed." context synopsis)))

;; #### FIXME: we should offer more restarts, like modify the name of the
;; option (handy in case of a typo for instance). But then, we will have to
;; split the parsing process into several individual functions so that they
;; can restart recursively (looking for the option etc).
(defmacro restartable-unknown-cmdline-option-error
    (place name &optional argument)
  "Restartably throw an unknown-cmdline-option-error."
  `(restart-case (error 'unknown-cmdline-option-error
		  :name ,name :argument ,argument)
    (discard ()
     :report "Discard unknown option."
     nil)
    (register (error)
     :report "Don't treat error right now, but remember it."
     :interactive (lambda ()
		    ;; #### FIXME: SBCL specific
		    (list sb-debug:*debug-condition*))
     (push error ,place))))

(defmethod initialize-instance :after ((context context) &key cmdline)
  "Parse CMDLINE."
  (setf (slot-value context 'progname) (pop cmdline))
  (let ((cmdline-items (list))
	(remainder (list)))
    (macrolet ((push-cmdline-option (place &rest body)
		 "Push a new CMDLINE-OPTION created with BODY onto PLACE."
		 `(push (make-cmdline-option ,@body) ,place))
	       (push-retrieved-option
		   (place func option &optional cmdline-value cmdline name-form)
		   "Retrieve OPTION from a FUNC call and push it onto PLACE.
- FUNC must be either :long, :short or :plus,
- CMDLINE-VALUE is a potentially already parsed option argument,
- CMDILNE is where to find a potentially required argument,
- NAME-FORM is how to compute the :name slot of the CMDLINE-OPTION structure.
  If not given, the option's long or short name will be used as appropriate."
		   (let* ((value (gensym "value"))
			  (vars (list value))
			  (call (list option
				      (find-symbol (concatenate 'string
						     "RETRIEVE-FROM-"
						     (symbol-name func)
						     "-CALL")
						   'clon)))
			  new-cmdline)
		     (unless name-form
		       (setq name-form
			     (ecase func
			       (:long `(long-name ,option))
			       (:short `(short-name ,option))
			       (:plus `(short-name ,option)))))
		     (when (eq func :long)
		       (push name-form call))
		     (when cmdline-value
		       (push cmdline-value call))
		     (when cmdline
		       (setq new-cmdline (gensym "new-cmdline"))
		       (push new-cmdline vars)
		       (unless cmdline-value
			 (push nil call))
		       (push cmdline call))
		     `(restart-case
		       (multiple-value-bind ,(reverse vars) ,(reverse call)
			 ,(when cmdline `(setq ,cmdline ,new-cmdline))
			 (push-cmdline-option ,place
			   :name ,name-form
			   :option ,option
			   :value ,value))
		       (register (error)
			:report "Don't treat error right now, but remember it."
			:interactive (lambda ()
				       ;; #### FIXME: SBCL specific
				       (list sb-debug:*debug-condition*))
			(push error ,place)))))
	       (do-pack ((option pack context) &body body)
		 "Evaluate BODY with OPTION bound to each option from PACK.
CONTEXT is where to look for the options."
		 (let ((char (gensym "char"))
		       (name (gensym "name")))
		   `(loop :for ,char :across ,pack
		     :do (let* ((,name (make-string 1 :initial-element ,char))
				(,option (search-option ,context
					   :short-name ,name)))
			   (assert ,option)
			   ,@body)))))
      (handler-bind ((cmdline-error
		      (lambda (error)
			(ecase (error-handler context)
			  (:quit
			   (let (*print-escape*) (print-object error t))
			   (terpri)
			   ;; #### FIXME: SBCL-specific
			   (sb-ext:quit :unix-status 1))
			  (:register
			   (invoke-restart 'register error))
			  (:none)))))
	(do ((arg (pop cmdline) (pop cmdline)))
	    ((null arg))
	  (cond ((string= arg "--")
		 ;; The Clon separator.
		 (setq remainder cmdline)
		 (setq cmdline nil))
		((beginning-of-string-p "--" arg)
		 ;; A long call.
		 (let* ((value-start (position #\= arg :start 2))
			(cmdline-name (subseq arg 2 value-start))
			(cmdline-value (when value-start
					 (subseq arg (1+ value-start))))
			(option (search-option context :long-name cmdline-name))
			(name cmdline-name))
		   (unless option
		     (multiple-value-setq (option name)
		       (search-option context :partial-name cmdline-name)))
		   (if option
		       (push-retrieved-option cmdline-items :long option
					      cmdline-value cmdline name)
		       (restartable-unknown-cmdline-option-error
			cmdline-items cmdline-name cmdline-value))))
		;; A short call, or a minus pack.
		((beginning-of-string-p "-" arg)
		 ;; #### FIXME: check invalid syntax -foo=val
		 (let* ((cmdline-name (subseq arg 1))
			(option (search-option context :short-name cmdline-name))
			cmdline-value)
		   (unless option
		     (multiple-value-setq (option cmdline-value)
		       (search-sticky-option context cmdline-name)))
		   (cond (option
			  (push-retrieved-option cmdline-items :short option
						 cmdline-value cmdline))
			 ((potential-pack-p cmdline-name context)
			  ;; #### NOTE: When parsing a minus pack, only the
			  ;; last option gets a cmdline argument because only
			  ;; the last one is allowed to retrieve an argument
			  ;; from there.
			  (do-pack (option
				    (subseq cmdline-name 0
					    (1- (length cmdline-name)))
				    context)
			    (push-retrieved-option cmdline-items :short option))
			  (let* ((name (subseq cmdline-name
					       (1- (length cmdline-name))))
				 (option (search-option context
							:short-name name)))
			    (assert option)
			    (push-retrieved-option
			     cmdline-items :short option nil cmdline)))
			 (t
			  (restartable-unknown-cmdline-option-error
			   cmdline-items cmdline-name)))))
		;; A plus call or a plus pack.
		((beginning-of-string-p "+" arg)
		 ;; #### FIXME: check invalid syntax +foo=val
		 (let* ((cmdline-name (subseq arg 1))
			;; #### NOTE: in theory, we could allow partial
			;; matches on short names when they're used with the
			;; +-syntax, because there's no sticky argument or
			;; whatever. But we don't. That's all. Short names are
			;; not meant to be long (otherwise, that would be long
			;; names right?), so they're not meant to be
			;; abbreviated.
			(option (search-option context :short-name cmdline-name)))
		   (cond (option
			  (push-retrieved-option cmdline-items :plus option))
			 ((potential-pack-p cmdline-name context)
			  (do-pack (option cmdline-name context)
			    (push-retrieved-option cmdline-items :plus option)))
			 (t
			  (restartable-unknown-cmdline-option-error
			   cmdline-items cmdline-name)))))
		(t
		 ;; Not an option call.
		 ;; #### FIXME: SBCL specific.
		 (cond ((sb-ext:posix-getenv "POSIXLY_CORRECT")
			;; That's the end of the Clon-specific part:
			(setq remainder (cons arg cmdline))
			(setq cmdline nil))
		       (t
			;; If there's no more option on the cmdline, consider
			;; this as the remainder (implicit since no "--" has
			;; been used). If there's still another option
			;; somewhere, then this is really junk.
			(cond ((notany #'option-call-p cmdline)
			       (setq remainder (cons arg cmdline))
			       (setq cmdline nil))
			      (t
			       (restart-case
				   (error 'cmdline-junk-error :junk arg)
				 (discard ()
				   :report "Discard junk."
				   nil)
				 (register (error)
				   :report
				   "Don't treat error right now, but remember it."
				   :interactive
				   (lambda ()
				     ;; #### FIXME: SBCL specific
				     (list sb-debug:*debug-condition*))
				   (push error cmdline-items)))))))))))
      (setf (cmdline-items context) (nreverse cmdline-items))
      (setf (slot-value context 'remainder) remainder))))

(defun make-context
    (&rest keys &key synopsis error-handler getopt-error-handler cmdline)
  "Make a new context.
- SYNOPSIS is the program synopsis to use in that context.
- ERROR-HANDLER is the behavior to adopt on errors at command-line parsing time.
  It can be one of:
  * :quit, meaning print the error and abort execution,
  * :none, meaning let the debugger handle the situation,
  * :register, meaning silently register the error.
- GETOPT-ERROR-HANDLER is the default behavior to adopt on command-line errors
  in the GETOPT family of functions (note that this behavior can be overridden
in the functions themselves). It is meaningful only if errors have been
previously registered. It can be one of:
  * :quit, meaning print the error and abort execution,
  * :none, meaning let the debugger handle the situation.
- CMDLINE is the argument list (strings) to process.
  It defaults to a POSIX conformant argv."
  (declare (ignore synopsis error-handler getopt-error-handler cmdline))
  (apply #'make-instance 'context keys))


;; -----------------------
;; Potential pack protocol
;; -----------------------

(defmethod potential-pack-p (pack (context context))
  "Return t if PACK (a string) is a potential pack in CONTEXT."
  (potential-pack-p pack (synopsis context)))


;; -------------------------
;; Option searching protocol
;; -------------------------

(defmethod search-option
    ((context context) &rest keys &key short-name long-name partial-name)
  "Search for an option in CONTEXT.
The search is actually done in the CONTEXT'synopsis."
  (declare (ignore short-name long-name partial-name))
  (apply #'search-option (synopsis context) keys))

(defmethod search-sticky-option ((context context) namearg)
  "Search for a sticky option in CONTEXT.
The search is actually done in the CONTEXT'synopsis."
  (search-sticky-option (synopsis context) namearg))


;; ============================================================================
;; The Option Retrieval Protocol
;; ============================================================================

(defun getopt (context &rest keys
		       &key short-name long-name option
			    (error-handler (getopt-error-handler context)))
  "Get an option's value in CONTEXT.
The option can be specified either by SHORT-NAME, LONG-NAME, or directly via
an OPTION object.
ERROR-HANDLER is the behavior to adopt when a command-line error has been
registered for this option. Its default value depends on the CONTEXT. See
`make-context' for a list of possible values.
This function returns two values:
- the retrieved value,
- the value's source."
  (unless option
    (setq option
	  (apply #'search-option context (remove-keys keys :error-handler))))
  (unless option
    (error "Getting option ~S from synopsis ~A in context ~A: unknown option."
	   (or short-name long-name)
	   (synopsis context)
	   context))
  ;; Try the command-line:
  (let ((cmdline-items (list)))
    (do ((cmdline-item
	  (pop (cmdline-items context))
	  (pop (cmdline-items context))))
	((null cmdline-item))
      (etypecase cmdline-item
	(cmdline-option
	 (cond ((eq (cmdline-option-option cmdline-item) option)
		(setf (cmdline-items context)
		      ;; #### NOTE: actually, I *do* have a use for nreconc,
		      ;; he he ;-)
		      (nreconc cmdline-items (cmdline-items context)))
		(return-from getopt
		  (values (cmdline-option-value cmdline-item)
			  (list :cmdline (cmdline-option-name cmdline-item)))))
	       (t
		(push cmdline-item cmdline-items))))
	(cmdline-option-error
	 (if (not (eq option (option cmdline-item)))
	     (push cmdline-item cmdline-items)
	     (ecase error-handler
	       (:quit
		(let (*print-escape*) (print-object cmdline-item t)
		     (terpri)
		     ;; #### FIXME: SBCL-specific
		     (sb-ext:quit :unix-status 1)))
	       (:none
		;; #### FIXME: we have no restarts here!
		(error cmdline-item)))))
	(cmdline-error
	 (push cmdline-item cmdline-items))))
    (setf (cmdline-items context) (nreverse cmdline-items)))
  ;; Try an environment variable:
  (handler-bind ((environment-error
		  (lambda (error)
		    (ecase error-handler
		      (:quit
		       (let (*print-escape*) (print-object error t))
		       (terpri)
		       ;; #### FIXME: SBCL-specific
		       (sb-ext:quit :unix-status 1))
		      (:none)))))
    (let* ((env-var (env-var option))
	   (env-val (sb-posix:getenv env-var)))
      (when env-val
	(return-from getopt
	  (values (retrieve-from-environment option env-val)
		  (list :environement env-var))))))
  ;; Try a default value:
  (when (and (typep option 'valued-option)
	     (slot-boundp option 'default-value))
    (values (default-value option) (list :default-value))))

(defun getopt-cmdline
    (context &key (error-handler (getopt-error-handler context)))
  "Get the next cmdline option in CONTEXT.
ERROR-HANDLER is the behavior to adopt when a command-line error has been
registered for this option. Its default value depends on the CONTEXT. See
`make-context' for a list of possible values.
This function returns three values:
- the option object,
- the option's name used on the command-line,
- the retrieved value."
  (let ((cmdline-item (pop (cmdline-items context))))
    (when cmdline-item
      (etypecase cmdline-item
	(cmdline-option
	 (values (cmdline-option-option cmdline-item)
		 (cmdline-option-name cmdline-item)
		 (cmdline-option-value cmdline-item)))
	(cmdline-error
	 (ecase error-handler
	   (:quit
	    (let (*print-escape*) (print-object cmdline-item t)
		 (terpri)
		 ;; #### FIXME: SBCL-specific
		 (sb-ext:quit :unix-status 1)))
	   (:none
	    ;; #### FIXME: we have no restart here!
	    (error cmdline-item))))))))

(defmacro multiple-value-getopt-cmdline
    ((option name value) (context &key error-handler) &body body)
  "Evaluate BODY on the next command-line option in CONTEXT.
OPTION, NAME and VALUE are bound to the option's object, name used on the
command-line) and retrieved value.
ERROR-HANDLER is the behavior to adopt when a command-line error has been
registered for this option. Its default value depends on the CONTEXT. See
`make-context' for a list of possible values."
  (let ((getopt-cmdline-args ()))
    (when error-handler
      (push error-handler getopt-cmdline-args)
      (push :error-handler getopt-cmdline-args))
    (push context getopt-cmdline-args)
    `(multiple-value-bind (,option ,name ,value)
      (getopt-cmdline ,@getopt-cmdline-args)
      ,@body)))

(defmacro do-cmdline-options
    ((option name value) (context &key error-handler) &body body)
  "Evaluate BODY over all command-line options in CONTEXT.
OPTION, NAME and VALUE are bound to each option's object, name used on the
command-line) and retrieved value."
  (let ((multiple-value-getopt-cmdline-2nd-arg ()))
    (when error-handler
      (push error-handler multiple-value-getopt-cmdline-2nd-arg)
      (push :error-handler multiple-value-getopt-cmdline-2nd-arg))
    (push context multiple-value-getopt-cmdline-2nd-arg)
    `(do () ((null (cmdline-items ,context)))
      (multiple-value-getopt-cmdline (,option ,name ,value)
	  ,multiple-value-getopt-cmdline-2nd-arg
	,@body))))


;;; context.lisp ends here
