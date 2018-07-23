Generalizable Variable E.
Typeclasses eauto := 6.

From QuickChick Require Import QuickChick.

Require Import Ascii.
Require Import String.
Require Import List.
Require Import PArith.
Require Fin.
Import ListNotations.

From Custom Require Import Show.

Require Import DeepWeb.Free.Monad.Free.
Import MonadNotations.
Require Import DeepWeb.Free.Monad.Common.
Import SumNotations.
Import NonDeterminismBis.

Require Import DeepWeb.Lib.Util.

(* begin hide *)
Set Warnings "-extraction-opaque-accessed,-extraction".
Open Scope string_scope.
(* end hide *)

(** The type of observations that can be made by the spec. *)
(* The observations are parameterized by a type of "hints" that
   can be used to help generating test cases. *)
(* TODO: decide whether to restore hints. *)
(* SHOW *)
Inductive observerE : Type -> Type :=
| (* Observe the creation of a new connection *)
  ObsConnect : observerE connection_id

| (* Observe a byte going into the server on a particular
     connection *)
  ObsToServer : connection_id -> observerE byte

  (* Observe a byte going out of the server.  This action can return
     [None], indicating a "hole" as a way to hypothesize that the
     server sent some message we haven't yet received, so we can keep
     testing the rest of the trace.  (The spec writer must be careful
     that, if a trace with holes is rejected, then it must also be for
     any substitution of actual values for those holes.) *)
| ObsFromServer : connection_id -> observerE (option byte).

Definition obs_connect {E} `{observerE -< E} : M E connection_id :=
  embed ObsConnect.

Definition obs_to_server {E} `{observerE -< E} :
  connection_id -> M E byte :=
  embed ObsToServer.

Definition obs_from_server {E} `{observerE -< E} :
  connection_id -> M E (option byte) :=
  embed ObsFromServer.
(* /SHOW *)

(* Make an assertion on a value, if it exists. *)
Definition assert_on {E A} `{nondetE -< E}
           (r : string) (oa : option A) (check : A -> bool) :
  M E unit :=
  match oa with
  | None => ret tt
  | Some a =>
    if check a then ret tt else fail ("assertion failed: " ++ r)
  end.

(* Helper for [obs_msg_to_server] *)
CoFixpoint obs_msg_to_server' `{observerE -< E}
           (c : connection_id) (n : nat) (k : bytes -> M E bytes) :
  M E bytes :=
  match n with
  | O => k ""
  | S n =>
    b <- ^ ObsToServer c;;
    obs_msg_to_server' c n (fun bs => k (String b bs))
  end.

(* Observe a complete message sent to the server. *)
Definition obs_msg_to_server `{observerE -< E}
           (buffer_size : nat)
           (c : connection_id) : M E bytes :=
  obs_msg_to_server' c buffer_size ret.

(* Observe a complete message received from the server. *)
CoFixpoint obs_msg_from_server `{observerE -< E} `{nondetE -< E}
           (c : connection_id) (msg : bytes) :
  M E unit :=
  match msg with
  | "" => ret tt
  | String b0 msg =>
    ob <- ^ ObsFromServer c;;
    assert_on "bytes must match" ob (fun b1 => b1 = b0 ?);;
    obs_msg_from_server c msg
  end.

(* Equality comparison, return a proof of equality of the
   indices (this could be generalized to a complete decision
   procedure). *)
Definition observer_eq {X Y : Type}
           (e1 : observerE X) (e2 : observerE Y) :
  option (X = Y) :=
  match e1, e2 with
  | ObsConnect, ObsConnect => Some eq_refl
  | ObsToServer c, ObsToServer c'
  | ObsFromServer c, ObsFromServer c' =>
    if c = c' ? then Some eq_refl else None
  | _, _ => None
  end.

Definition coerce {X Y : Type} (p : X = Y) (x : X) : Y :=
  match p in eq _ Y return Y with
  | eq_refl => x
  end.

Definition specE := nondetE +' observerE.

Definition itree_spec := M specE unit.

(* The spec can be viewed as a set of traces. *)

(* An [event] is an observer action together with its result. *)
Inductive event :=
| Event : forall X, observerE X -> X -> event.

Arguments Event {X}.

Definition show_event (ev : event) :=
  match ev with
  | Event _ e x =>
    match e in observerE X return X -> _ with
    | ObsConnect => fun '(Connection c) => show c ++ " !"
    | ObsToServer (Connection c) => fun b =>
      show c ++ " <-- """ ++ pretty_char b ++ """"
    | ObsFromServer (Connection c) => fun ob =>
      show c ++ " --> " ++
        match ob with
        | None => "?"
        | Some b => """" ++ pretty_char b ++ """"
        end
    end x
  end.

Instance Show_event : Show event :=
  { show := show_event }.

Definition trace := list event.

Definition match_obs {X Y R S : Type}
           (e0 : observerE X)
           (e1 : observerE Y)
           (cont : S -> R)
           (fail_ : R) :
  X -> (Y -> S) -> R :=
  match e0 in observerE X, e1 in observerE Y
        return X -> (Y -> _) -> _ with
  | ObsConnect, ObsConnect => fun x k => cont (k x)
  | ObsToServer c, ObsToServer c' => fun x k =>
    if c = c' ? then
      cont (k x)
    else
      fail_
  | ObsFromServer c, ObsFromServer c' => fun x k =>
    if c = c' ? then
      cont (k x)
    else
      fail_
  | _, _ => fun _ _ => fail_
  end.

(* [exists x, k x = true] *)
Definition nondet_exists {X : Type}
           (e : nondetE X) (k : X -> bool) : bool :=
  match e in nondetE X' return (X' -> X) -> _ with
  | Or n _ =>
    (fix go n0 : (Fin.t n0 -> X) -> bool :=
       match n0 with
       | O => fun _ => false
       | S n0 => fun f => k (f Fin.F1) || go n0 (fun m => f (Fin.FS m))
       end) n
  end%bool (fun x => x).

(* SHOW *)
(* BCP: But probably this will move up to the top-level interface --
   no need to show internals *)
(* Basically, a trace [t] belongs to a tree if there is a path
   through the tree (a list of [E0] effects) such that its
   restriction to [observerE] events is [t].
   Because trees are coinductive (in particular, they can contain
   arbitrary sequences of [Tau] or [Vis] with invisible effects),
   it is not possible to decide whether a trace matches the tree.
   Thus we add a [fuel] parameter assumed to be "big enough"
   for the result to be reliable. *)
Fixpoint is_trace_of
         (max_depth : nat) (s : itree_spec) (t : trace) : bool :=
  match max_depth with
  | O => false
  | S max_depth =>
    match s, t with
    | Tau s, t => is_trace_of max_depth s t
    | Ret tt, [] => true
    | Ret tt, _ :: _ => false
    | Vis _ (| e1 ) k, Event _ e0 x :: t =>
      match_obs e0 e1 (fun s => is_trace_of max_depth s t)
                false x k
    | Vis _ (| e1 ) k, [] => true
    (* The trace belongs to the tree [s] *)
    | Vis _ ( _Or |) k, t =>
      nondet_exists _Or (fun b => is_trace_of max_depth (k b) t)
    end
  end.

(* Some notations to make traces readable. *)
Module EventNotations.
Delimit Scope event_scope with event.

(* Connection [c] is open. *)
Notation "c !" := (Event ObsConnect (Connection c))
(at level 30) : event_scope.

(* Byte [b] goes to the server on connection [c]. *)
Notation "c <-- b" := (Event (ObsToServer (Connection c)) b%char)
(at level 30) : event_scope.

(* Byte [b] goes out of the server on connection [c]. *)
Notation "c --> b" := (Event (ObsFromServer (Connection c)) (Some b%char))
(at level 30) : event_scope.

(* Unknown byte goes out of the server on connection [c]. *)
Notation "c --> ?" := (Event (ObsFromServer (Connection c)) None)
(at level 30) : event_scope.

Open Scope event_scope.
End EventNotations.


(* The traces produced by the tree [swap_spec] are very structured,
   with sequences of bytes sent and received alternating tidily.
   However, in general:
   - the network may reorder some messages, so the traces
     we actually see during testing will not be directly
     checkable using [is_trace_of], they must be descrambled
     first;
   - a server implementation may also want to reorder responses
     differently for performance and other practical reasons;
     here we will consider a server correct if it cannot be
     distinguished over the network from a server that actually
     produces the same traces as the spec above. *)

(* The network's behavior is accounted for in
   [Lib/SimpleSpec_Descramble.v] *)
(* /SHOW *)
