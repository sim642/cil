(*

   Copyright (c) 2001-2003,
    George C. Necula    <necula@cs.berkeley.edu>
    Scott McPeak        <smcpeak@cs.berkeley.edu>
    Wes Weimer          <weimer@cs.berkeley.edu>
    Ben Liblit          <liblit@cs.berkeley.edu>
   All rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions are
   met:

   1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

   2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

   3. The names of the contributors may not be used to endorse or promote
   products derived from this software without specific prior written
   permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
   IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
   TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
   PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER
   OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

 *)
(* FrontC -- lexical analyzer
**
** 1.0	3.22.99	Hugues Cass�	First version.
** 2.0  George Necula 12/12/00: Many extensions
*)
{
open Cparser
open Pretty
exception InternalError of string
module E = Errormsg
module H = Hashtbl

let matchingParsOpen = ref 0

let currentLoc () = Cabshelper.currentLoc ()

(* string -> unit *)
let addComment c =
  let l = currentLoc() in
  let i = GrowArray.max_init_index Cabshelper.commentsGA in
  GrowArray.setg Cabshelper.commentsGA (i+1) (l,c,false)

(* track whitespace for the current token *)
let white = ref ""
let addWhite lexbuf = if not !Whitetrack.enabled then
    let w = Lexing.lexeme lexbuf in
    white := !white ^ w
let clear_white () = white := ""
let get_white () = !white

let lexeme = ref ""
let addLexeme lexbuf =
    let l = Lexing.lexeme lexbuf in
    lexeme := !lexeme ^ l
let clear_lexeme () = lexeme := ""
let get_extra_lexeme () = !lexeme

let int64_to_char value =
  if (compare value (Int64.of_int 255) > 0) || (compare value Int64.zero < 0) then
    begin
      let msg = Printf.sprintf "clexer:intlist_to_string: character 0x%Lx too big" value in
      E.parse_error msg;
    end
  else
    Char.chr (Int64.to_int value)

(* takes a not-nul-terminated list, and converts it to a string. *)
let rec intlist_to_string (str: int64 list):string =
  match str with
    [] -> ""  (* add nul-termination *)
  | value::rest ->
      let this_char = int64_to_char value in
      (String.make 1 this_char) ^ (intlist_to_string rest)

(* Some debugging support for line numbers *)
let dbgToken (t: token) =
  if false then begin
    ignore (E.log "%a" insert
              (match t with
                IDENT (n, l) -> dprintf "IDENT(%s,%d)\n" n l.Cabs.lineno
              | LBRACE l -> dprintf "LBRACE(%d)\n" l.Cabs.lineno
              | RBRACE l -> dprintf "RBRACE(%d)\n" l.Cabs.lineno
              | IF l -> dprintf "IF(%d)\n" l.Cabs.lineno
              | SWITCH l -> dprintf "SWITCH(%d)\n" l.Cabs.lineno
              | RETURN l -> dprintf "RETURN(%d)\n" l.Cabs.lineno
              | _ -> nil));
    t
  end else
    t


(*
** Keyword hashtable
*)
let lexicon = H.create 211
let init_lexicon _ =
  H.clear lexicon;
  List.iter
    (fun (key, builder) -> H.add lexicon key builder)
    [ ("auto", fun loc -> AUTO loc);
      ("const", fun loc -> CONST loc);
      ("__const", fun loc -> CONST loc);
      ("__const__", fun loc -> CONST loc);
      ("_Atomic", fun loc -> ATOMIC loc);
      ("_Complex", fun loc -> COMPLEX loc);
      ("__complex__", fun loc -> COMPLEX loc);
      ("static", fun loc -> STATIC loc);
      ("extern", fun loc -> EXTERN loc);
      ("long", fun loc -> LONG loc);
      ("short", fun loc -> SHORT loc);
      ("register", fun loc -> REGISTER loc);
      ("signed", fun loc -> SIGNED loc);
      ("__signed", fun loc -> SIGNED loc);
      ("unsigned", fun loc -> UNSIGNED loc);
      ("volatile", fun loc -> VOLATILE loc);
      ("__volatile", fun loc -> VOLATILE loc);
      (* WW: see /usr/include/sys/cdefs.h for why __signed and __volatile
         are accepted GCC-isms *)
      ("_Bool", fun loc -> BOOL loc);
      ("char", fun loc -> CHAR loc);
      ("int", fun loc -> INT loc);
      ("float", fun loc -> FLOAT loc);
      ("__float128", fun loc -> FLOAT128 loc);
      ("_Float128", fun loc -> FLOAT128 loc);
      ("_Float32", fun loc -> FLOAT32 loc);
      ("_Float64", fun loc -> FLOAT64 loc);
      ("_Float32x", fun loc -> FLOAT32X loc);
      ("_Float64x", fun loc -> FLOAT64X loc);
      ("double", fun loc -> DOUBLE loc);
      ("void", fun loc -> VOID loc);
      ("enum", fun loc -> ENUM loc);
      ("struct", fun loc -> STRUCT loc);
      ("typedef", fun loc -> TYPEDEF loc);
      ("union", fun loc -> UNION loc);
      ("break", fun loc -> BREAK loc);
      ("continue", fun loc -> CONTINUE loc);
      ("goto", fun loc -> GOTO loc);
      ("return", fun loc -> dbgToken (RETURN loc));
      ("switch", fun loc -> dbgToken (SWITCH loc));
      ("case", fun loc -> CASE loc);
      ("default", fun loc -> DEFAULT loc);
      ("while", fun loc -> WHILE loc);
      ("do", fun loc -> DO loc);
      ("for", fun loc -> FOR loc);
      ("if", fun loc -> dbgToken (IF loc));
      ("else", fun _ -> ELSE);
      (*** Implementation specific keywords ***)
      ("__signed__", fun loc -> SIGNED loc);
      ("__inline__", fun loc -> INLINE loc);
      ("inline", fun loc -> INLINE loc);
      ("__inline", fun loc -> INLINE loc);
      ("_inline", fun loc -> IDENT ("_inline", loc));
      ("_Noreturn", fun loc -> NORETURN loc);
      ("_Static_assert", fun loc -> STATIC_ASSERT loc);
      ("__attribute__", fun loc -> ATTRIBUTE loc);
      ("__attribute", fun loc -> ATTRIBUTE loc);
(*
      ("__attribute_used__", fun loc -> ATTRIBUTE_USED loc);
*)
      ("__blockattribute__", fun _ -> BLOCKATTRIBUTE);
      ("__blockattribute", fun _ -> BLOCKATTRIBUTE);
      ("__asm__", fun loc -> ASM loc);
      ("asm", fun loc -> ASM loc);
      ("__typeof__", fun loc -> TYPEOF loc);
      ("__typeof", fun loc -> TYPEOF loc);
      ("typeof", fun loc -> TYPEOF loc);
      ("__alignof", fun loc -> ALIGNOF loc);
      ("_Alignof", fun loc -> ALIGNOF loc);
      ("__alignof__", fun loc -> ALIGNOF loc);
      ("_Alignas", fun loc -> ALIGNAS loc);
      ("__volatile__", fun loc -> VOLATILE loc);
      ("__volatile", fun loc -> VOLATILE loc);
      ("__real__", fun loc -> REAL loc);
      ("__imag__", fun loc -> IMAG loc);
      ("__builtin_classify_type", fun loc -> CLASSIFYTYPE loc);
      ("__FUNCTION__", fun loc -> FUNCTION__ loc);
      ("__func__", fun loc -> FUNCTION__ loc); (* ISO 6.4.2.2 *)
      ("__PRETTY_FUNCTION__", fun loc -> PRETTY_FUNCTION__ loc);
      ("__label__", fun _ -> LABEL__);
      (*** weimer: GCC arcana ***)
      ("__restrict", fun loc -> RESTRICT loc);
      ("__restrict__", fun loc -> RESTRICT loc);
      ("restrict", fun loc -> RESTRICT loc);
      ("__auto_type", fun loc -> AUTOTYPE loc);
(*      ("__extension__", EXTENSION); *)
      (**** MS VC ***)
      ("__int32", fun loc -> INT loc);
      ("__int64", fun _ -> INT64 (currentLoc ()));
      ("__int128", fun _ -> INT128 (currentLoc ()));
      ("__declspec", fun loc -> DECLSPEC loc);
      ("__forceinline", fun loc -> INLINE loc); (* !! we turn forceinline
                                                   into inline *)
      (* weimer: some files produced by 'GCC -E' expect this type to be
         defined *)
      ("__builtin_va_list",
       fun _ -> NAMED_TYPE ("__builtin_va_list", currentLoc ()));
      ("__builtin_va_arg", fun loc -> BUILTIN_VA_ARG loc);
      ("__builtin_types_compatible_p", fun loc -> BUILTIN_TYPES_COMPAT loc);
      ("__builtin_offsetof", fun loc -> BUILTIN_OFFSETOF loc);
      (* On some versions of GCC __thread is a regular identifier *)
      ("__thread", fun loc ->
                      if !Machdep.theMachine.Machdep.__thread_is_keyword then
                         THREAD loc
                       else
                         IDENT ("__thread", loc));
      ("_Generic", fun loc -> GENERIC loc);
    ]

(* Mark an identifier as a type name. The old mapping is preserved and will
   be reinstated when we exit this context *)
let add_type name =
   (* ignore (print_string ("adding type name " ^ name ^ "\n"));  *)
   H.add lexicon name (fun loc -> NAMED_TYPE (name, loc))

let context : string list list ref = ref [[]]

let push_context _ = context := []::!context

let pop_context _ =
  match !context with
    [] -> raise (InternalError "Empty context stack")
  | con::sub ->
		(context := sub;
		List.iter (fun name ->
                           (* ignore (print_string ("removing lexicon for " ^ name ^ "\n")); *)
                            H.remove lexicon name) con)

(* Mark an identifier as a variable name. The old mapping is preserved and
   will be reinstated when we exit this context  *)
let add_identifier name =
  match !context with
    [] -> raise (InternalError "Empty context stack")
  | con::sub ->
      (context := (name::con)::sub;
       (*                print_string ("adding IDENT for " ^ name ^ "\n"); *)
       H.add lexicon name (fun loc ->
         dbgToken (IDENT (name, loc))))


(*
** Useful primitives
*)
let scan_ident id =
  let here = currentLoc () in
  try (H.find lexicon id) here
  (* default to variable name, as opposed to type *)
  with Not_found ->
    if id.[0] = '$' then QUALIFIER(id,here) else
    dbgToken (IDENT (id, here))


(*
** Buffer processor
*)


let init ~(filename: string) : Lexing.lexbuf =
  init_lexicon ();
  (* Inititialize the pointer in Errormsg *)
  Lexerhack.add_type := add_type;
  (* add some built-in types which are handled as Tnamed in cabs2cil *)
  add_type "__int128_t"; (* __int128 *)
  add_type "__uint128_t"; (* unsigned __int128 *)
  Lexerhack.push_context := push_context;
  Lexerhack.pop_context := pop_context;
  Lexerhack.add_identifier := add_identifier;
  E.startParsing filename

let initFromString (s: string) : Lexing.lexbuf =
  init_lexicon ();
  (* Inititialize the pointer in Errormsg *)
  Lexerhack.add_type := add_type;
  (* add some built-in types which are handled as Tnamed in cabs2cil *)
  add_type "__int128_t"; (* __int128 *)
  add_type "__uint128_t"; (* unsigned __int128 *)
  Lexerhack.push_context := push_context;
  Lexerhack.pop_context := pop_context;
  Lexerhack.add_identifier := add_identifier;
  E.startParsingFromString s


let finish () =
  E.finishParsing ()

(*** Error handling ***)
let error msg =
  E.parse_error msg


(*** escape character management ***)
let scan_escape (char: char) : int64 =
  let result = match char with
  | 'n' -> '\n'
  | 'r' -> '\r'
  | 't' -> '\t'
  | 'b' -> '\b'
  | 'f' -> '\012'  (* ASCII code 12 *)
  | 'v' -> '\011'  (* ASCII code 11 *)
  | 'a' -> '\007'  (* ASCII code 7 *)
  | 'e' | 'E' -> '\027'  (* ASCII code 27. This is a GCC extension *)
  | '\'' | '"' | '?' | '(' | '{' | '[' | '%' | '\\' -> char
  | _ -> error ("Unrecognized escape sequence: \\" ^ (String.make 1 char))
  in
  Int64.of_int (Char.code result)

let scan_hex_escape str =
  let radix = Int64.of_int 16 in
  let the_value = ref Int64.zero in
  (* start at character 2 to skip the \x *)
  for i = 2 to (String.length str) - 1 do
    let thisDigit = Cabshelper.valueOfDigit (String.get str i) in
    (* the_value := !the_value * 16 + thisDigit *)
    the_value := Int64.add (Int64.mul !the_value radix) thisDigit
  done;
  !the_value

let scan_oct_escape str =
  let radix = Int64.of_int 8 in
  let the_value = ref Int64.zero in
  (* start at character 1 to skip the \x *)
  for i = 1 to (String.length str) - 1 do
    let thisDigit = Cabshelper.valueOfDigit (String.get str i) in
    (* the_value := !the_value * 8 + thisDigit *)
    the_value := Int64.add (Int64.mul !the_value radix) thisDigit
  done;
  !the_value

(* For a given Unicode Code-point of type Int64, calculates the UTF-8 representation and returns the bytes
   in a list of 1-4 int64 values in reverse order, such that the first byte is the last element of the list *)
let utf8_representation value =
  let generate_bytes n =
    let first_byte =
      let first_byte_prefix = match n with 1 -> 0L | 2 -> 0xC0L | 3 -> 0xE0L | 4 -> 0xF0L | _ -> E.s(error "error in utf8_representation"); in
      Int64.logor first_byte_prefix (Int64.shift_right_logical value (6*(n-1)))
    in
    let rec generate_one bytes n =
      if n = 1 then bytes
      else generate_one ((Int64.logor 0x80L (Int64.logand (Int64.shift_right_logical value (6*(n-2))) 0x3FL)) :: bytes) (n-1)
    in
    generate_one [first_byte] n
  in
  let num_bytes = if value <= 127L then 1 else if value <= 2047L then 2 else if value <= 65535L then 3 else 4 in
  generate_bytes num_bytes

let lex_hex_escape remainder lexbuf =
  let prefix = scan_hex_escape (Lexing.lexeme lexbuf) in
  prefix :: remainder lexbuf

let lex_oct_escape remainder lexbuf =
  let prefix = scan_oct_escape (Lexing.lexeme lexbuf) in
  prefix :: remainder lexbuf

let lex_simple_escape remainder lexbuf =
  let lexchar = Lexing.lexeme_char lexbuf 1 in
  let prefix = scan_escape lexchar in
  prefix :: remainder lexbuf

let lex_universal_escape ischar remainder lexbuf =
  let value = scan_hex_escape (Lexing.lexeme lexbuf) in
  if ischar then
    value :: remainder lexbuf
  else
    let prefix = utf8_representation value in
    List.rev_append prefix (remainder lexbuf)

let lex_unescaped remainder lexbuf =
  let prefix = Int64.of_int (Char.code (Lexing.lexeme_char lexbuf 0)) in
  prefix :: remainder lexbuf

let lex_comment remainder lexbuf =
  let ch = Lexing.lexeme_char lexbuf 0 in
  let prefix = Int64.of_int (Char.code ch) in
  if ch = '\n' then E.newline();
  prefix :: remainder lexbuf


(* ISO standard locale-specific function to convert a wide character
   into a sequence of normal characters. Here we work on strings.
   We convert L"Hi" to "H\000i\000"
  matth: this seems unused.
let wbtowc wstr =
  let len = String.length wstr in
  let dest = String.make (len * 2) '\000' in
  for i = 0 to len-1 do
    dest.[i*2] <- wstr.[i] ;
  done ;
  dest
*)

(* This function converst the "Hi" in L"Hi" to { L'H', L'i', L'\0' }
  matth: this seems unused.
let wstr_to_warray wstr =
  let len = String.length wstr in
  let res = ref "{ " in
  for i = 0 to len-1 do
    res := !res ^ (Printf.sprintf "L'%c', " wstr.[i])
  done ;
  res := !res ^ "}" ;
  !res
*)

(* Pragmas get explicit end-of-line tokens.
   Elsewhere they are silently discarded as whitespace. *)
let pragmaLine = ref false

}

let decdigit = ['0'-'9']
let octdigit = ['0'-'7']
let hexdigit = ['0'-'9' 'a'-'f' 'A'-'F']
let letter = ['a'- 'z' 'A'-'Z']


let usuffix = ['u' 'U']
let lsuffix = "l"|"L"|"ll"|"LL"
let intsuffix = lsuffix | usuffix | usuffix lsuffix | lsuffix usuffix
              | usuffix ? "i64"


let hexprefix = '0' ['x' 'X']

let intnum = decdigit+ intsuffix?
let octnum = '0' octdigit+ intsuffix?
let hexnum = hexprefix hexdigit+ intsuffix?

let exponent = ['e' 'E']['+' '-']? decdigit+
let fraction  = '.' decdigit+
let decfloat = (intnum? fraction)
	      |(intnum exponent)
	      |(intnum? fraction exponent)
	      | (intnum '.')
              | (intnum '.' exponent)

let hexfraction = hexdigit* '.' hexdigit+ | hexdigit+ '.'
let binexponent = ['p' 'P'] ['+' '-']? decdigit+
let hexfloat = hexprefix hexfraction binexponent
             | hexprefix hexdigit+   binexponent

let floatsuffix = ['f' 'F' 'l' 'L']
let floatnum = (decfloat | hexfloat) floatsuffix?

let complexnum = (decfloat | hexfloat) ((['i' 'I'] floatsuffix) | (floatsuffix? ['i' 'I']))


let blank = [' ' '\t' '\012' '\r']+
let escape = '\\' _
let hex_escape = '\\' ['x' 'X'] hexdigit+
let oct_escape = '\\' octdigit octdigit? octdigit?
let hexquad = hexdigit hexdigit hexdigit hexdigit
let universal_escape = '\\' ('u' hexquad | 'U' hexquad hexquad)
let ident = (letter|'_'|'$'|universal_escape)(letter|decdigit|'_'|'$'|universal_escape)*

(* Pragmas that are not parsed by CIL.  We lex them as PRAGMA_LINE tokens *)
let no_parse_pragma =
               "warning" | "GCC" | "STDC" | "clang"
             (* Solaris-style pragmas:  *)
             | "ident" | "section" | "option" | "asm" | "use_section" | "weak"
             | "redefine_extname"
             | "TCS_align"
	     | "mark"


rule initial =
	parse 	"/*"			{ let il = comment lexbuf in
	                                  let sl = intlist_to_string il in
					  addComment sl;
                                          addWhite lexbuf;
                                          initial lexbuf}
|               "//"                    { let il = onelinecomment lexbuf in
                                          let sl = intlist_to_string il in
                                          addComment sl;
                                          E.newline();
                                          addWhite lexbuf;
                                          initial lexbuf
                                           }
|		blank			{ addWhite lexbuf; initial lexbuf}
|               '\n'                    { E.newline ();
                                          if !pragmaLine then
                                            begin
                                              pragmaLine := false;
                                              PRAGMA_EOL
                                            end
                                          else begin
                                            addWhite lexbuf;
                                            initial lexbuf
                                          end}
|               '\\' '\r' * '\n'        { addWhite lexbuf;
                                          E.newline ();
                                          initial lexbuf
                                        }
|		'#'			{ addWhite lexbuf; hash lexbuf}
|               "_Pragma" 	        { PRAGMA (currentLoc ()) }
|		'\''			{ CST_CHAR (chr lexbuf, currentLoc ())}
|		"L'"			{ CST_WCHAR (chr lexbuf, currentLoc ()) }
|   "u'"      { CST_CHAR16 (chr lexbuf, currentLoc ()) }
|   "U'"      { CST_CHAR32 (chr lexbuf, currentLoc ()) }
|		'"'			{ addLexeme lexbuf; (* '"' *)
(* matth: BUG:  this could be either a regular string or a wide string.
    e.g. if it's the "world" in
       L"Hello, " "world"
    then it should be treated as wide even though there's no L immediately
    preceding it.  See test/small1/wchar5.c for a failure case. *)
                                          try CST_STRING (str lexbuf, currentLoc ())
                                          with e ->
                                             raise (InternalError
                                                     ("str: " ^
                                                      Printexc.to_string e))}
|   "u8\""    { addLexeme lexbuf; (* '"' *)
                                          try CST_U8STRING (str lexbuf, currentLoc ())
                                          with e ->
                                             raise (InternalError
                                                     ("str: " ^
                                                      Printexc.to_string e))}
|		"L\""			{ (* weimer: wchar_t string literal *)
                                          try CST_WSTRING(str lexbuf, currentLoc ())
                                          with e ->
                                             raise (InternalError
                                                     ("wide string: " ^
                                                      Printexc.to_string e))}
|   "u\""       {try CST_STRING16(str lexbuf, currentLoc ())
                  with e ->
                    raise (InternalError ("wide string: " ^ Printexc.to_string e))}
|   "U\""       {try CST_STRING32(str lexbuf, currentLoc ())
                  with e ->
                    raise (InternalError ("wide string: " ^ Printexc.to_string e))}
|		floatnum		{CST_FLOAT (Lexing.lexeme lexbuf, currentLoc ())}
|   complexnum  {CST_COMPLEX (Lexing.lexeme lexbuf, currentLoc ())}
|		hexnum			{CST_INT (Lexing.lexeme lexbuf, currentLoc ())}
|		octnum			{CST_INT (Lexing.lexeme lexbuf, currentLoc ())}
|		intnum			{CST_INT (Lexing.lexeme lexbuf, currentLoc ())}
|		"!quit!"		{EOF}
|		"..."			{ELLIPSIS}
|		"+="			{PLUS_EQ}
|		"-="			{MINUS_EQ}
|		"*="			{STAR_EQ}
|		"/="			{SLASH_EQ}
|		"%="			{PERCENT_EQ}
|		"|="			{PIPE_EQ}
|		"&="			{AND_EQ}
|		"^="			{CIRC_EQ}
|		"<<="			{INF_INF_EQ}
|		">>="			{SUP_SUP_EQ}
|		"<<"			{INF_INF}
|		">>"			{SUP_SUP}
| 		"=="			{EQ_EQ}
| 		"!="			{EXCLAM_EQ}
|		"<="			{INF_EQ}
|		">="			{SUP_EQ}
|		"="				{EQ}
|		"<"				{INF}
|		">"				{SUP}
|		"++"			{PLUS_PLUS (currentLoc ())}
|		"--"			{MINUS_MINUS (currentLoc ())}
|		"->"			{ARROW}
|		'+'				{PLUS (currentLoc ())}
|		'-'				{MINUS (currentLoc ())}
|		'*'				{STAR (currentLoc ())}
|		'/'				{SLASH}
|		'%'				{PERCENT}
|		'!'			{EXCLAM (currentLoc ())}
|		"&&"			{AND_AND (currentLoc ())}
|		"||"			{PIPE_PIPE}
|		'&'				{AND (currentLoc ())}
|		'|'				{PIPE}
|		'^'				{CIRC}
|		'?'				{QUEST}
|		':'				{COLON (currentLoc ())}
|		'~'		       {TILDE (currentLoc ())}

|		'{'		       {dbgToken (LBRACE (currentLoc ()))}
|		'}'		       {dbgToken (RBRACE (currentLoc ()))}
|		'['				{LBRACKET}
|		']'				{RBRACKET}
|		'('		       {dbgToken (LPAREN (currentLoc ())) }
|		')'				{dbgToken (RPAREN (currentLoc ()))}
|		';'		       {dbgToken (SEMICOLON (currentLoc ())) }
|		','				{COMMA}
|		'.'				{DOT}
|		"sizeof"		{SIZEOF (currentLoc ())}
|               "__asm"                 { (ASM (currentLoc ())) }

(* If we see __pragma we eat it and the matching parentheses as well *)
|               "__pragma"              { matchingParsOpen := 0;
                                          let _ = matchingpars lexbuf in
                                          addWhite lexbuf;
                                          initial lexbuf
                                        }

(* sm: tree transformation keywords *)
|               "@transform"            {AT_TRANSFORM (currentLoc ())}
|               "@transformExpr"        {AT_TRANSFORMEXPR (currentLoc ())}
|               "@specifier"            {AT_SPECIFIER (currentLoc ())}
|               "@expr"                 {AT_EXPR (currentLoc ())}
|               "@name"                 {AT_NAME}

(* __extension__ is a black. The parser runs into some conflicts if we let it
   pass *)
|               "__extension__"         {addWhite lexbuf; initial lexbuf }
|		ident			{scan_ident (Lexing.lexeme lexbuf)}
|		eof			{EOF}
|		_			{E.parse_error "Invalid symbol"}
and comment =
    parse
      "*/"			        { addWhite lexbuf; [] }
(*|     '\n'                              { E.newline (); lex_unescaped comment lexbuf }*)
| 		_ 			{ addWhite lexbuf; lex_comment comment lexbuf }


and onelinecomment = parse
    '\n'|eof    {addWhite lexbuf; []}
|   _           {addWhite lexbuf; lex_comment onelinecomment lexbuf }

and matchingpars = parse
  '\n'          { addWhite lexbuf; E.newline (); matchingpars lexbuf }
| blank         { addWhite lexbuf; matchingpars lexbuf }
| '('           { addWhite lexbuf; incr matchingParsOpen; matchingpars lexbuf }
| ')'           { addWhite lexbuf; decr matchingParsOpen;
                  if !matchingParsOpen = 0 then
                     ()
                  else
                     matchingpars lexbuf
                }
|  "/*"		{ addWhite lexbuf; let il = comment lexbuf in
                  let sl = intlist_to_string il in
		  addComment sl;
                  matchingpars lexbuf}
|  '"'		{ addWhite lexbuf; (* '"' *)
                  let _ = str lexbuf in
                  matchingpars lexbuf
                 }
| _              { addWhite lexbuf; matchingpars lexbuf }

(* # <line number> <file name> ... *)
and hash = parse
  '\n'		{ addWhite lexbuf; E.newline (); initial lexbuf}
| blank		{ addWhite lexbuf; hash lexbuf}
| intnum	{ addWhite lexbuf; (* We are seeing a line number. This is the number for the
                     next line *)
                 let s = Lexing.lexeme lexbuf in
                 let lineno = try
                   int_of_string s
                 with Failure _ ->
                   (* the int is too big. *)
                   E.warn "Bad line number in preprocessed file: %s" s;
                   (-1)
                 in
                  (* A file name may follow *)
		  file (lineno - 1) lexbuf }
| "line"        { addWhite lexbuf; hash lexbuf } (* MSVC line number info *)
                (* For pragmas with irregular syntax, like #pragma warning,
                   we parse them as a whole line. *)
| "pragma" blank (no_parse_pragma as pragmaName)
                { let here = currentLoc () in
                  PRAGMA_LINE (pragmaName ^ pragma lexbuf, here)
                }
| "pragma"      { pragmaLine := true; PRAGMA (currentLoc ()) }
| _	        { addWhite lexbuf; endline lexbuf}

and file lineno =  parse
        '\n'		        {addWhite lexbuf; E.setCurrent ~file:None ~line:lineno; E.newline (); initial lexbuf}
|	blank			{addWhite lexbuf; file lineno lexbuf}
|	'"' ([^ '\012' '\t' '"']* as filename) '"' ((' ' ['1' -'4'])* as flags)
       { addWhite lexbuf;  (* '"' *)
         E.setCurrent ~file:(Some (filename, String.contains flags '3')) ~line:lineno;
				 endline lexbuf}

|	_			{addWhite lexbuf; E.setCurrent ~file:None ~line:lineno; endline lexbuf}

and endline = parse
        '\n' 			{ addWhite lexbuf; E.newline (); initial lexbuf}
|   eof                         { EOF }
|	_			{ addWhite lexbuf; endline lexbuf}

and pragma = parse
   '\n'                 { E.newline (); "" }
|   _                   { let cur = Lexing.lexeme lexbuf in
                          cur ^ (pragma lexbuf) }

and str = parse
        '"'             {[]} (* no nul terminiation in CST_STRING '"' *)
|	hex_escape	{addLexeme lexbuf; lex_hex_escape str lexbuf}
|	oct_escape	{addLexeme lexbuf; lex_oct_escape str lexbuf}
|	escape		{addLexeme lexbuf; lex_simple_escape str lexbuf}
| universal_escape {addLexeme lexbuf; lex_universal_escape false str lexbuf}
|	_		{addLexeme lexbuf; lex_unescaped str lexbuf}

and chr =  parse
	'\''	        {[]}
|	hex_escape	{lex_hex_escape chr lexbuf}
|	oct_escape	{lex_oct_escape chr lexbuf}
|	escape		{lex_simple_escape chr lexbuf}
| universal_escape {lex_universal_escape true chr lexbuf}
|	_		{lex_unescaped chr lexbuf}

{

}
