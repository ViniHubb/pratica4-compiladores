# Atividade Prática IV – Compiladores

Extensão do compilador do TP I (Flex + Bison) com **análise semântica** e **geração de código intermediário de três endereços**, armazenado internamente como **quádruplas**.

Grupo: Vinicius Niquini e Arthur Cunha

## Como compilar e executar

```bash
make                                  # gera ./compilador
./compilador programa.txt             # análise + tabela de símbolos + código + quádruplas
./compilador programa.txt saida.tac   # também salva o código de três endereços em arquivo
make testes                           # roda todos os programas de testes/
make clean
```

Se houver qualquer erro (léxico, sintático ou semântico), o compilador lista todos e **não** gera o código intermediário.

## Arquivos

| Arquivo | Papel |
|---|---|
| `lexico.l` | Analisador léxico do TP I. Única mudança: identificadores e literais agora enviam o lexema ao Bison (`yylval.str`). |
| `sintatico.y` | Gramática do TP I + ações semânticas (verificação e geração de código). |
| `tabela.c/.h` | Tabela de símbolos com pilha de escopos. |
| `semantica.c/.h` | Regras semânticas e geração de código: tipos, declarações, chamadas, `return`, condições. |
| `codigo.c/.h` | Quádruplas, `novo_temp()`, `novo_rotulo()` e impressão. |
| `tipos.h` | Tipos da linguagem (`int`, `float`, `bool`, `string`). |
| `testes/` | `validos/`, `erros_lexicos/`, `erros_sintaticos/` (do TP I) e `erros_semanticos/` (novos). |
| `saidas/` | Saída do compilador para cada teste. |

## Tabela de símbolos

Cada símbolo guarda nome, categoria (`var global`, `var local`, `parametro`, `funcao`), tipo, escopo (`global` ou nome da função), nível, linha e, para funções, a quantidade e os tipos dos parâmetros.

Os escopos formam uma pilha:

- **nível 0** – global: variáveis globais (MAIÚSCULAS) e funções;
- **nível 1** – função: parâmetros e variáveis declaradas no corpo;
- **nível 2+** – cada bloco de `if`/`else`/`while` abre um escopo novo.

A busca vai do topo até o global. Uma variável local de bloco **não pode** ter o nome de outra local ou parâmetro ainda visível na mesma função (mesma regra do Java); isso é erro semântico. Blocos irmãos (o `if` e o `else`, ou dois `while` seguidos) podem repetir nomes, porque um já saiu de escopo quando o outro começa. Assim, cada nome visível dentro de uma função é único e o código intermediário usa os nomes do programa sem renomear nada.

A função é inserida na tabela logo após o `)` dos parâmetros, antes do corpo — por isso chamadas recursivas funcionam.

## Verificações semânticas

| Verificação | Exemplo de mensagem |
|---|---|
| Variável declarada antes do uso | `variavel 'y' nao declarada` |
| Global usada antes de ser declarada | `variavel 'LIMITE' nao declarada` |
| Variável de bloco usada fora dele | `variavel 'dentro' nao declarada` |
| Declaração duplicada no mesmo escopo (global, local, parâmetro, função) | `'r' ja foi declarada neste escopo (linha 5)` |
| Local de bloco com o nome de outra local/parâmetro visível | `'i' ja foi declarada em um bloco externo de 'contarAte' (linha 3)` |
| Tipos em atribuição e inicialização | `atribuicao incompativel: 'x' e int, mas a expressao e float` |
| Tipos em expressões aritméticas e relacionais | `operador '+' nao se aplica aos tipos string e int` |
| Função não declarada | `funcao 'calcularTotal' nao declarada` |
| Quantidade de argumentos | `funcao 'somarValores' espera 2 argumento(s), mas recebeu 1` |
| Tipo de cada argumento | `argumento 1 de 'dobrarValor' e string, mas o parametro e int` |
| Tipo do `return` | `'pegarNome' deve retornar int, mas a expressao e string` |
| Condição de `if`/`while` | `condicao do if deve ser bool, mas e int` |

Regras de tipos:

- `+ - * /` e menos unário: só `int`/`float`; o resultado é `float` se algum operando for `float`.
- `< > <= >=`: só números; resultado `bool`.
- `== !=`: dois números, ou dois valores do mesmo tipo (`bool`/`string`); resultado `bool`.
- Única conversão implícita: **`int` → `float`** (em atribuição, argumento, `return` e operação mista). No código ela aparece como `t = (float) x`.
- `float` → `int` e qualquer mistura com `bool`/`string` são erro.
- Condições de `if`/`while` precisam ser `bool`.
- `principal()` sem tipo não pode retornar valor; `int principal()` pode.

Depois que uma expressão dá erro ela recebe o tipo interno `<erro>`, e o compilador não reclama de novo dela (evita erros em cascata).

## Código intermediário

### Convenção das quádruplas (`op`, `arg1`, `arg2`, `result`)

Campos não usados ficam vazios (mostrados como `-`).

| op | arg1 | arg2 | result | Texto gerado |
|---|---|---|---|---|
| `+ - * /` | a | b | t | `t = a + b` |
| `< > <= >= == !=` | a | b | t | `t = a < b` |
| `minus` | a | – | t | `t = - a` |
| `itof` | a | – | t | `t = (float) a` |
| `=` | a | – | x | `x = a` |
| `func` | – | – | f | `f:` (início da função) |
| `label` | – | – | L | `L:` |
| `goto` | – | – | L | `goto L` |
| `ifFalse` | c | – | L | `ifFalse c goto L` |
| `ifFalse<`, `ifFalse>`, … | a | b | L | `ifFalse a < b goto L` |
| `param` | a | – | – | `param a` |
| `call` | f | n | t | `t = call f, n` (`t` fica sem uso quando a chamada é um comando) |
| `return` | a | – | – | `return a` |

`op` é `char *` (e não `char`, como na sugestão do enunciado) porque operadores como `<=`, `ifFalse` e `param` têm mais de um caractere.

Temporários (`t1`, `t2`, …) e rótulos (`L1`, `L2`, …) vêm de contadores globais. Como os desvios usam rótulos simbólicos, não é preciso fazer *backpatching*.

### Esquemas de tradução

```
x = E                 código de E ; x = E.end

if (C) B              ifFalse C goto L1 ; B ; L1:

if (C) B1 else B2     ifFalse C goto L1 ; B1 ; goto L2 ; L1: ; B2 ; L2:

while (C) B           L1: ; ifFalse C goto L2 ; B ; goto L1 ; L2:

f(E1, ..., En)        código de E1..En ; param E1.end ... param En.end ; t = call f, n

return E              código de E ; return E.end
```

Uma comparação (`a < b`) não gera temporário de imediato. Se for condição de `if`/`while`, vira direto `ifFalse a < b goto L` (como no exemplo do enunciado); se for usada como valor (`passou = MEDIA >= 6;`), vira `t = a >= b`.

Os parâmetros só são empilhados depois que todos os argumentos foram avaliados, para que chamadas aninhadas (`f(g(1), g(2))`) não misturem seus `param`.

As instruções ficam numa única lista, na ordem em que são geradas. Inicializações de variáveis globais (`int CONTADOR = 0;`) aparecem onde a global foi declarada; como os testes declaram as globais no início, elas aparecem antes das funções.

### Exemplo do enunciado

Para `testes/validos/exemplo_enunciado.txt` o compilador gera exatamente o código mostrado no PDF:

```
calcularSoma:
    t1 = a + b
    resultado = t1
    return resultado

principal:
    x = 10
    y = 20
    param x
    param y
    t2 = call calcularSoma, 2
    SOMA = t2
    ifFalse SOMA > 20 goto L1
    t3 = x + 1
    x = t3
L1:
L2:
    ifFalse x < SOMA goto L3
    t4 = x + 1
    x = t4
    goto L2
L3:
```

E as quádruplas correspondentes (trecho):

```
N    op         arg1             arg2       result
0    func       -                -          calcularSoma
1    +          a                b          t1
2    =          t1               -          resultado
3    return     resultado        -          -
...
11   ifFalse>   SOMA             20         L1
```

## Testes

| Pasta | Conteúdo |
|---|---|
| `validos/` | exemplo do enunciado, programa completo do TP I, recursão (fatorial), escopos de bloco, conversões de tipo, chamada usada como comando |
| `erros_lexicos/` | do TP I |
| `erros_sintaticos/` | do TP I |
| `erros_semanticos/` | variável não declarada, global usada antes, escopo de bloco, duplicadas, variável escondida, tipos em atribuição, tipos em expressões, quantidade e tipos de argumentos, função não declarada, `return` e condições |

A saída de cada teste está em `saidas/`.
