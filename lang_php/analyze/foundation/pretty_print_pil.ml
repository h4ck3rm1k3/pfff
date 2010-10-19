(*s: pretty_print_pil.ml *)
(*s: Facebook copyright *)
(* Yoann Padioleau
 *
 * Copyright (C) 2010 Facebook
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

module A = Ast_php
module P = Pil

let _show_types = ref false

(* This module is a pretty printer for Pil
 * The output code is correct PHP code that can be parsed and executed
 *)

let string_of_name (n:A.name) = match n with
| A.Name sw -> A.unwrap sw
| A.XhpName xw -> xw |> A.unwrap |> string_of_list (fun s->s) (*TODOjjeannin *)

let string_of_dname (d:A.dname) = match d with
| A.DName sw -> "$"^(A.unwrap sw)

let string_of_qualifier (q:A.qualifier) = match q with
| A.Qualifier(f, _) -> (string_of_name f)^"::"
| A.Self(_, _) -> "self::"
| A.Parent(_, _) -> "parent::"

let string_of_indirect (i:A.indirect) = match i with
| A.Dollar _ -> "$(???Indirect)" (* TODOjjeannin *)

let string_of_binaryOp (b:A.binaryOp) = match b with
|A.Arith A.Plus      -> "+"
|A.Arith A.Minus     -> "-"
|A.Arith A.Mul       -> "*"
|A.Arith A.Div       -> "/"
|A.Arith A.Mod       -> "%"
|A.Arith A.DecLeft   -> "<<" 
|A.Arith A.DecRight  -> ">>"
|A.Arith A.And       -> "&"
|A.Arith A.Or        -> "|"
|A.Arith A.Xor       -> "^"
|A.Logical A.Inf     -> "<"
|A.Logical A.Sup     -> ">"
|A.Logical A.InfEq   -> "<="
|A.Logical A.SupEq   -> ">="
|A.Logical A.Eq      -> "=="
|A.Logical A.NotEq   -> "!=" 
|A.Logical A.Identical    -> "==="
|A.Logical A.NotIdentical -> "!=="
|A.Logical A.AndLog  -> " and "
|A.Logical A.OrLog   -> " or "
|A.Logical A.XorLog  -> " xor "
|A.Logical A.AndBool -> "&&"
|A.Logical A.OrBool  -> "||"
|A.BinaryConcat      -> "."

let string_of_unaryOp (u:A.unaryOp) = match u with
|A.UnPlus  -> "+" 
|A.UnMinus -> "-"
|A.UnBang  -> "!"
|A.UnTilde -> "~"

let string_of_constant (c:A.constant) = match c with
|A.Int sw | A.Double sw | A.String sw -> A.unwrap sw
|A.CName n -> string_of_name n
|A.PreProcess _ -> raise Todo
|A.XdebugClass _ -> raise Todo
|A.XdebugResource _ -> raise Todo

let string_of_class_name_reference (cnr:A.class_name_reference) = 
match cnr with
|A.ClassNameRefStatic n -> string_of_name n
|A.ClassNameRefDynamic _ -> raise Todo

let string_of_assignOp (a:A.assignOp) = match a with
|A.AssignOpArith o -> (string_of_binaryOp (A.Arith o))^"="
|A.AssignConcat    -> ".="

let string_of_castOp (c:A.castOp) = match c with
|A.BoolTy   -> "bool"
|A.IntTy    -> "int"
|A.DoubleTy -> "float"
|A.StringTy -> "string"
|A.ArrayTy  -> "array"
|A.ObjectTy -> "object"

let string_of_type_info (t:P.type_info) = 
  if !_show_types
  then "/* TYPE */" (* TODOjjeannin *)
  else ""

let string_of_var (v:P.var) = match v with
|P.Var d -> string_of_dname d
|P.This _ -> "$this"

let rec string_of_lvalue ((lv, ti):P.lvalue) =
  let string_of_lvaluebis = function
  |P.VVar v -> string_of_var v
  |P.VQualifier(q,v) -> (string_of_qualifier q)^(string_of_var v)
  |P.ArrayAccess(v,None) -> (string_of_var v)^"[]"
  |P.ArrayAccess(v,Some e) -> (string_of_var v)^"["^
                              (string_of_expr e)^"]"
  |P.ObjAccess(v,n) -> (string_of_var v)^"->"^(string_of_name n)
  |P.DynamicObjAccess(v1,v2) -> (string_of_var v1)^"->"^
                                (string_of_var v2)
  |P.IndirectAccess(v,i) -> (string_of_var v)^"->"^
                            (string_of_indirect i)
  in
(string_of_lvaluebis lv)^(string_of_type_info ti)

and string_of_expr ((e, ti):P.expr) =
  let string_of_exprbis = function
  |P.Lv lv -> string_of_lvalue lv
  |P.C c -> string_of_constant c
  |P.ClassConstant(q, n) -> (string_of_qualifier q) ^ "::" ^
                            (string_of_name n)
  |P.Binary(e1, b, e2)->"("^(string_of_expr e1)^")"^
                        (string_of_binaryOp b)^
                        "("^(string_of_expr e2)^")"
  |P.Unary(u, e)->(string_of_unaryOp u)^"("^(string_of_expr e)^")"
  |P.CondExpr(e1, e2, e3)->"("^(string_of_expr e1)^")"^" ? "^
                           "("^(string_of_expr e2)^")"^" : "^
                           "("^(string_of_expr e3)^")"
  |P.ConsArray(el)->"array("^
                    (String.concat ", " (List.map string_of_expr el))^
                    ")"
  |P.ConsHash(l)->"array("^
                  (String.concat ", "
                   (List.map (fun (k,e) -> 
                              (string_of_expr k)^" => "^
                              (string_of_expr e)) l)
                  )^")"
  |P.Cast(c, e)->"("^(string_of_castOp c)^")"^(string_of_expr e)
  |P.InstanceOf(e, cnr) -> (string_of_expr e)^" instanceof "^
                           (string_of_class_name_reference cnr)
  in
(string_of_exprbis e)^(string_of_type_info ti)

let string_of_assign_kind = function
|P.AssignEq -> "="
|P.AssignOp o -> string_of_assignOp o

let string_of_call_kind = function
|P.SimpleCall n -> string_of_name n
|P.StaticMethodCall(q, n) -> (string_of_qualifier q)^"::"^(string_of_name n)
|P.MethodCall(v, n) ->(string_of_var v)^"->"^(string_of_name n)
|P.DynamicCall(None, v) ->(string_of_var v)
|P.DynamicCall(Some q, v) -> (string_of_qualifier q)^"::"^(string_of_var v)
|P.DynamicMethodCall(v1, v2) ->(string_of_var v1)^"->"^(string_of_var v2)
|P.New(cnr) -> "new "^(string_of_class_name_reference cnr) 

let string_of_argument = function
|P.Arg e -> string_of_expr e
|P.ArgRef lv -> "&("^(string_of_lvalue lv)^")"

let rec string_of_instr (i:P.instr) = match i with
|P.Assign(lv, ak, e) -> (string_of_lvalue lv)^(string_of_assign_kind ak)^
                         (string_of_expr e)^"; "
|P.AssignRef(lv1, lv2) -> (string_of_lvalue lv1)^" =& "^
                           (string_of_lvalue lv2)^"; "
|P.Call(s,f,args) ->
    (string_of_lvalue s)^" = "^(string_of_call_kind f)^"("^
    (String.concat ", " (List.map string_of_argument args))^"); "
|P.Eval(e) -> "eval("^(string_of_expr e)^"); "

let string_of_catch x = 
  raise Todo

let rec string_of_stmt (s:P.stmt) = match s with
|P.Instr i -> (string_of_instr i)^"\n"
|P.Block sl -> "{\n"^(String.concat "\n" (List.map string_of_stmt sl))^
                "\n}\n"
|P.EmptyStmt -> ";\n"
|P.If(e, s1, s2) ->"if("^(string_of_expr e)^")"^
                    (string_of_stmt s1)^"else "^
                    (string_of_stmt s2)
|P.While(e, s) -> "while("^(string_of_expr e)^")"^
                   (string_of_stmt s)
|P.Break(None) -> "break;\n"
|P.Break(Some e) -> "break "^(string_of_expr e)^";\n"
|P.Continue(None) -> "continue;\n"
|P.Continue(Some e) -> "continue "^(string_of_expr e)^";\n"
|P.Return(None) -> "return;\n"
|P.Return(Some e) -> "return "^(string_of_expr e)^";\n"
|P.Throw(e) -> "throw "^(string_of_expr e)^";\n"
|P.Try(s, c) -> "try "^(string_of_stmt s)^"catch "^(string_of_catch c)^"\n"
|P.Echo(el) ->"echo "^(String.concat ", " (List.map string_of_expr el))^
               ";\n"


let string_of_hint_type hint = 
  string_of_name hint
let string_of_option_type_hint x = 
  match x with 
  | None -> ""
  | Some hint -> string_of_hint_type hint ^ " "

let string_of_param p =
  (string_of_option_type_hint p.P.p_type) ^
  (* p_ref ? *)
  (string_of_dname p.P.p_name) ^
  (match p.P.p_default with
  | None -> ""
  | Some e -> " = " ^ string_of_expr e
  )

let string_of_program ?(show_types=false) xs = 
  Common.save_excursion _show_types show_types (fun () ->
    xs +> List.map (fun top ->
      match top with
      | P.TopStmt st -> string_of_stmt st

      | P.FunctionDef def ->
          let header = spf "function %s(%s) %s {\n"
            (string_of_name def.P.f_name)
            (def.P.f_params +> List.map string_of_param +> Common.join ", ")
            (string_of_option_type_hint def.P.f_return_type)
          in
          (* todo? f_ref ? *)
          let body = 
            def.P.f_body +> List.map string_of_stmt +> Common.join ""
          in
          header ^ body ^ "}\n"

      | _ -> raise Todo
    ) +> Common.join ""
  )
(*e: pretty_print_pil.ml *)
