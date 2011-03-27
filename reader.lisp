(in-package #:vacietis.reader)
(in-readtable vacietis)

;;; this makes things a lot less hairy

(defvar %in)

;;; error reporting

(define-condition c-reader-error (reader-error simple-error)
  ((line-number :reader line-number :initarg :line-number))
  (:default-initargs :line-number *line-number*))

(defun read-error (msg &rest args)
  (error (make-condition 'c-reader-error
                         :stream %in
                         :format-control (format nil "Error reading from C stream at line ~a: ~?"
                                                 *line-number* msg args))))

;;; basic stream stuff

(defvar *line-number* 0)

(defun c-read-char ()
  (let ((c (read-char %in nil 'end)))
    (when (eql c #\Newline)
      (incf *line-number*))
    c))

(defun c-unread-char (c)
  (when (eql c #\Newline)
    (decf *line-number*))
  (unread-char c %in))

(defun c-read-line ()
  (incf *line-number*)
  (read-line %in))

(defmacro loop-reading (&body body)
  `(loop with c do (setf c (c-read-char))
        ,@body))

(defun whitespace? (c)
  (or (char= c #\Space) (char= c #\Tab) (char= c #\Newline)))

(defun next-char (&optional (eof-error? t))
  (loop-reading
     while (if (eq 'end c)
               (when eof-error?
                 (read-error "Unexpected end of file"))
               (whitespace? c))
     finally (return c)))

(defun make-string-buffer ()
  (make-array '(3) :adjustable t :fill-pointer 0 :element-type 'character))

(defun slurp-while (predicate)
  (let ((string-buffer (make-string-buffer)))
    (loop-reading
       while (and (not (eq c 'end)) (funcall predicate c))
       do (vector-push-extend c string-buffer)
       finally (unless (eq c 'end) (c-unread-char c)))
    string-buffer))

;;; numbers

(defun read-octal ()
  (parse-integer (slurp-while (lambda (c) (char<= #\0 c #\7))) :radix 8))

(defun read-hex ()
  (parse-integer (slurp-while (lambda (c) (or (char<= #\0 c #\9) (char-not-greaterp #\A c #\F)))) :radix 16))

(defun read-float (prefix separator)
  (let ((*readtable* (find-readtable :common-lisp)))
    (read-from-string
     (format nil "~d~a~a" prefix separator
             (slurp-while (lambda (c) (find c "0123456789+-eE" :test #'char=)))))))

(defun read-decimal (c0) ;; c0 must be #\1 to #\9
  (labels ((digit-value (c) (- (char-code c) 48)))
    (let ((value (digit-value c0)))
      (loop-reading
           (cond ((eq c 'end) (return value))
                 ((char<= #\0 c #\9) (setf value (+ (* 10 value) (digit-value c))))
                 ((or (char-equal c #\E) (char= c #\.)) (return (read-float value c)))
                 (t (c-unread-char c) (return value)))))))

(defun read-c-number (c)
  (prog1 (if (char= c #\0)
             (let ((next (peek-char nil %in)))
               (if (digit-char-p next 8)
                   (read-octal)
                   (case next
                     ((#\X #\x) (c-read-char) (read-hex))
                     (#\.       (c-read-char) (read-float 0 #\.))
                     (otherwise 0))))
             (read-decimal c))
    (loop repeat 2 do (when (find (peek-char nil %in nil nil) "ulf" :test #'eql)
                        (c-read-char)))))

;;; string and chars (caller has to remember to discard leading #\L!!!)

(defun read-char-literal (c)
  (if (char= c #\\)
      (let ((c (c-read-char)))
        (code-char (case c
                     (#\a 7)
                     (#\f 12)
                     (#\n 10)
                     (#\r 13)
                     (#\t 9)
                     (#\v 11)
                     (#\x (read-hex))
                     (otherwise (if (char<= #\0 c #\7)
                                    (progn (c-unread-char c) (read-octal))
                                    (char-code c))))))
      c))

(defun read-character-constant ()
  (prog1 (read-char-literal (c-read-char))
    (unless (char= (c-read-char) #\')
      (read-error "Junk in character constant"))))

(defun read-c-string (c1)
  (declare (ignore c1))
  (let ((string (make-string-buffer)))
    (loop-reading
       (if (char= c #\") ;; c requires concatenation of adjacent string literals, retardo
           (progn (setf c (next-char nil))
                  (unless (eql c #\")
                    (unless (eq c 'end) (c-unread-char c))
                    (return string)))
           (vector-push-extend (read-char-literal c) string)))))

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

(defparameter *assignment-ops* '(= += -= *= /= %= <<= >>= &= ^= |\|=|))

(defparameter *binary-ops-table*
  '(|\|\|| ; or
    &&     ; and
    |\||   ; logior
    ^      ; logxor
    &      ; logand
    == !=
    < > <= >=
    << >>  ; ash
    + -
    * / &))

;; leave this to implementation
;; (defun convert-assignment-op (aop lvalue rvalue)
;;   (if (eql '= aop)
;;       `(setf ,lvaue ,rvalue)
;;       `(setf ,lvalue (,(intern (reverse (subseq (reverse (symbol-name aop)) 1))) ,lvalue ,rvalue))))

(defun parse-nary (args)
  (flet ((split-recurse (x)
           (list (elt args x) (parse-infix (subseq args 0 x)) (parse-infix (subseq args (1+ x))))))
    (acond ((position-if (lambda (x) (member x *assignment-ops*)) args)
            (split-recurse it))
           ((position '? args)
            (let ((?pos it))
              (append (list 'if (parse-infix (subseq args 0 ?pos)))
                      (aif (position '|:| args)
                           (list (parse-infix (subseq args (1+ ?pos) it)) (parse-infix (subseq args (1+ it))))
                           (read-error %in "Error parsing ?: trinary operator in: ~A" args)))))
           ((loop for op in *binary-ops-table* thereis (position op args))
            (split-recurse it))
           (t (read-error %in "Error parsing expression: ~A" args)))))

(defun parse-unary (a b)
  (aif (find a '(++ -- ! ~))
       (list it b)
       (case a
         (* `(deref* ,b))
         (& `(addr& ,b))
         (t (case b
              (++ `(post++ ,a))
              (-- `(post-- ,a))
              (t  `(,a ,@(if (listp b) b (list b))))))))) ;; assume funcall for now

(defun parse-infix (args)
  (if (consp args)
      (case (length args)
        (1 (parse-infix (car args)))
        (2 (parse-unary (parse-infix (first args)) (parse-infix (second args))))
        (t (parse-nary args)))
      args))

;;; statements

(defun read-c-block (c)
  (if (eql c #\{)
      (cons 'progn
            (loop with c do (setf c (next-char))
                  until (eql c #\}) collect (read-c-statement c)))
      (read-error "Expected opening brace '{' but found '~A'" c)))

(defun c-type? (identifier)
  ;; and also do checks for struct, union, enum and typedef types
  (member identifier '(int static void const signed unsigned short long float double)))

(defun next-exp ()
  (read-c-exp (next-char)))

(defun read-control-flow-statement (statement)
  (case statement
    (if (list 'if
              (parse-infix (next-exp))
              (let ((next-char (next-char)))
                (if (eql next-char #\{)
                    (read-c-block next-char)
                    (read-c-statement next-char)))))
    (return (list 'return (read-c-statement (next-char))))))

(defun read-comma-separated-list (open-delimiter)
  (let ((close-delimiter (ecase open-delimiter (#\( #\)) (#\{ #\}))))
    (loop with c do (setf c (next-char))
          until (eql c close-delimiter)
          unless (eql #\, c) collect (read-c-exp c))))

(defun read-function (name)
  `(defun ,name ,(remove-if #'c-type? ;; do the right thing with type declarations
                            (read-comma-separated-list (next-char)))
     ,(read-c-block (next-char))))

(defun read-variable (name)
  ;; have to deal with array declarations like *foo_bar[baz]
  `(defvar ,name)
  )

(defun read-declaration (token)
  (when (c-type? token)
    (let ((name (next-exp))) ;; throw away type info
      (if (eql #\( (peek-char t %in))
          (read-function name)
          (read-variable name)))))

(defun read-c-statement (c)
  (let ((next-token (read-c-exp c)))
    (or (read-declaration next-token)
        (read-control-flow-statement next-token)
        (parse-infix (cons next-token
                           (loop with c do (setf c (next-char))
                              until (eql c #\;) collect (read-c-exp c)))))))

(defun read-c-identifier (c)
  ;; assume inverted readtable (need to fix for case-preserving lisps)
  (let* ((raw-name (concatenate 'string (string c) (slurp-while (lambda (c) (or (eql c #\_) (alphanumericp c))))))
         (raw-name-alphas (remove-if-not #'alpha-char-p raw-name))
         (identifier-name (format nil (cond ((every #'upper-case-p raw-name-alphas) "~(~A~)")
                                            ((every #'lower-case-p raw-name-alphas) "~:@(~A~)")
                                            (t "~A"))
                                  raw-name)))
    (or (find-symbol identifier-name '#:vacietis.c) (intern identifier-name))))

(defparameter *ops*
  '(= += -= *= /= %= <<= >>= &= ^= |\|=| ? |:| |\|\|| && |\|| ^ & == != < > <= >= << >> ++ -- + - * / ! ~ -> |.|))

;; this would be really simple if streams could unread more than one char
;; also if CLISP didn't have bugs w/unread-char after peek and near EOF
(defun match-longest-op (one)
  (flet ((seq-matches (&rest chars)
           (find (make-array (length chars) :element-type 'character :initial-contents chars)
                 *ops* :test #'string= :key #'symbol-name)))
    (let* ((two       (c-read-char))
           (two-match (seq-matches one two)))
      (if two-match
          (let ((three-match (seq-matches one two (peek-char nil %in))))
            (if three-match
                (progn (c-read-char) three-match)
                two-match))
          (progn (c-unread-char two)
                 (seq-matches one))))))

(defun read-c-exp (c)
  (or (match-longest-op c)
      (cond ((digit-char-p c) (read-c-number c))
            ((or (eql c #\_) (alpha-char-p c)) (read-c-identifier c))
            (t
             (case c
               ;; (#\# (let ((*in-preprocessor-p* t)) ;; preprocessor
               ;;        (read-c-macro stream)))
               ;; (#\/ (c-read-char stream) ;; comment
               ;;      (case (c-read-char stream)
               ;;        (#\/ (c-read-line stream))
               ;;        (#\* (slurp-while stream
               ;;                          (let ((previous-char (code-char 0)))
               ;;                            (lambda (c)
               ;;                              (prog1 (not (and (char= previous-char #\*)
               ;;                                               (char= c #\/)))
               ;;                                (setf previous-char c)))))
               ;;             (c-read-char stream))
               ;;        (otherwise (read-error stream "Expected comment"))))
               (#\" (read-c-string c))
               (#\( (read-comma-separated-list #\())
               (#\{ (read-delimited-list #\} t)) ;; initializer list
               (#\[ (list 'aref
                          (parse-infix (loop with c do (setf c (next-char))
                                          until (eql c #\]) collect (read-c-exp c))))))))))

;;; readtable

(defun read-c-toplevel (stream c)
  (let ((%in stream)
        (*line-number* 0))
    (read-c-statement c)))

(macrolet
    ((def-c-readtable ()
       `(defreadtable c-readtable
         (:case :invert)

         ;; unary and prefix operators
         ,@(loop for i in '(#\+ #\- #\~ #\! #\( #\& #\*) collect `(:macro-char ,i 'read-c-toplevel nil))

;         (:macro-char #\# 'read-c-macro nil)

         ;; numbers (should this be here?)
         ,@(loop for i from 0 upto 9 collect `(:macro-char ,(digit-char i) 'read-c-toplevel nil))

         ;; identifiers
         (:macro-char #\_ 'read-c-toplevel nil)
         ,@(loop for i from (char-code #\a) upto (char-code #\z) collect `(:macro-char ,(code-char i) 'read-c-toplevel nil))
         ,@(loop for i from (char-code #\A) upto (char-code #\Z) collect `(:macro-char ,(code-char i) 'read-c-toplevel nil))
         )))
  (def-c-readtable))
