(*
The MIT License (MIT)

Copyright (c) 2014 Leonardo Laguna Ruiz

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*)

open CLike
open GenerateParams

(** Returns true if the expression is simple and does not need parenthesis *)
let isSimple (e:cexp) : bool =
   match e with
   | CEInt _
   | CEFloat _
   | CEBool _
   | CEString _
   | CECall _
   | CEVar _
   | CENewObj -> true
   | _ -> false

(** Returns a template the print the expression *)
let rec printExp (params:params) (e:cexp) : Pla.t =
   match e with
   | CEEmpty -> Pla.unit
   | CEFloat(s,n) ->
      (** Parenthesize if it has a unary minus *)
      if n < 0.0 then
         Pla.parenthesize (Pla.string s)
      else
         Pla.string s

   | CEInt(n) ->
      (** Parenthesize if it has a unary minus *)
      if n < 0 then
         Pla.parenthesize (Pla.int n)
      else
         Pla.int n
   | CEBool(v) -> Pla.int (if v then 1 else 0)

   | CEString(s) -> Pla.string_quoted s

   | CEArray(elems) ->
      let telems = Pla.map_sep Pla.comma (printExp params) elems in
      {pla|{<#telems#>}|pla}

   | CECall(name,args) ->
      let targs = Pla.map_sep Pla.comma (printExp params) args in
      {pla|<#name#s>(<#targs#>)|pla}

   | CEUnOp(op,e) ->
      let te = printExp params e in
      {pla|(<#op#s> <#te#>)|pla}

   | CEOp(op,elems) ->
      let sop = {pla| <#op#s> |pla} in
      let telems = Pla.map_sep sop (printExp params) elems in
      {pla|(<#telems#>)|pla}

   | CEVar(name) -> Pla.string name

   | CEIf(cond,then_,else_) ->
      let tcond = printExp params cond in
      let tthen = printExp params then_ in
      let telse = printExp params else_ in
      {pla|(<#tcond#>?<#tthen#>:<#telse#>)|pla}

   | CENewObj -> Pla.string "{}"

   | CETuple(elems) ->
      let telems = Pla.map_sep Pla.comma (printChField params) elems in
      {pla|{ <#telems#> }|pla}

(** Used to print the elements of a tuple *)
and printChField (params:params) ((name:string),(value:cexp)) =
   let tval = printExp params value in
   {pla|.<#name#s> = <#tval#>|pla}

(** Returns the base type name and a list of its sizes *)
let rec simplifyArray (typ:type_descr) : string * string list =
   match typ with
   | CTSimple(name) -> name, []
   | CTArray(sub,size) ->
      let name,sub_size = simplifyArray sub in
      name, sub_size @ [string_of_int size]

(** Returns the representation of a type description *)
let printTypeDescr (typ:type_descr) : Pla.t =
   let kind, sizes = simplifyArray typ in
   match sizes with
   | [] -> Pla.string kind
   | _ ->
      let tsize = Pla.map_sep Pla.comma Pla.string sizes in
      {pla|<#kind#s>[<#tsize#>]|pla}

(** Used to print declarations and rebindings of lhs variables *)
let printTypeAndName (is_decl:bool) (typ:type_descr) (name:string) : Pla.t =
   let kind, sizes = simplifyArray typ in
   match is_decl, sizes with
   (* Simple varible declaration (no sizes) *)
   | true,[] -> {pla|<#kind#s> <#name#s>|pla}
   (* Array declarations (with sizes) *)
   | true,_  ->
      let t_sizes = Pla.map_sep Pla.comma Pla.string sizes in
      {pla|<#kind#s> <#name#s>[<#t_sizes#>]|pla}
   (* Simple rebinding (no declaration) *)
   | _,_ -> {pla|<#name#s>|pla}

(** Used to print assignments of a tuple field to a variable *)
let printLhsExpTuple (var:string) (is_var:bool) (i:int) (e:clhsexp) : Pla.t =
   match e with
   (* Assigning to a simple variable *)
   | CLId(CTSimple(typ),name) ->
      if is_var then (* with declaration *)
         {pla|<#typ#s> <#name#s> = <#var#s>.field_<#i#i>;|pla}
      else (* with no declaration *)
         {pla|<#name#s> = <#var#s>.field_<#i#i>;|pla}

   | CLId(typ,name) ->
      let tdecl = printTypeAndName is_var typ name in
      {pla|<#tdecl#> = <#var#s>.field_<#i#i>;|pla}

   | CLWild -> Pla.unit

   | _ -> failwith "printLhsExpTuple: All other cases should be already covered"

(** Used to print assignments on to an array element *)
let printArrayBinding params (var:string) (i:int) (e:cexp) : Pla.t =
   let te = printExp params e in
   {pla|<#var#s>[<#i#i>] = <#te#>; |pla}

(** Prints lhs values with and without declaration *)
let printLhsExp (is_var:bool) (e:clhsexp) : Pla.t =
   match e with
   (* With declaration *)
   | CLId(CTSimple(typ),name) when is_var ->
      {pla|<#typ#s> <#name#s>|pla}
   (* without declaration *)
   | CLId(CTSimple(_),name) ->
      Pla.string name
   (* Other cases can be covered by printTypeAndName *)
   | CLId(typ,name) ->
      printTypeAndName is_var typ name
   (* if it was an '_' do not print anything *)
   | CLWild -> Pla.unit

   | _ -> failwith "printLhsExp: All other cases should be already covered"

(** Prints arguments to functions either pass by value or reference *)
let printFunArg (ntype,name) : Pla.t =
   match ntype with
   | Var(typ) ->
      let tdescr = printTypeDescr typ in
      {pla|<#tdescr#> <#name#s>|pla}
   | Ref(typ) ->
      let tdescr = printTypeDescr typ in
      {pla|<#tdescr#> &<#name#s>|pla}

(** Print a statement *)
let rec printStmt (params:params) (stmt:cstmt) : Pla.t option =
   match stmt with
   (* Strange case '_' *)
   | CSVarDecl(CLWild,None) -> None

   (* Prints type _ = ... *)
   | CSVarDecl(CLWild,Some(value)) ->
      let te = printExp params value in
      Some({pla|<#te#>;|pla})

   (* Prints type x = ... *)
   | CSVarDecl((CLId(_,_) as lhs),Some(value)) ->
      let tlhs = printLhsExp true lhs in
      let te   = printExp params value in
      Some({pla|<#tlhs#> = <#te#>;|pla})

   (* Prints type x; *)
   | CSVarDecl((CLId(_,_) as lhs),None) ->
      let tlhs = printLhsExp true lhs in
      Some({pla|<#tlhs#>;|pla})

   (* Print type (x,y,z) = ... *)
   | CSVarDecl(CLTuple(elems),Some(CEVar(name))) ->
      let t = List.mapi (printLhsExpTuple name true) elems |> Pla.join in
      Some(t)

   (* All other cases of assigning tuples will be wrong *)
   | CSVarDecl(CLTuple(_),_) -> failwith "printStmt: invalid tuple assign"

   (* Prints _ = ... *)
   | CSBind(CLWild,value) ->
      let te = printExp params value in
      Some({pla|<#te#>;|pla})

   (* Print (x,y,z) = ... *)
   | CSBind(CLTuple(elems),CEVar(name)) ->
      let t =List.mapi (printLhsExpTuple name false) elems |> Pla.join in
      Some(t)

   (* All other cases of assigning tuples will be wrong *)
   | CSBind(CLTuple(_),_) -> failwith "printStmt: invalid tuple assign"

   (* Prints x = [ ... ] *)
   | CSBind(CLId(_,name),CEArray(elems)) ->
      let t = List.mapi (printArrayBinding params name) elems |> Pla.join in
      Some(t)

   (* Prints x = ... *)
   | CSBind(CLId(_,name),value) ->
      let te = printExp params value in
      Some({pla|<#name#s> = <#te#>;|pla})

   (* Function declarations cotaining more than one statement *)
   | CSFunction(ntype,name,args,(CSBlock(_) as body)) ->
      let ret   = printTypeDescr ntype in
      let targs = Pla.map_sep Pla.commaspace printFunArg args in
      (* if we are printing a header, skip the body *)
      if params.is_header then begin
         Some({pla|<#ret#> <#name#s>(<#targs#>);<#>|pla})
      end
      else begin
         match printStmt params body with
         | Some(tbody) ->
            Some({pla|<#ret#> <#name#s>(<#targs#>)<#tbody#><#>|pla})
         (* Covers the case when the body is empty *)
         | None -> Some({pla|<#ret#> <#name#s>(<#targs#>){};<#>|pla})
      end
   (* Function declarations cotaining a single statement *)
   | CSFunction(ntype,name,args,body) ->
      let ret = printTypeDescr ntype in
      let targs = Pla.map_sep Pla.commaspace printFunArg args in
      (* if we are printing a header, skip the body *)
      if params.is_header then
         Some({pla|<#ret#> <#name#s>(<#targs#>);<#>|pla})
      else
         let tbody = CCOpt.get_or ~default:Pla.unit (printStmt params body) in
         Some({pla|<#ret#> <#name#s>(<#targs#>){<#tbody#>}<#>|pla})

   (* Prints return x *)
   | CSReturn(e1) ->
      let te = printExp params e1 in
      Some({pla|return <#te#>;|pla})

   (* Printf while(cond) ... *)
   | CSWhile(cond,body) ->
      let tcond = printExp params cond in
      let tbody = CCOpt.get_or ~default:Pla.semi (printStmt params body) in
      Some({pla|while(<#tcond#>)<#tbody#>|pla})

   (* Prints a block of statements*)
   | CSBlock(elems) ->
      let telems = printStmtList params elems in
      Some({pla|{<#telems#+>}|pla})

   (* If-statement without an else*)
   | CSIf(cond,then_,None) ->
      let tcond = printExp params cond in
      let tcond = if isSimple cond then Pla.wrap (Pla.string "(") (Pla.string ")") tcond else tcond in
      let tthen = CCOpt.get_or ~default:Pla.semi (printStmt params then_) in
      Some({pla|if<#tcond#><#tthen#>|pla})

   (* If-statement with else*)
   | CSIf(cond,then_,Some(else_)) ->
      let tcond = printExp params cond in
      let tcond = if isSimple cond then Pla.wrap (Pla.string "(") (Pla.string ")") tcond else tcond in
      let tthen = CCOpt.get_or ~default:Pla.semi (printStmt params then_) in
      let telse = CCOpt.get_or ~default:Pla.semi (printStmt params else_) in
      Some({pla|if<#tcond#><#tthen#><#>else<#><#telse#>|pla})

   (* Type declaration (only in headers) *)
   | CSType(name,members) when params.is_header ->
      let tmembers =
         Pla.map_sep_all Pla.newline
            (fun (typ, name) ->
                let tmember = printTypeAndName true typ name in
                {pla|<#tmember#>;|pla}
            ) members;
      in
      Some({pla|typedef struct <#name#s> {<#tmembers#+>} <#name#s>;<#>|pla})

   (* Do not print type delcarations in implementation file *)
   | CSType(_,_) -> None

   (* Type declaration aliases (only in headers) *)
   | CSAlias(t1,t2) when params.is_header ->
      let tdescr = printTypeDescr t2 in
      Some({pla|typedef <#t1#s> <#tdescr#>;<#>|pla})

   (* Do not print type delcarations in implementation file *)
   | CSAlias(_,_) -> None

   (* External function definitions (only in headers) *)
   | CSExtFunc(ntype,name,args) when params.is_header ->
      let ret = printTypeDescr ntype in
      let targs = Pla.map_sep Pla.commaspace printFunArg args in
      Some({pla|<#ret#> <#name#s>(<#targs#>);|pla})

   (* Do not print external function delcarations in implementation file *)
   | CSExtFunc _ -> None

   | CSEmpty -> None

and printStmtList (params:params) (stmts:cstmt list) : Pla.t =
   (* Prints the statements and removes all elements that are None *)
   let tstmts = CCList.filter_map (printStmt params) stmts in
   Pla.map_sep_all Pla.newline (fun a -> a) tstmts

let printChCode (params:params) (stmts:cstmt list) : Pla.t =
   let code = printStmtList params stmts in
   Templates.apply params code

(** Generates the .c and .h file contents for the given parsed files *)
let print (params:params) (stmts:CLike.cstmt list) : (Pla.t * string) list =
   let h   = printChCode { params with is_header = true } stmts in
   let cpp = printChCode { params with is_header = false } stmts in
   [h,"h"; cpp,"cpp"]
