(** Generate OCaml code defining uris from a RDFs graph. *)

let caml_kw = List.fold_right
  Rdf_types.SSet.add
    [
      "and" ; "as" ; "assert" ; "begin"; "class"; "constraint"; "do";
      "done"; "downto"; "else"; "end"; "exception"; "external";
      "false"; "for"; "fun"; "function"; "functor";
      "if"; "in"; "include"; "inherit"; "initializer";
      "lazy"; "let"; "match"; "method"; "module"; "mutable";
      "new"; "object"; "of"; "open"; "or"; "private";
      "rec"; "sig"; "struct"; "then"; "to"; "true"; "try"; "type";
      "val"; "virtual"; "when"; "while"; "with";
      "mod"; "land"; "lor"; "lxor"; "lsl"; "lsr"; "asr";
    ]
    Rdf_types.SSet.empty
;;


let caml_id s =
  let len = String.length s in
  for i = 0 to len - 1 do
    match s.[i] with
      'a'..'z' | 'A'..'Z' | '0'..'9' | '_' -> ()
    | _ -> s.[i] <- '_'
  done;
  if Rdf_types.SSet.mem s caml_kw then s^"_" else s
;;

let get_properties g =
  let q =
   "PREFIX rdf: <"^(Rdf_uri.string Rdf_rdf.rdf)^">
    PREFIX rdfs: <"^(Rdf_uri.string Rdf_rdf.rdfs)^">
    SELECT ?prop ?comment ?comment_en
      { ?prop a ?type .
        OPTIONAL { ?prop rdfs:comment ?comment FILTER (!LangMatches(lang(?comment),\"*\")) }
        OPTIONAL { ?prop rdfs:comment ?comment_en FILTER LangMatches(lang(?comment_en),\"en\") }
        FILTER (?type IN (rdf:Property, rdfs:Class))
      }
      ORDER BY LCASE(STR(?prop))"
  in
  let ds = Rdf_ds.simple_dataset g in
  let q = Rdf_sparql.parse_from_string q in
  let sols = Rdf_sparql.select (g.Rdf_graph.name()) ds q in
  let f acc sol =
    let prop = Rdf_sparql.get_iri sol (g.Rdf_graph.name()) "prop" in
    let comment =
      if Rdf_sparql.is_bound sol "comment_en" then
        Some (Rdf_sparql.get_string sol "comment_en")
      else
        if Rdf_sparql.is_bound sol "comment" then
          Some (Rdf_sparql.get_string sol "comment")
        else
          None
    in
    (prop, comment) :: acc
  in
  List.fold_left f [] sols
;;

let get_under s1 s2 =
  let len1 = String.length s1 in
  let len2 = String.length s2 in
  if len2 > len1 && (String.sub s2 0 len1) = s1 then
    String.sub s2 len1 (len2 - len1)
  else
    ""
;;

let gen_impl ?(comments=true) oc prefix base props =
  let p s = output_string oc s in
  let pc s = if comments then p ("(** "^s^" *)\n") else () in
  pc ("Properties of ["^(Rdf_uri.string base)^"]");
  p "\n";
  pc ("["^(Rdf_uri.string base)^"]");
  p ("let "^prefix^" = Rdf_uri.uri \""^(Rdf_uri.string base)^"\";;\n");
  p ("let "^prefix^"_ = Rdf_uri.append "^prefix^";;\n\n");

  let f (prop, comment) =
    (match comment with None -> () | Some c -> pc c) ;
    p ("let "^prefix^"_"^(caml_id prop)^" = "^prefix^"_\""^prop^"\" ;;\n\n")
  in
  List.iter f props
;;

let gen_intf oc prefix base props =
  let p s = output_string oc s in
  let pc s = p ("(** "^s^" *)\n") in
  pc ("Properties of ["^(Rdf_uri.string base)^"]");
  p "\n";
  pc ("["^(Rdf_uri.string base)^"]");
  p ("val "^prefix^" : Rdf_uri.uri\n");
  p ("val "^prefix^"_ : string -> Rdf_uri.uri\n\n");

  let f (prop, comment) =
    (match comment with None -> () | Some c -> pc c) ;
    p ("val "^prefix^"_"^(caml_id prop)^" : Rdf_uri.uri\n\n")
  in
  List.iter f props
;;


let generate ?file prefix base g =
  let props = get_properties g in
  let s_base = Rdf_uri.string base in
  let f acc (prop, comment) =
    let s_prop = Rdf_uri.string prop in
    match get_under s_base s_prop with
      "" -> acc
    | s -> (s, comment) :: acc
  in
  let props = List.fold_left f [] props in
  match file with
    None -> gen_impl stdout prefix base props
  | Some f ->
      let oc = open_out (f^".ml") in
      gen_impl ~comments: false oc prefix base props;
      close_out oc;

      let oc = open_out (f^".mli") in
      gen_intf oc prefix base props;
      close_out oc;
;;


let fatal s = prerr_endline s ; exit 1 ;;
let usage = Printf.sprintf "Usage: %s [options] <prefix> <base_uri> <file>" Sys.argv.(0);;

let main () =
  let load = ref Rdf_xml.from_file in
  let file_prefix = ref None in
  let args = ref [] in
  Arg.parse
    [
      "--ttl", Arg.Unit (fun () -> load := Rdf_ttl.from_file),
      " indicate input file is in turtle format rather than XML/RDF" ;

      "-f", Arg.String (fun s -> file_prefix := Some s),
      " <s> generate code in <s>.ml and <s>.mli" ;
    ]
    (fun s -> args := s :: !args)
    (usage^"\nwhere options are:");
  match List.rev !args with
  | prefix :: base_uri :: file :: _ ->
      begin
        try
          let base_uri = Rdf_uri.uri base_uri in
          let prefix = caml_id prefix in
          let options = [ "storage", "mem" ] in
          let g = Rdf_graph.open_graph ~options base_uri in
          !load g file ;
          generate ?file: !file_prefix prefix base_uri g
        with
          Rdf_uri.Invalid_uri s -> failwith ("Invalid uri: "^s)
        | Rdf_ttl.Error e -> failwith (Rdf_ttl.string_of_error e)
        | Rdf_xml.Invalid_rdf msg -> failwith msg
        | Rdf_sparql.Error e -> failwith (Rdf_sparql.string_of_error e)
      end
  | _ -> fatal usage
;;


(*c==v=[Misc.safe_main]=1.0====*)
let safe_main main =
  try main ()
  with
    Failure s
  | Sys_error s ->
      prerr_endline s;
      exit 1
(*/c==v=[Misc.safe_main]=1.0====*)

let () = safe_main main;;