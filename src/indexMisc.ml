(**************************************************************************)
(*                                                                        *)
(*  Copyright 2013 OCamlPro                                               *)
(*                                                                        *)
(*  All rights reserved.  This file is distributed under the terms of     *)
(*  the Lesser GNU Public License version 3.0.                            *)
(*                                                                        *)
(*  This software is distributed in the hope that it will be useful,      *)
(*  but WITHOUT ANY WARRANTY; without even the implied warranty of        *)
(*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *)
(*  Lesser GNU General Public License for more details.                   *)
(*                                                                        *)
(**************************************************************************)


let debug_enabled =
  try match Sys.getenv "OCP_DEBUG" with "" | "0" -> false | _ -> true
  with Not_found -> false

let debug =
  if debug_enabled then
    fun fmt -> Printf.eprintf ("\027[36m"^^fmt^^"\027[m%!")
  else
    fun fmt -> Printf.ifprintf stderr fmt

let timer () =
  if debug_enabled then
    let t = Sys.time () in
    fun () -> Sys.time () -. t
  else
    fun () -> 0.

type key = char list

(* Used as path separator in keys *)
let dot = char_of_int 0
let dots = String.make 1 dot

let string_to_key s =
  let rec aux acc i =
    if i >= 0 then
      let c = match s.[i] with
        | '.' | '#' as c when i > 0 ->
            (match s.[i-1] with 'a'..'z' | 'A'..'Z' | '0'..'9' -> dot
                              | _ -> c)
        | c -> c
      in
      aux (c::acc) (i - 1)
    else acc
  in
  aux [] (String.length s - 1)

let key_to_string l =
  let rec aux n = function
    | [] -> String.create n
    | c::r ->
        let s = aux (n+1) r in
        s.[n] <- if c = dot then '.' else c; s
  in
  aux 0 l

let modpath_to_key path =
  List.fold_right (fun p acc -> string_to_key p @ dot :: acc) path []

let key_to_modpath l =
  let rec aux n = function
    | [] -> if n > 0 then [String.create n] else []
    | '\000'::r -> String.create n :: aux 0 r
    | c::r ->
        match aux (n+1) r with
        | s::_ as p -> s.[n] <- c; p
        | [] -> assert false
  in
  aux 0 l

let modpath_to_string path = String.concat "." path

let unique_subdirs dir_list =
  let rec subdirs acc path =
    Array.fold_left
      (fun acc p ->
        let path = Filename.concat path p in
        if try Sys.is_directory path with Sys_error _ -> false
        then subdirs acc path else acc)
      (path::acc)
      (Sys.readdir path)
  in
  let remove_dups l =
    let rec aux = function
      | a::(b::_ as r) when a = b -> aux r
      | a::r -> a :: aux r
      | [] -> []
    in
    aux (List.sort compare l)
  in
  remove_dups (List.fold_left subdirs [] dir_list)


(* - Project root finding - *)

let build_roots = (* by increasing order of priority *)
  [ "_darcs"; ".hg"; ".git";
    "jengaroot.ml"; "omakeroot"; "_build"; "_obuild" ]

let find_build_dir path =
  let ( / ) = Filename.concat in
  let files = Sys.readdir path in
  let _, root =
    let rec memsuffix x = function
      | a::r -> if x = a then Some r else memsuffix x r
      | [] -> None
    in
    Array.fold_left (fun (roots,found) f ->
        match memsuffix f roots with
        | None -> roots, found
        | Some roots -> roots, Some f)
      (build_roots, None) files
  in
  match root with
  | None -> None
  | Some ("_obuild" | "_build" as dir) -> Some (path / dir)
  | Some _ -> Some path

let project_root ?(path=Sys.getcwd()) () =
  let ( / ) = Filename.concat in
  let home = try Sys.getenv "HOME" with Not_found -> "" in
  let path =
    if Filename.is_relative path then Sys.getcwd () / path
    else path
  in
  let rec find path =
    match find_build_dir path with
    | None ->
        let parent = Filename.dirname path in
        if path = parent || path = home then None
        else find parent
    | Some build -> Some (path, build)
  in
  match find path with
  | None -> None, None
  | Some (root, build) -> Some root, Some build
