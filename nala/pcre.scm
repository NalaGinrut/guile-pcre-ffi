;;  Copyright (C) 2015
;;      "Mu Lei" known as "NalaGinrut" <NalaGinrut@gmail.com>
;;  This file is free software: you can redistribute it and/or modify
;;  it under the terms of the GNU General Public License as published by
;;  the Free Software Foundation, either version 3 of the License, or
;;  (at your option) any later version.

;;  This file is distributed in the hope that it will be useful,
;;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;  GNU General Public License for more details.

;;  You should have received a copy of the GNU General Public License
;;  along with this program.  If not, see <http://www.gnu.org/licenses/>.

(define-module (nala pcre)
  #:use-module (rnrs)
  #:use-module (system foreign)
  #:export (new-pcre
            pcre-match
            pcre-get-substring
            pcre-search))

(define (make-blob-pointer len)
  (bytevector->pointer (make-bytevector len)))

(define pcre-ffi (dynamic-link "libpcre"))

(define %pcre-compile2
  (pointer->procedure '*
                       (dynamic-func "pcre_compile2" pcre-ffi)
                       (list '* int '* '* '* '*)))

(define %pcre-compile
  (pointer->procedure '*
                       (dynamic-func "pcre_compile" pcre-ffi)
                       (list '* int '* '* '*)))

(define %pcre-exec
  (pointer->procedure int
                      (dynamic-func "pcre_exec" pcre-ffi)
                      (list '* '* '* int int int '* int)))

(define %pcre-study
  (pointer->procedure '*
                      (dynamic-func "pcre_study" pcre-ffi)
                      (list '* int '*)))

(define %pcre-get-substring
  (pointer->procedure '*
                      (dynamic-func "pcre_get_substring" pcre-ffi)
                      (list '* '* int int '*)))

(define %pcre-free-study
  (pointer->procedure void
                      (dynamic-func "pcre_free_study" pcre-ffi)
                      (list '*)))

(define %pcre-free-substring
  (pointer->procedure void
                      (dynamic-func "pcre_free_substring" pcre-ffi)
                      (list '*)))

(define-record-type pcre
  (fields
   errptr
   (mutable strptr)
   (mutable ovector)
   (mutable matched)
   (mutable code)
   (mutable extra)))
   
(define (%new-pcre)
  (make-pcre (make-blob-pointer uint64) ; errptr
             #f #f 0 #f #f))

(define* (new-pcre re #:optional (options 0))
  (let ((reptr (string->pointer re))
        (errcodeptr (make-blob-pointer int))
        (erroffset (make-blob-pointer int))
        (tableptr %null-pointer)
        (pcre (%new-pcre)))
    ;; FIXME: add exceptional handling
    (pcre-code-set! pcre
                    (%pcre-compile2 reptr options errcodeptr
                                    (pcre-errptr pcre) erroffset tableptr))
    pcre))

(define* (pcre-match pcre str #:key (study-options 0) (exec-options 0)
                     (ovecsize 30) (offset 0))
  (let ((extra (%pcre-study (pcre-code pcre) study-options (pcre-errptr pcre)))
        (strptr (string->pointer str))
        (ovector (make-blob-pointer (* int ovecsize))))
    (pcre-matched-set! pcre
                       (%pcre-exec (pcre-code pcre)
                                   extra
                                   strptr
                                   (string-length str)
                                   offset
                                   exec-options
                                   ovector
                                   ovecsize))
    (pcre-ovector-set! pcre ovector)
    (pcre-strptr-set! pcre strptr)
    (%pcre-free-study extra)
    pcre))

(define (pcre-get-substring pcre index)
  (let ((strptr (pcre-strptr pcre))
        (ovector (pcre-ovector pcre))
        (matched (pcre-matched pcre))
        (buf (make-blob-pointer uint64)))
    (%pcre-get-substring strptr ovector matched index buf)
    (let ((ret (pointer->string (dereference-pointer buf))))
      (%pcre-free-substring (dereference-pointer buf))
      ret)))

(define* (pcre-search pcre str #:key (study-options 0) (exec-options 0)
                      (exclude " "))
  (define (trim s)
    (string-trim-both s (lambda (x) (string-contains exclude (string x)))))
  (define len (string-length str))
  (let lp((i 0) (ret '()))
    (cond
     ((>= i len) (and ret (reverse ret)))
     (else
      (pcre-match pcre str #:study-options study-options #:exec-options exec-options #:offset i)
      (if (<= (pcre-matched pcre) 0)
          (lp len #f)
          (let ((hit (pcre-get-substring pcre 1))
                (sublen (string-length (pcre-get-substring pcre 0))))
            (lp (+ i sublen) (cons (trim hit) ret))))))))
