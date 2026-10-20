%------------------------------------------------------------------------------
% FOF: first-order form, with the usual connectives and quantifiers.
%------------------------------------------------------------------------------
fof(reflexivity, axiom, ! [X] : X = X).
fof(symmetry, axiom, ! [X, Y] : ( X = Y => Y = X )).
fof(connectives, hypothesis,
    ( ( p & q ) | ~ r | ( s <=> t ) | ( a <~> b ) | ( c ~| d ) | ( e ~& f ) | ( g <= h ) )).
fof(quoted, axiom, 'a quoted atom'('It\'s', "distinct object") != $true).
fof(numbers, axiom, p(0, -1, 1/2, -3/4, 1.5, -2.5e10, 1E-3)).
fof(defined, axiom, ( $true | $false | $distinct(a, b) )).
fof(fof, axiom, fof).
fof(conjecture_1, conjecture, ? [Y] : p(Y)).
