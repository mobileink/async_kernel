open! Core_kernel.Std
open! Import
open! Deferred_std

type ('a, 'phantom) t =
  { current_value           : 'a Moption.t
  ; taken                   : unit Bvar.t
  ; mutable value_available : unit Ivar.t }
[@@deriving fields, sexp_of]

let value_available t = Ivar.read t.value_available

let is_empty t = Moption.is_none t.current_value

let invariant invariant_a _ (t : _ t) =
  Invariant.invariant [%here] t [%sexp_of: (_, _) t] (fun () ->
    let check f = Invariant.check_field t f in
    Fields.iter
      ~current_value:(check (Moption.invariant invariant_a))
      ~taken:(check (Bvar.invariant Unit.invariant))
      ~value_available:(check (fun value_available ->
        [%test_result: bool] (Ivar.is_full value_available)
          ~expect:(Moption.is_some t.current_value))))
;;

let peek t = Moption.get t.current_value

let peek_exn t =
  if is_empty t then failwith "Mvar.peek_exn called on empty mvar";
  Moption.get_some_exn t.current_value
;;

let sexp_of_t sexp_of_a _ t = [%sexp (peek t : a option)]

module Read_write = struct
  type nonrec 'a t = ('a, read_write) t [@@deriving sexp_of]

  let invariant invariant_a t = invariant invariant_a ignore t
end

module Read_only = struct
  type nonrec 'a t = ('a, read) t [@@deriving sexp_of]

  let invariant invariant_a t = invariant invariant_a ignore t
end

let read_only (t : _ Read_write.t) = (t :> _ Read_only.t)

let create () =
  { current_value   = Moption.create ()
  ; taken           = Bvar.create ()
  ; value_available = Ivar.create () }
;;

let take_nonempty t =
  assert (not (is_empty t));
  Bvar.broadcast t.taken ();
  let r = Moption.get_some_exn t.current_value in
  Moption.set_none t.current_value;
  t.value_available <- Ivar.create ();
  r
;;

let take_exn t =
  if is_empty t then failwith "Mvar.take_exn called on empty mvar";
  take_nonempty t;
;;

let take t =
  if is_empty t
  then None
  else Some (take_nonempty t)
;;

let set t v =
  Moption.set_some t.current_value v;
  Ivar.fill_if_empty t.value_available ();
;;

let update     t ~f = set t (f (peek     t))
let update_exn t ~f = set t (f (peek_exn t))

let taken t = Bvar.wait t.taken

let rec put t v =
  if is_empty t
  then (
    set t v;
    Deferred.unit)
  else (
    taken t
    >>= fun () ->
    put t v)
;;