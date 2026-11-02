CC ?= gcc
N ?= 384
TLP ?= 6
CFLAGS ?= -O3 -march=native -std=c11 -Wall -Wextra -Wpedantic -fno-loop-interchange -fno-tree-loop-distribute-patterns
LDLIBS ?=
HOST ?= $(shell hostname -s)
ARCH ?= $(shell uname -m)
RESULTDIR := $(HOST)-$(ARCH)

.PHONY: all run tlp clean vet asm inspecao
all: eficiente ineficiente openmp

eficiente: eficiente.c
	$(CC) $(CFLAGS) $< -o $@ $(LDLIBS)

ineficiente: ineficiente.c
	$(CC) $(CFLAGS) $< -o $@ $(LDLIBS)

openmp: openmp.c
	$(CC) $(CFLAGS) -fopenmp $< -o $@ $(LDLIBS)

eficiente-tlp: eficiente.c
	$(CC) $(CFLAGS) -ftree-parallelize-loops=$(TLP) -fopenmp $< -o $@ $(LDLIBS)

ineficiente-tlp: ineficiente.c
	$(CC) $(CFLAGS) -ftree-parallelize-loops=$(TLP) -fopenmp $< -o $@ $(LDLIBS)

tlp: eficiente-tlp ineficiente-tlp
	./eficiente-tlp $(N)
	./ineficiente-tlp $(N)

run: all
	./eficiente $(N)
	./ineficiente $(N)
	./openmp $(N)

vet:
	$(CC) $(CFLAGS) -fopt-info-vec-all=eficiente.vec.txt -c eficiente.c -o /dev/null
	$(CC) $(CFLAGS) -fopt-info-vec-all=ineficiente.vec.txt -c ineficiente.c -o /dev/null

asm:
	$(CC) $(CFLAGS) -S eficiente.c -o eficiente.s
	$(CC) $(CFLAGS) -S ineficiente.c -o ineficiente.s

$(RESULTDIR):
	mkdir -p "$@"

# Relatorios numerados: 10..31.
# 10-20: versoes seriais; 21-25: OpenMP; 26-31: paralelizacao automatica (TLP).
# Contadores de hardware dependem das permissoes do perf.
# Cachegrind e opcional; utiliza arquivo temporario fora dos resultados.
PERFSPECS := eficiente:17-PerfEficiente ineficiente:18-PerfIneficiente openmp:24-PerfOpenmp eficiente-tlp:30-PerfEficienteTlp ineficiente-tlp:31-PerfIneficienteTlp
CGSPECS := eficiente:19 ineficiente:20 openmp:25

inspecao: all eficiente-tlp ineficiente-tlp | $(RESULTDIR)
	@{ echo 'HOST=$(HOST)'; echo 'ARCH=$(ARCH)'; echo 'Compilador:'; $(CC) --version | head -n 1; echo; lscpu; } > "$(RESULTDIR)/10-ArquiteturaCPU.txt" 2>&1
	@$(CC) $(CFLAGS) -fopt-info-vec-all="$(RESULTDIR)/11-VetorizacaoEficiente.txt" -c eficiente.c -o /dev/null
	@$(CC) $(CFLAGS) -fopt-info-vec-all="$(RESULTDIR)/12-VetorizacaoIneficiente.txt" -c ineficiente.c -o /dev/null
	@$(CC) $(CFLAGS) -fopenmp -fopt-info-vec-all="$(RESULTDIR)/21-VetorizacaoOpenmp.txt" -c openmp.c -o /dev/null
	@$(CC) $(CFLAGS) -ftree-parallelize-loops=$(TLP) -fopenmp -fopt-info-loop="$(RESULTDIR)/26-ParalelizacaoAutomatica-eficiente.txt" -c eficiente.c -o /dev/null
	@$(CC) $(CFLAGS) -ftree-parallelize-loops=$(TLP) -fopenmp -fopt-info-loop="$(RESULTDIR)/27-ParalelizacaoAutomatica-ineficiente.txt" -c ineficiente.c -o /dev/null
	@$(CC) $(CFLAGS) -S eficiente.c -o "$(RESULTDIR)/13-AssemblyEficiente.txt"
	@$(CC) $(CFLAGS) -S ineficiente.c -o "$(RESULTDIR)/14-AssemblyIneficiente.txt"
	@$(CC) $(CFLAGS) -fopenmp -S openmp.c -o "$(RESULTDIR)/22-AssemblyOpenmp.txt"
	@objdump -d -M intel ./eficiente > "$(RESULTDIR)/15-DisassemblyEficiente.txt"
	@objdump -d -M intel ./ineficiente > "$(RESULTDIR)/16-DisassemblyIneficiente.txt"
	@objdump -d -M intel ./openmp > "$(RESULTDIR)/23-DisassemblyOpenmp.txt"
	@objdump -d -M intel ./eficiente-tlp > "$(RESULTDIR)/28-DisassemblyEficienteTlp.txt"
	@objdump -d -M intel ./ineficiente-tlp > "$(RESULTDIR)/29-DisassemblyIneficienteTlp.txt"
	@if command -v perf >/dev/null 2>&1; then \
	  for spec in $(PERFSPECS); do \
	    bin=$${spec%%:*}; nome=$${spec##*:}; \
	    perf stat -r 5 -e cycles,instructions,cache-references,cache-misses ./$$bin $(N) > "$(RESULTDIR)/$$nome.txt" 2>&1 \
	      || echo 'AVISO: perf indisponivel ou sem permissao para esses eventos.' >> "$(RESULTDIR)/$$nome.txt"; \
	  done; \
	else \
	  for spec in $(PERFSPECS); do \
	    nome=$${spec##*:}; echo 'perf nao instalado.' > "$(RESULTDIR)/$$nome.txt"; \
	  done; \
	fi
	@if command -v valgrind >/dev/null 2>&1 && command -v cg_annotate >/dev/null 2>&1; then \
	  for spec in $(CGSPECS); do \
	    bin=$${spec%%:*}; numero=$${spec##*:}; \
	    log="$(RESULTDIR)/$$numero-Cachegrind-$${bin}.txt"; \
	    tmp=$$(mktemp); \
	    if valgrind --tool=cachegrind --cachegrind-out-file="$$tmp" ./$$bin $(N) > "$$log" 2>&1; then \
	      cg_annotate "$$tmp" >> "$$log" 2>&1; \
	    else echo 'AVISO: Cachegrind falhou.' >> "$$log"; fi; \
	    rm -f "$$tmp"; \
	  done; \
	else \
	  for spec in $(CGSPECS); do \
	    bin=$${spec%%:*}; numero=$${spec##*:}; \
	    echo 'Valgrind/Cachegrind nao instalado.' > "$(RESULTDIR)/$$numero-Cachegrind-$${bin}.txt"; \
	  done; \
	fi
	@echo "Relatorios em: $(RESULTDIR)/"

clean:
	rm -f eficiente ineficiente openmp eficiente-tlp ineficiente-tlp *.s *.vec.txt
