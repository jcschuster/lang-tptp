% Generated test input; assertions point at the line above.

fof(ax1, axiom, ! [X] : p(X, $sum(1, c))).
% <- keyword
%  ^ punctuation.bracket
%   ^ label
%      ^ punctuation.delimiter
%        ^ keyword.modifier
%               ^ operator
%                  ^ variable
%                       ^ function
%                            ^ function.builtin
%                                 ^ number
%                                    ^ constant

tff(t, type, age: person > $int).
%            ^ constant
%                        ^ operator
%                          ^ type.builtin

cnf(c, plain, $$sk(X) | "obj", inference(res, [], [a])).
%             ^ function.macro
%                     ^ operator
%                       ^ string
%                              ^ keyword
%                                        ^ function

include('Axioms/SET001-0.ax').
% <- keyword
%       ^ string.special.path

thf(l, axiom, $let(g: i > i, g @ X := X, g @ c = c)).
%             ^ keyword
%                              ^ operator
%                                  ^ operator
