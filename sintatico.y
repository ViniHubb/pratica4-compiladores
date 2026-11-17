%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern int yylex();
extern int yylineno;
extern char *yytext;
extern FILE *yyin;

int num_erros = 0;           /* soma erros lexicos, sintaticos e semanticos */
void yyerror(const char *s);
%}

/* tipos usados nos atributos (visiveis tambem no sintatico.tab.h) */
%code requires {
#include "tipos.h"
#include "tabela.h"
#include "codigo.h"
#include "semantica.h"
}

/* mensagens de erro detalhadas: "unexpected X, expecting Y" */
%define parse.error verbose

/* atributos dos simbolos da gramatica */
%union {
    char      *str;     /* lexema (identificadores e literais) ou rotulo */
    Tipo       tipo;
    Expr      *expr;
    ListaArgs *args;
}

/* tokens (devem corresponder aos returns do lexico.l) */
%token BOOL INT FLOAT STRING VERDADEIRO FALSO
%token IF ELSE WHILE RETURN PRINCIPAL
%token <str> ID_FUNCAO ID_GLOBAL ID_LOCAL NUMERO NUMERO_REAL TEXTO
%token MENOR_IGUAL MAIOR_IGUAL IGUAL DIFERENTE MENOR MAIOR
%token ATRIBUICAO MAIS MENOS VEZES DIVIDIDO
%token ABRE_PARENTESES FECHA_PARENTESES ABRE_CHAVE FECHA_CHAVE PONTO_VIRGULA VIRGULA

%type <tipo>    tipo
%type <expr>    expressao chamada_funcao
%type <args>    argumentos lista_argumentos
%type <str>     inicio_if

/* precedencia: quanto mais abaixo, maior a prioridade */
%left IGUAL DIFERENTE
%left MENOR MAIOR MENOR_IGUAL MAIOR_IGUAL
%left MAIS MENOS
%left VEZES DIVIDIDO
%right MENOS_UNARIO          /* pseudo-token, usado so com %prec */

%start programa

%%

programa:
    lista_declaracoes
    ;

lista_declaracoes:
    lista_declaracoes declaracao
    | declaracao
    ;

/* nivel global: so variaveis GLOBAIS e funcoes */
declaracao:
    declaracao_global
    | declaracao_funcao
    | funcao_principal
    ;

declaracao_global:
    tipo ID_GLOBAL PONTO_VIRGULA                        { declarar_variavel($1, $2, NULL); }
    | tipo ID_GLOBAL ATRIBUICAO expressao PONTO_VIRGULA { declarar_variavel($1, $2, $4); }
    ;

tipo:
    INT      { $$ = T_INT; }
    | FLOAT  { $$ = T_FLOAT; }
    | BOOL   { $$ = T_BOOL; }
    | STRING { $$ = T_STRING; }
    ;

/* A funcao e registrada na tabela depois dos parametros e antes do corpo,
 * para que o corpo possa chama-la (recursao). */
declaracao_funcao:
    tipo ID_FUNCAO ABRE_PARENTESES      { iniciar_funcao($1, $2); }
    parametros FECHA_PARENTESES         { registrar_funcao(); }
    corpo_funcao                        { finalizar_funcao(); }
    ;

funcao_principal:
    PRINCIPAL ABRE_PARENTESES FECHA_PARENTESES
        { iniciar_funcao(T_VOID, "principal"); registrar_funcao(); }
    corpo_funcao
        { finalizar_funcao(); }
    | tipo PRINCIPAL ABRE_PARENTESES FECHA_PARENTESES
        { iniciar_funcao($1, "principal"); registrar_funcao(); }
    corpo_funcao
        { finalizar_funcao(); }
    ;

parametros:
    lista_parametros
    | %empty
    ;

lista_parametros:
    lista_parametros VIRGULA parametro
    | parametro
    ;

parametro:
    tipo ID_LOCAL           { declarar_parametro($1, $2); }
    ;

/* o corpo da funcao usa o mesmo escopo dos parametros (nivel 1) */
corpo_funcao:
    ABRE_CHAVE comandos FECHA_CHAVE
    ;

/* blocos de if/while abrem um escopo novo */
bloco:
    ABRE_CHAVE              { ts_abrir_escopo(); }
    comandos FECHA_CHAVE    { ts_fechar_escopo(); }
    ;

comandos:
    lista_comandos
    | %empty
    ;

lista_comandos:
    lista_comandos comando
    | comando
    ;

/* dentro de funcoes: so variaveis LOCAIS sao declaradas */
comando:
    declaracao_local
    | atribuicao
    | comando_if
    | comando_while
    | comando_return
    | chamada_funcao PONTO_VIRGULA      { /* valor descartado */ }
    | error PONTO_VIRGULA               /* recuperacao: descarta ate o ';' */
    ;

declaracao_local:
    tipo ID_LOCAL PONTO_VIRGULA                         { declarar_variavel($1, $2, NULL); }
    | tipo ID_LOCAL ATRIBUICAO expressao PONTO_VIRGULA  { declarar_variavel($1, $2, $4); }
    ;

/* atribuir a uma global dentro de funcao continua permitido */
atribuicao:
    ID_GLOBAL ATRIBUICAO expressao PONTO_VIRGULA    { atribuir($1, $3); }
    | ID_LOCAL ATRIBUICAO expressao PONTO_VIRGULA   { atribuir($1, $3); }
    ;

/*  if (c) B            ifFalse c goto L1 / B / L1:
 *  if (c) B1 else B2   ifFalse c goto L1 / B1 / goto L2 / L1: / B2 / L2:  */
inicio_if:
    IF ABRE_PARENTESES expressao FECHA_PARENTESES
        { $$ = novo_rotulo(); desvio_se_falso($3, $$, "if"); }
    ;

comando_if:
    inicio_if bloco
        { emitir("label", NULL, NULL, $1); }
    | inicio_if bloco ELSE
        { $<str>$ = novo_rotulo(); emitir("goto", NULL, NULL, $<str>$);
          emitir("label", NULL, NULL, $1); }
      bloco
        { emitir("label", NULL, NULL, $<str>4); }
    ;

/*  while (c) B    L1: / ifFalse c goto L2 / B / goto L1 / L2:  */
comando_while:
    WHILE
        { $<str>$ = novo_rotulo(); emitir("label", NULL, NULL, $<str>$); }
    ABRE_PARENTESES expressao FECHA_PARENTESES
        { $<str>$ = novo_rotulo(); desvio_se_falso($4, $<str>$, "while"); }
    bloco
        { emitir("goto", NULL, NULL, $<str>2); emitir("label", NULL, NULL, $<str>6); }
    ;

comando_return:
    RETURN expressao PONTO_VIRGULA      { cmd_return($2); }
    ;

chamada_funcao:
    ID_FUNCAO ABRE_PARENTESES argumentos FECHA_PARENTESES   { $$ = expr_chamada($1, $3); }
    ;

argumentos:
    lista_argumentos    { $$ = $1; }
    | %empty            { $$ = args_novo(); }
    ;

lista_argumentos:
    lista_argumentos VIRGULA expressao  { $$ = args_anexar($1, $3); }
    | expressao                         { $$ = args_anexar(args_novo(), $1); }
    ;

expressao:
    expressao MAIS expressao            { $$ = expr_aritmetica("+", $1, $3); }
    | expressao MENOS expressao         { $$ = expr_aritmetica("-", $1, $3); }
    | expressao VEZES expressao         { $$ = expr_aritmetica("*", $1, $3); }
    | expressao DIVIDIDO expressao      { $$ = expr_aritmetica("/", $1, $3); }
    | expressao MENOR expressao         { $$ = expr_relacional("<", $1, $3); }
    | expressao MAIOR expressao         { $$ = expr_relacional(">", $1, $3); }
    | expressao MENOR_IGUAL expressao   { $$ = expr_relacional("<=", $1, $3); }
    | expressao MAIOR_IGUAL expressao   { $$ = expr_relacional(">=", $1, $3); }
    | expressao IGUAL expressao         { $$ = expr_igualdade("==", $1, $3); }
    | expressao DIFERENTE expressao     { $$ = expr_igualdade("!=", $1, $3); }
    | MENOS expressao %prec MENOS_UNARIO { $$ = expr_menos_unario($2); }
    | ABRE_PARENTESES expressao FECHA_PARENTESES { $$ = $2; }
    | chamada_funcao                    { $$ = $1; }
    | ID_GLOBAL                         { $$ = expr_variavel($1); }
    | ID_LOCAL                          { $$ = expr_variavel($1); }
    | NUMERO                            { $$ = expr_literal(T_INT, $1); }
    | NUMERO_REAL                       { $$ = expr_literal(T_FLOAT, $1); }
    | TEXTO                             { $$ = expr_literal(T_STRING, $1); }
    | VERDADEIRO                        { $$ = expr_literal(T_BOOL, "true"); }
    | FALSO                             { $$ = expr_literal(T_BOOL, "false"); }
    ;

%%

void yyerror(const char *s) {
    printf("ERRO SINTATICO na linha %d: %s (perto de '%s')\n", yylineno, s, yytext);
    num_erros++;
}

/* uso: ./compilador programa.txt [saida.tac] */
int main(int argc, char *argv[]) {
    if (argc > 1) {
        yyin = fopen(argv[1], "r");
        if (!yyin) { perror(argv[1]); return 1; }
    }

    ts_iniciar();
    int resultado = yyparse();   /* 0 = chegou ao fim; 1 = abortou */

    if (resultado != 0 || num_erros > 0) {
        printf("Programa com %d erro(s). Codigo intermediario nao gerado.\n", num_erros);
        return 1;
    }

    printf("Analise lexica concluida.\n");
    printf("Analise sintatica concluida.\n");
    printf("Analise semantica concluida.\n");

    printf("\n===== Tabela de simbolos =====\n");
    ts_imprimir();

    printf("\n===== Codigo intermediario (tres enderecos) =====\n");
    ci_imprimir_texto(stdout);

    printf("\n===== Quadruplas =====\n");
    ci_imprimir_quadruplas(stdout);

    if (argc > 2) {
        FILE *f = fopen(argv[2], "w");
        if (!f) { perror(argv[2]); return 1; }
        ci_imprimir_texto(f);
        fclose(f);
        printf("\nCodigo intermediario salvo em %s\n", argv[2]);
    }
    return 0;
}
