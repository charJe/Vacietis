(in-package #:vacietis.reader)
(in-readtable vacietis)

;;; error reporting

(define-condition c-reader-error (reader-error simple-error)
  ((line-number :reader line-number :initarg :line-number))
  (:default-initargs :line-number *line-number*))

(defun read-error (stream msg &rest args)
  (error (make-condition 'c-reader-error
                         :stream stream
                         :format-control (format nil "Error reading from C stream at line ~a: ~?"
                                                 *line-number* msg args))))

;;; basic stream stuff

(defvar *line-number* 0)

(defun c-read-char (stream)
  (let ((c (read-char stream nil 'end)))
    (when (eql c #\Newline)
      (incf *line-number*))
    c))

(defun c-unread-char (c stream)
  (when (eql c #\Newline)
    (decf *line-number*))
  (unread-char c stream))

(defun c-read-line (stream)
  (incf *line-number*)
  (read-line stream))

(defmacro loop-read (stream &body body)
  `(loop with c do (setf c (c-read-char ,stream))
        ,@body))

(defun whitespace? (c)
  (or (char= c #\Space) (char= c #\Tab) (char= c #\Newline)))

(defun next-char (stream &optional (eof-error? t))
  (loop-read stream
     while (if (eq 'end c)
               (when eof-error?
                 (read-error stream "Unexpected end of file"))
               (whitespace? c))
     finally (return c)))

(defun make-peek-buffer ()
  (make-array '(3) :adjustable t :fill-pointer 0 :element-type 'character))

(defun slurp-while (stream predicate)
  (let ((peek-buffer (make-peek-buffer)))
    (loop-read stream
       while (and (not (eq c 'end)) (funcall predicate c))
       do (vector-push-extend c peek-buffer)
       finally (unless (eq c 'end) (c-unread-char c stream)))
    peek-buffer))

;;; numbers

(defun read-octal (stream)
  (parse-integer (slurp-while stream (lambda (c) (char<= #\0 c #\7))) :radix 8))

(defun read-hex (stream)
  (parse-integer (slurp-while stream (lambda (c) (or (char<= #\0 c #\9) (char-not-greaterp #\A c #\F)))) :radix 16))

(defun read-float (prefix separator stream)
  (let ((*readtable* (find-readtable :common-lisp)))
    (read-from-string
     (format nil "~d~a~a" prefix separator
             (slurp-while stream (lambda (c) (find c "0123456789+-eE" :test #'char=)))))))

(defun read-decimal (stream)
  (labels ((digit-value (c) (- (char-code c) 48)))
    (let ((value 0))
      (loop-read stream
           (cond ((eq c 'end) (return value))
                 ((char<= #\0 c #\9) (setf value (+ (* 10 value) (digit-value c))))
                 ((or (char-equal c #\E) (char= c #\.)) (return (read-float value c stream)))
                 (t (c-unread-char c stream) (return value)))))))

(defun read-c-number (stream c)
  (prog1 (if (char= c #\0)
             (case (peek-char nil stream)
               ((#\X #\x) (c-read-char stream) (read-hex stream))
               (#\. (c-unread-char c stream) (read-decimal stream))
               (otherwise (read-octal stream)))
             (progn (c-unread-char c stream) (read-decimal stream)))
    (loop repeat 2 do (when (find (peek-char nil stream nil nil) "ulf" :test #'eql)
                        (c-read-char stream)))))

;;; string and chars (caller has to remember to discard leading #\L!!!)

(defun read-char-literal (stream c)
  (if (char= c #\\)
      (let ((c (c-read-char stream)))
        (code-char (case c
                     (#\a 7)
                     (#\f 12)
                     (#\n 10)
                     (#\r 13)
                     (#\t 9)
                     (#\v 11)
                     (#\x (read-hex stream))
                     (otherwise (if (char<= #\0 c #\7)
                                    (progn (c-unread-char c stream) (read-octal stream))
                                    (char-code c))))))
      c))

(defun read-character-constant (stream)
  (prog1 (read-char-literal stream (c-read-char stream))
    (unless (char= (c-read-char stream) #\')
      (read-error stream "Junk in character constant"))))

(defun read-c-string (stream c1)
  (declare (ignore c1))
  (let ((string (make-peek-buffer)))
    (loop-read stream
         (if (char= c #\") ;; c requires concatenation of adjacent string literals, retardo
             (progn (setf c (next-char stream nil))
                    (unless (eql c #\")
                      (unless (eq c 'end) (c-unread-char c stream))
                      (return string)))
             (vector-push-extend (read-char-literal stream c) string)))))

;;; keywords

(defvar *keywords* '("auto" "break" "case" "char" "const" "continue" "default" "do" "double" "else" "enum" "extern" "float" "for" "goto" "if" "inline" "int" "long" "register" "restrict" "return" "short" "signed" "sizeof" "static" "struct" "switch" "typedef" "union" "unsigned" "void" "volatile" "while" "_Bool" "_Complex" "_Imaginary"))

;;; preprocessor

(defvar *in-preprocessor-p* nil)
(defvar *in-preprocessor-conditional-p* nil)
(defvar *preprocessor-eval-p* t)

(defun preprocessor-if-test (test-str)
  (not (eql 0 (eval test-str)))) ;; HALP

;; (defun read-c-macro (stream)
;;   (let ((pp-directive (read stream t nil t)))
;;     (case pp-directive
;;       (include
;;        (next-char stream)
;;        (let ((delimiter (case (c-read-char stream)
;;                           (#\" #\") (#\< #\>)
;;                           (otherwise (read-error stream "Error reading include path: ~A" (c-read-line stream))))))
;;          (let ((file (slurp-while stream (lambda (c) (char/= c delimiter)))))
;;            (when *preprocessor-eval-p*
;;              (c-read (c-file-stream file) t)))))
;;       (if
;;        (let* ((*in-preprocessor-conditional-p* t)
;;               (test (c-read-line stream))
;;               (*preprocessor-eval-p* (when *preprocessor-eval-p* (preprocessor-if-test test))))
;;          (read-c-macro stream)))
;;       (endif
;;        (when (not *in-preprocessor-conditional-p*)
;;          (read-error stream "Misplaced #endif")))
;;       (otherwise
;;        (read-error stream "Unknown preprocessor directive #~A" pp-directive)))))

;;; reader

;; (defun c-read (stream &optional recursive-p)
;;   (let ((*readtable* (find-readtable 'c-readtable))
;;         (*in-preprocessor-p* nil)
;;         (*in-preprocessor-conditional-p* nil)
;;         (*preprocessor-eval-p* t)
;;         (c (next-char stream)))
;;     (read stream )))

(defun cread-str (str) ;; for development
  (let ((*readtable* (find-readtable 'c-readtable)))
    (read-from-string str)))

;;; infix

;; (defun find-highest-precedence-operator (args)
;;   ((aref) (funcall) |.| -> ++ -- sizeof (lognot) (not) (address-of) (indirection) (cast) * / & + - << >> < > <= >= == != logand logxor logior logand logor elvis-if = += -= *= /= %= <<= >>= &= ^= )
;;   (parse-infix before)
;;   ()
;;   (parse-infix after))

(defun parse-infix (args)
  (if (listp args)
      (if (cdr args)
          (list (second args) (first args) (third args))
          (car args))
      args))

;;; statements

(defun read-c-block (stream c)
  (if (eql c #\{)
      (cons 'progn
            (loop with c do (setf c (next-char stream))
                  until (eql c #\}) collect (read-c-statement stream c)))
      (read-error stream "Expected opening brace '{' but found '~A'" c)))

(defun control-flow-statement? (identifier)
  (member identifier '(if)))

(defun c-type? (identifier)
  ;; and also do checks for struct, union, enum and typedef types
  (member identifier '(int static void const signed unsigned short long float double)))

(defun next-exp (stream)
  (read-c-exp stream (next-char stream)))

(defun read-control-flow-statement (stream statement)
  (case statement
    (if (list 'if
              (parse-infix (next-exp stream))
              (let ((next-char (next-char stream)))
                (if (eql next-char #\{)
                    (read-c-block stream next-char)
                    (read-c-statement stream next-char)))))))

(defun read-comma-separated-list (stream open-delimiter)
  (let ((close-delimiter (ecase open-delimiter (#\( #\)) (#\{ #\}))))
    (loop with c do (setf c (next-char stream))
          until (eql c close-delimiter)
          unless (eql #\, c) collect (read-c-exp stream c))))

(defun read-function (stream name)
  `(defun ,name ,(remove-if #'c-type? ;; do the right thing with type declarations
                            (read-comma-separated-list stream (next-char stream)))
     ,(read-c-block stream (next-char stream))))

(defun read-variable (stream name)
  ;; have to deal with array declarations like *foo_bar[baz]
  `(defvar ,name)
  )

(defun read-declaration (stream token)
  (if (c-type? token)
      (read-declaration stream (next-exp stream)) ;; throw away type info
      (if (eql #\( (peek-char t stream))
          (read-function stream token)
          (read-variable stream token))))

(defun read-c-statement (stream c)
  (let ((next-token (read-c-exp stream c)))
    (cond ((c-type? next-token)
           (read-declaration stream next-token))
          ((control-flow-statement? next-token)
           (read-control-flow-statement stream next-token))
          (t (parse-infix (cons next-token
                                (loop with c do (setf c (next-char stream))
                                      until (eql c #\;) collect (read-c-exp stream c))))))))

(defun read-c-identifier (stream c)
  (unread-char c stream)
  (let ((identifier-name (slurp-while stream (lambda (c) (or (eql c #\_) (alphanumericp c))))))
    (when (eq (readtable-case (find-readtable 'vacietis)) :invert) ;; otherwise it better be :preserve!
      (dotimes (i (length identifier-name))
        (setf #1=(aref identifier-name i) (if (upper-case-p #1#)
                                              (char-downcase #1#)
                                              (char-upcase #1#)))))
    (or (find-symbol identifier-name '#:vacietis.c) (intern identifier-name))))

(defun read-c-exp (stream c)
  (cond ((digit-char-p c) (read-c-number stream c))
        ((or (eql c #\_) (alpha-char-p c)) (read-c-identifier stream c))
        (t
         (case c
           ;; (#\# (let ((*in-preprocessor-p* t)) ;; preprocessor
           ;;        (read-c-macro stream)))
           (#\/ (c-read-char stream) ;; comment
                (case (c-read-char stream)
                  (#\/ (c-read-line stream))
                  (#\* (slurp-while stream
                                    (let ((previous-char (code-char 0)))
                                      (lambda (c)
                                        (prog1 (not (and (char= previous-char #\*)
                                                         (char= c #\/)))
                                          (setf previous-char c)))))
                       (c-read-char stream))
                  (otherwise (read-error stream "Expected comment"))))
           (#\{ (read-delimited-list #\} stream t)) ;; initializer list
           (#\[ (list 'aref
                      (parse-infix (loop with c do (setf c (next-char stream))
                                      until (eql c #\]) collect (read-c-exp stream c)))))
           (#\- (if (eql (peek-char nil stream) #\-)
                    (list '-- (progn (c-read-char stream) (next-exp stream)))
                    '-))
           (#\+ (if (eql (peek-char nil stream) #\+)
                    (list '++ (progn (c-read-char stream) (next-exp stream)))
                    '+))
           (#\~ (list 'lognot (next-exp stream)))
           (#\! (if (eql (peek-char nil stream) #\=)
                    (progn (c-read-char stream) '!=)
                    (list 'not (next-exp stream))))
           (#\= (if (eql (peek-char nil stream) #\=)
                    (progn (c-read-char stream) '==)
                    'setf))))))

;;; readtable

(macrolet
    ((def-c-readtable ()
       `(defreadtable c-readtable
         (:case :invert)

         (:macro-char #\- 'read-c-statement nil) (:macro-char #\* 'read-c-statement nil)

         (:macro-char #\" 'read-c-string nil)

;         (:macro-char #\# 'read-c-macro nil)

         ,@(loop for i from 0 upto 9 collect `(:macro-char ,(digit-char i) 'read-c-statement nil))

         (:macro-char #\_ 'read-c-statement nil)
         ,@(loop for i from (char-code #\a) upto (char-code #\z) collect `(:macro-char ,(code-char i) 'read-c-statement nil))
         ,@(loop for i from (char-code #\A) upto (char-code #\Z) collect `(:macro-char ,(code-char i) 'read-c-statement nil))
         )))
  (def-c-readtable))
