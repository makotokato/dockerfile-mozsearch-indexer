FROM ubuntu:18.04
MAINTAINER Makoto Kato <m_kato@ga2.so-net.ne.jp>

ENV CLANG_VERSION 8

RUN apt-get update
RUN apt-get install -y software-properties-common

# For latest git
RUN add-apt-repository ppa:git-core/ppa
RUN apt-get update

# unattended upgrades pose a problem for debugging running processes because we
# end up running version N but have debug symbols for N+1 and that doesn't work.
RUN apt-get remove -y unattended-upgrades
# and we want to be able to debug python
RUN apt-get install -y gdb python-dbg

# we want to be able to extract stuff from json
RUN apt-get install -y jq git curl

# dos2unix is used to normalize generated files from windows
RUN apt-get install -y dos2unix

# Livegrep (Bazel is needed for Livegrep builds, OpenJDK 8 required for bazel)
RUN apt-get install -y unzip openjdk-8-jdk libssl-dev

# Install Bazel 0.16.1
# Note that bazel unzips itself so we can't just pipe it to sudo bash.
WORKDIR /work/bazel
RUN curl -sSfL -O https://github.com/bazelbuild/bazel/releases/download/0.22.0/bazel-0.22.0-installer-linux-x86_64.sh && \
    chmod +x bazel-0.22.0-installer-linux-x86_64.sh && \
    ./bazel-0.22.0-installer-linux-x86_64.sh
WORKDIR /work

# Clang
RUN apt-get install -y wget
RUN wget -O - http://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add -
RUN apt-add-repository "deb http://apt.llvm.org/bionic/ llvm-toolchain-bionic-${CLANG_VERSION} main"
RUN apt-get update
RUN apt-get install -y clang-${CLANG_VERSION} libclang-${CLANG_VERSION}-dev

# Other
RUN apt-get install -y parallel python-virtualenv python-pip

# Firefox: https://developer.mozilla.org/en-US/docs/Mozilla/Developer_guide/Build_Instructions/Linux_Prerequisites
RUN wget -O bootstrap.py https://hg.mozilla.org/mozilla-central/raw-file/default/python/mozboot/bin/bootstrap.py
RUN python bootstrap.py --application-choice=browser --no-interactive || true
RUN rm bootstrap.py

# pygit2
RUN apt-get install -y python-dev libffi-dev cmake

# Setup direct links to clang
RUN update-alternatives --install /usr/bin/llvm-config llvm-config /usr/bin/llvm-config-${CLANG_VERSION} 410
RUN update-alternatives --install /usr/bin/clang clang /usr/bin/clang-${CLANG_VERSION} 410
RUN update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-${CLANG_VERSION} 410

# Install Rust. We need rust nightly to use the save-analysis
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH=$PATH:/root/.cargo/bin
RUN rustup install nightly
RUN rustup default nightly
RUN rustup uninstall stable

# Install codesearch.
WORKDIR /work
RUN rm -rf livegrep
RUN git clone -b mozsearch-version4 https://github.com/mozsearch/livegrep
# The last two options turn off the bazel sandbox, which doesn't work
# inside an LDX container.
WORKDIR /work/livegrep
RUN bazel build //src/tools:codesearch && \
    install bazel-bin/src/tools/codesearch /usr/local/bin
WORKDIR /work
# Remove ~2G of build artifacts that we don't need anymore
RUN rm -rf .cache/bazel

# Install AWS scripts.
RUN pip install boto3

# Install pygit2.
ENV LIBGIT2_VERSION 0.28.4
ENV LIBGIT2_TARBALL v${LIBGIT2_VERSION}.tar.gz
ENV PYGIT2_VERSION 0.28.2
RUN rm -rf libgit2-*
RUN wget -nv https://github.com/libgit2/libgit2/archive/v0.28.4.tar.gz
RUN tar xf v0.28.4.tar.gz
RUN rm -rf v0.28.4.tar.gz
WORKDIR /work/libgit2-${LIBGIT2_VERSION}
RUN cmake . && \
    make && \
    make install
WORKDIR /work
RUN ldconfig
RUN pip install pygit2==${PYGIT2_VERSION}

# Install pandoc
RUN apt-get install -y pandoc

# Install nodejs >= 8.11.3, needed for mozilla-central build
RUN curl -sSfL https://deb.nodesource.com/setup_8.x | bash
RUN apt-get install -y nodejs


# Install git-cinnabar

ENV CINNABAR_REVISION cb546ebfa6e2e4fbfa2b96f17f82e3883ae28ea2
RUN rm -rf git-cinnabar
RUN git clone https://github.com/glandium/git-cinnabar
WORKDIR /work/git-cinnabar
RUN git checkout ${CINNABAR_REVISION}
RUN ./git-cinnabar download
WORKDIR /work

# Install SpiderMonkey
RUN wget -nv https://index.taskcluster.net/v1/task/gecko.v2.mozilla-central.nightly.latest.firefox.linux64-opt/artifacts/public/build/target.jsshell.zip
RUN mkdir js
WORKDIR /work/js
RUN unzip ../target.jsshell.zip && \
    install js /usr/local/bin && \
    install *.so /usr/local/lib && \
    ldconfig
WORKDIR /work

RUN apt-get clean

ENV SHELL=/bin/bash
