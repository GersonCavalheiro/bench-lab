#!/usr/bin/env bash
# Executa todos os experimentos em sequencia unica, sem Makefile.
# Inclui as funcionalidades de coleta da maquina (relatorios 01..06) e do
# Makefile (compilacao, execucao, vetorizacao, assembly, disassembly,
# perf e cachegrind -> 07 e 10..31).
# Tudo e escrito em ./${HOST}-${ARCH}/ (binarios em ${HOST}-${ARCH}/bin/).
#
# Uso: ./executa_experimentos.sh              # N=384, TLP=6
#      N=1024 TLP=12 ./executa_experimentos.sh
#      MCA=llvm-mca-19 ./executa_experimentos.sh   # forca versao do mca
#      ./executa_experimentos.sh limpar       # remove ${HOST}-${ARCH}/
set -euo pipefail
cd "$(dirname "$0")"

N=${N:-384}
TLP=${TLP:-6}
CC=${CC:-gcc}
HOST=${HOST:-$(hostname)}
ARCH=$(uname -m)
DIR="${HOST}-${ARCH}"
BIN="$DIR/bin"
# CFLAGS="-O3 -march=native -std=c11 -Wall -Wextra -Wpedantic -fno-loop-interchange -fno-tree-loop-distribute-patterns"
CFLAGS="-O2 -g -mavx2 -mfma -std=c11 -Wall -Wextra -Wpedantic -fno-loop-interchange -fno-tree-loop-distribute-patterns"

# O sufixo do llvm-mca varia entre maquinas (llvm-mca-18, llvm-mca-19, ...).
# Detecta a primeira versao disponivel; MCA no ambiente força uma especifica.
MCA=${MCA:-}
if [ -z "$MCA" ]; then
    for cand in llvm-mca-18 llvm-mca-19 llvm-mca-20 llvm-mca-17 llvm-mca-16 \
                llvm-mca-15 llvm-mca-14 llvm-mca; do
        if command -v "$cand" >/dev/null 2>&1; then
            MCA=$cand
            break
        fi
    done
fi

if [ "${1:-}" = "limpar" ]; then
    echo "Removendo resultados e binarios de '${DIR}/'"
    rm -rf "$DIR"
    exit 0
fi
if ! mkdir -p "$BIN" 2>/dev/null; then
    echo "ERRO: sem permissao para criar '${DIR}/' em $(pwd)." >&2
    echo "      Causas provaveis:" >&2
    echo "        1) docker run com --user e SEM -v: monte um diretorio gravavel" >&2
    echo "           com -v \"\$PWD/saida:/opt/bench-lab/${DIR}\" (mkdir -p saida" >&2
    echo "           antes, para o diretorio ficar seu); ou" >&2
    echo "        2) o diretorio do volume no host pertence ao root:" >&2
    echo "           sudo rm -rf saida  (depois refaca o mkdir -p saida)." >&2
    exit 1
fi

SEP='------------------------------------------------------------'
passo() {
    printf '\n%s\n' "$SEP"
    printf '%s\n' "$1"
    printf '%s\n\n' "$SEP"
}

passo "EXPERIMENTO 1 - Recursos de concorrencia disponiveis na maquina
  O que se analisa:
    * 01: modelo de CPU, nucleos, threads, caches e flags -> teto de TLP/DLP;
    * 02: topologia SMT (quais CPUs sao irmaas) -> como distribuir threads;
    * 03: conjuntos SIMD (SSE/AVX/FMA) -> vetorizacao disponivel;
    * 04: GPUs presentes; 05: plataformas OpenCL -> offload possivel ou nao.
  Arquivos: ${DIR}/01-cpu.txt, 02-topologia.txt, 03-simd.txt, 04-gpu.txt, 05-opencl.txt"

lscpu > "${DIR}/01-cpu.txt"
lscpu -e=CPU,SOCKET,CORE,NODE > "${DIR}/02-topologia.txt"
grep -m1 '^flags' /proc/cpuinfo 2>/dev/null |
    cut -d: -f2 |
    tr ' ' '\n' |
    grep -E '^(mmx|sse.*|ssse3|avx.*|fma.*)$' \
    > "${DIR}/03-simd.txt" || true
if command -v lspci >/dev/null 2>&1; then
    lspci -nn | grep -Ei 'VGA|3D|Display' > "${DIR}/04-gpu.txt" || true
else
    echo 'lspci indisponivel.' > "${DIR}/04-gpu.txt"
fi
if command -v clinfo >/dev/null 2>&1; then
    clinfo > "${DIR}/05-opencl.txt" 2>&1 || true
else
    echo 'clinfo indisponivel.' > "${DIR}/05-opencl.txt"
fi

passo "EXPERIMENTO 2 - Paralelismo em nivel de instrucao (ILP)
  O que se analisa (${MCA:-llvm-mca ausente} sobre ilp.s, 100 iteracoes):
    * bloco 'independentes': IPC, largura de despacho e as 4 ALUs em
      paralelo -> superscalaridade e teto de ILP;
    * bloco 'dependentes': cadeia RAW em %eax -> limite por latencia;
    * latencia vs RThroughput -> comportamento de pipeline.
  Arquivo: ${DIR}/06-ilp.txt"

if [ -n "$MCA" ] && command -v "$MCA" >/dev/null 2>&1; then
    "$MCA" -mcpu=native -iterations=100 ilp.s > "${DIR}/06-ilp.txt"
else
    echo 'llvm-mca indisponivel (instale llvm ou defina MCA=llvm-mca-XX).' \
        > "${DIR}/06-ilp.txt"
fi

passo "EXPERIMENTO 3 - Geracao de codigo das multiplicacoes (N=${N}, TLP=${TLP})
  O que se analisa: cinco variantes geradas com -O3 -march=native:
    * eficiente        -> ordem ikj, sequencial;
    * ineficiente      -> ordem ijk (acesso em coluna), sequencial;
    * openmp           -> ikj com #pragma omp parallel for;
    * eficiente-tlp    -> ikj com -ftree-parallelize-loops=${TLP} (paralelizacao automatica);
    * ineficiente-tlp  -> ijk com -ftree-parallelize-loops=${TLP}.
  Binarios: ${BIN}/"

$CC $CFLAGS eficiente.c   -o "$BIN/eficiente"
echo "  gerado ${BIN}/eficiente"
$CC $CFLAGS ineficiente.c -o "$BIN/ineficiente"
echo "  gerado ${BIN}/ineficiente"
$CC $CFLAGS -fopenmp openmp.c -o "$BIN/openmp"
echo "  gerado ${BIN}/openmp"
$CC $CFLAGS -ftree-parallelize-loops="$TLP" -fopenmp eficiente.c   -o "$BIN/eficiente-tlp"
echo "  gerado ${BIN}/eficiente-tlp"
$CC $CFLAGS -ftree-parallelize-loops="$TLP" -fopenmp ineficiente.c -o "$BIN/ineficiente-tlp"
echo "  gerado ${BIN}/ineficiente-tlp"

passo "EXPERIMENTO 4 - Execucao das multiplicacoes (N=${N})
  O que se analisa: tempo de execucao de cada variante e efeito do TLP
  (openmp com 1 thread e com todas as threads + OMP_PROC_BIND=spread;
  versoes -tlp) e da ordem dos lacos (eficiente vs ineficiente).
  Checksums devem ser identicos em todas as versoes.
  Arquivo: ${DIR}/07-Tempos.txt"

{
  echo "N=${N} TLP=${TLP}"
  echo "# sequencial (ikj) / sequencial (ijk) / openmp padrao /"
  echo "# openmp OMP_NUM_THREADS=1 / openmp spread+cores / tlp eficiente / tlp ineficiente"
  "$BIN/eficiente" "$N"
  "$BIN/ineficiente" "$N"
  "$BIN/openmp" "$N"
  OMP_NUM_THREADS=1 "$BIN/openmp" "$N"
  OMP_PROC_BIND=spread OMP_PLACES=cores "$BIN/openmp" "$N"
  "$BIN/eficiente-tlp" "$N"
  "$BIN/ineficiente-tlp" "$N"
} > "$DIR/07-Tempos.txt"
cat "$DIR/07-Tempos.txt"

passo "EXPERIMENTO 5 - Relatorios de geracao de codigo (antes 'vet'/'asm'/inspecao)
  O que se analisa em cada arquivo:
    10-ArquiteturaCPU: compilador e CPU usados nos testes.
    11/12/21-Vetorizacao*: se o GCC vetorizou o laco interno e com quais
        instrucoes (DLP/AVX2) - comparar ikj (eficiente) vs ijk (ineficiente).
    26/27-ParalelizacaoAutomatica*: qual laço o GCC escolheu para TLP
        (laço externo = bom; interno = sobrecarga de regioes).
    13/14/22-Assembly*: codigo assembly de cada versao.
    15/16/23/28/29-Disassembly*: binarios desmontados (chamadas GOMP,
        instrucoes AVX, laços paralelos).
    17/18/24/30/31-Perf*: ciclos, instrucoes, IPC e falhas de cache medidos
        em execucao real (5 repeticoes).
    19/20/25-Cachegrind*: falhas de cache L1/LL por versao (valgrind).
  Arquivos: ${DIR}/10-*.txt ... ${DIR}/31-*.txt"

{
  echo "HOST=${HOST}"
  echo "ARCH=${ARCH}"
  echo "Compilador:"
  $CC --version | head -n 1
  echo
  lscpu
} > "$DIR/10-ArquiteturaCPU.txt" 2>&1

$CC $CFLAGS -fopt-info-vec-all="$DIR/11-VetorizacaoEficiente.txt" -c eficiente.c -o /dev/null
$CC $CFLAGS -fopt-info-vec-all="$DIR/12-VetorizacaoIneficiente.txt" -c ineficiente.c -o /dev/null
$CC $CFLAGS -fopenmp -fopt-info-vec-all="$DIR/21-VetorizacaoOpenmp.txt" -c openmp.c -o /dev/null
$CC $CFLAGS -ftree-parallelize-loops="$TLP" -fopenmp -fopt-info-loop="$DIR/26-ParalelizacaoAutomatica-eficiente.txt" -c eficiente.c -o /dev/null
$CC $CFLAGS -ftree-parallelize-loops="$TLP" -fopenmp -fopt-info-loop="$DIR/27-ParalelizacaoAutomatica-ineficiente.txt" -c ineficiente.c -o /dev/null

$CC $CFLAGS -S eficiente.c -o "$DIR/13-AssemblyEficiente.txt"
$CC $CFLAGS -S ineficiente.c -o "$DIR/14-AssemblyIneficiente.txt"
$CC $CFLAGS -fopenmp -S openmp.c -o "$DIR/22-AssemblyOpenmp.txt"

objdump -d -M intel "$BIN/eficiente"      > "$DIR/15-DisassemblyEficiente.txt"
objdump -d -M intel "$BIN/ineficiente"    > "$DIR/16-DisassemblyIneficiente.txt"
objdump -d -M intel "$BIN/openmp"         > "$DIR/23-DisassemblyOpenmp.txt"
objdump -d -M intel "$BIN/eficiente-tlp"  > "$DIR/28-DisassemblyEficienteTlp.txt"
objdump -d -M intel "$BIN/ineficiente-tlp" > "$DIR/29-DisassemblyIneficienteTlp.txt"

PERFSPECS="eficiente:17-PerfEficiente ineficiente:18-PerfIneficiente openmp:24-PerfOpenmp eficiente-tlp:30-PerfEficienteTlp ineficiente-tlp:31-PerfIneficienteTlp"
CGSPECS="eficiente:19 ineficiente:20 openmp:25"

if command -v perf >/dev/null 2>&1; then
  for spec in $PERFSPECS; do
    bin=${spec%%:*}
    nome=${spec##*:}
    perf stat -r 5 -e cycles,instructions,cache-references,cache-misses \
      "$BIN/$bin" "$N" > "$DIR/$nome.txt" 2>&1 \
      || echo 'AVISO: perf indisponivel ou sem permissao para esses eventos.' >> "$DIR/$nome.txt"
  done
else
  for spec in $PERFSPECS; do
    nome=${spec##*:}
    echo 'perf nao instalado.' > "$DIR/$nome.txt"
  done
fi

if command -v valgrind >/dev/null 2>&1 && command -v cg_annotate >/dev/null 2>&1; then
  for spec in $CGSPECS; do
    bin=${spec%%:*}
    numero=${spec##*:}
    log="$DIR/$numero-Cachegrind-$bin.txt"
    tmp=$(mktemp)
    if valgrind --tool=cachegrind --cachegrind-out-file="$tmp" \
        "$BIN/$bin" "$N" > "$log" 2>&1; then
      cg_annotate "$tmp" >> "$log" 2>&1 \
        || echo 'AVISO: cg_annotate falhou.' >> "$log"
    else
      echo 'AVISO: Cachegrind falhou.' >> "$log"
    fi
    rm -f "$tmp"
  done
else
  for spec in $CGSPECS; do
    bin=${spec%%:*}
    numero=${spec##*:}
    echo 'Valgrind/Cachegrind nao instalado.' > "$DIR/$numero-Cachegrind-$bin.txt"
  done
fi

passo "CONCLUIDO - todos os resultados estao em ${DIR}/
  Experimento 1: 01..05   Experimento 2: 06
  Experimento 3: ${DIR}/bin/   Experimento 4: 07
  Experimento 5: 10..31"
