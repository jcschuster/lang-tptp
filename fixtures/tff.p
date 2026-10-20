/* TFF: typed first-order form, with arithmetic and $let/$ite. */
tff(person_type, type, person: $tType).
tff(age_type, type, age: person > $int).
tff(pair_type, type, pair: ( $int * $int ) > $o).
tff(arith, axiom, ! [X: $int] : $less(X, $sum(X, 1))).
tff(polymorphic, type, list: $tType > $tType).
tff(poly_fn, type, nil: !>[A: $tType] : list(A)).
tff(ite, axiom, ! [X: $int] : $ite($greater(X, 0), p(X), q(X))).
tff(let, axiom, $let(c: $int, c := 3, $greater(c, 2))).
tff(tuple, axiom, [a, b] = [a, b]).
tff(subtype, type, nat << $int).
