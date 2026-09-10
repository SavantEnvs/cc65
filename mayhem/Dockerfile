# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile for cc65, built ON TOP of the org C/C++ base.
# The base provides clang/llvm + libFuzzer + the build-contract ENV
# (CC/CXX/SANITIZER_FLAGS/SRC). cc65's command-line tools (ca65, cc65, da65,
# ld65, od65, co65, sp65, ar65, grc65, chrcvt65) are plain C built by a simple
# GNU Makefile with no external deps, so mayhem/build.sh installs nothing and
# the air-gapped re-run needs no network.

FROM ghcr.io/savantenvs/base:20260621

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG MAYHEM_JOBS=

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
