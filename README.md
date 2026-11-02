# bench-lab — Estudo de Paralelismo e Desempenho

Projeto didático que investiga **que tipos de concorrência uma máquina oferece e
como explorá-los**, usando duas frentes complementares:

1. **Análise estática da arquitetura** — identificação dos recursos de paralelismo
   (TLP, DLP/SIMD, ILP, GPU/OpenCL) e medição do paralelismo em nível de
   instrução com `llvm-mca`.
2. **Experimentos práticos de desempenho** — três implementações da mesma
   multiplicação de matrizes (que diferem na ordem dos laços e no uso de
   OpenMP/paralelização automática), executadas e instrumentadas para mostrar
   na prática como cada tipo de concorrência se reflete no tempo de execução.

O objetivo é relacionar os **dados coletados da máquina** (CPU, topologia SMT,
SIMD, GPU, ILP) com o **desempenho observado** dos programas.

## Estrutura do repositório

```
.
├── executa_experimentos.sh      # driver: roda TODOS os experimentos em sequência
├── Dockerfile                   # imagem com todas as dependências (+ clone do repo)
├── .dockerignore
├── Makefile                     # alvos alternativos: run, tlp, vet, asm, inspecao, clean
├── ilp.s                        # código de teste para o llvm-mca (blocos de addl)
├── eficiente.c                  # multiplicação ikj  (acesso sequencial)
├── ineficiente.c                # multiplicação ijk  (acesso em coluna, stride n)
├── openmp.c                     # ikj + #pragma omp parallel for
└── README.md

# gerado na execução (não versionado):
└── ${HOST}-${ARCH}/             # resultados 01..31 + bin/  (ex.: Abitite-x86_64/)
```

## Experimentos e arquivos gerados

O script `executa_experimentos.sh` executa tudo em sequência e
imprime, a cada etapa, o que se espera analisar e em qual arquivo o resultado
é gravado (tudo em `./${HOST}-${ARCH}/`):

| Nº | Experimento | O que se analisa |
|----|-------------|------------------|
| `01-cpu.txt` | Recursos da CPU | modelo, núcleos, threads, caches, flags → **teto de TLP/DLP** |
| `02-topologia.txt` | Topologia | quais CPUs são irmãs SMT → como distribuir threads |
| `03-simd.txt` | SIMD | SSE/AVX/FMA disponíveis → **vetorização (DLP)** |
| `04-gpu.txt` / `05-opencl.txt` | GPU / OpenCL | hardware gráfico e runtime → **offload possível?** |
| `06-ilp.txt` | ILP (`llvm-mca`) | blocos `independentes` vs `dependentes`: IPC, largura de despacho, latência vs throughput → **superscalaridade e pipeline** |
| `07-Tempos.txt` | Execuções | tempo das 5 variantes + OpenMP (1 thread / spread) → **efeito real do TLP e da ordem dos laços** |
| `10..12, 21` | Vetorização | se o GCC vetorizou e com quais instruções (relatório `vet`) |
| `13, 14, 22` | Assembly | código-fonte assembly gerado (relatório `asm`) |
| `15, 16, 23, 28, 29` | Disassembly | binários desmontados (chamadas `GOMP`, instruções AVX) |
| `17, 18, 24, 30, 31` | `perf` | ciclos, instruções, IPC e falhas de cache em execução real (5 repetições) |
| `19, 20, 25` | Cachegrind | falhas de cache L1/LL por versão (valgrind) |
| `26, 27` | Paralelização automática | qual laço o GCC escolheu com `-ftree-parallelize-loops` |

### As três implementações da multiplicação (`N×N`, `int32_t`)

| Programa | Laço interno | Paralelismo |
|----------|--------------|-------------|
| `ineficiente.c` | ordem **ijk** — varre colunas de `B` (stride `n`) | sequencial; cadeia RAW em `soma` |
| `eficiente.c` | ordem **ikj** — varre linhas, `a` escalar pré-carregado | sequencial; `j` independente → ILP + vetorial |
| `openmp.c` | ordem **ikj** + `#pragma omp parallel for` no laço externo `i` | **TLP** (linhas disjuntas de `C`) |

Além disso, `eficiente.c` e `ineficiente.c` são compilados com
`-ftree-parallelize-loops=$(TLP)` (**paralelização automática**) gerando as
variantes `eficiente-tlp` e `ineficiente-tlp`.

## Como executar

### Nativamente

Dependências: `gcc` (com OpenMP), `llvm-mca` (qualquer versão), `binutils`,
`util-linux`, `pciutils`, `clinfo`. Opcionais: `perf` e `valgrind` (sem eles os
relatórios recebem um aviso e a execução continua).

```bash
./executa_experimentos.sh                # N=384, TLP=6
N=1024 TLP=12 ./executa_experimentos.sh  # outros parâmetros
MCA=llvm-mca-19 ./executa_experimentos.sh  # força versão do llvm-mca
./executa_experimentos.sh limpar         # remove ${HOST}-${ARCH}/
```

O `llvm-mca` é **auto-detectado** (`llvm-mca-18`, `llvm-mca-19`, …,
`llvm-mca`), pois o sufixo varia entre máquinas; `MCA=...` força um
específico.

### Com Docker

O `Dockerfile` **clona este repositório**
(`github.com/GersonCavalheiro/bench-lab`) durante o build e executa os
arquivos clonados; se o clone falhar (repositório ainda não publicado, ou
sem rede), usa os arquivos locais do contexto de build.

> **Atenção:** ao lançar o contêiner **sem abrir uma sessão interativa**
> (`docker run --rm ...`), **informe um diretório para o registro das saídas**
> com a flag `-v`. Sem o volume montado, os relatórios gravados em
> `/opt/bench-lab/${HOST}-${ARCH}/` ficam presos no contêiner e são perdidos
> quando ele termina e é removido pelo `--rm`.

```bash
docker build -t bench-lab .

# execução normal: diretório de saída no host (use --user para os arquivos
# ficarem seus) — os relatórios 01..31 aparecem em ./saida/:
mkdir -p saida && docker run --rm --user $(id -u):$(id -g) \
    -v "$PWD/saida:/opt/bench-lab/container-x86_64" bench-lab

# outros parâmetros (N, TLP, MCA, ...), sempre com o diretório de saída:
mkdir -p saida && docker run --rm --user $(id -u):$(id -g) \
    -e N=1024 -e TLP=12 \
    -v "$PWD/saida:/opt/bench-lab/container-x86_64" bench-lab

# apenas para teste rápido, SEM volume (as saídas são perdidas ao final):
docker run --rm bench-lab
```

#### Lançamento direto a partir de `gersoncavalheiro/bench-lab`

Não é preciso clonar o repositório para usar o projeto — é possível lançar o
contêiner **diretamente a partir de `gersoncavalheiro/bench-lab`**:

```bash
# build direto do GitHub (o Docker clona e usa o Dockerfile da raiz):
docker build -t bench-lab github.com/GersonCavalheiro/bench-lab

# ou, com a imagem publicada no Docker Hub — sempre informando o
# diretório de saída com -v para não perder os relatórios:
mkdir -p saida && docker run --rm --user $(id -u):$(id -g) \
    -v "$PWD/saida:/opt/bench-lab/container-x86_64" gersoncavalheiro/bench-lab
```

Os resultados são gerados dentro do contêiner em
`/opt/bench-lab/${HOST}-${ARCH}/` (`HOST=container` por padrão) e, com o
volume acima, são registrados no diretório `saida/` do host.

### Pelo Makefile (alternativa)

```bash
make run          # compila e executa as versões sequenciais + openmp
make tlp          # compila/executa as variantes de paralelização automática
make inspecao     # gera os relatórios 10..31 (usa perf/cachegrind se disponíveis)
make clean
```

## Principais resultados (Ryzen 5 5500U — 6 núcleos / 12 threads)

* **ILP** (`06-ilp.txt`): bloco independente com IPC ≈ **3,94** (≈ `Dispatch Width` 4,
  saturando as 4 ALUs); bloco dependente com IPC = **1,0** → o custo das
  dependências RAW é de ≈ **4×**, o teto de ILP da máquina.
* **Ordem dos laços** (`07-Tempos.txt`): `ikj` é ~**14×** mais rápido que `ijk`
  em N=384 e ~**55×** em N=1024 — o ganho vai além do teto de ILP porque o
  acesso sequencial habilita **vetorização AVX2** e evita falhas de cache.
* **TLP** (OpenMP): `parallel for` no laço externo rende **5–6×** com 12 threads;
  com `OMP_NUM_THREADS=1` o tempo volta ao normal → a diferença é só de TLP.
* **Paralelização automática**: ajuda no `ineficiente` (laço externo escolhido)
  mas **atrapalha** o `eficiente` (GCC escolhe o laço interno → milhares de
  regioes OpenMP) — ver `26/27-ParalelizacaoAutomatica*.txt`.
* **`collapse`**: aplicar `collapse(2)` sobre `(i,k)` é **incorreto** aqui (as
  itações colapsadas escrevem na mesma linha de `C` → corrida de dados);
  o correto é paralelizar apenas o laço externo `i`, como em `openmp.c`.

Todos os programas imprimem um `checksum` idêntico para o mesmo `N`, o que
valida que as versões computam o mesmo resultado.
