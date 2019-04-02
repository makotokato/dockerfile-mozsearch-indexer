FROM ubuntu:16.04
MAINTAINER Makoto Kato <m_kato@ga2.so-net.ne.jp>

# For latest git
RUN apt-get update
RUN apt-get install -y software-properties-common
RUN add-apt-repository ppa:git-core/ppa
RUN apt-get update
RUN apt-get install -y git curl

# dos2unix is used to normalize generated files from windows
RUN apt-get install -y dos2unix

# Livegrep (Bazel is needed for Livegrep builds, OpenJDK 8 required for bazel)
RUN apt-get install -y unzip openjdk-8-jdk libssl-dev

# Install Bazel 0.16.1
# Note that bazel unzips itself so we can't just pipe it to sudo bash.
WORKDIR /work/bazel
RUN curl -sSfL -O https://github.com/bazelbuild/bazel/releases/download/0.16.1/bazel-0.16.1-installer-linux-x86_64.sh && \
    chmod +x bazel-0.16.1-installer-linux-x86_64.sh && \
    ./bazel-0.16.1-installer-linux-x86_64.sh
WORKDIR /work

# Clang
RUN apt-get install -y wget
RUN wget -O - http://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add -
RUN apt-add-repository "deb http://apt.llvm.org/xenial/ llvm-toolchain-xenial-6.0 main"
RUN apt-get update
RUN apt-get install -y clang-6.0 clang-6.0-dev

# Firefox: https://developer.mozilla.org/en-US/docs/Mozilla/Developer_guide/Build_Instructions/Linux_Prerequisites
RUN apt-get install -y zip unzip mercurial g++ make autoconf2.13 yasm libgtk2.0-dev libgtk-3-dev libglib2.0-dev libdbus-1-dev libdbus-glib-1-dev libasound2-dev libcurl4-openssl-dev libiw-dev libxt-dev mesa-common-dev libgstreamer0.10-dev libgstreamer-plugins-base0.10-dev libpulse-dev m4 flex libx11-xcb-dev ccache libgconf2-dev

# Other
RUN apt-get install -y parallel realpath python-virtualenv python-pip

# pygit2
RUN apt-get install -y python-dev libffi-dev cmake

# Setup direct links to clang
RUN update-alternatives --install /usr/bin/llvm-config llvm-config /usr/bin/llvm-config-6.0 400
RUN update-alternatives --install /usr/bin/clang clang /usr/bin/clang-6.0 400
RUN update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-6.0 400

# Install codesearch.
WORKDIR /work
RUN rm -rf livegrep
RUN git clone -b mozsearch-version3 https://github.com/mozsearch/livegrep
# The last two options turn off the bazel sandbox, which doesn't work
# inside an LDX container.
WORKDIR /work/livegrep
RUN bazel build //src/tools:codesearch --spawn_strategy=standalone --genrule_strategy=standalone && \
    install bazel-bin/src/tools/codesearch /usr/local/bin
WORKDIR /work

# Remove ~2G of build artifacts that we don't need anymore
RUN rm -rf .cache/bazel

# Install AWS scripts.
RUN pip install boto3

# Install pygit2.
RUN rm -rf libgit2-0.27.1
RUN wget -nv https://github.com/libgit2/libgit2/archive/v0.27.1.tar.gz
RUN tar xf v0.27.1.tar.gz
RUN rm -rf v0.27.1.tar.gz
WORKDIR /work/libgit2-0.27.1
RUN cmake . && \
    make && \
    make install
WORKDIR /work
RUN ldconfig
RUN pip install pygit2

# Install pandoc
RUN apt-get install -y pandoc

# Install nodejs >= 8.11.3, needed for mozilla-central build
RUN curl -sSfL https://deb.nodesource.com/setup_8.x | bash
RUN apt-get install -y nodejs

RUN apt-get clean

# Install SpiderMonkey
RUN wget -nv https://index.taskcluster.net/v1/task/gecko.v2.mozilla-central.nightly.latest.firefox.linux64-opt/artifacts/public/build/target.jsshell.zip
RUN mkdir js
RUN cd js && \
    unzip ../target.jsshell.zip && \
    install js /usr/local/bin && \
    install *.so /usr/local/lib && \
    ldconfig

# Install Rust. We need rust nightly to use the save-analysis
ENV USER mozsearch
ENV HOME /home/${USER}

RUN useradd --uid 1000 -m ${USER}
USER ${USER}
WORKDIR ${HOME}
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH=$PATH:/home/mozsearch/.cargo/bin
RUN rustup install nightly
RUN rustup default nightly
RUN rustup uninstall stable

ENV SHELL=/bin/bash
