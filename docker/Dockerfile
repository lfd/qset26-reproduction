FROM debian:forky-slim

ARG USER="qc_analysis"
ARG HOME="/home/${USER}"
ARG D_PROJECT="${HOME}/qc_analysis"
ARG D_VENV="${HOME}/venv"
ARG UID
ARG GID

ARG REQS_R="analysis/requirements.R"
ARG REQS_PY="analysis/requirements.txt"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get dist-upgrade -y && \
    apt-get install -y --no-install-recommends \
        biber \
        cloc \
        git \
        latexmk \
        locales \
        python3 \
        python3-venv \
        python3-pip \
        r-base \
        r-base-dev \
	texlive \
	texlive-bibtex-extra \
	texlive-fonts-extra \
	texlive-latex-extra \
	texlive-luatex \
	texlive-plain-generic \
        sudo \
        vim && \
    sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Install R packages in system-wide context
COPY ${REQS_R} /tmp/requirements.R
RUN mkdir -p /root/.R && \
    echo "MAKEFLAGS = -j$(($(nproc)/4))" > /root/.R/Makevars && \
    Rscript -e "\
      pkgs <- readLines('/tmp/requirements.R'); \
      pkgs <- trimws(pkgs); \
      pkgs <- pkgs[nzchar(pkgs)]; \
      install.packages( \
        pkgs, \
        repos='https://cloud.r-project.org', \
        Ncpus=parallel::detectCores(), \
        clean=TRUE \
      )" && \
    rm /tmp/requirements.R

RUN groupadd --gid ${GID} --force $USER && \
    useradd -m -u ${UID} -g ${GID} -G adm ${USER} && \
    echo "${USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

USER ${USER}
WORKDIR ${HOME}

## Create virtual environment and install build backend.
RUN python3 -m venv ${D_VENV}
ENV VIRTUAL_ENV=${D_VENV}
ENV PATH="${D_VENV}/bin:$PATH"

# Install dependencies only
COPY --chown=${UID}:${GID} ${REQS_PY} ${D_PROJECT}/
RUN pip install --upgrade pip hatchling && \
    pip install -r ${D_PROJECT}/requirements.txt

# Remove the temporary dependency file again
RUN rm -rf ${D_PROJECT}
