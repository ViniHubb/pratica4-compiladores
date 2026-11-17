#include <stdlib.h>
#include <string.h>
#include "codigo.h"

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
