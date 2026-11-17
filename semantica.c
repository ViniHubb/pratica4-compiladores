#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include "semantica.h"
#include "tabela.h"
#include "codigo.h"

extern int yylineno;

/* ------------------------------------------------------------------ */
/* mensagens                                                           */
/* ------------------------------------------------------------------ */

void erro_semantico(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    printf("ERRO SEMANTICO na linha %d: ", yylineno);
    vprintf(fmt, ap);
    printf("\n");
    va_end(ap);
    num_erros++;
}

/* ------------------------------------------------------------------ */
/* funcoes auxiliares                                                  */
/* ------------------------------------------------------------------ */

static Expr *nova_expr(Tipo t, const char *end) {
    Expr *e = calloc(1, sizeof(Expr));
    e->tipo = t;
    e->end = end ? strdup(end) : strdup("?");
    return e;
}

static Expr *expr_erro(void) { return nova_expr(T_ERRO, "?"); }

/* Materializa uma comparacao pendente: t = a op b. Devolve o endereco. */
static char *valor(Expr *e) {
    if (e->relop) {
        char *t = novo_temp();
        emitir(e->relop, e->rel_a, e->rel_b, t);
        e->end = t;
        e->relop = NULL;
    }
    return e->end;
}

/* Devolve o endereco de e ja convertido para o tipo destino.
 * Unica conversao implicita da linguagem: int -> float. */
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
    if (destino == T_ERRO || origem == T_ERRO) return 1;   /* erro ja reportado */
    if (destino == origem) return 1;
    return destino == T_FLOAT && origem == T_INT;
}

/* ------------------------------------------------------------------ */
/* expressoes                                                          */
/* ------------------------------------------------------------------ */

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

/* ------------------------------------------------------------------ */
/* chamadas de funcao                                                  */
/* ------------------------------------------------------------------ */

ListaArgs *args_novo(void) { return calloc(1, sizeof(ListaArgs)); }

ListaArgs *args_anexar(ListaArgs *l, Expr *e) {
    if (l->n == l->cap) {
        l->cap = l->cap ? 2 * l->cap : 4;
        l->v = realloc(l->v, l->cap * sizeof(Expr *));
    }
    l->v[l->n++] = e;
    return l;
}

/* Verifica a chamada e gera param/call. O valor de retorno vai sempre para
 * um temporario (que fica sem uso quando a chamada e um comando). */
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

    /* os argumentos ja foram avaliados; agora converte e empilha */
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

/* ------------------------------------------------------------------ */
/* declaracoes de variaveis e atribuicoes                              */
/* ------------------------------------------------------------------ */

/* estado da funcao que esta sendo analisada */
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
    /* Como em Java, uma local de bloco nao pode esconder outra local ou
     * parametro da mesma funcao que ainda esteja visivel. Blocos irmaos
     * (if/else, dois whiles seguidos) podem repetir o nome. */
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

/* ------------------------------------------------------------------ */
/* funcoes                                                             */
/* ------------------------------------------------------------------ */

void iniciar_funcao(Tipo t, const char *nome) {
    func_nome = strdup(nome);
    func_tipo = t;
    func_nparams = 0;
    ts_abrir_escopo();              /* nivel 1: parametros + corpo */
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

/* Chamado depois do ')' e antes do corpo: assim a funcao ja e
 * visivel dentro do proprio corpo (recursao). */
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

/* ifFalse cond goto rotulo (usado por if e while) */
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
