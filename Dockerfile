# Imagem para executar o conjunto completo de experimentos do bench-lab.
#
# Construcao (a partir da raiz do repositorio):
#   docker build -t bench-lab .
#
# O build clona o repositorio oficial e executa os arquivos dele; se o
# clone falhar (repo ainda nao publicado, ou sem rede), usa os arquivos
# locais do contexto de build como fallback.
#
# Execucao (sem sessao interativa: informe um diretorio com -v para o
# registro das saidas — sem o volume montado, os relatorios gerados em
# /opt/bench-lab/${HOST}-${ARCH}/ sao perdidos quando o --rm remove o
# contêiner):
#   mkdir -p saida && docker run --rm --user $(id -u):$(id -g) \
#       -v "$PWD/saida:/opt/bench-lab/container-x86_64" bench-lab
#   docker run --rm -e N=1024 -e TLP=12 -e HOST=meupc \
#       -v "$PWD/saida:/opt/bench-lab/container-x86_64" bench-lab
#   docker run --rm -e MCA=llvm-mca-19 \
#       -v "$PWD/saida:/opt/bench-lab/container-x86_64" bench-lab  # forca mca
#
# Teste rapido, SEM volume (as saidas sao perdidas ao final):
#   docker run --rm bench-lab
#
# Alternativa para recuperar as saidas sem ter usado volume:
#   docker create --name res bench-lab
#   docker cp res:/opt/bench-lab/container-x86_64 ./saida
#   docker rm res
#
# O sufixo do llvm-mca (18, 19, ...) varia entre maquinas: a imagem instala
# o llvm padrao do Ubuntu 24.04 (llvm-18) e o script executa_experimentos.sh
# auto-detecca qualquer llvm-mca-* disponivel (MCA=... força um especifico).
#
# perf: os contadores de hardware exigem --cap-add PERFMON (ou --privileged)
# e o linux-tools da versao do kernel do host; sem isso o script grava
# "AVISO: perf indisponivel" nos relatorios 17/18/24/30/31 e continua.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    HOST=container

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        build-essential \
        binutils \
        util-linux \
        grep \
        pciutils \
        clinfo \
        llvm-18 \
        valgrind \
        python3 \
        git \
        linux-tools-common \
        linux-tools-generic \
    && rm -rf /var/lib/apt/lists/*

# Garante um llvm-mca qualquer mesmo se a imagem for reconstruida com
# outra versao do LLVM (o script auto-detecca; o alias evita surpresa).
RUN set -eux; \
    if ! command -v llvm-mca-18 >/dev/null 2>&1; then \
        mca="$(ls /usr/bin/llvm-mca-* 2>/dev/null | sort | tail -n 1)"; \
        test -n "$mca"; \
        ln -s "$mca" /usr/bin/llvm-mca-18; \
    fi

# Repositorio oficial do projeto; fallback para os arquivos locais.
COPY . /tmp/local-experimentos
RUN set -eux; \
    if git clone --depth 1 https://github.com/GersonCavalheiro/bench-lab.git \
        /opt/bench-lab; then \
        echo 'Usando o repositorio clonado do GitHub.'; \
    else \
        echo 'AVISO: clone falhou; usando os arquivos locais do contexto de build.'; \
        mkdir -p /opt/bench-lab; \
        cp -a /tmp/local-experimentos/. /opt/bench-lab/; \
    fi; \
    rm -rf /tmp/local-experimentos

WORKDIR /opt/bench-lab
# a+rwX: permite que runs com --user criem ${HOST}-${ARCH}/ quando NENHUM
# volume esta montado (sem volume as saidas sao perdidas; e apenas p/ teste).
RUN chmod +x executa_experimentos.sh && chmod a+rwX /opt/bench-lab

CMD ["./executa_experimentos.sh"]
