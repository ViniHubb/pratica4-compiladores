#ifndef TABELA_H
#define TABELA_H

#include "tipos.h"

typedef enum {
    CAT_VAR_GLOBAL,
    CAT_VAR_LOCAL,
    CAT_PARAMETRO,
    CAT_FUNCAO
} Categoria;

typedef struct Simbolo {
    char *nome;          /* nome no programa fonte                          */
    Categoria cat;
    Tipo tipo;           /* tipo da variavel ou tipo de retorno da funcao   */
    int nparams;         /* so para funcoes                                 */
    Tipo *params;        /* tipos dos parametros, na ordem                  */
    char *escopo;        /* "global" ou nome da funcao                      */
    int nivel;           /* 0 = global, 1 = funcao, 2+ = blocos internos    */
    int linha;
    struct Simbolo *prox;   /* proximo simbolo do mesmo escopo */
} Simbolo;

/* Pilha de escopos: o escopo 0 (global) e aberto em ts_iniciar(). */
void ts_iniciar(void);
void ts_abrir_escopo(void);
void ts_fechar_escopo(void);
int  ts_nivel(void);

/* Procura so no escopo do topo (para detectar duplicatas). */
Simbolo *ts_buscar_no_escopo_atual(const char *nome);
/* Procura do topo ate o global (regra de visibilidade). */
Simbolo *ts_buscar(const char *nome);
/* Procura so no escopo global (funcoes). */
Simbolo *ts_buscar_global(const char *nome);

/* Insere no escopo do topo (ou no global, para funcoes). */
Simbolo *ts_inserir(const char *nome, Categoria cat, Tipo tipo,
                    const char *escopo, int linha);
Simbolo *ts_inserir_global(const char *nome, Categoria cat, Tipo tipo, int linha);

/* Lista todos os simbolos ja declarados (inclusive de escopos fechados). */
void ts_imprimir(void);

#endif
