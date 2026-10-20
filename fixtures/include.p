% include directives, with and without a formula selection.
include('Axioms/SET001-0.ax').
include('Axioms/GRP001-0.ax', [left_identity, left_inverse]).
include('Axioms/GRP001-0.ax', *).
