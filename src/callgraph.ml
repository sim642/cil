(* callgraph.ml *)
(* code for callgraph.mli *)

(* see copyright notice at end of this file *)

open Cil
open Trace
open Printf
module P = Pretty


(* ------------------- interface ------------------- *)
(* a call node describes the local calling structure for a
 * single function: which functions it calls, and which
 * functions call it *)
type callnode = {
  (* name of the function this node describes *)
  cnName: string;

  (* set of functions this one calls *)
  cnCallees: (string, callnode) Hashtbl.t;

  (* set of functions that call this one *)
  cnCallers: (string, callnode) Hashtbl.t;
}

(* a call graph is a hashtable, mapping a function name to
 * the node which describes that function's call structure *)
type callgraph =
  (string, callnode) Hashtbl.t


(* ------------------- implementation --------------------------- *)
(* add something to a hashtable if it's not already there, instead of
 * the default pushback behavior of Hashtbl.add *)
let add_if (table : ('a,'b) Hashtbl.t) (key:'a) (data:'b) : unit =
begin
  if (not (Hashtbl.mem table key)) then
    (Hashtbl.add table key data)
end


class cgComputer = object(self)
  inherit nopCilVisitor

  (* this is the graph we are computing, and will eventually return;
   * it is created empty when the object is constructed, and will
   * be added-to during the computation *)
  val graph: callgraph = (Hashtbl.create 117)

  (* the current function we're in, so when we visit a call node
   * we know who is the caller *)
  val mutable curFunc: callnode option = None


  (* I don't know syntax for extracting a field directly, or else
   * OCaml doesn't allow it.. *)
  method getGraph () : callgraph = graph

  (* given the name of a function, retrieve its callnode; this
   * will create a node if one doesn't already exist *)
  method getNode (name:string) : callnode =
  begin
    try
      (Hashtbl.find graph name)

    with Not_found -> (
      (* make a new node *)
      let ret:callnode = {
        cnName = name;
        cnCallees = (Hashtbl.create 5);
        cnCallers = (Hashtbl.create 5);
      }  in

      (* add it to the table, then return it *)
      (Hashtbl.add graph name ret);
      ret
    )
  end

  (* begin visiting a function definition *)
  method vfunc (f:fundec) : fundec visitAction =
  begin
    (trace "callgraph" (P.dprintf "entering function %s\n" f.svar.vname));
    curFunc <- (Some (self#getNode f.svar.vname));
    DoChildren
  end

  (* visit an instruction; we're only interested in calls *)
  method vinst (i:instr) : instr list visitAction =
  begin
    (*(trace "callgraph" (P.dprintf "visiting instruction: %a\n" dn_instr i));*)

    (match curFunc, i with
    | Some(caller),       (* should always be set to something *)
      Call(_,lval,_,_) -> (
        (* match calls using named functions, thereby ignoring
         * function pointers (!) *)
        match lval with
        | Lval(Var(vi),NoOffset) -> (
            (* get the callee's node *)
            let callee:callnode = (self#getNode vi.vname) in
            (trace "callgraph" (P.dprintf "I see a call by %s to %s\n"
                                          caller.cnName callee.cnName));

            (* add one entry to each node's appropriate list *)
            (add_if caller.cnCallees callee.cnName callee);
            (add_if callee.cnCallers caller.cnName caller)
          )
        | _ ->
          (trace "callgraph" (P.dprintf "ignoring indirect call: %a\n"
                                        dn_instr i));
      )
    | _ -> ());     (* ignore other kinds instructions *)
    DoChildren
  end
end

let computeGraph (f:file) : callgraph =
begin
  let obj:cgComputer = (new cgComputer) in

  (* visit the whole file, computing the graph *)
  (visitCilFileSameGlobals (obj :> cilVisitor) f);

  (* return the computed graph *)
  (obj#getGraph ())
end

let printGraph (out:out_channel) (g:callgraph) : unit =
begin
  let printEntry (s:string) (n:callnode) : unit =
    (Printf.fprintf out " %s" s) in

  let printNode (name:string) (node:callnode) : unit =
  begin
    (fprintf out "%s:\n" name);
    (fprintf out "  calls:");
    (Hashtbl.iter printEntry node.cnCallees);
    (fprintf out "\n  is called by:");
    (Hashtbl.iter printEntry node.cnCallers);
    (fprintf out "\n")
  end in
  
  (Hashtbl.iter printNode g)
end


(*
 *
 * Copyright (c) 2001 by
 *  George C. Necula	necula@cs.berkeley.edu
 *  Scott McPeak        smcpeak@cs.berkeley.edu
 *  Wes Weimer          weimer@cs.berkeley.edu
 *   
 * All rights reserved.  Permission to use, copy, modify and distribute
 * this software for research purposes only is hereby granted, 
 * provided that the following conditions are met: 
 * 1. XSRedistributions of source code must retain the above copyright notice, 
 * this list of conditions and the following disclaimer. 
 * 2. Redistributions in binary form must reproduce the above copyright notice, 
 * this list of conditions and the following disclaimer in the documentation 
 * and/or other materials provided with the distribution. 
 * 3. The name of the authors may not be used to endorse or promote products 
 * derived from  this software without specific prior written permission. 
 *
 * DISCLAIMER:
 * THIS SOFTWARE IS PROVIDED BY THE AUTHORS ``AS IS'' AND ANY EXPRESS OR 
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. 
 * IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS 
 * OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON 
 * ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT 
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF 
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 *)
