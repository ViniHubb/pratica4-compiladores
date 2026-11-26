%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

extern int yylex();
extern int yylineno;
extern char *yytext;
extern FILE *yyin;

int num_erros = 0;           /* total de erros */
void yyerror(const char *s);
%}

/* tipos usados no %union (vao para o sintatico.tab.h) */
%code requires {
#include "tipos.h"
#include "tabela.h"
#include "codigo.h"

/* valor de uma expressao */
typedef struct {
    Tipo tipo;
    char *end;              /* variavel, constante ou temporario */
    char *relop;            /* comparacao ainda nao gerada (a relop b) */
    char *rel_a, *rel_b;
} Expr;

/* argumentos de uma chamada */
typedef struct {
    Expr **v;
    int n, cap;
} ListaArgs;
}

/* funcoes da analise semantica (definidas no fim do arquivo) */
%code {
void erro_semantico(const char *fmt, ...);

/* expressoes */
Expr *expr_literal(Tipo t, const char *texto);
Expr *expr_variavel(const char *nome);
Expr *expr_aritmetica(const char *op, Expr *a, Expr *b);
Expr *expr_relacional(const char *op, Expr *a, Expr *b);
Expr *expr_igualdade(const char *op, Expr *a, Expr *b);
Expr *expr_menos_unario(Expr *a);

/* chamadas de funcao */
ListaArgs *args_novo(void);
ListaArgs *args_anexar(ListaArgs *l, Expr *e);
Expr      *expr_chamada(const char *nome, ListaArgs *args);

/* declaracoes e comandos */
void declarar_variavel(Tipo t, const char *nome, Expr *init);
void atribuir(const char *nome, Expr *e);
void iniciar_funcao(Tipo t, const char *nome);
void declarar_parametro(Tipo t, const char *nome);
void registrar_funcao(void);
void finalizar_funcao(void);
void cmd_return(Expr *e);
void desvio_se_falso(Expr *cond, const char *rotulo, const char *comando);
}

/* mensagens de erro detalhadas */
%define parse.error verbose

/* atributos dos simbolos da gramatica */
%union {
    char      *str;     /* lexema ou rotulo */
    Tipo       tipo;
    Expr      *expr;
    ListaArgs *args;
}

/* tokens */
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

/* precedencia (mais abaixo = maior) */
%left IGUAL DIFERENTE
%left MENOR MAIOR MENOR_IGUAL MAIOR_IGUAL
%left MAIS MENOS
%left VEZES DIVIDIDO
%right MENOS_UNARIO

%start programa

%%

programa:
    lista_declaracoes
    ;

lista_declaracoes:
    lista_declaracoes declaracao
    | declaracao
    ;

/* globais e funcoes */
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

/* registra a funcao antes do corpo (permite recursao) */
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

/* mesmo escopo dos parametros */
corpo_funcao:
    ABRE_CHAVE comandos FECHA_CHAVE
    ;

/* if/while abrem escopo novo */
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

comando:
    declaracao_local
    | atribuicao
    | comando_if
    | comando_while
    | comando_return
    | chamada_funcao PONTO_VIRGULA
    | error PONTO_VIRGULA               /* recuperacao de erro */
    ;

declaracao_local:
    tipo ID_LOCAL PONTO_VIRGULA                         { declarar_variavel($1, $2, NULL); }
    | tipo ID_LOCAL ATRIBUICAO expressao PONTO_VIRGULA  { declarar_variavel($1, $2, $4); }
    ;

atribuicao:
    ID_GLOBAL ATRIBUICAO expressao PONTO_VIRGULA    { atribuir($1, $3); }
    | ID_LOCAL ATRIBUICAO expressao PONTO_VIRGULA   { atribuir($1, $3); }
    ;

/* if:      ifFalse c goto L1, B, L1:
   if/else: ifFalse c goto L1, B1, goto L2, L1:, B2, L2: */
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

/* while: L1:, ifFalse c goto L2, B, goto L1, L2: */
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
    int resultado = yyparse();

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

/* ===== Analise semantica e geracao de codigo ===== */

void erro_semantico(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    printf("ERRO SEMANTICO na linha %d: ", yylineno);
    vprintf(fmt, ap);
    printf("\n");
    va_end(ap);
    num_erros++;
}

static Expr *nova_expr(Tipo t, const char *end) {
    Expr *e = calloc(1, sizeof(Expr));
    e->tipo = t;
    e->end = end ? strdup(end) : strdup("?");
    return e;
}

static Expr *expr_erro(void) { return nova_expr(T_ERRO, "?"); }

/* gera t = a relop b, se houver comparacao pendente */
static char *valor(Expr *e) {
    if (e->relop) {
        char *t = novo_temp();
        emitir(e->relop, e->rel_a, e->rel_b, t);
        e->end = t;
        e->relop = NULL;
    }
    return e->end;
}

/* converte int -> float quando preciso */
static char *converter(Expr *e, Tipo destino) {
    char *v = valor(e);
    if (destino == T_FLOAT && e->tipo == T_INT) {
        char *t = novo_temp();
        emitir("itof", v, NULL, t);
        return t;
    }
    return v;
}

/* destino = origem e permitido? */
static int atribuivel(Tipo destino, Tipo origem) {
    if (destino == T_ERRO || origem == T_ERRO) return 1;   /* ja reportado */
    if (destino == origem) return 1;
    return destino == T_FLOAT && origem == T_INT;
}

/* expressoes */

Expr *expr_literal(Tipo t, const char *texto) { return nova_expr(t, texto); }

Expr *expr_variavel(const char *nome) {
    Simbolo *s = ts_buscar(nome);
    if (!s) {
        erro_semantico("variavel '%s' nao declarada", nome);
        return expr_erro();
    }
    return nova_expr(s->tipo, s->nome);
}

Expr *expr_aritmetica(const char *op, Expr *a, Expr *b) {
    if (a->tipo == T_ERRO || b->tipo == T_ERRO) return expr_erro();
    if (!eh_numerico(a->tipo) || !eh_numerico(b->tipo)) {
        erro_semantico("operador '%s' nao se aplica aos tipos %s e %s",
                       op, nome_tipo(a->tipo), nome_tipo(b->tipo));
        return expr_erro();
    }
    Tipo r = (a->tipo == T_FLOAT || b->tipo == T_FLOAT) ? T_FLOAT : T_INT;
    char *va = converter(a, r);
    char *vb = converter(b, r);
    char *t = novo_temp();
    emitir(op, va, vb, t);
    return nova_expr(r, t);
}

static Expr *comparacao_pendente(const char *op, Expr *a, Expr *b, Tipo comum) {
    char *va = converter(a, comum);
    char *vb = converter(b, comum);
    Expr *e = nova_expr(T_BOOL, NULL);
    e->relop = strdup(op);
    e->rel_a = va;
    e->rel_b = vb;
    return e;
}

Expr *expr_relacional(const char *op, Expr *a, Expr *b) {
    if (a->tipo == T_ERRO || b->tipo == T_ERRO) return expr_erro();
    if (!eh_numerico(a->tipo) || !eh_numerico(b->tipo)) {
        erro_semantico("operador '%s' exige operandos numericos, mas recebeu %s e %s",
                       op, nome_tipo(a->tipo), nome_tipo(b->tipo));
        return expr_erro();
    }
    Tipo comum = (a->tipo == T_FLOAT || b->tipo == T_FLOAT) ? T_FLOAT : T_INT;
    return comparacao_pendente(op, a, b, comum);
}

Expr *expr_igualdade(const char *op, Expr *a, Expr *b) {
    if (a->tipo == T_ERRO || b->tipo == T_ERRO) return expr_erro();
    if (eh_numerico(a->tipo) && eh_numerico(b->tipo)) {
        Tipo comum = (a->tipo == T_FLOAT || b->tipo == T_FLOAT) ? T_FLOAT : T_INT;
        return comparacao_pendente(op, a, b, comum);
    }
    if (a->tipo != b->tipo) {
        erro_semantico("operador '%s' compara tipos incompativeis: %s e %s",
                       op, nome_tipo(a->tipo), nome_tipo(b->tipo));
        return expr_erro();
    }
    return comparacao_pendente(op, a, b, a->tipo);
}

Expr *expr_menos_unario(Expr *a) {
    if (a->tipo == T_ERRO) return expr_erro();
    if (!eh_numerico(a->tipo)) {
        erro_semantico("menos unario nao se aplica ao tipo %s", nome_tipo(a->tipo));
        return expr_erro();
    }
    char *v = valor(a);
    char *t = novo_temp();
    emitir("minus", v, NULL, t);
    return nova_expr(a->tipo, t);
}

/* chamadas de funcao */

ListaArgs *args_novo(void) { return calloc(1, sizeof(ListaArgs)); }

ListaArgs *args_anexar(ListaArgs *l, Expr *e) {
    if (l->n == l->cap) {
        l->cap = l->cap ? 2 * l->cap : 4;
        l->v = realloc(l->v, l->cap * sizeof(Expr *));
    }
    l->v[l->n++] = e;
    return l;
}

/* verifica a chamada e gera param/call */
Expr *expr_chamada(const char *nome, ListaArgs *a) {
    Simbolo *f = ts_buscar_global(nome);
    if (!f || f->cat != CAT_FUNCAO) {
        erro_semantico("funcao '%s' nao declarada", nome);
        return expr_erro();
    }

    int ok = 1;
    if (a->n != f->nparams) {
        erro_semantico("funcao '%s' espera %d argumento(s), mas recebeu %d",
                       nome, f->nparams, a->n);
        ok = 0;
    } else {
        for (int i = 0; i < a->n; i++) {
            if (!atribuivel(f->params[i], a->v[i]->tipo)) {
                erro_semantico("argumento %d de '%s' e %s, mas o parametro e %s",
                               i + 1, nome, nome_tipo(a->v[i]->tipo), nome_tipo(f->params[i]));
                ok = 0;
            }
        }
    }
    if (!ok) return expr_erro();

    /* converte e gera os param */
    char **ends = malloc((a->n ? a->n : 1) * sizeof(char *));
    for (int i = 0; i < a->n; i++) ends[i] = converter(a->v[i], f->params[i]);
    for (int i = 0; i < a->n; i++) emitir("param", ends[i], NULL, NULL);
    free(ends);

    char n[16];
    snprintf(n, sizeof n, "%d", a->n);
    char *t = novo_temp();
    emitir("call", nome, n, t);
    return nova_expr(f->tipo, t);
}

/* declaracoes e atribuicoes */

/* funcao atual */
static char *func_nome = NULL;
static Tipo  func_tipo = T_VOID;
static Tipo  func_params[64];
static int   func_nparams = 0;

void declarar_variavel(Tipo t, const char *nome, Expr *init) {
    int global = (ts_nivel() == 0);
    Simbolo *dup = ts_buscar_no_escopo_atual(nome);
    if (dup) {
        erro_semantico("'%s' ja foi declarada neste escopo (linha %d)", nome, dup->linha);
        return;
    }
    /* nao pode esconder local/parametro visivel (como em Java) */
    Simbolo *externa = global ? NULL : ts_buscar(nome);
    if (externa && externa->nivel >= 1) {
        erro_semantico("'%s' ja foi declarada em um bloco externo de '%s' (linha %d)",
                       nome, func_nome, externa->linha);
        return;
    }
    Simbolo *s = ts_inserir(nome, global ? CAT_VAR_GLOBAL : CAT_VAR_LOCAL, t,
                            global ? "global" : func_nome, yylineno);
    if (!init) return;
    if (!atribuivel(t, init->tipo)) {
        erro_semantico("nao e possivel inicializar '%s' (%s) com valor do tipo %s",
                       nome, nome_tipo(t), nome_tipo(init->tipo));
        return;
    }
    if (init->tipo == T_ERRO) return;
    emitir("=", converter(init, t), NULL, s->nome);
}

void atribuir(const char *nome, Expr *e) {
    Simbolo *s = ts_buscar(nome);
    if (!s) {
        erro_semantico("variavel '%s' nao declarada", nome);
        return;
    }
    if (!atribuivel(s->tipo, e->tipo)) {
        erro_semantico("atribuicao incompativel: '%s' e %s, mas a expressao e %s",
                       nome, nome_tipo(s->tipo), nome_tipo(e->tipo));
        return;
    }
    if (e->tipo == T_ERRO) return;
    emitir("=", converter(e, s->tipo), NULL, s->nome);
}

/* funcoes */

void iniciar_funcao(Tipo t, const char *nome) {
    func_nome = strdup(nome);
    func_tipo = t;
    func_nparams = 0;
    ts_abrir_escopo();              /* parametros + corpo */
    emitir("func", NULL, NULL, nome);
}

void declarar_parametro(Tipo t, const char *nome) {
    Simbolo *dup = ts_buscar_no_escopo_atual(nome);
    if (dup) {
        erro_semantico("parametro '%s' repetido em '%s'", nome, func_nome);
        return;
    }
    ts_inserir(nome, CAT_PARAMETRO, t, func_nome, yylineno);
    if (func_nparams < 64) func_params[func_nparams++] = t;
}

/* chamado antes do corpo (permite recursao) */
void registrar_funcao(void) {
    Simbolo *dup = ts_buscar_global(func_nome);
    if (dup) {
        erro_semantico("funcao '%s' ja foi declarada (linha %d)", func_nome, dup->linha);
        return;
    }
    Simbolo *f = ts_inserir_global(func_nome, CAT_FUNCAO, func_tipo, yylineno);
    f->nparams = func_nparams;
    f->params = malloc((func_nparams ? func_nparams : 1) * sizeof(Tipo));
    memcpy(f->params, func_params, func_nparams * sizeof(Tipo));
}

void finalizar_funcao(void) {
    ts_fechar_escopo();
}

void cmd_return(Expr *e) {
    if (func_tipo == T_VOID) {
        erro_semantico("'%s' nao tem tipo de retorno e nao pode retornar valor", func_nome);
        return;
    }
    if (!atribuivel(func_tipo, e->tipo)) {
        erro_semantico("'%s' deve retornar %s, mas a expressao e %s",
                       func_nome, nome_tipo(func_tipo), nome_tipo(e->tipo));
        return;
    }
    if (e->tipo == T_ERRO) return;
    emitir("return", converter(e, func_tipo), NULL, NULL);
}

/* ifFalse cond goto rotulo */
void desvio_se_falso(Expr *cond, const char *rotulo, const char *comando) {
    if (cond->tipo != T_BOOL && cond->tipo != T_ERRO)
        erro_semantico("condicao do %s deve ser bool, mas e %s", comando, nome_tipo(cond->tipo));
    if (cond->relop) {
        char op[16];
        snprintf(op, sizeof op, "ifFalse%s", cond->relop);
        emitir(op, cond->rel_a, cond->rel_b, rotulo);
    } else {
        emitir("ifFalse", cond->end, NULL, rotulo);
    }
}
