/* $Id$ */

/*
 *
 * Copyright (C) 1998 David Mazieres (dm@uun.org)
 *   updated for OKWS in 2003-4 by Maxwell Krohn (max@okcupid.com)
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2, or (at
 * your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
 * USA
 *
 */

%{
#include "rpcc.h"
#define YYSTYPE YYSTYPE

static int proc_compare (const void *, const void *);
static int vers_compare (const void *, const void *);
static str getnewid (str);
static str getid (str);
%}

%token <str> T_ID
%token <str> T_NUM

%token T_CONST
%token T_STRUCT
%token T_UNION
%token T_ENUM
%token T_TYPEDEF
%token T_PROGRAM
%token T_TXA
%token T_SEED

%token T_UNSIGNED
%token T_INT
%token T_HYPER
%token T_DOUBLE
%token T_QUADRUPLE
%token T_VOID

%token T_VERSION
%token T_SWITCH
%token T_CASE
%token T_DEFAULT

%token <str> T_OPAQUE
%token <str> T_STRING

%type <str> id newid type_or_void type base_type value 
%type <decl> declaration
%type <cnst> enum_cnstag
%type <num> number
%type <tok> ptxa_tok
%type <tokset> ptxa_tok_list

%%
file: /* empty */ { checkliterals (); }
	| file { checkliterals (); } definition { checkliterals (); }
	;

definition: def_const
	| def_enum
	| def_struct
	| def_type
	| def_union
	| ptxa_def_program
	| ptxa_seed
	;

def_type: T_TYPEDEF declaration
	{
	  rpc_sym *s = &symlist.push_back ();
	  s->settype (rpc_sym::TYPEDEF);
	  *s->stypedef = $2;
	  s->stypedef->id = getnewid (s->stypedef->id);
	}
	| T_TYPEDEF T_STRUCT declaration
	{
	  rpc_sym *s = &symlist.push_back ();
	  s->settype (rpc_sym::TYPEDEF);
	  *s->stypedef = $3;
	  s->stypedef->type = strbuf ("struct ") << $3.type;
	  s->stypedef->id = getnewid (s->stypedef->id);
	}
	;

def_const: T_CONST newid '=' value ';'
	{
	  rpc_sym *s = &symlist.push_back ();
	  s->settype (rpc_sym::CONST);
	  s->sconst->id = $2;
	  s->sconst->val = $4;
	}
	;

def_enum: T_ENUM newid '{'
	{
	  rpc_sym *s = &symlist.push_back ();
	  s->settype (rpc_sym::ENUM);
	  s->senum->id = $2;
	}
	enum_taglist comma_warn '}' ';'
	;

comma_warn: /* empty */
	| ',' { yywarn ("comma not allowed at end of enum"); }
	;

def_struct: T_STRUCT newid '{'
	{
	  rpc_sym *s = &symlist.push_back ();
	  s->settype (rpc_sym::STRUCT);
	  s->sstruct->id = $2;
	}
	struct_decllist '}' ';'
	;

def_union: T_UNION newid T_SWITCH '(' type T_ID ')' '{'
	{
	  rpc_sym *s = &symlist.push_back ();
	  s->settype (rpc_sym::UNION);
	  s->sunion->id = $2;
	  s->sunion->tagtype = $5;
	  s->sunion->tagid = $6;
	}
	union_taglist '}' ';'
	;

ptxa_seed: T_SEED '(' T_ID ')' ';'
	{
	  ptxa_seed = $3;
	}
	;

ptxa_def_program: T_TXA '(' ptxa_tok_list ')' 
	{
	  ptxa_prog_toklist = $3;
	}
	'{' def_program_list '}' ';'
	{
	  ptxa_prog_toklist = NULL;
	}
	| 
	def_program_decl
	;

def_program_list: def_program_decl | def_program_list def_program_decl
	;

ptxa_tok: '-' T_ID
	{
	  $$ = ptxa_tok_t ($2, false);
	}
	| T_ID
	{
	  $$ = ptxa_tok_t ($1);
	  alltoks.insert ($1);
	}
	;

ptxa_tok_list: ptxa_tok 
	{
	  ptr<ptxa_tokset_t> s = New refcounted<ptxa_tokset_t> ();
	  s->insert ($1);
	  $$ = s;
	}
	| ptxa_tok_list ',' ptxa_tok
	{
	  ptr<ptxa_tokset_t> s = $1;
	  s->insert ($3);
	  $$ = s;
	}
	;

def_program_decl: T_PROGRAM newid '{'
	{
	  rpc_sym *s = &symlist.push_back ();
	  s->settype (rpc_sym::PROGRAM);
	  s->sprogram->tokset = ptxa_prog_toklist;
	  s->sprogram->id = $2;
	}
	ptxa_version_list '}' '=' number ';'
	{
	  rpc_sym *s = &symlist.back ();
	  s->sprogram->val = $8;

	  qsort (s->sprogram->vers.base (), s->sprogram->vers.size (),
		 sizeof (rpc_vers), vers_compare);
	}
	;

ptxa_version_list: ptxa_version_decl | ptxa_version_list ptxa_version_decl
	;

ptxa_version_decl:
	T_TXA '(' ptxa_tok_list ')'
	{
	  ptxa_vers_toklist = $3;
	}
	'{' version_list '}' ';'
	{
	  ptxa_vers_toklist = NULL;
	}
	|
	version_decl
	;

version_list: version_decl | version_list version_decl
	;

version_decl: T_VERSION newid '{'
	{
	  rpc_sym *s = &symlist.back ();
	  rpc_vers *rv = &s->sprogram->vers.push_back ();
	  rv->id = $2;
	  rv->max_proc_id = 0;
	  rv->tokset = ptxa_vers_toklist;
	}
	ptxa_proc_list '}' '=' number ';'
	{
	  rpc_sym *s = &symlist.back ();
	  rpc_vers *rv = &s->sprogram->vers.back ();
	
	  // 
	  // add special RPC for TXA LOGIN; that is, the client needs
	  // to ship TXA authentication tokens to the server on login,
	  // and this RPC will be automatically generated for those
	  // (rpc_prog, rpc_version) pairs that require it.
	  //
	  rpc_program_p *prog = s->sprogram;
	  if (prog->has_positive_toks () || rv->has_positive_toks ()) {
	     rpc_proc *rp = &rv->procs.push_back ();
	     rp->id = str (strbuf (prog->id) << "_" << rv->id 
			    << "_TXA_LOGIN" );
	     rp->arg = "txa_login_arg_t";
	     rp->res = "txa_login_res_t";
	     rp->val = rv->max_proc_id + 1;
	     rv->txa_rpc = rp->id;
	  }

	  rv->val = $8;
	  qsort (rv->procs.base (), rv->procs.size (),
		 sizeof (rpc_proc), proc_compare);
	}
	;

ptxa_proc_list: ptxa_proc_decl | ptxa_proc_list ptxa_proc_decl
	;

ptxa_proc_decl:
	T_TXA '(' ptxa_tok_list ')'
	{
	  ptxa_proc_toklist = $3;
	}
	'{' proc_list '}' ';'
	{
	  ptxa_proc_toklist = NULL;
	}
	|
	proc_decl
	;
	

proc_list: proc_decl | proc_list proc_decl
	;

proc_decl: type_or_void newid '(' type_or_void ')' '=' number ';'
	{
	  rpc_sym *s = &symlist.back ();
	  rpc_vers *rv = &s->sprogram->vers.back ();
	  
	  rpc_proc *rp = &rv->procs.push_back ();
	  rp->id = $2;
	  rp->val = $7;
	  rp->arg = $4;
	  rp->res = $1;
	  rp->tokset = ptxa_proc_toklist;

	  //	
          // easier than sorting, but somewhat of a hack...
	  //
	  if ($7 > rv->max_proc_id)
	    rv->max_proc_id = $7;
	}
	;

union_taglist: union_tag | union_taglist union_tag
	;

union_tag: union_caselist union_decl
	;

union_caselist: union_case | union_caselist union_case
	;

union_case: T_CASE value ':'
	{
	  rpc_sym *s = &symlist.back ();
	  rpc_utag *ut = &s->sunion->cases.push_back ();
	  ut->tagvalid = false;
	  ut->swval = $2;
	}
	| T_DEFAULT ':'
	{
	  rpc_sym *s = &symlist.back ();
	  rpc_utag *ut = &s->sunion->cases.push_back ();
	  ut->tagvalid = false;
	}
	;

union_decl: declaration
	{
	  rpc_sym *s = &symlist.back ();
	  rpc_utag *ut = &s->sunion->cases.back ();
	  ut->tagvalid = true;
	  ut->tag = $1;
	}
	| T_VOID ';'
	{
	  rpc_sym *s = &symlist.back ();
	  rpc_utag *ut = &s->sunion->cases.back ();
	  ut->tagvalid = true;
	  ut->tag.type = "void";
	  ut->tag.qual = rpc_decl::SCALAR;
	}
	;

struct_decllist: struct_decl | struct_decllist struct_decl
	;

struct_decl: declaration
	{ symlist.back ().sstruct->decls.push_back ($1); }
	;

enum_taglist: enum_tag {}
	| enum_taglist ',' enum_tag {}
	;

enum_tag: enum_cnstag
	{ symlist.back ().senum->tags.push_back ($1); }
	;

enum_cnstag: newid '=' value { $$.id = $1; $$.val = $3; }
	| newid { $$.id = $1; }
	;

declaration: type T_ID ';'
	 { $$.id = $2; $$.type = $1; $$.qual = rpc_decl::SCALAR; }
	| T_STRING T_ID ';'
	 { $$.id = $2; $$.type = $1; $$.qual = rpc_decl::VEC;
	   $$.bound = "RPC_INFINITY";
	   yywarn ("strings require variable-length array declarations");
	 }
	| type '*' T_ID ';'
	 { $$.id = $3; $$.type = $1; $$.qual = rpc_decl::PTR; }
	| type T_ID '[' value ']' ';'
	 { $$.id = $2; $$.type = $1; $$.qual = rpc_decl::ARRAY;
	   $$.bound = $4; }
	| T_OPAQUE T_ID '[' value ']' ';'
	 { $$.id = $2; $$.type = $1; $$.qual = rpc_decl::ARRAY;
	   $$.bound = $4; }
	| type T_ID '<' value '>' ';'
	 { $$.id = $2; $$.type = $1; $$.qual = rpc_decl::VEC; $$.bound = $4; }
	| T_STRING T_ID '<' value '>' ';'
	 { $$.id = $2; $$.type = $1; $$.qual = rpc_decl::VEC; $$.bound = $4; }
	| T_OPAQUE T_ID '<' value '>' ';'
	 { $$.id = $2; $$.type = $1; $$.qual = rpc_decl::VEC; $$.bound = $4; }
	| type T_ID '<' '>' ';'
	 { $$.id = $2; $$.type = $1; $$.qual = rpc_decl::VEC;
	   $$.bound = "RPC_INFINITY"; }
	| T_STRING T_ID '<' '>' ';'
	 { $$.id = $2; $$.type = $1; $$.qual = rpc_decl::VEC;
	   $$.bound = "RPC_INFINITY"; }
	| T_OPAQUE T_ID '<' '>' ';'
	 { $$.id = $2; $$.type = $1; $$.qual = rpc_decl::VEC;
	   $$.bound = "RPC_INFINITY"; }
	;

type_or_void: type | T_VOID { $$ = "void"; }
	;

type: base_type | id
	;

base_type: T_UNSIGNED { $$ = "u_int32_t"; }
	| T_INT { $$ = "int32_t"; }
	| T_UNSIGNED T_INT { $$ = "u_int32_t"; }
	| T_HYPER { $$ = "int64_t"; }
	| T_UNSIGNED T_HYPER { $$ = "u_int64_t"; }
	| T_DOUBLE { $$ = "double"; }
	| T_QUADRUPLE { $$ = "quadruple"; }
	;

value: id | T_NUM
	;

number: T_NUM { $$ = strtoul ($1, NULL, 0); }
	;

newid: T_ID { $$ = getnewid ($1); }
	;

id: T_ID { $$ = getid ($1); }
	;

%%
symlist_t symlist;

//
// TXA Data elements
//
ptr<ptxa_tokset_t> ptxa_prog_toklist;
ptr<ptxa_tokset_t> ptxa_vers_toklist;
ptr<ptxa_tokset_t> ptxa_proc_toklist;
bhash<str> alltoks;

static int
proc_compare (const void *_a, const void *_b)
{
  rpc_proc *a = (rpc_proc *) _a;
  rpc_proc *b = (rpc_proc *) _b;
  return a->val < b->val ? -1 : a->val != b->val;
}

static int
vers_compare (const void *_a, const void *_b)
{
  rpc_vers *a = (rpc_vers *) _a;
  rpc_vers *b = (rpc_vers *) _b;
  return a->val < b->val ? -1 : a->val != b->val;
}

void
checkliterals ()
{
  for (size_t i = 0; i < litq.size (); i++) {
    rpc_sym *s = &symlist.push_back ();
    s->settype (rpc_sym::LITERAL);
    *s->sliteral = litq[i];
  }
  litq.clear ();
}

static str
getnewid (str id)
{
  if (ids[id])
    yywarn ("redefinition of symbol " << id);
  else
    ids.insert (id);
  if (idprefix)
    id = idprefix << id;
  return id;
}

static str
getid (str id)
{
  if (idprefix && ids[id])
    id = idprefix << id;
  return id;
}
