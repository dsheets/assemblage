(*
 * Copyright (c) 2014 Thomas Gazagnaire <thomas@gazagnaire.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Printf
open Cmdliner

(* Atomic features *)

type atom = {
  name: string;
  default: bool;
  doc: string;
}

let create_atom ?(default = true) name ~doc = { name; default; doc }
let name t = t.name
let default t = t.default
let doc_of t = t.doc
let with_default t default = { t with default }
let parse t =
  let docv = "BOOL" in
  let opt = Arg.(value & opt bool t.default & info [t.name] ~doc:t.doc ~docv) in
  Term.(pure (fun value -> t, value) $ opt)

(* Atomic feature sets *)

module Set = Set.Make
    (struct
      type t = atom
      let compare x y = String.compare x.name y.name
    end)

type set = Set.t
let (++) = Set.union

(* Features *)

type t =
  | True | False
  | Atom of atom
  | Not of t
  | And of t * t
  | Or of t * t

let create ?default name ~doc = Atom (create_atom ?default ~doc name)
let true_ = True
let false_ = False
let atom t = Atom t

let neg ?on f = match on with
| Some false -> True
| None | Some true ->
    match f with
    | True -> False
    | False -> True
    | Not t -> t
    | t  -> Not t

let (&&&) x y = match x, y with
| True, x  | x, True  -> x
| False, _ | _, False -> False
| _ -> And (x, y)

let (|||) x y = match x, y with
| True, _  | _, True  -> True
| False, x | x, False -> x
| _ -> Or (x, y)

let atoms t =
  let set = ref Set.empty in
  let rec aux = function
    | True
    | False     -> ()
    | Atom t    -> set := Set.add t !set
    | Not x     -> aux x
    | And (x, y)
    | Or (x, y) -> aux x; aux y in
  aux t;
  !set

let rec eval tbl = function
  | True       -> true
  | False      -> false
  | Atom t     -> (try List.assoc t tbl with Not_found -> false)
  | Not f      -> not (eval tbl f)
  | And (x, y) -> (eval tbl x) && (eval tbl y)
  | Or (x, y)  -> (eval tbl x) || (eval tbl y)

(* CNF *)

type cnf = [ `Conflict | `And of [ `P of atom | `N of atom ] list ]

let negate : cnf -> cnf = function
  | `Conflict -> `And []
  | `And []   -> `Conflict
  | `And l    -> `And (List.map (function `P t -> `N t | `N t -> `P t) l)

let (@) (x:cnf) (y:cnf) = match x, y with
  | `Conflict , _ | _, `Conflict -> `Conflict
  | `And []   , x | x, `And []   -> x
  | `And x , `And y  ->
    let p = Hashtbl.create (List.length x + List.length y) in
    let n = Hashtbl.create (List.length x + List.length y) in
    let add = function
      | `P x -> Hashtbl.replace p x true
      | `N x -> Hashtbl.replace n x true in
    List.iter add x;
    List.iter add y;
    try
      let ps =
        Hashtbl.fold (fun p _ acc ->
            if Hashtbl.mem n p then raise Exit
            else `P p :: acc
          ) p [] in
      let ns = Hashtbl.fold (fun n _ acc ->
          if Hashtbl.mem p n then raise Exit
          else `N n :: acc
        ) n [] in
      `And (ps @ ns)
    with Exit ->
      `Conflict

let rec cnf: t -> cnf = function
  | True       -> `And []
  | False      -> `Conflict
  | Atom x     -> `And [`P x]
  | Not x      -> negate (cnf x)
  | And (x, y) -> cnf x @ cnf y
  | Or (x, y)  -> cnf (Not x) @ cnf (Not y)

(* Built-in features *)

let byte_atom = create_atom
    "byte" ~default:true ~doc:"Byte code OCaml compilation is available."

let native_atom = create_atom
    "native" ~default:true ~doc:"Native code OCaml compilation is available."

let native_dynlink_atom = create_atom
    "native-dynlink" ~default:true
    ~doc:"Native code OCaml dynamic linking is available."

let native_toolchain_atom = create_atom
    "native-toolchain" ~default:true
    ~doc:"The native compiled OCaml toolchain is available (.opt tools)."

let js_atom = create_atom
    "js" ~default:false
    ~doc:"JavaScript code OCaml compilation with js_of_ocaml is available."

let annot_atom = create_atom
    "annot" ~default:true  ~doc:"Build OCaml binary annotations files."

let debug_atom = create_atom
    "debug" ~default:true ~doc:"Build with debugging support."

let warn_error_atom = create_atom
    "warn-error" ~default:false  ~doc:"Build with warnings as errors."

let test_atom = create_atom
    "test" ~default:false  ~doc:"Build the tests."

let doc_atom = create_atom
    "doc" ~default:false ~doc:"Build the documentation."

let builtin = List.fold_left (fun set t -> Set.add t set) Set.empty [
    byte_atom; native_atom; native_dynlink_atom; native_toolchain_atom;
    js_atom; debug_atom; annot_atom; warn_error_atom; test_atom; doc_atom; ]

let byte = atom byte_atom
let native = atom native_atom
let native_dynlink = atom native_dynlink_atom
let native_toolchain = atom native_dynlink_atom
let js = atom js_atom
let annot = atom annot_atom
let warn_error = atom warn_error_atom
let debug = atom debug_atom
let test = atom test_atom
let doc = atom doc_atom
