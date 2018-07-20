(** * Extract: Running 
On my machine, in the byte-code interpreter this prints,


Insert and lookup 1000000 random integers in 1.076 seconds.
Insert and lookup 20000 random integers in 0.015 seconds.
Insert and lookup 20000 consecutive integers in 5.054 seconds.


You can compile and run this with the ocaml native-code compiler by:

ocamlopt searchtree.mli searchtree.ml -open Searchtree test_searchtree.ml -o test_searchtree
./test_searchtree


On my machine this prints,

Insert and lookup 1000000 random integers in 0.468 seconds.
Insert and lookup 20000 random integers in 0. seconds.
Insert and lookup 20000 consecutive integers in 0.374 seconds.
*)

(* ################################################################# *)
(** * Unbalanced Binary Search Trees *)
(** Why is the performance of the algorithm so much worse when the
   keys are all inserted consecutively?  To examine this, let's compute
   with some searchtrees inside Coq.  We cannot do this with the search
   trees defined thus far in this file, because they use a key-comparison
   function [ltb]  that is abstract and uninstantiated (only during
   Extraction to Ocaml does [ltb] get instantiated).

   So instead, we'll use the SearchTree module, 
   where everything runs inside Coq. *)

Require SearchTree.
Module Experiments.
Open Scope nat_scope.
Definition empty_tree := SearchTree.empty_tree nat.
Definition insert := SearchTree.insert nat.
Definition lookup := SearchTree.lookup nat 0.
Definition E := SearchTree.E nat.
Definition T := SearchTree.T nat.

Goal insert 5 1 (insert 4 1 (insert 3 1 (insert 2 1 (insert 1 1 (insert 0 1 empty_tree))))) <> E.
simpl. fold E; repeat fold T.

(** Look here!  The tree is completely unbalanced.  Looking up [5] will take linear time.
   That's why the runtime on consecutive integers is so bad. *)

Abort.

(* ################################################################# *)
(** * Balanced Binary Search Trees *)

(** To achieve robust performance (that stays N log N for a sequence
    of N operations, and does not degenerate to N*N), we must keep the
    search trees balanced.  The next chapter, [Redblack],
    implements that idea. *)

End Experiments.
