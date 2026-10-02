
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; MODULE      : text-navigator.scm
;; DESCRIPTION : Side tool for navigating through the sections of a document
;; COPYRIGHT   : (C) 2026  Jacopo Rizzuto
;;
;; This software falls under the GNU general public license version 3 or later.
;; It comes WITHOUT ANY WARRANTY WHATSOEVER. For details, see the file LICENSE
;; in the root directory or <http://www.gnu.org/licenses/gpl-3.0.html>.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(texmacs-module (text text-navigator)
  (:use (text text-structure)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Preferences
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-preferences
  ("section navigator" "off" noop)
  ("section navigator levels" "1" noop))

(tm-define (section-navigator-on?)
  (== (get-preference "section navigator") "on"))

(tm-define (extra-left-tools?)
  (or (section-navigator-on?) (former)))

(tm-define (toggle-section-navigator)
  (:synopsis "Toggle the section navigator in the left side tools")
  (:check-mark "v" section-navigator-on?)
  (with on? (not (section-navigator-on?))
    (set-boolean-preference "section navigator" on?)
    (with l (window->tools (current-window) :transient-left :left :bottom-left)
      (show-side-tools 1 (or on? (nnull? l))))
    (update-menus)))

(define (section-navigator-close)
  (when (section-navigator-on?)
    (toggle-section-navigator)))

(define (section-navigator-levels)
  (with s (get-preference "section navigator levels")
    (or (string->number s) 100)))

(tm-define (set-section-navigator-levels s)
  (set-preference "section navigator levels" (if (== s "All") "all" s))
  (update-menus))

(define (section-navigator-levels-string)
  (with s (get-preference "section navigator levels")
    (if (string->number s) s "All")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Collecting the sections
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (section-rank s)
  (with l (tree-label s)
    (cond ((in? l '(part part*)) 0)
          ((in? l '(chapter chapter* appendix appendix*)) 1)
          ((in? l '(section section*)) 2)
          ((in? l '(subsection subsection*)) 3)
          ((in? l '(subsubsection subsubsection*)) 4)
          ((in? l '(paragraph paragraph*)) 5)
          (else 6))))

;; converting titles to strings is slow (about 1 ms each), so the strings
;; are remembered for each title
(define title-table (make-ahash-table))
(define title-count 0)

(define (shorten s n)
  (if (<= (string-length s) n) s
      (let* ((r (substring s 0 n))
             (i (string-search-backwards "<" n r))
             (j (string-search-backwards ">" n r)))
        ;; do not cut a Cork escape such as <#20AC> in two
        (string-append (if (and (>= i 0) (> i j)) (substring r 0 i) r)
                       "..."))))

(define (section-title s)
  (let* ((key (list (tree-label s) (tree->stree (tree-ref s 0))))
         (old (ahash-ref title-table key)))
    (or old
        (with new (shorten (tm/section-get-title-string s #f) 50)
          ;; titles being edited add new keys: start afresh now and then
          (set! title-count (+ title-count 1))
          (when (> title-count 5000)
            (set! title-table (make-ahash-table))
            (set! title-count 0))
          (ahash-set! title-table key new)
          new))))

(define (path-before? p c)
  ;; the tree at path @p starts before the cursor path @c (or contains it)
  (cond ((null? p) #t)
        ((null? c) #f)
        ((< (car p) (car c)) #t)
        ((> (car p) (car c)) #f)
        (else (path-before? (cdr p) (cdr c)))))

(define (section-navigator-entries)
  ;; list of (section depth current? in-branch?) in document order
  (let* ((l (tree-search-sections (buffer-tree)))
         (v (list->vector l))
         (n (vector-length v))
         (ranks (list->vector (map section-rank l)))
         (top (if (null? l) 0 (apply min (vector->list ranks))))
         (parents (make-vector n #f))
         (c (cursor-path))
         (cur #f))
    ;; parent of each section, and the section the cursor is in
    (let loop ((i 0) (stack '()))
      (when (< i n)
        (let* ((r (vector-ref ranks i))
               (st (list-drop-while stack
                     (lambda (j) (>= (vector-ref ranks j) r)))))
          (vector-set! parents i (and (pair? st) (car st)))
          (with p (tree->path (vector-ref v i))
            (when (and p c (path-before? p c)) (set! cur i)))
          (loop (+ i 1) (cons i st)))))
    ;; the current section and its ancestors
    (let ((branch (make-vector n #f))
          (levels (section-navigator-levels)))
      (let up ((i cur))
        (when i
          (vector-set! branch i #t)
          (up (vector-ref parents i))))
      (let loop ((i (- n 1)) (r '()))
        (if (< i 0) r
            (let* ((par (vector-ref parents i))
                   (level (- (vector-ref ranks i) top))
                   (show? (or (< level levels) (not par)
                              (vector-ref branch i)
                              (and par (vector-ref branch par)))))
              (loop (- i 1)
                    (if show?
                        (cons (list (vector-ref v i)
                                    (let depth ((j par) (d 0))
                                      (if j (depth (vector-ref parents j) (+ d 1))
                                          d))
                                    (== i cur)
                                    (vector-ref branch i))
                              r)
                        r))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; The side tool
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (entry-label e)
  ;; the current section is marked with a triangle
  (with (s depth current? branch?) e
    `(verbatim ,(string-append (make-string (* 3 depth) #\space)
                               (if current? "<#25B8> " "")
                               (section-title s)))))

(define (entry-kind e)
  (with (s depth current? branch?) e
    (cond (current? 'current) (branch? 'branch) (else 'other))))

(define (section-navigator-go s)
  ;; give the focus back to the document first, otherwise the view does not
  ;; scroll to the new cursor position
  (keyboard-focus-on "canvas")
  (delayed
    (:idle 1)
    (when (tree->path s)
      (tree-go-to s 0 :start))))

(define (section-navigator-check-visible win)
  ;; the left side tools are hidden in new windows: show them again
  (when (and (== win (current-window)) (not (visible-side-tools? 1)))
    (delayed
      (:idle 10)
      (when (section-navigator-on?)
        (show-side-tools 1 #t)))))

(tm-widget (section-navigator-widget win)
  (division "title"
    (hlist
      (text "Sections")
      >>
      (division "plain"
        ("x" (section-navigator-close)))))
  (hlist
    (text "Levels:") //
    (enum (set-section-navigator-levels answer)
          '("1" "2" "3" "4" "All")
          (section-navigator-levels-string) "5em")
    >>)
  ===
  (with l (begin
            (section-navigator-check-visible win)
            (section-navigator-entries))
    (if (null? l)
        (hlist (text "No sections") >>)
        (glue #f #t 0 0))
    (if (nnull? l)
        (resize '("200px" "300px" "600px") '("100px" "400px" "10000px")
          (scrollable
            (division "plain"
              (vertical
                (for (e l)
                  ;; the current section is checked, and bold like its ancestors
                  (if (== (entry-kind e) 'current)
                      (bold
                        ((check (eval (entry-label e)) "v" #t)
                         (section-navigator-go (car e)))))
                  (if (== (entry-kind e) 'branch)
                      (bold
                        ((eval (entry-label e)) (section-navigator-go (car e)))))
                  (if (== (entry-kind e) 'other)
                      ((eval (entry-label e)) (section-navigator-go (car e)))))
                (glue #f #t 0 0))))))))
