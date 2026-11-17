#ifndef SEMANTICA_H
#define SEMANTICA_H

#include "tipos.h"

/* Atributo sintetizado de uma expressao.
 * - tipo: tipo calculado na analise semantica
 * - end : "endereco" do valor no codigo intermediario (variavel, constante
 *         ou temporario)
 * - relop/rel_a/rel_b: uma comparacao (a < b) ainda nao materializada.
 *   Em if/while ela vira direto "ifFalse a < b goto L" (como no enunciado);
 *   em qualquer outro uso ela vira "t = a < b". */
typedef struct {
    Tipo tipo;
    char *end;
    char *relop;
    char *rel_a, *rel_b;
} Expr;

/* Argumentos de uma chamada, guardados ate o fim da lista para que os
 * "param" de chamadas aninhadas, como f(g(1), g(2)), nao se misturem. */
typedef struct {
    Expr **v;
    int n, cap;
} ListaArgs;

extern int num_erros;

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
Expr      *expr_chamada(const char *nome, ListaArgs *args);   /* t = call f, n */

/* declaracoes e comandos */
void declarar_variavel(Tipo t, const char *nome, Expr *init);
void atribuir(const char *nome, Expr *e);
void iniciar_funcao(Tipo t, const char *nome);
void declarar_parametro(Tipo t, const char *nome);
void registrar_funcao(void);
void finalizar_funcao(void);
void cmd_return(Expr *e);
void desvio_se_falso(Expr *cond, const char *rotulo, const char *comando);

#endif
