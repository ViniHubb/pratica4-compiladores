/* Atividade Pratica IV - Compiladores
 * Vinicius Niquini e Arthur Cunha
 *
 * Versao em um arquivo so: gramatica, analise semantica, tabela de
 * simbolos e codigo de tres enderecos.
 *
 *   bison -d sintatico.y
 *   flex lexico.l
 *   gcc sintatico.tab.c lex.yy.c -o compilador
 *   ./compilador programa.txt [saida.tac]
 */

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
/* tipos da linguagem; T_ERRO marca expressao que ja deu erro */
typedef enum {
    T_INT,
    T_FLOAT,
    T_BOOL,
    T_STRING,
    T_VOID,
    T_ERRO
} Tipo;

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

%code {
/* ----- tipos ----- */
const char *nome_tipo(Tipo t);
int eh_numerico(Tipo t);

/* ----- tabela de simbolos ----- */
typedef enum {
    CAT_VAR_GLOBAL,
    CAT_VAR_LOCAL,
    CAT_PARAMETRO,
    CAT_FUNCAO
} Categoria;

typedef struct Simbolo {
    char *nome;
    Categoria cat;
    Tipo tipo;              /* tipo da variavel ou retorno da funcao */
    int nparams;            /* so para funcoes */
    Tipo *params;
    char *escopo;           /* "global" ou nome da funcao */
    int nivel;              /* 0 = global, 1 = funcao, 2+ = blocos */
    int linha;
    struct Simbolo *prox;   /* proximo do mesmo escopo */
} Simbolo;

void ts_iniciar(void);
void ts_abrir_escopo(void);
void ts_fechar_escopo(void);
int  ts_nivel(void);
Simbolo *ts_buscar_no_escopo_atual(const char *nome);   /* so no topo */
Simbolo *ts_buscar(const char *nome);                   /* topo ate o global */
Simbolo *ts_buscar_global(const char *nome);            /* so no global */
Simbolo *ts_inserir(const char *nome, Categoria cat, Tipo tipo,
                    const char *escopo, int linha);
Simbolo *ts_inserir_global(const char *nome, Categoria cat, Tipo tipo, int linha);
void ts_imprimir(void);

/* ----- codigo intermediario ----- */
typedef struct {
    char *op;
    char *arg1;
    char *arg2;
    char *result;           /* campos nao usados ficam NULL */
} Quadrupla;

void  emitir(const char *op, const char *arg1, const char *arg2, const char *result);
char *novo_temp(void);      /* t1, t2, ... */
char *novo_rotulo(void);    /* L1, L2, ... */
void  ci_imprimir_texto(FILE *f);
void  ci_imprimir_quadruplas(FILE *f);

/* ----- analise semantica ----- */
void erro_semantico(const char *fmt, ...);

Expr *expr_literal(Tipo t, const char *texto);
Expr *expr_variavel(const char *nome);
Expr *expr_aritmetica(const char *op, Expr *a, Expr *b);
Expr *expr_relacional(const char *op, Expr *a, Expr *b);
Expr *expr_igualdade(const char *op, Expr *a, Expr *b);
Expr *expr_menos_unario(Expr *a);

ListaArgs *args_novo(void);
ListaArgs *args_anexar(ListaArgs *l, Expr *e);
Expr      *expr_chamada(const char *nome, ListaArgs *args);

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

/* ===== Tabela de simbolos ===== */

#define MAX_NIVEIS   64
#define MAX_SIMBOLOS 1024

/* Cada nivel da pilha guarda uma lista encadeada com os simbolos do escopo. */
static Simbolo *pilha[MAX_NIVEIS];
static int topo = -1;

/* Registro de todos os simbolos, para imprimir a tabela no final
 * (os escopos locais ja foram fechados quando o programa termina). */
static Simbolo *registro[MAX_SIMBOLOS];
static int nregistro = 0;

const char *nome_tipo(Tipo t) {
    switch (t) {
        case T_INT:    return "int";
        case T_FLOAT:  return "float";
        case T_BOOL:   return "bool";
        case T_STRING: return "string";
        case T_VOID:   return "void";
        default:       return "<erro>";
    }
}

int eh_numerico(Tipo t) { return t == T_INT || t == T_FLOAT; }

static const char *nome_categoria(Categoria c) {
    switch (c) {
        case CAT_VAR_GLOBAL: return "var global";
        case CAT_VAR_LOCAL:  return "var local";
        case CAT_PARAMETRO:  return "parametro";
        default:             return "funcao";
    }
}

void ts_iniciar(void) { topo = -1; ts_abrir_escopo(); }

void ts_abrir_escopo(void) {
    if (topo + 1 >= MAX_NIVEIS) { fprintf(stderr, "escopos aninhados demais\n"); exit(1); }
    pilha[++topo] = NULL;
}

void ts_fechar_escopo(void) {
    /* os simbolos continuam no registro; so saem da pilha de visibilidade */
    if (topo > 0) pilha[topo--] = NULL;
}

int ts_nivel(void) { return topo; }

static Simbolo *buscar_na_lista(Simbolo *s, const char *nome) {
    for (; s; s = s->prox)
        if (strcmp(s->nome, nome) == 0) return s;
    return NULL;
}

Simbolo *ts_buscar_no_escopo_atual(const char *nome) {
    return buscar_na_lista(pilha[topo], nome);
}

Simbolo *ts_buscar(const char *nome) {
    for (int n = topo; n >= 0; n--) {
        Simbolo *s = buscar_na_lista(pilha[n], nome);
        if (s) return s;
    }
    return NULL;
}

Simbolo *ts_buscar_global(const char *nome) {
    return buscar_na_lista(pilha[0], nome);
}

static Simbolo *novo_simbolo(const char *nome, Categoria cat, Tipo tipo,
                             const char *escopo, int nivel, int linha) {
    Simbolo *s = calloc(1, sizeof(Simbolo));
    s->nome = strdup(nome);
    s->cat = cat;
    s->tipo = tipo;
    s->escopo = strdup(escopo);
    s->nivel = nivel;
    s->linha = linha;
    if (nregistro < MAX_SIMBOLOS) registro[nregistro++] = s;
    return s;
}

Simbolo *ts_inserir(const char *nome, Categoria cat, Tipo tipo,
                    const char *escopo, int linha) {
    Simbolo *s = novo_simbolo(nome, cat, tipo, escopo, topo, linha);
    s->prox = pilha[topo];
    pilha[topo] = s;
    return s;
}

Simbolo *ts_inserir_global(const char *nome, Categoria cat, Tipo tipo, int linha) {
    Simbolo *s = novo_simbolo(nome, cat, tipo, "global", 0, linha);
    s->prox = pilha[0];
    pilha[0] = s;
    return s;
}

void ts_imprimir(void) {
    printf("%-16s %-11s %-7s %-18s %-5s %-6s %s\n",
           "Nome", "Categoria", "Tipo", "Escopo", "Nivel", "Linha", "Parametros");
    for (int i = 0; i < nregistro; i++) {
        Simbolo *s = registro[i];
        char params[256] = "-";
        if (s->cat == CAT_FUNCAO) {
            params[0] = '(';
            params[1] = '\0';
            for (int p = 0; p < s->nparams; p++) {
                if (p) strncat(params, ", ", sizeof params - strlen(params) - 1);
                strncat(params, nome_tipo(s->params[p]), sizeof params - strlen(params) - 1);
            }
            strncat(params, ")", sizeof params - strlen(params) - 1);
        }
        printf("%-16s %-11s %-7s %-18s %-5d %-6d %s\n",
               s->nome, nome_categoria(s->cat), nome_tipo(s->tipo), s->escopo,
               s->nivel, s->linha, params);
    }
}

/* ===== Codigo intermediario ===== */

/*
 * Convencao das quadruplas (op, arg1, arg2, result):
 *
 *   +  -  *  /             a      b      t       t = a op b
 *   <  >  <=  >=  ==  !=   a      b      t       t = a op b      (resultado bool)
 *   minus                  a      -      t       t = - a
 *   itof                   a      -      t       t = (float) a   (conversao implicita)
 *   =                      a      -      x       x = a
 *   func                   -      -      f       f:              (inicio da funcao f)
 *   label                  -      -      L       L:
 *   goto                   -      -      L       goto L
 *   ifFalse                c      -      L       ifFalse c goto L
 *   ifFalse<  ifFalse>  ...a      b      L       ifFalse a < b goto L
 *   param                  a      -      -       param a
 *   call                   f      n      t       t = call f, n
 *   return                 a      -      -       return a
 */

/* todas as instrucoes, na ordem em que foram geradas */
static Quadrupla *quads = NULL;
static int nquads = 0, cap = 0;

static int cont_temp = 0;
static int cont_rotulo = 0;

static char *dup(const char *s) { return s ? strdup(s) : NULL; }

void emitir(const char *op, const char *arg1, const char *arg2, const char *result) {
    if (nquads == cap) {
        cap = cap ? 2 * cap : 64;
        quads = realloc(quads, cap * sizeof(Quadrupla));
    }
    Quadrupla q = { dup(op), dup(arg1), dup(arg2), dup(result) };
    quads[nquads++] = q;
}

char *novo_temp(void) {
    char buf[16];
    snprintf(buf, sizeof buf, "t%d", ++cont_temp);
    return strdup(buf);
}

char *novo_rotulo(void) {
    char buf[16];
    snprintf(buf, sizeof buf, "L%d", ++cont_rotulo);
    return strdup(buf);
}

static const char *c(const char *s) { return s ? s : "-"; }

static int eh_op_binario(const char *op) {
    static const char *ops[] = { "+", "-", "*", "/", "<", ">", "<=", ">=", "==", "!=", NULL };
    for (int i = 0; ops[i]; i++) if (strcmp(op, ops[i]) == 0) return 1;
    return 0;
}

static void imprimir_instrucao(FILE *f, Quadrupla *q) {
    const char *op = q->op;
    if (strcmp(op, "func") == 0)           fprintf(f, "\n%s:\n", q->result);
    else if (strcmp(op, "label") == 0)     fprintf(f, "%s:\n", q->result);
    else if (eh_op_binario(op))            fprintf(f, "    %s = %s %s %s\n", q->result, q->arg1, op, q->arg2);
    else if (strcmp(op, "minus") == 0)     fprintf(f, "    %s = - %s\n", q->result, q->arg1);
    else if (strcmp(op, "itof") == 0)      fprintf(f, "    %s = (float) %s\n", q->result, q->arg1);
    else if (strcmp(op, "=") == 0)         fprintf(f, "    %s = %s\n", q->result, q->arg1);
    else if (strcmp(op, "goto") == 0)      fprintf(f, "    goto %s\n", q->result);
    else if (strcmp(op, "ifFalse") == 0)   fprintf(f, "    ifFalse %s goto %s\n", q->arg1, q->result);
    else if (strncmp(op, "ifFalse", 7) == 0)
        fprintf(f, "    ifFalse %s %s %s goto %s\n", q->arg1, op + 7, q->arg2, q->result);
    else if (strcmp(op, "param") == 0)     fprintf(f, "    param %s\n", q->arg1);
    else if (strcmp(op, "call") == 0)      fprintf(f, "    %s = call %s, %s\n", q->result, q->arg1, q->arg2);
    else if (strcmp(op, "return") == 0)    fprintf(f, "    return %s\n", q->arg1);
    else fprintf(f, "    %s %s %s %s\n", op, c(q->arg1), c(q->arg2), c(q->result));
}

void ci_imprimir_texto(FILE *f) {
    for (int i = 0; i < nquads; i++) imprimir_instrucao(f, &quads[i]);
}

void ci_imprimir_quadruplas(FILE *f) {
    fprintf(f, "%-4s %-10s %-16s %-10s %s\n", "N", "op", "arg1", "arg2", "result");
    for (int i = 0; i < nquads; i++) {
        Quadrupla *q = &quads[i];
        fprintf(f, "%-4d %-10s %-16s %-10s %s\n", i, q->op, c(q->arg1), c(q->arg2), c(q->result));
    }
}
