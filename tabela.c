#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tabela.h"

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
