/* -*-fundamental-*- */
/* $Id$ */

%{
#include "pub_parse.h"
#include "parse.h"
#define YY_STR_BUFLEN 20*1024

static int end_GH ();
static int begin_GH ();
static void begin_PSTR (int i);
static void end_PSTR ();
static void begin_STR (int i, int j);
static int  end_STR ();
static void addch (int c1, int c2);
static void addstr (char *c, int l);
static void nlcount (int m = 0);
static void pop_ECF ();
static void push_ECF ();
static void eos_plinc ();

int yy_ssln;
int yy_wss_nl;
int yywss;
int yyesc;
int yy_oldesc;
char str_buf[YY_STR_BUFLEN];
int sbi;
char *eof_tok;

%}

%option stack
%option noyywrap

VAR	[a-zA-Z_][a-zA-Z_0-9]*
HNAM	[a-zA-Z_][a-zA-Z_0-9-]*
HVAL	[a-zA-Z0-9_#-]+
ST	[Ss][Cc][Rr][Ii][Pp][Tt]
PRET    [Pp][Rr][Ee]
WS	[ \t]
WSN	[ \t\n]
EOL	[ \t]*\n?
TPRFX	"<!--#"[ \t]*

%x GSEC STR SSTR H HTAG PTAG GH PSTR PVAR WH WGH HCOM JS GFILE EC WEC CCODE
%x ECCODE ECF GCODE PRE

%%

<INITIAL>\n	{ PLINC; return ('\n'); }

<GFILE>{
"/*o" |
"/**"(guy|pub)"*" |
"/*<"(guy|pub)">"  { yy_push_state (GSEC); return T_BGUY; }
"/"		{ return '/' ; }
[^/]+		{ yylval.str = yytext; nlcount (); return T_CODE; }
}

<EC,WEC,ECF>{
"<%ec"{WSN}*	{ yy_push_state (ECCODE); nlcount (); return T_EC_EC; }
"<%c"{WSN}+	{ pop_ECF (); yy_push_state (CCODE); 
	          nlcount (); return T_EC_C; }
"<%"(p|g){WSN}+	{ yy_push_state (GSEC); nlcount (); return T_EC_G; }
"<%v"{WSN}+ 	{ yy_push_state (ECCODE); nlcount (); return T_EC_V; }
"<%uv"{WSN}+	{ yy_push_state (ECCODE); nlcount (); return T_EC_UV; }
"<%cf"{WSN}+	{ push_ECF (); yy_push_state (CCODE);
		  nlcount (); return T_EC_CF; }
"<%m%>"{EOL}	{ pop_ECF (); nlcount (); return T_EC_M; }
"<%/m%>"{EOL}	{ push_ECF (); nlcount (); return T_EC_EM; }
\\+"<%"[a-z]	{ yylval.str = yytext + 1; return T_HTML; }
}

<ECF>{
\n		{ PLINC; }
{WS}+		/* ignore */ ;
.		yyerror ("illegal token found in HTML-free zone");
}

<CCODE>{
"%>"{EOL}	{ yy_pop_state (); nlcount (); return T_EC_CLOSE; }
\\+"%>"		{ yylval.str = yytext + 1; return T_CODE; }
[^%\\]+		{ yylval.str = yytext; nlcount (); return T_CODE; }
[%\\]		{ yylval.ch = yytext[0]; return T_CH; }
}


<GSEC>{
\n		{ PLINC; }
{WS}+		/* ignore */ ;

"o*/" |
"**"(guy|pub)"*/"{WS}*\n? |
"</"(guy|pub)">*/"{WS}*\n? 	{ yy_pop_state (); 
	                          if (yytext[yyleng - 1] == '\n') PLINC; 
	                          return T_EGUY; }

"%>"		{ yy_pop_state ();  return T_EC_CLOSE; }

"<<"{VAR};	{ eos_plinc (); return begin_GH (); }
"//".*$		/* discard */;
uvar		return T_UVARS;		
vars		return T_VARS;
print		return T_PRINT;
ct_include	return T_CTINCLUDE;
include		return T_INCLUDE;
init_publist	return T_INIT_PDL;
<<EOF>>		{ yyerror ("unterminated GUY mode in file"); }
}

<PTAG>{
"-->"		{ yy_pop_state (); return T_EPTAG; }
}

<ECCODE>{
"%>"{EOL}	{ yy_pop_state (); nlcount (); return T_EC_CLOSE; }
}

<GSEC,PTAG,ECCODE>{
{WS}+		/* discard */ ;
\n		{ PLINC; }

=>		|
[(),{}=;]	return yytext[0];


int(32(_t)?)?[(]	return T_INT_ARR; 
char[(]			return T_CHAR_ARR;
int64(_t)?[(]		return T_INT64_ARR;
int16(_t)?[(]		return T_INT16_ARR;

u_int(32(_t)?)?[(]	return T_UINT_ARR;
u_int16(_t)?[(]		return T_UINT16_ARR;


{VAR}		{ yylval.str = yytext; return T_VAR; }

[+-]?[0-9]+	|
[+-]?0x[0-9]+	{ yylval.str = yytext; return T_NUM; }

\"		{ begin_PSTR (1); return (yytext[0]); }

"//".*$		/* discard */ ;

.		{ yyerror ("illegal token found in GUY/PTAG/EC++ "
	                   "environment"); }
}

<WGH,GH>^{VAR}/\n	{ if (end_GH ()) return T_EGH; else return T_HTML; }
<H,GH,EC>\n		{ PLINC; return (yytext[0]); }

<H,WH>{
{TPRFX}include		{ yy_push_state (PTAG); return T_PTINCLUDE; }
{TPRFX}inclist		{ yy_push_state (PTAG); return T_PTINCLIST; }
{TPRFX}set		{ yy_push_state (PTAG); return T_PTSET; }
{TPRFX}switch		{ yy_push_state (PTAG); return T_PTSWITCH; }
{TPRFX}"#"	    	|
{TPRFX}com(ment)?	{ yy_push_state (HCOM); }
}

<GH,H,WH,WGH,EC,WEC,JS,PSTR,GSEC,PTAG,ECCODE,HTAG>{
"@{"		{ yy_push_state (GCODE); return T_BGCODE; }
"${"		{ yy_push_state (PVAR); return T_BVAR; }
"%{"		{ yy_push_state (GCODE); return T_BGCCE; }
\\+[$@%]"{"	{ yylval.str = yytext + 1; return T_HTML; }
[$@%]		{ yylval.ch = yytext[0]; return T_CH; }
}

<GH>[^$@%\\\n]+	{ yylval.str = yytext; return T_HTML; }
<H,EC>{
[^$@%\\<]+	{ yylval.str = yytext; nlcount (); return T_HTML; }
"<"		{ yylval.ch = yytext[0]; return T_CH; }
}

<H,GH,EC>{
\\		{ yylval.ch = yytext[0]; return T_CH; }
}

<WH,WGH,WEC>{
\<!--		{ yy_push_state (HCOM); }
}


<WH,WGH,WEC>{	
{WSN}+		{ nlcount (); return (' '); }
[<][/]?		{ yy_push_state (HTAG); yylval.str = yytext; return T_BTAG; }
\<{ST}/[ \t\n>]	{ yy_push_state (JS); yy_push_state (HTAG); return T_BJST; }

\<{PRET}{WSN}*\> { yy_push_state (PRE); nlcount (); yylval.str = yytext; 
	          return T_BPRE; }
}

<PRE>{
[^<]+		{ yylval.str = yytext; nlcount (); return T_HTML; }
"</"{PRET}\>	{ yy_pop_state (); yylval.str = yytext; return T_EPRE; }
\<		{ yylval.ch = yytext[0]; return T_CH; }
}

<JS>{
"</"{ST}{WS}*\>	{ yy_pop_state (); yylval.str = yytext; return T_EJS; }
[$@<\\]		{ yylval.ch = yytext[0]; return T_CH; }
[^\\$@<]+	{ yylval.str = yytext; nlcount (); return T_HTML; }
}

<HCOM>{
\n		PLINC;
--\>		{ yy_pop_state (); }
[^-\n]*		/* discard */ ;
-		/* discard */ ;
}

<WH,WGH,WEC>{
[^$@\\<\n\t ]+ 	{ yylval.str = yytext; return T_HTML; }
\\		{ yylval.ch = yytext[0]; return T_CH; }
}

<HTAG>{
\n		{ PLINC; }
\"		{ begin_PSTR (0); return ('"'); }
\'		{ begin_STR (SSTR, 0); }	

"/>"		|
\>		{ yy_pop_state (); yylval.str = yytext; return T_ETAG; }

{WSN}+		/* discard */;
{HNAM}		{ yylval.str = yytext; return T_HNAM; }
{HVAL}		{ yylval.str = yytext; return T_HVAL; }
=		{ return (yytext[0]); }
.		{ yyerror ("illegal token found in parsed HTAG"); }
}

<SSTR,STR>\n	{ PLINC; addch ('\n', -1); }
<STR>\" 	{ return (end_STR ()); }
<SSTR>\'	{ return (end_STR ()); }

<STR,SSTR>{
\\n  		addch ('\n', 'n');
\\t  		addch ('\t', 't');
\\r		addch ('\r', 'r');
\\b		addch ('\b', 'b');
\\f		addch ('\f', 'f');
\\(.|\n)	addch (yytext[1], yytext[1]);
}

<STR>[^\\\n\"]+		addstr (yytext, yyleng);
<SSTR>[^\\\n\']+	addstr (yytext, yyleng);

<PSTR>{
\n		{ yyerror ("unterminated parsed string"); }
\\[\\"tn]	{ if (yyesc) { yylval.ch = yytext[1]; return T_CH; }
	  	  else { yylval.str = yytext; return T_STR; } }
\\.		{ yyerror ("illegal escape sequence"); }
\"		{ end_PSTR (); return (yytext[0]); }
[^"\\$@%]+	{ yylval.str = yytext; return T_STR; }
}

<STR,PSTR,SSTR>{
<<EOF>>		{ yyerror (strbuf ("EOF found in str started on line %d", 
			           yy_ssln)); 
		}
}

<GCODE>{
[}]		{ yy_pop_state (); return (yytext[0]); }
[^{};]+		{ yylval.str = yytext; return T_GCODE; }
.		{ yyerror ("illegal token found in @{..}"); }
}

<PVAR>{
{VAR}		{ yylval.str = yytext; return T_VAR; }
\}		{ yy_pop_state (); return (yytext[0]); }
.		{ yyerror ("illegal token found in ${..}"); }
}

.		{ yyerror ("illegal token found in input"); }

%%
int
end_GH ()
{
  if (mystrcmp (eof_tok, yytext)) {
    free (eof_tok);
    yy_pop_state ();
    return 1;
  } else {
    return 0;
  }
}

int
begin_GH ()
{
  int strlen = yyleng - 3;
  eof_tok = (char *)malloc (strlen + 1);
  memcpy (eof_tok, yytext + 2, strlen);
  eof_tok[strlen] = 0;
  yy_push_state (yywss ? WGH : GH);
  return (yywss ? T_BWGH : T_BGH);
}

void
begin_PSTR (int i)
{
  yy_oldesc = yyesc;
  yyesc = i;
  yy_push_state (PSTR);
  yy_ssln = PLINENO;
}

void
end_PSTR ()
{
  yyesc = yy_oldesc;
  yy_pop_state ();
}

void
begin_STR (int s, int e)
{
  sbi = 0;
  yy_oldesc = yyesc;
  yyesc = e;
  yy_push_state (s);
  yy_ssln = PLINENO;
}

int
end_STR ()
{
  str_buf[sbi] = '\0';
  yy_pop_state ();
  yylval.str = str_buf;
  yyesc = yy_oldesc;
  return T_STR;
}

void
addch (int c1, int c2)
{
  int len = (yyesc || c2 < 0) ? 1 : 2;
  if (sbi >= YY_STR_BUFLEN - len)
    yyerror ("string buffer overflow");
  if (yyesc || c2 < 0)
    str_buf[sbi++] = c1;
  else
    sbi += sprintf (str_buf + sbi, "\\%c", c2);
}

void
addstr (char *s, int l)
{
  if (sbi + l >= YY_STR_BUFLEN - 1)
    yyerror ("string buffer overflow");
  memcpy (str_buf + sbi, s, l);
  sbi += l;
}

void
nlcount (int m)
{
  int n = 0;
  for (char *y = yytext; *y; y++)
    if (*y == '\n') {
      n++;
      if (m && m == n) 
        break;
    }
  PFILE->inc_lineno (n);
}

int
yyerror (str msg)
{
  if (!msg) 
    msg = "bailing out due to earlier warnings";
  PWARN(msg);
  PARSEFAIL;	
  yyterminate ();
  return 0;
}

int
yywarn (str msg)
{
  PWARN("lexer warning: " << msg);
  return 0;
}

void
yy_push_pubstate (pfile_type_t t)
{
  switch (t) {
  case PFILE_TYPE_CONF:
    yy_push_state (H);
    break;
  case PFILE_TYPE_GUY:
  case PFILE_TYPE_CODE:
    yy_push_state (GFILE);
    break;
  case PFILE_TYPE_H:
    yy_push_state (H);
    break;
  case PFILE_TYPE_WH:
    yy_push_state (WH);
    break;
  case PFILE_TYPE_EC:
    yy_push_state (EC);
    yy_push_state (ECF);
    break;
  case PFILE_TYPE_WEC:
    yy_push_state (WEC);
    yy_push_state (ECF);
    break;
  default:
    fatal << "unknown lexer state\n";
  }
}

void
pop_ECF ()
{
  if (YY_START == ECF)
    yy_pop_state ();
}

void
push_ECF ()
{
  if (YY_START != ECF)
    yy_push_state (ECF);
}

void
yy_pop_pubstate ()
{
  yy_pop_state ();
}

void
eos_plinc ()
{
  if (yytext[yyleng - 1] == '\n')
    PLINC;
}

void
yyswitch (yy_buffer_state *s)
{
  yy_switch_to_buffer (s);
}

yy_buffer_state *
yycreatebuf (FILE *fp)
{
  return (yy_create_buffer (fp, YY_BUF_SIZE));
}

void
gcc_hack_use_static_functions ()
{
  assert (false);
  yyunput (yy_top_state (), "hello");
}


/*
// States:
//   GFILE - C/C++ mode -- passthrough / ECHO
//   GUY - directives within a C/C++ file such as ct_include and include
//   STR - string within an HTML tag or within regular mode
//   SSTR - string with single quotes around it
//   H - HTML w/ includes and variables and switches and such
//   HTAG - Regular tag within HTML mode
//   PTAG - Pub tag within HTML
//   GH - HTML from within a Guy file -- i.e., HTML + also look
//	   for an EOF-like tok (G-HTML)
//   PSTR - Parsed string
//   PVAR - Variable state (within ${...})
//   WH - White-space-stripped HTML
//   WGH - White-space-stripped G-HTML
//   HCOM - HTML Comment
//   JS - JavaScript
//   EC - Embedded C
//   WEC - White-space-stripped Embedded C
//
*/
