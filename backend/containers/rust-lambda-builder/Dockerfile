# Custom base image for building Rust Lambda functions
# Pre-installs Rust 1.88 and cargo-lambda to speed up builds
FROM public.ecr.aws/docker/library/ubuntu:22.04

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    libssl-dev \
    pkg-config \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Rust 1.88 (stable channel)
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.88.0 \
    && chmod -R a+w $RUSTUP_HOME $CARGO_HOME

# Add aarch64 target for ARM Lambda builds
RUN rustup target add aarch64-unknown-linux-gnu

# Install cargo-lambda (latest version compatible with Rust 1.88)
RUN cargo install cargo-lambda

# Verify installations
RUN rustc --version && \
    cargo --version && \
    cargo-lambda --version

# Set working directory
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]
