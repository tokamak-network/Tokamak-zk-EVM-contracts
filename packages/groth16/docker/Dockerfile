# tokamak-groth16 passes BASE_IMAGE at runtime.
ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    bash \
    build-essential \
    ca-certificates \
    curl \
    git \
    python3 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/tokamak-groth16

COPY package.json ./
RUN npm install --omit=dev --ignore-scripts

COPY cli ./cli
COPY lib ./lib
COPY circuits ./circuits
COPY prover ./prover
COPY README.md ./

RUN test -f cli/tokamak-groth16-cli.mjs \
    && test -f circuits/circom-2.0-linux-amd64 \
    && chmod +x cli/tokamak-groth16-cli.mjs \
    && chmod +x circuits/run-circom-2.0.mjs \
    && chmod +x circuits/circom-2.0-linux-amd64

ENTRYPOINT ["node", "/opt/tokamak-groth16/cli/tokamak-groth16-cli.mjs"]
