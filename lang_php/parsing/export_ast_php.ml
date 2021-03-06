(*s: export_ast_php.ml *)
(*s: Facebook copyright *)
(* Yoann Padioleau
 * 
 * Copyright (C) 2009-2011 Facebook
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file license.txt.
 * 
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * license.txt for more details.
 *)
(*e: Facebook copyright *)

open Common

(*s: json_ast_php.ml *)
module J = Json_type 

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

(* 
 * It can be useful for people who don't like OCaml to still benefit 
 * from pfff parsing by having at least a JSON representation
 * of the Ast, hence this file. Other parts of pfff generates JSON
 * data (see flib_navigator/, fb_phpunit/, h_visualization/).
 *
 *)

(*****************************************************************************)
(* Entry points *)
(*****************************************************************************)

let json_string_of_expr x = 
  x |> Meta_ast_php.vof_expr |> Ocaml.json_of_v |> Json_out.string_of_json
let json_string_of_toplevel x = 
  x |> Meta_ast_php.vof_toplevel |> Ocaml.json_of_v |> Json_out.string_of_json
let json_string_of_program x = 
  Common.profile_code "json_of_program" (fun () ->
    x |> Meta_ast_php.vof_program |> Ocaml.json_of_v |> Json_out.string_of_json
  )

let json_string_of_program_fast x = 
  Common.profile_code "json_of_program_fast" (fun () ->
    let json = x |> Meta_ast_php.vof_program |> Ocaml.json_of_v 
    in
    Common.profile_code "string_of_json" (fun () ->
      Json_io.string_of_json ~compact:true ~recursive:false json
    )
  )
(*e: json_ast_php.ml *)
(*s: sexp_ast_php.ml *)
(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* 
 * I was previously auto generating this file with 'ocamltarzan -choice sof'
 * but now that I use Ocaml.v and 'ocamltarzan -choice vof' in meta_ast_php.ml, 
 * this module can just be a wrapper over meta_ast_php.ml.
 *)

(*****************************************************************************)
(* Flags *)
(*****************************************************************************)

let show_info = ref false
let show_expr_info = ref true (* not used for now *)
let show_annot = ref false

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

(* TODO: now that use sexp_of_v, the code below should be moved in 
 * meta_ast_php.ml
 *)

(* This patch makes it easier to see the string in the sexp, but I think
 * it also forbids to have a xxx_of_sexp. As I don't need such func for now,
 * no problem.
 * 
 * monkey patch:
 *)
module Conv = struct
include Conv
let sexp_of_string x = 
  Sexp.Atom (Common.spf "'%s'" x)
end

module Scope_php = struct
open Scope_php
let sexp_of_phpscope x =
  if not !show_annot then Sexp.Atom ""
  else 
    Scope_code.sexp_of_scope x
end

module Sexp_phptype = struct
open Type_php
let rec sexp_of_phptype v = Conv.sexp_of_list sexp_of_phptypebis v
and sexp_of_phptypebis =
  function
  | Basic v1 ->
      let v1 = sexp_of_basictype v1 in Sexp.List [ Sexp.Atom "Basic"; v1 ]
  | ArrayFamily v1 ->
      let v1 = sexp_of_arraytype v1
      in Sexp.List [ Sexp.Atom "ArrayFamily"; v1 ]
  | Object vs ->
      let v1 = Conv.sexp_of_list Conv.sexp_of_string vs
      in Sexp.List [ Sexp.Atom "Object"; v1 ]
  | Function ((v1, v2)) ->
      let v1 = Conv.sexp_of_list (Conv.sexp_of_option sexp_of_phptype) v1
      and v2 = sexp_of_phptype v2
      in Sexp.List [ Sexp.Atom "Function"; v1; v2 ]
  | Resource -> Sexp.Atom "Resource"
  | Null -> Sexp.Atom "Null"
  | TypeVar v1 ->
      let v1 = Conv.sexp_of_string v1 in Sexp.List [ Sexp.Atom "TypeVar"; v1 ]
  | Unknown -> Sexp.Atom "Unknown"
  | Top -> Sexp.Atom "Top"
and sexp_of_basictype =
  function
  | Bool -> Sexp.Atom "Bool"
  | Int -> Sexp.Atom "Int"
  | Float -> Sexp.Atom "Float"
  | String -> Sexp.Atom "String"
  | Unit -> Sexp.Atom "Unit"
and sexp_of_arraytype =
  function
  | Array v1 ->
      let v1 = sexp_of_phptype v1 in Sexp.List [ Sexp.Atom "Array"; v1 ]
  | Hash v1 ->
      let v1 = sexp_of_phptype v1 in Sexp.List [ Sexp.Atom "Hash"; v1 ]
  | Record v1 ->
      let v1 =
        Conv.sexp_of_list
          (fun (v1, v2) ->
             let v1 = Conv.sexp_of_string v1
             and v2 = sexp_of_phptype v2
             in Sexp.List [ v1; v2 ])
          v1
      in Sexp.List [ Sexp.Atom "Record"; v1 ]
  
end
(* pad addons end *)

(*****************************************************************************)
(* Algo *)
(*****************************************************************************)

(* todo? could be moved in ocaml.ml ? but have special case on Dict 
 * could also use string_of_v, we don't really need sexp anymore.
 *)
let rec sexp_of_v v = 
  match v with
  | Ocaml.VString v1 ->
      Conv.sexp_of_string v1

  | Ocaml.VSum ((s, v2)) ->
      let xs = List.map sexp_of_v v2
      in Sexp.List ((Sexp.Atom s)::xs)

  | Ocaml.VTuple xs ->
      let xs' = List.map sexp_of_v xs in
      Sexp.List xs'

  | Ocaml.VDict xs ->
      let hide = 
        ((not !show_info) &&
          (xs |> List.map fst |> List.exists (fun fld -> fld = "pinfo"))) ||
        false
      in
      if hide 
      then Sexp.Atom ""
      else 
        let xs' = 
          xs |> List.map (fun (fld, v) ->
            let v' = sexp_of_v v in
            Sexp.List [Sexp.Atom (fld ^ ":"); v']
          )
        in
        Sexp.List xs'

  | Ocaml.VList v1 ->
      Conv.sexp_of_list sexp_of_v v1

  | Ocaml.VNone -> 
      Conv.sexp_of_option sexp_of_v None
  | Ocaml.VSome v1 -> 
      Conv.sexp_of_option sexp_of_v (Some v1)

  | Ocaml.VRef v1 -> 
      Conv.sexp_of_ref sexp_of_v ({contents = v1})


  (* TODO *)
  | Ocaml.VUnit -> Sexp.Atom "VUnit"
  | Ocaml.VBool v1 ->
      let v1 = Conv.sexp_of_bool v1 in Sexp.List [ Sexp.Atom "VBool"; v1 ]
  | Ocaml.VFloat v1 ->
      let v1 = Conv.sexp_of_float v1 in Sexp.List [ Sexp.Atom "VFloat"; v1 ]
  | Ocaml.VChar v1 ->
      let v1 = Conv.sexp_of_char v1 in Sexp.List [ Sexp.Atom "VChar"; v1 ]
  | Ocaml.VInt v1 ->
      let v1 = Conv.sexp_of_int v1 in Sexp.List [ Sexp.Atom "VInt"; v1 ]

  | Ocaml.VVar v1 ->
      let v1 =
        (match v1 with
         | (v1, v2) ->
             let v1 = Conv.sexp_of_string v1
             and v2 = Conv.sexp_of_int64 v2
             in Sexp.List [ v1; v2 ])
      in Sexp.List [ Sexp.Atom "VVar"; v1 ]
  | Ocaml.VArrow v1 ->
      let v1 = Conv.sexp_of_string v1 in Sexp.List [ Sexp.Atom "VArrow"; v1 ]

  | Ocaml.VTODO v1 ->
      let v1 = Conv.sexp_of_string v1 in Sexp.List [ Sexp.Atom "VTODO"; v1 ]

(*****************************************************************************)
(* Entry points *)
(*****************************************************************************)

(* pad addons: *)

let sexp_string_of_expr x = 
  x |> Meta_ast_php.vof_expr |> sexp_of_v |> Sexp.to_string_hum
let sexp_string_of_toplevel x = 
  x |> Meta_ast_php.vof_toplevel |> sexp_of_v |> Sexp.to_string_hum
let sexp_string_of_program x = 
  x |> Meta_ast_php.vof_program |> sexp_of_v |> Sexp.to_string_hum

let sexp_string_of_phptype top = 
  raise Todo

(*e: sexp_ast_php.ml *)

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(*
  let v = Ocaml.VList [
    Ocaml.VInt 10000; Ocaml.VInt 10000; Ocaml.VInt 10000; Ocaml.VInt 10000;
    Ocaml.VInt 10000; Ocaml.VInt 10000; Ocaml.VInt 10000; Ocaml.VInt 10000;
    Ocaml.VInt 10000; Ocaml.VInt 10000; Ocaml.VInt 10000; Ocaml.VInt 10000;
    Ocaml.VInt 10000; Ocaml.VInt 10000; Ocaml.VInt 10000; Ocaml.VInt 10000;
    Ocaml.VSum ("Foo", [Ocaml.VInt 10000; Ocaml.VInt 10000;]);
    ]
  in

  let s = Ocaml.string_of_v v in
  pr2 s;
*)

let string_of_v v =
  let cnt_i = ref 0 in
  let cnt_other = ref 0 in

  (* transformation to not have the parse info or type info in the output *)
  let v' = Ocaml.map_v ~f:(fun ~k x ->
    match x with
    | Ocaml.VDict (xs) ->
        (match () with
        | _ when xs +> List.exists (function ("token", _) ->true | _ -> false)->
            incr cnt_i;
            Ocaml.VVar ("i", Int64.of_int !cnt_i)
        | _ when xs +> List.exists (function ("t", _) -> true | _ -> false)->
            incr cnt_other;
            Ocaml.VVar ("t", Int64.of_int !cnt_other)
        | _ when xs +> List.exists (function ("tvar", _) -> true | _ -> false)->
            incr cnt_other;
            Ocaml.VVar ("tlval", Int64.of_int !cnt_other)
        | _ -> 
            (* recurse, x can be a record containing itself some records *)
            k x
        )
    | _ -> k x
  ) v
  in
  let s = Ocaml.string_of_v v' in
  s

let ml_pattern_string_of_program ast = 
  Meta_ast_php.vof_program ast +> string_of_v

let ml_pattern_string_of_expr e = 
  Meta_ast_php.vof_expr e +> string_of_v

let ml_pattern_string_of_any any =
  Meta_ast_php.vof_any any +> string_of_v

(*e: export_ast_php.ml *)
