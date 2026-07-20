# Containerfile.cnpg-postgresql-source

ARG BASE=docker.io/photon:5.0@sha256:6db86de5ffc11d5c55e59d23790ad526b68e5bca4f030cb6a94e6136280866dd
ARG IMAGE_TITLE="CloudNativePG PostgreSQL on Photon"
ARG IMAGE_DESCRIPTION="PostgreSQL built from upstream source on Photon OS for CloudNativePG."
ARG IMAGE_AUTHORS="Paul Christophel <pmartin@gatech.edu>"
ARG IMAGE_VENDOR="Paul Christophel"
ARG IMAGE_SOURCE="https://github.com/PaulChristophel/docker-postgresql"
ARG IMAGE_REPOSITORY="docker.io/pcm0/postgres"
ARG IMAGE_URL="https://hub.docker.com/r/pcm0/postgres"
ARG IMAGE_DOCUMENTATION="https://github.com/PaulChristophel/docker-postgresql#readme"
ARG IMAGE_REVISION="unknown"
ARG IMAGE_CREATED="1970-01-01T00:00:00Z"
ARG IMAGE_LICENSES="PostgreSQL"

FROM $BASE AS postgres-builder
ARG PG_MAJOR=18
ARG PG_VERSION=18.4
ARG PG_SHA256=81a81ec695fb0c7901407defaa1d2f7973617154cf27ba74e3a7ab8e64436094

USER root
RUN tdnf install -y \
      bison \
      binutils \
      clang \
      clang-devel \
      flex \
      gawk \
      gcc \
      glibc-devel \
      icu-devel \
      krb5-devel \
      libxml2-devel \
      libxslt-devel \
      libxcrypt-devel \
      linux-api-headers \
      llvm-devel \
      lz4-devel \
      make \
      openldap-devel \
      openssl-devel \
      Linux-PAM-devel \
      perl \
      python3-devel \
      readline-devel \
      tar \
      tcl-devel \
      wget \
      xz \
      zlib-devel \
      zstd-devel \
 && wget -O /tmp/postgresql.tar.bz2 https://ftp.postgresql.org/pub/source/v${PG_VERSION}/postgresql-${PG_VERSION}.tar.bz2 \
 && echo "${PG_SHA256}  /tmp/postgresql.tar.bz2" | sha256sum -c - \
 && mkdir -p /tmp/postgresql-src \
 && tar -xjf /tmp/postgresql.tar.bz2 -C /tmp/postgresql-src --strip-components=1 \
 && cd /tmp/postgresql-src \
 && PERL_CORE="$(perl -MConfig -e 'print "$Config{archlibexp}/CORE"')" \
 && mkdir -p /usr/local/include \
 && cp "${PERL_CORE}"/*.h /usr/local/include/ \
 && ./configure \
      --prefix=/usr/pgsql/${PG_MAJOR} \
      --with-gssapi \
      --with-icu \
      --with-ldap \
      --with-libxml \
      --with-libxslt \
      --with-llvm \
      --with-lz4 \
      --with-openssl \
      --with-pam \
      --with-perl \
      --with-python \
      --with-tcl \
      --with-zstd \
 && make -j"$(nproc)" world-bin \
 && make install-world-bin


FROM $BASE AS extension-builder
ARG PG_MAJOR=18
ARG PG_CRON_VERSION=1.6.7
ARG PGVECTOR_VERSION=0.8.5
ARG PGAUDIT_VERSION=18.0

COPY --from=postgres-builder /usr/pgsql/${PG_MAJOR} /usr/pgsql/${PG_MAJOR}

USER root
RUN tdnf install -y \
      binutils \
      clang \
      clang-devel \
      gcc \
      glibc-devel \
      git \
      icu-devel \
      krb5-devel \
      libxml2-devel \
      libxslt-devel \
      linux-api-headers \
      llvm-devel \
      lz4-devel \
      make \
      openldap-devel \
      openssl-devel \
      Linux-PAM-devel \
      zlib-devel \
      zstd-devel \
 && git clone --depth 1 --branch v${PG_CRON_VERSION} https://github.com/citusdata/pg_cron.git /tmp/pg_cron \
 && PATH=/usr/pgsql/${PG_MAJOR}/bin:$PATH make -C /tmp/pg_cron \
 && PATH=/usr/pgsql/${PG_MAJOR}/bin:$PATH make -C /tmp/pg_cron install \
 && git clone --depth 1 --branch v${PGVECTOR_VERSION} https://github.com/pgvector/pgvector.git /tmp/pgvector \
 && PATH=/usr/pgsql/${PG_MAJOR}/bin:$PATH make -C /tmp/pgvector \
 && PATH=/usr/pgsql/${PG_MAJOR}/bin:$PATH make -C /tmp/pgvector install \
 && git clone --depth 1 --branch ${PGAUDIT_VERSION} https://github.com/pgaudit/pgaudit.git /tmp/pgaudit \
 && PATH=/usr/pgsql/${PG_MAJOR}/bin:$PATH make -C /tmp/pgaudit USE_PGXS=1 \
 && PATH=/usr/pgsql/${PG_MAJOR}/bin:$PATH make -C /tmp/pgaudit USE_PGXS=1 install \
 && mkdir -p \
      /tmp/extension-artifacts/usr/pgsql/${PG_MAJOR}/lib/bitcode \
      /tmp/extension-artifacts/usr/pgsql/${PG_MAJOR}/share/extension \
 && for ext in pg_cron vector pgaudit; do \
      cp /usr/pgsql/${PG_MAJOR}/lib/${ext}.so /tmp/extension-artifacts/usr/pgsql/${PG_MAJOR}/lib/; \
      cp /usr/pgsql/${PG_MAJOR}/share/extension/${ext}.control /tmp/extension-artifacts/usr/pgsql/${PG_MAJOR}/share/extension/; \
      cp /usr/pgsql/${PG_MAJOR}/share/extension/${ext}--*.sql /tmp/extension-artifacts/usr/pgsql/${PG_MAJOR}/share/extension/; \
      if [ -d /usr/pgsql/${PG_MAJOR}/lib/bitcode/${ext} ]; then \
        cp -a /usr/pgsql/${PG_MAJOR}/lib/bitcode/${ext} /tmp/extension-artifacts/usr/pgsql/${PG_MAJOR}/lib/bitcode/; \
      fi; \
      if [ -f /usr/pgsql/${PG_MAJOR}/lib/bitcode/${ext}.index.bc ]; then \
        cp /usr/pgsql/${PG_MAJOR}/lib/bitcode/${ext}.index.bc /tmp/extension-artifacts/usr/pgsql/${PG_MAJOR}/lib/bitcode/; \
      fi; \
    done


FROM $BASE
ARG BASE
ARG PG_MAJOR=18
ARG PG_VERSION=18.4
ARG PG_CRON_VERSION=1.6.7
ARG PGVECTOR_VERSION=0.8.5
ARG PGAUDIT_VERSION=18.0
ARG IMAGE_TITLE
ARG IMAGE_DESCRIPTION
ARG IMAGE_AUTHORS
ARG IMAGE_VENDOR
ARG IMAGE_OWNER
ARG IMAGE_SOURCE
ARG IMAGE_REPOSITORY
ARG IMAGE_URL
ARG IMAGE_DOCUMENTATION
ARG IMAGE_REVISION
ARG IMAGE_CREATED
ARG IMAGE_LICENSES

LABEL org.opencontainers.image.title="${IMAGE_TITLE}" \
      org.opencontainers.image.description="${IMAGE_DESCRIPTION}" \
      org.opencontainers.image.authors="${IMAGE_AUTHORS}" \
      org.opencontainers.image.vendor="${IMAGE_VENDOR}" \
      org.opencontainers.image.source="${IMAGE_SOURCE}" \
      org.opencontainers.image.url="${IMAGE_URL}" \
      org.opencontainers.image.documentation="${IMAGE_DOCUMENTATION}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.created="${IMAGE_CREATED}" \
      org.opencontainers.image.licenses="${IMAGE_LICENSES}" \
      org.opencontainers.image.base.name="${BASE}" \
      org.opencontainers.image.version="${PG_VERSION}" \
      org.opencontainers.image.ref.name="${IMAGE_REPOSITORY}" \
      org.opencontainers.image.component.postgresql.version="${PG_VERSION}" \
      org.opencontainers.image.component.pg_cron.version="${PG_CRON_VERSION}" \
      org.opencontainers.image.component.pgvector.version="${PGVECTOR_VERSION}" \
      org.opencontainers.image.component.pgaudit.version="${PGAUDIT_VERSION}" \
      edu.gatech.image.owner="${IMAGE_OWNER}" \
      edu.gatech.image.repository="${IMAGE_REPOSITORY}"

USER root
# Top line of installs is vuln prevention
RUN tdnf install -y \
      sqlite-libs libssh2 \
      icu \
      krb5 \
      Linux-PAM \
      libxml2 \
      libxslt \
      libllvm \
      lz4 \
      openldap \
      openssl \
      perl \
      python3 \
      readline \
      shadow \
      tcl \
      zlib \
      zstd \
 && groupadd -g 26 postgres \
 && useradd -u 26 -g 26 -d /var/lib/pgsql -s /bin/bash postgres \
 && mkdir -p /var/lib/pgsql \
 && chown -R postgres:postgres /var/lib/pgsql

COPY --from=postgres-builder /usr/pgsql/${PG_MAJOR} /usr/pgsql/${PG_MAJOR}
COPY --from=extension-builder /tmp/extension-artifacts/ /
RUN chown -R postgres:postgres /usr/pgsql/${PG_MAJOR} /var/lib/pgsql
ENV PATH=/usr/pgsql/${PG_MAJOR}/bin:$PATH
USER postgres
