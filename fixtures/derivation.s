% SZS status Theorem for SYN000+1
% SZS output start CNFRefutation for SYN000+1
fof(a1, axiom, p, file('SYN000+1.p', a1)).
fof(c1, conjecture, p, file('SYN000+1.p', c1)).
fof(n1, negated_conjecture, ~ p, inference(negated_conjecture, [status(cth)], [c1])).
cnf(n2, negated_conjecture, ~ p, inference(cnf_transformation, [], [n1])).
cnf(f1, plain, $false, inference(resolution, [status(thm), theory(equality)], [a1, n2:[bind(X, $fot(a))]])).
fof(intro, plain, q, introduced(definition, [new_symbols(definition, [q])], [])).
fof(file, axiom, p, file('foo.p')).
fof(inference, plain, p, inference(rule, [], [file, inference])).
cnf(u1, axiom, p, unknown).
fof(lang, plain, p, inference(rule, [], [a1:[$fof(p), $cnf(p), $fot(a)]])).
% SZS output end CNFRefutation for SYN000+1
