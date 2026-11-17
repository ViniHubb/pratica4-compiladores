%option noyywrap
%option yylineno

%{
#include <stdio.h>
#include <string.h>
#include "sintatico.tab.h"   /* codigos dos tokens, gerados pelo Bison */

extern int num_erros;        /* contador definido no sintatico.y */

/* TP II: guarda o lexema para as acoes semanticas do Bison */
#define LEXEMA (yylval.str = strdup(yytext))

void erro_lexico(const char *msg) {
    printf("ERRO LEXICO na linha %d: %s '%s'\n", yylineno, msg, yytext);
    num_erros++;
}
%}

/* ---------- definicoes regulares ---------- */
ESPACO      [ \t\r\n]+
DIGITO      [0-9]
MAIUSCULA   [A-Z]
MINUSCULA   [a-z]

NUMERO      {DIGITO}+
NUMERO_REAL {DIGITO}+"."{DIGITO}+
TEXTO       \"[^\"\n]*\"
ID_GLOBAL   {MAIUSCULA}({MAIUSCULA}|{DIGITO}|_)*
ID_LOCAL    {MINUSCULA}({MINUSCULA}|{DIGITO}|_)*
VERBO       {MINUSCULA}+(ar|er|ir)
ID_FUNCAO   {VERBO}{MAIUSCULA}[A-Za-z0-9]*
ID_INVALIDO [A-Za-z_][A-Za-z0-9_]*

%%

{ESPACO}                { /* espacos: ignora */ }
"//".*                  { /* comentario de linha: ignora */ }

 /* palavras reservadas: ANTES dos identificadores */
"bool"                  { return BOOL; }
"int"                   { return INT; }
"float"                 { return FLOAT; }
"string"                { return STRING; }
"true"                  { return VERDADEIRO; }
"false"                 { return FALSO; }
"if"                    { return IF; }
"else"                  { return ELSE; }
"while"                 { return WHILE; }
"return"                { return RETURN; }
"principal"             { return PRINCIPAL; }

 /* identificadores: a ordem decide os empates */
{ID_FUNCAO}             { LEXEMA; return ID_FUNCAO; }
{ID_GLOBAL}             { LEXEMA; return ID_GLOBAL; }
{ID_LOCAL}              { LEXEMA; return ID_LOCAL; }
{ID_INVALIDO}           { erro_lexico("identificador fora das convencoes"); }

 /* literais: NUMERO_REAL e mais longo que NUMERO em "3.5" */
{NUMERO_REAL}           { LEXEMA; return NUMERO_REAL; }
{NUMERO}                { LEXEMA; return NUMERO; }
{TEXTO}                 { LEXEMA; return TEXTO; }
\"[^\"\n]*              { erro_lexico("string sem aspas de fechamento"); }

 /* operadores de 2 caracteres: o maior casamento resolve "<" x "<=" */
"<="                    { return MENOR_IGUAL; }
">="                    { return MAIOR_IGUAL; }
"=="                    { return IGUAL; }
"!="                    { return DIFERENTE; }
"<"                     { return MENOR; }
">"                     { return MAIOR; }
"="                     { return ATRIBUICAO; }
"+"                     { return MAIS; }
"-"                     { return MENOS; }
"*"                     { return VEZES; }
"/"                     { return DIVIDIDO; }

"("                     { return ABRE_PARENTESES; }
")"                     { return FECHA_PARENTESES; }
"{"                     { return ABRE_CHAVE; }
"}"                     { return FECHA_CHAVE; }
";"                     { return PONTO_VIRGULA; }
","                     { return VIRGULA; }

 /* qualquer outra coisa: ULTIMA regra */
.                       { erro_lexico("caractere invalido"); }

%%
