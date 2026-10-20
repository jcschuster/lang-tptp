% THF: typed higher-order form.
thf(i_type, type, i: $tType).
thf(f_type, type, f: i > i > $o).
thf(lambda, axiom, ( ^ [X: i] : ( f @ X @ X ) ) = ( ^ [Y: i] : ( f @ Y @ Y ) )).
thf(choice, axiom, ( @+ [X: i] : ( f @ X @ X ) ) = c).
thf(big, axiom, ( !! @ ( ^ [X: i] : $true ) )).
thf(connective_term, axiom, ( (&) @ $true @ $false )).
thf(let, axiom, $let(g: i > i, g @ X := X, g @ c = c)).
thf(sequent, axiom, [a] --> [b]).
