(* Yoann Padioleau
 * 
 * Copyright (C) 2012 Facebook
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
open Common
(* floats are the norm in graphics *)
open Common.ArithFloatInfix

module CairoH = Cairo_helpers3
module DM = Dependencies_matrix_code

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

(*****************************************************************************)
(* The code model *)
(*****************************************************************************)

type model = {
  (* unused for now *)
  root: Common.dirname;

  g: Graph_code.graph;
  full_matrix: Dependencies_matrix_code.dm;
}

(*****************************************************************************)
(* The drawing model *)
(*****************************************************************************)

(* All the 'float' below are to be intepreted as user coordinates except when
 * explicitely mentioned. All the 'int' are usually device coordinates.
 *)
type world = {
  model: model;

  mutable path: Dependencies_matrix_code.config_path;
  (* cache of Dependencies_matrix_code.build (config_of_path path) g *)
  mutable m: Dependencies_matrix_code.dm;
  (* to memoize DM.projection on this particular matrix/path *)
  mutable projection_cache: Dependencies_matrix_code.projection_cache;
  
  (* set each time in View_matrix.draw_matrix.
   * opti: use a quad tree?
   *)
  mutable interactive_regions: (region * Figures.rectangle) list;

  mutable base: [ `Any ] Cairo.surface;
  mutable overlay: [ `Any ] Cairo.surface;

  (* viewport, device coordinates *)
  mutable width: int;
  mutable height: int;
}
  and region =
    | Cell of int * int (* i, j *)
    | Row of int (* i *)
    | Column of int (* j *)

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

let new_surface ~alpha ~width ~height =
  let drawable = GDraw.pixmap ~width:1 ~height:1 () in
  drawable#set_foreground `WHITE;
  drawable#rectangle ~x:0 ~y:0 ~width:1 ~height:1 ~filled:true ();

  let cr = Cairo_lablgtk.create drawable#pixmap in
  let surface = Cairo.get_target cr in
  Cairo.surface_create_similar surface
    (if alpha 
    then Cairo.CONTENT_COLOR_ALPHA
    else Cairo.CONTENT_COLOR
    ) width height

(*****************************************************************************)
(* Main entry point *)
(*****************************************************************************)

let config_of_path (path: DM.config_path) m =
  let initial_config = DM.basic_config m.g in
  pr2_gen path;
  path +> List.fold_left (fun config e ->
    match e with
    | DM.Expand node ->
        DM.expand_node node config m.g
    | DM.Focus (node, kind) ->
        let dm = DM.build config (Some m.full_matrix) m.g in
        DM.focus_on_node node kind config dm
  ) initial_config


(* width/height are a first guess. The first configure ev will force a resize
 * coupling: with View_matrix.recompute_matrix
 *)
let init_world ?(width = 600) ?(height = 600) path model =
  let config = config_of_path path model in
  let m = 
    Common.profile_code2 "Model.building matrix" (fun () -> 
      Dependencies_matrix_code.build config (Some model.full_matrix) model.g 
    )
  in
  {
    model; 
    projection_cache = Hashtbl.create 101;
    path;
    interactive_regions = [];
    m;
    width; height;
    base = new_surface ~alpha:false ~width ~height;
    overlay = new_surface ~alpha:false ~width ~height;
  }

(*****************************************************************************)
(* Coordinate system *)
(*****************************************************************************)

(* On my 30' monitor, when I run codegraph and expand it to take the
 * whole screen, then the Grab utility tells me that the drawing area
 * is 2560 x 1490 (on my laptop it's 1220 x 660).
 * So if we want a uniform coordinate system that is
 * still aware of the proportion (like I did in Treemap.xy_ratio),
 * then 1.71 x 1 is a good choice.
 *)
let xy_ratio = 1.71

let scale_coordinate_system cr w =
  Cairo.scale cr
    (float_of_int w.width / xy_ratio)
    (float_of_int w.height);
  ()

(*****************************************************************************)
(* Layout *)
(*****************************************************************************)

(* todo: can put some of it as mutable? as we expand things we may want
 * to reserve more space to certain things?
 *)
type layout = {
(* this assumes a xy_ratio of 1.71 *)
  x_start_matrix_left: float;
  x_end_matrix_right: float;
  y_start_matrix_up: float;
  y_end_matrix_down: float;

  width_vertical_label: float;

  nb_elts: int;
  width_cell: float;
  height_cell: float;
}

let layout_of_w w = 
  let x_start_matrix_left = 0.3 in
  let x_end_matrix_right = 1.71 in
  (* this will be with 45 degrees so it can be less than x_start_matrix_left *)
  let y_start_matrix_up = 0.1 in
  let y_end_matrix_down = 1.0 in

  let nb_elts = Array.length w.m.DM.matrix in
  let width_cell = 
    (x_end_matrix_right - x_start_matrix_left) / (float_of_int nb_elts) in
  let height_cell = 
    (1.0 - y_start_matrix_up) / (float_of_int nb_elts) in
  {
    x_start_matrix_left;
    x_end_matrix_right;
    y_start_matrix_up;
    y_end_matrix_down;

    width_vertical_label = 0.025;

    nb_elts;
    width_cell;
    height_cell;
  }

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

let find_region_at_user_point w ~x ~y =
  let regions = w.interactive_regions in
  let pt = { Figures. x = x; y = y } in
  
  try 
    let (kind, rect) = regions +> List.find (fun (kind, rect) ->
      Figures.point_is_in_rectangle pt rect
    )
    in
    Some kind
  with Not_found -> None
