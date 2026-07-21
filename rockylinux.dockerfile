# Containerfile.cnpg-postgresql-source

ARG BASE=docker.io/rockylinux/rockylinux:10-ubi-micro@sha256:23f5d986ef65b6f3c84299a7bd065b51beea2e917bd8f0a11bf0a9a53774735c
ARG BUILD_BASE=docker.io/rockylinux/rockylinux:10@sha256:e372170ca8630f0f03e9b70fdd0bf4a3ce3426b0de7cdba615f06337389de176
ARG IMAGE_TITLE="CloudNativePG PostgreSQL on Rocky Linux"
ARG IMAGE_DESCRIPTION="PostgreSQL built from upstream source on Rocky Linux for CloudNativePG."
ARG IMAGE_AUTHORS="Paul Christophel <pmartin@gatech.edu>"
ARG IMAGE_VENDOR="Paul Christophel"
ARG IMAGE_SOURCE="https://github.com/PaulChristophel/docker-postgresql"
ARG IMAGE_REPOSITORY="docker.io/pcm0/postgres"
ARG IMAGE_URL="https://hub.docker.com/r/pcm0/postgres"
ARG IMAGE_DOCUMENTATION="https://github.com/PaulChristophel/docker-postgresql#readme"
ARG IMAGE_REVISION="unknown"
ARG IMAGE_CREATED="1970-01-01T00:00:00Z"
ARG IMAGE_LICENSES="PostgreSQL"

FROM $BUILD_BASE AS postgres-builder
ARG PG_MAJOR=18
ARG PG_VERSION=18.4
ARG PG_SHA256=81a81ec695fb0c7901407defaa1d2f7973617154cf27ba74e3a7ab8e64436094
ARG POSTGRES_CFLAGS="-O2 -pipe -fstack-protector-strong -D_FORTIFY_SOURCE=3"
ARG POSTGRES_LDFLAGS="-Wl,-z,relro,-z,now -Wl,--as-needed"
ARG WITH_UNTRUSTED_LANGUAGES=false

USER root
RUN build_packages="\
      bison \
      binutils \
      bsdtar \
      clang \
      clang-devel \
      diffutils \
      flex \
      gawk \
      gcc \
      glibc-devel \
      libicu-devel \
      krb5-devel \
      libxml2-devel \
      libxslt-devel \
      libxcrypt-devel \
      kernel-headers \
      libuuid-devel \
      llvm-devel \
      lz4 \
      lz4-devel \
      make \
      openldap-devel \
      openssl \
      openssl-devel \
      pam-devel \
      perl \
      readline-devel \
      tzdata \
      wget \
      xz \
      zlib-devel \
      zstd \
      libzstd-devel" \
 && install_options="" \
 && if [ "${WITH_UNTRUSTED_LANGUAGES}" = "true" ]; then \
      build_packages="${build_packages} python3-devel tcl-devel"; \
    fi \
 && if [ "${PG_MAJOR}" -ge 18 ]; then \
      build_packages="${build_packages} libcurl-devel liburing-devel"; \
      install_options="--enablerepo=crb"; \
    fi \
 && dnf install -y ${install_options} ${build_packages} \
 && wget -O /tmp/postgresql.tar.bz2 https://ftp.postgresql.org/pub/source/v${PG_VERSION}/postgresql-${PG_VERSION}.tar.bz2 \
 && echo "${PG_SHA256}  /tmp/postgresql.tar.bz2" | sha256sum -c - \
 && mkdir -p /tmp/postgresql-src \
 && bsdtar -xjf /tmp/postgresql.tar.bz2 -C /tmp/postgresql-src --strip-components=1 \
 && mkdir -p /usr/local/include \
 && if [ "${WITH_UNTRUSTED_LANGUAGES}" = "true" ]; then \
      PERL_CORE="$(perl -MConfig -e 'print "$Config{archlibexp}/CORE"')"; \
      cp "${PERL_CORE}"/*.h /usr/local/include/; \
    fi \
 && groupadd -r postgres-build \
 && useradd -r -g postgres-build -d /tmp/postgres-build postgres-build \
 && mkdir -p /tmp/postgres-build /tmp/postgres-install \
 && chown -R postgres-build:postgres-build \
      /tmp/postgresql-src \
      /tmp/postgres-build \
      /tmp/postgres-install

USER postgres-build
WORKDIR /tmp/postgresql-src
RUN configure_untrusted="" \
 && configure_modern="" \
 && if [ "${WITH_UNTRUSTED_LANGUAGES}" = "true" ]; then \
      configure_untrusted="--with-perl --with-python --with-tcl"; \
    fi \
 && if [ "${PG_MAJOR}" -ge 18 ]; then \
      configure_modern="--with-libcurl --with-liburing"; \
    fi \
 && ./configure \
      CFLAGS="${POSTGRES_CFLAGS}" \
      LDFLAGS="${POSTGRES_LDFLAGS}" \
      --prefix=/usr/pgsql/${PG_MAJOR} \
      --with-gssapi \
      --with-icu \
      --with-ldap \
      --with-libxml \
      --with-libxslt \
      --with-llvm \
      --with-lz4 \
      --with-ssl=openssl \
      --with-pam \
      --with-uuid=e2fs \
      --with-zstd \
      --with-system-tzdata=/usr/share/zoneinfo \
      ${configure_modern} \
      ${configure_untrusted} \
 && make -j"$(nproc)" world-bin \
 && make -j"$(nproc)" check-world \
 && make install-world-bin DESTDIR=/tmp/postgres-install


FROM $BUILD_BASE AS extension-builder
ARG PG_MAJOR=18
ARG PG_CRON_VERSION=1.6.7
ARG PG_CRON_COMMIT=465b38c737f584d520229f5a1d69d1d44649e4e5
ARG PG_CRON_SOURCE_SHA256=ab41d388d845c05ab6f34fa8e12011da2d71f7f562194ee105a6fdecb506a70f
ARG PGVECTOR_VERSION=0.8.5
ARG PGVECTOR_COMMIT=159b79aaad5983fb7459c1e3df2897fbb2d11788
ARG PGVECTOR_SOURCE_SHA256=9a483fad70ae2e0a50b3dccb6c4b4931d9a07375a1d5815e82b57870448a7d52
ARG PGAUDIT_VERSION=18.0
ARG PGAUDIT_COMMIT=f39f8dbb15dc5bd4cbe5f1e5abe0d930ed7593a8
ARG PGAUDIT_SOURCE_SHA256=bbfc57be090c82b4efd8f8ed7f613e2d8537c38c35f25bb2d1c005d5747ef2e4

COPY --from=postgres-builder /tmp/postgres-install/usr/pgsql/${PG_MAJOR} /usr/pgsql/${PG_MAJOR}

USER root
RUN dnf install -y \
      binutils \
      bsdtar \
      clang \
      clang-devel \
      gcc \
      glibc-devel \
      libicu-devel \
      krb5-devel \
      libxml2-devel \
      libxslt-devel \
      kernel-headers \
      llvm-devel \
      lz4-devel \
      make \
      openldap-devel \
      openssl-devel \
      pam-devel \
      zlib-devel \
      libzstd-devel \
      wget \
 && wget -O /tmp/pg_cron.tar.gz https://github.com/citusdata/pg_cron/archive/${PG_CRON_COMMIT}.tar.gz \
 && echo "${PG_CRON_SOURCE_SHA256}  /tmp/pg_cron.tar.gz" | sha256sum -c - \
 && mkdir /tmp/pg_cron \
 && bsdtar -xzf /tmp/pg_cron.tar.gz -C /tmp/pg_cron --strip-components=1 \
 && PATH=/usr/pgsql/${PG_MAJOR}/bin:$PATH make -C /tmp/pg_cron \
 && PATH=/usr/pgsql/${PG_MAJOR}/bin:$PATH make -C /tmp/pg_cron install \
 && wget -O /tmp/pgvector.tar.gz https://github.com/pgvector/pgvector/archive/${PGVECTOR_COMMIT}.tar.gz \
 && echo "${PGVECTOR_SOURCE_SHA256}  /tmp/pgvector.tar.gz" | sha256sum -c - \
 && mkdir /tmp/pgvector \
 && bsdtar -xzf /tmp/pgvector.tar.gz -C /tmp/pgvector --strip-components=1 \
 && PATH=/usr/pgsql/${PG_MAJOR}/bin:$PATH make -C /tmp/pgvector OPTFLAGS="" \
 && PATH=/usr/pgsql/${PG_MAJOR}/bin:$PATH make -C /tmp/pgvector OPTFLAGS="" install \
 && wget -O /tmp/pgaudit.tar.gz https://github.com/pgaudit/pgaudit/archive/${PGAUDIT_COMMIT}.tar.gz \
 && echo "${PGAUDIT_SOURCE_SHA256}  /tmp/pgaudit.tar.gz" | sha256sum -c - \
 && mkdir /tmp/pgaudit \
 && bsdtar -xzf /tmp/pgaudit.tar.gz -C /tmp/pgaudit --strip-components=1 \
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


FROM $BUILD_BASE AS runtime-builder
ARG PG_MAJOR=18
ARG WITH_UNTRUSTED_LANGUAGES=false

USER root
RUN runtime_packages="\
      bash \
      coreutils \
      glibc-minimal-langpack \
      krb5-libs \
      libicu \
      libuuid \
      libxml2 \
      libxslt \
      libzstd \
      llvm-libs \
      lz4-libs \
      openldap \
      openssl-libs \
      pam \
      readline \
      shadow-utils \
      sqlite-libs \
      tzdata \
      zlib-ng-compat" \
 && if [ "${WITH_UNTRUSTED_LANGUAGES}" = "true" ]; then \
      runtime_packages="${runtime_packages} perl python3 tcl"; \
    fi \
 && if [ "${PG_MAJOR}" -ge 18 ]; then \
      runtime_packages="${runtime_packages} libcurl-minimal liburing"; \
    fi \
 && mkdir -p /mnt/rootfs \
 && dnf install -y \
      --installroot=/mnt/rootfs \
      --releasever=10 \
      --setopt=install_weak_deps=False \
      ${runtime_packages} \
 && dnf clean all --installroot=/mnt/rootfs \
 && rm -rf /mnt/rootfs/var/cache/dnf


FROM $BASE
ARG BASE
ARG PG_MAJOR=18
ARG PG_VERSION=18.4
ARG WITH_UNTRUSTED_LANGUAGES=false
ARG PG_CRON_VERSION=1.6.7
ARG PG_CRON_COMMIT=465b38c737f584d520229f5a1d69d1d44649e4e5
ARG PGVECTOR_VERSION=0.8.5
ARG PGVECTOR_COMMIT=159b79aaad5983fb7459c1e3df2897fbb2d11788
ARG PGAUDIT_VERSION=18.0
ARG PGAUDIT_COMMIT=f39f8dbb15dc5bd4cbe5f1e5abe0d930ed7593a8
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

LABEL org.opencontainers.image.created="${IMAGE_CREATED}"
LABEL org.opencontainers.image.base.name="${BASE}"
LABEL org.opencontainers.image.authors="${IMAGE_AUTHORS}"
LABEL org.opencontainers.image.title="${IMAGE_TITLE}"
LABEL org.opencontainers.image.description="${IMAGE_DESCRIPTION}"
LABEL org.opencontainers.image.vendor="${IMAGE_VENDOR}"
LABEL org.opencontainers.image.source="${IMAGE_SOURCE}"
LABEL org.opencontainers.image.url="${IMAGE_URL}"
LABEL org.opencontainers.image.documentation="${IMAGE_DOCUMENTATION}"
LABEL org.opencontainers.image.version="${PG_VERSION}"
LABEL org.opencontainers.image.revision="${IMAGE_REVISION}"
LABEL org.opencontainers.image.licenses="${IMAGE_LICENSES}"
LABEL org.opencontainers.image.ref.name="${IMAGE_REPOSITORY}"
LABEL org.opencontainers.image.component.postgresql.version="${PG_VERSION}"
LABEL org.opencontainers.image.component.pg_cron.version="${PG_CRON_VERSION}"
LABEL org.opencontainers.image.component.pg_cron.revision="${PG_CRON_COMMIT}"
LABEL org.opencontainers.image.component.pgvector.version="${PGVECTOR_VERSION}"
LABEL org.opencontainers.image.component.pgvector.revision="${PGVECTOR_COMMIT}"
LABEL org.opencontainers.image.component.pgaudit.version="${PGAUDIT_VERSION}"
LABEL org.opencontainers.image.component.pgaudit.revision="${PGAUDIT_COMMIT}"
LABEL edu.gatech.image.owner="${IMAGE_OWNER}"
LABEL edu.gatech.image.repository="${IMAGE_REPOSITORY}"

COPY --from=runtime-builder /mnt/rootfs/ /

USER root
RUN groupadd -g 26 postgres \
 && useradd -u 26 -g 26 -d /var/lib/pgsql -s /bin/bash postgres \
 && mkdir -p /var/lib/pgsql \
 && chown -R postgres:postgres /var/lib/pgsql

COPY --from=postgres-builder /tmp/postgres-install/usr/pgsql/${PG_MAJOR} /usr/pgsql/${PG_MAJOR}
COPY --from=extension-builder /tmp/extension-artifacts/ /
RUN chown -R root:root /usr/pgsql/${PG_MAJOR} \
 && chmod -R a-w /usr/pgsql/${PG_MAJOR} \
 && if [ "${WITH_UNTRUSTED_LANGUAGES}" = "false" ]; then \
      for runtime in perl python3 tclsh; do \
        if command -v "${runtime}" >/dev/null; then \
          echo "unexpected language runtime in safe image: ${runtime}" >&2; \
          exit 1; \
        fi; \
      done; \
      for extension in plperl plpython3u pltcl; do \
        test ! -e "/usr/pgsql/${PG_MAJOR}/share/extension/${extension}.control"; \
      done; \
    fi
ENV PATH=/usr/pgsql/${PG_MAJOR}/bin:$PATH
USER postgres
RUN postgres --version \
 && pg_config --cc \
 && pg_config --cflags \
 && pg_config --configure \
 && test -e /usr/share/zoneinfo/UTC \
 && if [ "${PG_MAJOR}" -ge 18 ]; then \
      pg_config --configure | grep -q -- '--with-libcurl'; \
      pg_config --configure | grep -q -- '--with-liburing'; \
      set -- /usr/pgsql/${PG_MAJOR}/lib/libpq-oauth*; test -e "$1"; \
    fi \
 && mkdir /tmp/pg-smoke-socket \
 && initdb -D /tmp/pg-smoke-data \
 && pg_ctl -D /tmp/pg-smoke-data \
      -o "-c listen_addresses='' -c unix_socket_directories=/tmp/pg-smoke-socket -c shared_preload_libraries=pg_cron,pgaudit -c cron.database_name=postgres" \
      -w start \
 && psql -h /tmp/pg-smoke-socket -d postgres -v ON_ERROR_STOP=1 \
      -c 'CREATE EXTENSION vector' \
      -c 'CREATE EXTENSION pg_cron' \
      -c 'CREATE EXTENSION pgaudit' \
      -c 'CREATE EXTENSION "uuid-ossp"' \
      -c 'SELECT extname, extversion FROM pg_extension ORDER BY extname' \
 && if [ "${WITH_UNTRUSTED_LANGUAGES}" = "true" ]; then \
      psql -h /tmp/pg-smoke-socket -d postgres -v ON_ERROR_STOP=1 \
        -c 'CREATE EXTENSION plperl' \
        -c 'CREATE EXTENSION plpython3u' \
        -c 'CREATE EXTENSION pltcl'; \
    fi \
 && pg_ctl -D /tmp/pg-smoke-data -m fast -w stop \
 && rm -rf /tmp/pg-smoke-data /tmp/pg-smoke-socket
