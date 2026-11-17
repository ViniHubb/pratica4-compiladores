#ifndef CODIGO_H
#define CODIGO_H

#include <stdio.h>

/* Instrucao de tres enderecos. Campos nao usados ficam NULL (impresso "-").
 * A convencao de cada op esta documentada no README e em codigo.c. */
typedef struct {
    char *op;
    char *arg1;
    char *arg2;
    char *result;
} Quadrupla;

void  emitir(const char *op, const char *arg1, const char *arg2, const char *result);
char *novo_temp(void);      /* t1, t2, ...  */
char *novo_rotulo(void);    /* L1, L2, ...  */

void ci_imprimir_texto(FILE *f);
void ci_imprimir_quadruplas(FILE *f);

#endif
