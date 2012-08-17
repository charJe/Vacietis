(in-package #:vacietis.test.basic)
(in-readtable vacietis:vacietis)

(in-suite vacietis.test::basic-tests)

(eval-test addition0
  "1 + 2;"
  3)

(eval-test subtraction0
  "3-2;"
  1)

(eval-test global-var
  "int foobar = 10;
foobar;"
  10)

;; (eval-test for-loop0
;;   "int foobar;
;; for (int x = 0, foobar = 0; x <= 10; x++) foobar += x;
;; foobar;"
;;   55) ;; comes out to 0 because of foobar scope, bug or feature?

(eval-test for-loop1
  "int foobar = 0;
for (int x = 0; x <= 10; x++) foobar += x;
foobar;"
  55)

(eval-test string-literal
  "char foobar[] = \"foobar\";
foobar;"
  (string-to-char* "foobar"))

(eval-test h&s-while-string-copy
  "char source_pointer[] = \"foobar\", dest_pointer[7];
while ( *dest_pointer++ = *source_pointer++ );
dest_pointer - 7;"
  (string-to-char* "foobar"))

(eval-test define-foo
  "#define FOO 1
int x = FOO;
x;"
  1)

(eval-test define-foo1
  "#define foo 2
int baz = foo * 2;
baz;"
  4)

(eval-test define-foo2
  "#define foo 1 + 4
int baz = foo * 2;
baz;"
  9)

(eval-test preprocessor-if-1
  "#if 2 < 1
int baz = 5;
baz;
#endif"
  nil)

(eval-test preprocessor-if-2
  "int baz = 123;
#if 2 >= 1
baz = 456;
#endif
baz;"
  456)

(eval-test preprocessor-ifdef
  "#define FOOMAX
int baz = 1;
#ifdef FOOMAX
int baz = 2;
#endif
baz;"
  2)

(eval-test preprocessor-define-template
  "#define foo(x, y) x+y
foo(1,2);"
  3)

(eval-test sizeof-static-array
  "static char buf[10];
sizeof buf;"
  10)

(eval-test sizeof-int
  "int foo;
sizeof foo;"
  1)

(eval-test sizeof-int1
  "int foo1 = 120;
sizeof foo1;"
  1)

(eval-test sizeof0
  "char foobar;
sizeof (foobar);"
  1)

(eval-test sizeof1
  "long foobar;
1 + sizeof (foobar);"
  2)

(eval-test sizeof2
  "sizeof int;"
  1)

(eval-test sizeof3
  "sizeof (int);"
  1)

(eval-test if-then-else1
  "int baz;
if (2 < 1) {
  baz = 2;
} else {
  baz = 3;
}
baz;"
  3)

(eval-test if-then-none
  "int baz = 0;
if (2 < 1) {
  baz = 2;
}
baz;"
  0)

;;; fixme: literals and '' single quoting
;; (eval-test sizeof-literal
;;   "sizeof('c');"
;;   2)
