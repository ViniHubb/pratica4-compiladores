#ifndef TIPOS_H
#define TIPOS_H

/* Tipos da linguagem. T_VOID so e usado pela funcao principal() sem tipo;
 * T_ERRO marca uma expressao que ja gerou erro, para nao repetir mensagens
 * em cascata. */
typedef enum {
    T_INT,
    T_FLOAT,
    T_BOOL,
    T_STRING,
    T_VOID,
    T_ERRO
} Tipo;

const char *nome_tipo(Tipo t);
int eh_numerico(Tipo t);

#endif
