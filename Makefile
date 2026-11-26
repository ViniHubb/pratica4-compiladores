CC     = gcc
CFLAGS = -Wall -Wno-unused-function
FONTES = sintatico.tab.c lex.yy.c tabela.c codigo.c

compilador: lexico.l sintatico.y tabela.c tabela.h codigo.c codigo.h tipos.h
	bison -d sintatico.y
	flex lexico.l
	$(CC) $(CFLAGS) $(FONTES) -o compilador

testes: compilador
	@for f in testes/*/*.txt; do echo "===== $$f"; ./compilador $$f; echo; done

clean:
	rm -f compilador sintatico.tab.c sintatico.tab.h lex.yy.c
