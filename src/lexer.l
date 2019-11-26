/*
 *  OpenSCAD (www.openscad.org)
 *  Copyright (C) 2009-2011 Clifford Wolf <clifford@clifford.at> and
 *                          Marius Kintel <marius@kintel.net>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  As a special exception, you have permission to link this program
 *  with the CGAL library and distribute executables, as long as you
 *  follow the requirements of the GNU GPL in regard to all of the
 *  software in the executable aside from CGAL.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 */

%option prefix="lexer"

%{

#include <glib.h>
#include "handle_dep.h"
#include "printutils.h"
#include "parsersettings.h"
#include "Assignment.h"
#include "parser.hxx"
#include "FileModule.h"
#include <assert.h>
#include <boost/lexical_cast.hpp>
#include <boost/filesystem.hpp>
namespace fs = boost::filesystem;

//isatty for visual c++ and mingw-cross-env
#if defined __WIN32__ && ! defined _MSC_VER
#include "unistd.h"
#endif
#if defined __WIN32__ || defined _MSC_VER
extern "C" int __cdecl _isatty(int _FileHandle);
#define isatty _isatty
#define strdup _strdup
#define fileno _fileno
#endif

std::string stringcontents;
int lexerget_lineno(void);
#ifdef __GNUC__
static void yyunput(int, char*) __attribute__((unused));
#endif
extern const char *parser_input_buffer;
extern FileModule *rootmodule;

#define YY_INPUT(buf,result,max_size) {   \
  if (yyin && yyin != stdin) {            \
    int c = fgetc(yyin);                  \
    if (c >= 0) {                         \
      result = 1;                         \
      buf[0] = c;                         \
    } else {                              \
      result = YY_NULL;                   \
    }                                     \
  } else {                                \
    if (*parser_input_buffer) {           \
      result = 1;                         \
      buf[0] = *(parser_input_buffer++);  \
      parser_error_pos++;                 \
    } else {                              \
      result = YY_NULL;                   \
    }                                     \
  }                                       \
}

/*
  Handle locations.
  Note: Since flex doesn't handle column numbers, we deal with those manually.
  The yycolumn is manually reset for each encountered newline.
*/
extern YYLTYPE parserlloc;
int yycolumn = 1;
#define YY_USER_ACTION {              \
  parserlloc.first_line = yylineno;   \
  parserlloc.first_column = yycolumn; \
  yycolumn = yycolumn + yyleng;       \
  parserlloc.last_column = yycolumn;  \
  parserlloc.last_line = yylineno;    \
}

extern void parsererror(char const *s);
void to_utf8(const char *, char *);
void includefile();
std::shared_ptr<fs::path> sourcefile();
std::shared_ptr<fs::path> parser_sourcefile;
std::vector<std::shared_ptr<fs::path>> filename_stack;
std::vector<int> lineno_stack;
std::vector<FILE*> openfiles;
std::vector<std::string> openfilenames;

std::string filename;
std::string filepath;
%}

%option yylineno
%option noyywrap

%x cond_comment cond_lcomment cond_string
%x cond_include
%x cond_use

D [0-9]
E [Ee][+-]?{D}+
H [0-9a-fA-F]

/* Unicode C1 Controls and Latin-1 Supplement */
NOTS    \xc2\xac
MDOT    \xc2\xb7
L1Sa    \xc3[\x80-\x96]
MULS    \xc3\x97
L1Sb    \xc3[\x98-\xb6]
DIVS    \xc3\xb7
L1Sc    \xc3[\xb8-\xbf]
L1S     {L1Sa}|{L1Sb}|{L1Sc}

/* Unicode Greek and Coptic */
GRKUa   \xce[\x91-\xa1]
GRKUb   \xce[\xa3-\xa9]
GRKLa   \xce[\xb1-\xbf]
GRKLb   \xcf[\x80-\x89]
GRK     {GRKUa}|{GRKUb}|{GRKLa}|{GRKLb}

/* Unicode General Punctuation */
DVLS    \xe2\x80\x96

/* Unicode Mathematical Operators */
ANDS    \xe2\x88\xa7
ORS     \xe2\x88\xa8
CEQS    \xe2\x89\x94
NES     \xe2\x89\xa0
LES     \xe2\x89\xa4
GES     \xe2\x89\xa5

U       [\x80-\xbf]
U2a     \xc2[\xa1-\xab]
U2b     \xc2[\xad-\xb6]
U2c     \xc2[\xb8-\xbf]
U2d     [\xc4-\xcd]{U}
U2e     \xce[\x80-\x90]
U2f     \xce\xa2
U2g     \xce[\xaa-\xb0]
U2h     \xcf[\x8a-\xbf]
U2i     [\xd0-\xdf]{U}
U2      {U2a}|{U2b}|{U2c}|{MULS}|{U2d}|{U2e}|{U2f}|{U2g}|{U2h}|{U2i}
U3a     [\xe0-\xe1]{U}{U}
U3b     \xe2\x80[\x80-\x95]
U3c     \xe2\x80[\x97-\xbf]
U3d     \xe2[\x81-\x87]{U}
U3e     \xe2\x88[\x80-\xa6]
U3f     \xe2\x88[\xa9-\xbf]
U3g     \xe2\x89[\x80-\x93]
U3h     \xe2\x89[\x95-\x9f]
U3i     \xe2\x89[\xa1-\xa3]
U3j     \xe2\x89[\xa6-\xbf]
U3k     \xe2[\x8a-\xbf]{U}
U3l     [\xe3-\xef]{U}{U}
U3      {U3a}|{U3b}|{DVLS}|{U3c}|{U3d}|{U3e}|{U3f}|{U3g}|{U3h}|{U3i}|{U3j}|{U3k}|{U3l}
U4      [\xf0-\xf4]
UNICODE {U2}|{U3}|{U4}{U}{U}{U}

/* [a-zA-Z] */
LL      [\x61-\x7a]
LU      [\x41-\x5a]

IDCHAR  {LL}|{LU}|{D}|"_"|{L1S}|{GRK}

%%

include[ \t\r\n]*"<"	{ BEGIN(cond_include); filepath = filename = ""; }
<cond_include>{
[^\t\r\n>]*"/"	{ filepath = yytext; }
[^\t\r\n>/]+	{ filename = yytext; }
">"		{ BEGIN(INITIAL); includefile(); }
<<EOF>>         { parsererror("Unterminated include statement"); return TOK_ERROR; }
}


use[ \t\r\n]*"<"	{ BEGIN(cond_use); }
<cond_use>{
[^\t\r\n>]+	{ filename = yytext; }
 ">"		{
	BEGIN(INITIAL);
        fs::path fullpath = find_valid_path(sourcefile()->parent_path(), fs::path(filename), &openfilenames);
	if (fullpath.empty()) {
          PRINTB("WARNING: Can't open library '%s'.", filename);
          parserlval.text = strdup(filename.c_str());
	} else {
          auto used_path = fullpath.generic_string();
          handle_dep(used_path);
          parserlval.text = strdup(used_path.c_str());
	}
        return TOK_USE;
    }
<<EOF>>         { parsererror("Unterminated use statement"); return TOK_ERROR; }
}

\"			{ BEGIN(cond_string); stringcontents.clear(); }
<cond_string>{
\\n			{ stringcontents += '\n'; }
\\t			{ stringcontents += '\t'; }
\\r			{ stringcontents += '\r'; }
\\\\			{ stringcontents += '\\'; }
\\\"			{ stringcontents += '"'; }
{UNICODE}               { parser_error_pos -= strlen(lexertext) - 1; stringcontents += lexertext; }
\\x[0-7]{H}             { unsigned long i = strtoul(lexertext + 2, NULL, 16); stringcontents += (i == 0 ? ' ' : (unsigned char)(i & 0xff)); }
\\u{H}{4}|\\U{H}{6}     { char buf[8]; to_utf8(lexertext + 2, buf); stringcontents += buf; }
[^\\\n\"]		{ stringcontents += lexertext; }
[\n\r]		        { yycolumn = 1; }
\"			{ BEGIN(INITIAL);
			parserlval.text = strdup(stringcontents.c_str());
			return TOK_STRING; }
<<EOF>>                 { parsererror("Unterminated string"); return TOK_ERROR; }
}

[\t ]                   /* whitespace */
[\n\r]

\/\/ BEGIN(cond_lcomment);
<cond_lcomment>{
\n                      { BEGIN(INITIAL); yycolumn = 1; }
{UNICODE}               { parser_error_pos -= strlen(lexertext) - 1; }
[^\n]
}

"/*" BEGIN(cond_comment);
<cond_comment>{
"*/"                    { BEGIN(INITIAL); }
{UNICODE}               { parser_error_pos -= strlen(lexertext) - 1; }
.|\n
<<EOF>>                 { parsererror("Unterminated comment"); return TOK_ERROR; }
}

<<EOF>> {
	if (!filename_stack.empty()) filename_stack.pop_back();
	if (!lineno_stack.empty()) {
		yylineno = lineno_stack.back();
		lineno_stack.pop_back();
	}
	if (yyin && yyin != stdin) {
		assert(!openfiles.empty());
		fclose(openfiles.back());
		openfiles.pop_back();
		openfilenames.pop_back();
	}
	yypop_buffer_state();
	if (!YY_CURRENT_BUFFER)
		yyterminate();
}

"\x03"		return TOK_EOT;

"module"	return TOK_MODULE;
"function"	return TOK_FUNCTION;
"if"		return TOK_IF;
"else"		return TOK_ELSE;
"let"		return TOK_LET;
"assert"	return TOK_ASSERT;
"echo"	        return TOK_ECHO;
"for"		return TOK_FOR;
"each"		return TOK_EACH;

"true"		return TOK_TRUE;
"false"		return TOK_FALSE;
"undef"		return TOK_UNDEF;

%{/*
 U+00A0 (UTF-8 encoded: C2A0) is no-break space. We support it since Qt's QTextEdit
 automatically converts these to spaces and we want to be able to process the same
 files on the cmd-line as in the editor.
*/%}

[\xc2\xa0]+

{UNICODE}+              { parser_error_pos -= strlen(yytext); return TOK_ERROR; }

{D}+{E}? |
{D}*\.{D}+{E}? |
{D}+\.{D}*{E}?          {
                            try {
                                parserlval.number = boost::lexical_cast<double>(yytext);
                                return TOK_NUMBER;
                            } catch (boost::bad_lexical_cast&) {}
                        }
"$"?{IDCHAR}+           { parserlval.text = strdup(yytext); return TOK_ID; }

{CEQS}|":="             return DFDF;
{MDOT}|"*"              return MUL;
{DIVS}|"/"              return DIV;
{LES}|"<="              return LE;
{GES}|">="              return GE;
"="                     return EQ;
{NES}|"!="              return NE;
{ANDS}|"&&"             return AND;
{ORS}|"||"              return OR;
{NOTS}|"!"              return NOT;

. { return yytext[0]; }

%%

/*!
 * Convert unicode codepoint given in hex notation
 * into UTF8 encoding. The output buffer must be 8
 * characters long.
 */
void to_utf8(const char *str, char *out)
{
    memset(out, 0, 8);
    const gunichar c = strtoul(str, NULL, 16);
    if (g_unichar_validate(c) && (c != 0)) {
        g_unichar_to_utf8(c, out);
    } else {
        out[0] = ' ';
    }
}

void lexer_set_parser_sourcefile(const fs::path& path)
{
    parser_sourcefile = std::make_shared<fs::path>(path);
}

// Filename of the source file currently being lexed.
std::shared_ptr<fs::path>  sourcefile()
{
  if (!filename_stack.empty()) return filename_stack.back();

  return parser_sourcefile;
}

/*
  Rules for include <path/file>
  1) include <sourcepath/path/file>
  2) include <librarydir/path/file>

  Globals used: filepath, sourcefile, filename
 */
void includefile()
{
  fs::path localpath = fs::path(filepath) / filename;
  fs::path fullpath = find_valid_path(sourcefile()->parent_path(), localpath, &openfilenames);
  if (!fullpath.empty()) {
    rootmodule->registerInclude(localpath.generic_string(), fullpath.generic_string());
  }
  else {
    rootmodule->registerInclude(localpath.generic_string(), localpath.generic_string());
    PRINTB("WARNING: Can't open include file '%s'.", localpath.generic_string());
    return;
  };

  std::string fullname = fullpath.generic_string();

  filepath.clear();
  filename_stack.push_back(std::make_shared<fs::path>(fullpath));

  handle_dep(fullname);

  yyin = fopen(fullname.c_str(), "r");
  if (!yyin) {
    PRINTB("WARNING: Can't open include file '%s'.", localpath.generic_string());
    filename_stack.pop_back();
    return;
  }

  lineno_stack.push_back(yylineno);
  yylineno = 1;
  openfiles.push_back(yyin);
  openfilenames.push_back(fullname);
  filename.clear();

  yypush_buffer_state(yy_create_buffer(yyin, YY_BUF_SIZE));
}

/*!
  In case of an error, this will make sure we clean up our custom data structures
  and close all files.
*/
void lexerdestroy()
{
	for (auto f : openfiles) fclose(f);
	openfiles.clear();
	openfilenames.clear();
	filename_stack.clear();
	lineno_stack.clear();
}
