#lang racket/base
(require racket/contract
         racket/match
         racket/set
         datalog/ast
         datalog/eval
         racklog
         racket/pretty
         (only-in racklog/lang/lang
                  racklog-answers->literals))

(provide/contract
 [compile-program (program/c . -> . syntax?)]
 [compile-statement (statement/c . -> . syntax?)])

;; The result of `compile-program` already has bindings for
;; everything that it uses, so it can be incorprated into
;; a context without any binding --- and that context must
;; have no bindings if it would create ambiguities --- but
;; the context must ensure that `rackloc/lang/lang` is
;; instantiated.
(define (compile-program p)
  (with-syntax ([(pred ...)
                 (map pred->stx
                      (set->list
                       (for/seteq ([s (in-list p)]
                                   #:when (assertion? s))
                                  (coerce-sym 
                                   (clause-predicate (assertion-clause s))))))])
    (quasisyntax
     (#%module-begin
      (require racklog
               (only-in racket/base #%datum)
               datalog/eval) 
      (define pred %empty-rel)
      ...
      (provide pred ...)
      #,@(map compile-statement p)))))

(define coerce-sym
  (match-lambda
   [(predicate-sym _ s)
    s]
   [(? symbol? s)
    s]))

(define (sym-set->id-list s)
  (map (lambda (sym) (datum->syntax #f sym))
       (set->list s)))

(define pred-cache (make-hasheq))
(define (pred->stx maybe-p)
  (define p (coerce-sym maybe-p))
  (hash-ref! pred-cache p
             (λ ()
               (datum->syntax #f p))))

(define compile-statement
  (match-lambda
    [(assertion srcloc c)
     (define srcstx (datum->syntax #f 'x srcloc))
     (quasisyntax/loc srcstx
       (%assert! #,(pred->stx (clause-predicate c))
                 #,(sym-set->id-list (clause-variables c))
                 [#,(compile-clause-head c)
                  #,@(compile-clause-body c)]))]
    [(retraction srcloc c)
     (define srcstx (datum->syntax #f 'x srcloc))
     ; XXX implement
     (raise-syntax-error 'racklog "Retraction is not yet supported in racklog" srcstx)]
    [(query srcloc l)
     (define srcstx (datum->syntax #f 'x srcloc))
     (quasisyntax/loc srcstx
       (print-questions
        (racklog-answers->literals
         #,l
         (%find-all #,(sym-set->id-list (literal-variables l))
                    #,(compile-literal l)))))]))

(define (clause-predicate c)
  (literal-predicate (clause-head c)))

(define literal-variables
  (match-lambda
    [(literal _ _ ts)
     (for/seteq ([t (in-list ts)]
                 #:when (variable? t))
                (coerce-sym (variable-sym t)))]))

(define clause-variables
  (match-lambda
    [(clause _ h bs)
     (for/fold ([s (seteq)])
       ([l (in-list (list* h bs))])
       (set-union s (literal-variables l)))]))

(define compile-clause-head
  (match-lambda
    [(clause srcloc head _)
     (define srcstx (datum->syntax #f 'x srcloc))
     (quasisyntax/loc srcstx
       #,(compile-literal-terms head))]))

(define compile-clause-body
  (match-lambda
    [(clause _ _ body)
     (map compile-literal body)]))

(define compile-literal
  (match-lambda
    [(literal srcloc '= (and ts (app length 2)))
     (define srcstx (datum->syntax #f 'x srcloc))
     (quasisyntax/loc srcstx
       (%= #,@(compile-terms ts)))]
    [(literal srcloc pred ts)
     (define srcstx (datum->syntax #f 'x srcloc))
     (quasisyntax/loc srcstx
       (#,(pred->stx pred) #,@(compile-terms ts)))]))

(define (compile-literal-terms l)
  (compile-terms (literal-terms l)))

(define (compile-terms ts)
  (map compile-term ts))

(define compile-term
  (match-lambda
    [(variable srcloc sym)
     (datum->syntax #f (coerce-sym sym) srcloc)]
    [(constant srcloc (? string? str))
     (datum->syntax #f str srcloc)]
    [(constant srcloc (? symbol? sym))
     (define srcstx (datum->syntax #f 'x srcloc))
     (quasisyntax/loc srcstx
       '#,sym)]))
