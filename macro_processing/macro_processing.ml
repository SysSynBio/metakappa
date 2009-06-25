(* 2009/06/20*)
(* Meta language for Kappa *)
(* Jerome Feret LIENS (INRIA/ENS/CNRS) & Russ Harmer PPS (CNRS)*)
(* Academic uses only *)
(* Macro processing module *)
(* macro_processing.ml *)

open Error_handler 
open Data_structures_metakappa 

(* report an error at line i*)
let error i = 
  let _ = print_string (string_of_int i) in 
  let _ = print_newline () in 
  unsafe_frozen None (Some "macro_processing.ml") None (Some ("line "^(string_of_int i))) (fun () -> failwith ("error"^(string_of_int i)))


let id = (fun x -> x)

let collect_def l log = 
  let rec seek_macro_def l sol dictionary  = 
    match l with t::q -> 
      begin 
	match t with 
	  PP_BMAC_L (x,i) -> seek_macro_end q (x (fun (x,_)->x),i) [] sol dictionary 
	| PP_EMAC_L (_,i) -> failwith ("END OF MACRO unexpected in line "^(string_of_line i))
	| _ -> seek_macro_def q (t::sol) dictionary 
      end
    | [] -> List.rev sol,dictionary  
  and
      seek_macro_end l ((ag,int,string),i) local sol dictionary = 
    match l with [] -> 
      begin
	failwith ("the MACRO that begins in line "^(string_of_line i)^" is not ended")
      end
    | t::q -> 
	begin
	  match t with 
	    PP_BMAC_L(_,i2) -> 
	      failwith ("MACRO cannot be nested (line "^(string_of_line i)^" and "^(string_of_line i2))
	  | PP_EMAC_L(_,i2) -> 
	      let dictionary' = 
		try 
		  let _,i3  = StringMap.find ag dictionary 
		  in failwith ("MACRO "^ag^" both defined on line "^(string_of_line i3)^" and "^(string_of_line i))
		with 
		  Not_found -> StringMap.add ag ((int,List.rev local),i) dictionary in 
	      seek_macro_def q sol dictionary'
	  | _ -> seek_macro_end q ((ag,int,string),i) (t::local) sol dictionary
	end
  in 
  seek_macro_def  l [] StringMap.empty , log 


let print_def handler def = 
  let _ = handler.string "List of Macro-definitions\n" in 
  let _ = 
    StringMap.iter 
      (fun a ((b,c),d) -> 
	handler.string a;handler.line ();
	List.iter handler.string b;
	handler.line ())
      def 
  in
  let _ = handler.string "End of the list of Macro-definitions \n\n\n" in 
  ()


let get_macro_var rule = 
  let sol  = ref String2Set.empty in 
    match rule with 
	PP_EMAC_L _ | PP_BMAC_L _ -> error 72 
      | PP_INIT_L (x,_) -> let _ = x (fun x -> let _ = sol:= String2Set.add x (!sol) in fst x) in !sol 
      | PP_DONT_CARE_L (x,_) -> let _ = x (fun x -> let _ = sol:= String2Set.add x (!sol) in fst x) in !sol 
      | PP_OBS_L (x,_)  ->  let _ = x (fun x -> let _ = sol:= String2Set.add x (!sol) in fst x) in !sol 
      | PP_STORY_L (x,_) -> let _ = x (fun x -> let _ = sol:= String2Set.add x (!sol) in fst x) in !sol 
      | PP_GEN_L (x,_)  ->  let _ = x (fun x -> let _ = sol:= String2Set.add x (!sol) in fst x) in !sol 
      | PP_CONC_L (x,_)  ->  let _ = x (fun x -> let _ = sol:= String2Set.add x (!sol) in fst x) in !sol 
      | PP_RULE_L (x,_) ->  let _ = x (fun x -> let _ = sol:= String2Set.add x (!sol) in fst x) in !sol 
      | PP_PREPROCESSED_RULE (x,_) ->  let _ = x (fun x -> let _ = sol:= String2Set.add x (!sol) in (fst x)) in !sol 
      | PP_CMAC_L (x,_)  ->  let _ = x (fun x -> let _ = sol:= String2Set.add x (!sol) in fst x) in !sol

let get_subs varset int arg  = 
  let map = 
    let rec scan l1 l2 map = 
      match l1,l2 with [],[] -> map
      |	t1::q1,t2::q2 -> scan q1 q2 (StringMap.add t1 t2 map)
      | _ -> error 88 
    in scan int arg StringMap.empty 
  in
  String2Set.fold 
    (fun var prefixlist -> 
      try 
	let a = StringMap.find (fst var) map
	in 
	List.fold_left 
	  (fun sol prefix -> 
	    List.fold_left 
	      (fun sol image -> (String2Map.add var image prefix)::sol)
	      sol
	      a) [] prefixlist
      with 
	Not_found -> prefixlist)
    varset 
    [String2Map.empty],map

let extend_flag x stack tag = 
  if stack = [] then x
  else
    let flag = 
      List.fold_left 
	(fun sol x -> sol^"@"^x)
	(fst x)
	stack
    in
    flag^tag,snd x
	  
	    
let rec macro_expanse calling_stack def f tag l sol log = 
  match l with 
    [] -> sol,log 
  | t::q -> 
      begin
	let sol',log  = 
	  match t with 
	    PP_INIT_L (x,i) -> INIT_L(let a,b = x f in a,b,i)::sol,log
	  | PP_DONT_CARE_L (x,i) -> DONT_CARE_L(x f,i)::sol,log
	  | PP_OBS_L (x,i) -> OBS_L(let a,b = x f in a,b,i)::sol,log
	  | PP_STORY_L (x,i) -> STORY_L(let a,b = x f in a,b,i)::sol,log
	  | PP_GEN_L (x,i) -> GEN_L(x f,i)::sol,log
	  | PP_CONC_L (x,i) -> CONC_L(x f,i)::sol,log
	  | PP_RULE_L (x,i) -> RULE_L(extend_flag (x f) calling_stack tag,i)::sol,log
	  | PP_PREPROCESSED_RULE (x,i) -> PREPROCESSED_RULE(let a,b = x f in a,b,i)::sol,log
	  | PP_EMAC_L _ | PP_BMAC_L _ -> 
	      error 129 
	  | PP_CMAC_L (cont,i) -> 
	      let rec call (x,arg,string) sol calling_stack log = 
		try 
		  let _ = print_string x in 
		  let (int,body),i2= 
		    StringMap.find x def 
		  in 
		  List.fold_left 
		    (fun (sol,log) rule -> 
		      let variables = get_macro_var rule in 
		      let _ = 
			if List.length int <> List.length arg
			then failwith ("Wrong number of arguments in Line: "^(string_of_line i))
		      in
		      let fun_list,subs_to_list = get_subs variables int arg  in 
		      match rule 
		      with PP_CMAC_L(cont2,i2) -> 
			let (x2,arg2,string2) = cont2 f in 
			let arg3 = 
			  List.map 
			    (fun l -> 
			       let set = 
				 List.fold_left 
				   (fun set x -> 
				      List.fold_left 
					(fun set y -> StringSet.add y set)
					set
					(try 
					   StringMap.find x subs_to_list 
					  with 
					    Not_found -> [x]))
				      StringSet.empty 
				      l
				  in 
				  StringSet.fold (fun x l -> x::l) set [])
				arg2
			    in 
			    call (x2,arg3,string2) sol ((string_of_line i2)::calling_stack) log
			|	rule -> 
				  List.fold_left 
				    (fun (sol,log) sigma -> 
				       let tag = 
					 String2Map.fold 
					   (fun (x,a) y tag -> 
					      (tag^"."^x^"%"^a^"/"^y))
					   
					   sigma 
					   ""
				       in
					 
				       let sigma x = 
					 try 
					   String2Map.find x sigma 
					 with 
					     Not_found -> (fst x) 
				       in 
					 
					 macro_expanse calling_stack def sigma tag [rule] sol log )
				    (sol,log) 
				    fun_list)
		    (sol,log) body 
		with 
		    Not_found -> 
		      failwith ("MACRO "^x^" undefined at line "^(string_of_line i))
	      in (call (cont f) sol ((string_of_line i)::calling_stack) log)
	in macro_expanse calling_stack def f tag q sol' log
      end

let macro_expanse x a b c d e f = 
  let rep,log = macro_expanse x a b c d e f
  in List.rev rep,log 
