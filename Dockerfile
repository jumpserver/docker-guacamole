FROM library/tomcat:9-jre8 AS builder

ARG PREFIX_DIR=/usr/local/guacamole
ARG GUACD_VER=1.2.0

RUN curl -o /etc/apt/sources.list "https://mirrors.163.com/.help/sources.list.stretch"

ARG BUILD_DEPENDENCIES="              \
        autoconf                      \
        automake                      \
        freerdp2-dev                  \
        gcc                           \
        libcairo2-dev                 \
        libjpeg62-turbo-dev           \
        libossp-uuid-dev              \
        libpango1.0-dev               \
        libpulse-dev                  \
        libssh2-1-dev                 \
        libssl-dev                    \
        libtelnet-dev                 \
        libtool                       \
        libvncserver-dev              \
        libwebsockets-dev             \
        libwebp-dev                   \
        make"

# Bring build environment up to date and install build dependencies
RUN apt-get update                         && \
    apt-get install -y $BUILD_DEPENDENCIES && \
    rm -rf /var/lib/apt/lists/*

RUN curl -SLO "http://download.jumpserver.org/public/guacamole-server-${GUACD_VER}.tar.gz" && ls \
  && tar -xzf guacamole-server-${GUACD_VER}.tar.gz && mkdir ${PREFIX_DIR} \
  && cp -r guacamole-server-${GUACD_VER}/src/guacd-docker/bin ${PREFIX_DIR}/bin/

RUN ${PREFIX_DIR}/bin/build-guacd.sh guacamole-server-${GUACD_VER} "$PREFIX_DIR"

RUN ${PREFIX_DIR}/bin/list-dependencies.sh    \
        ${PREFIX_DIR}/sbin/guacd              \
        ${PREFIX_DIR}/lib/libguac-client-*.so \
        ${PREFIX_DIR}/lib/freerdp2/guac*.so   \
        > ${PREFIX_DIR}/DEPENDENCIES

FROM library/tomcat:9-jre8
ARG PREFIX_DIR=/usr/local/guacamole
ARG VERSION=v2.2.0
ENV JMS_VERSION=${VERSION}
ENV ARCH=amd64 \
    GUACAMOLE_HOME=/config/guacamole

# Runtime environment
ENV LC_ALL=C.UTF-8
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${PREFIX_DIR}/lib
ENV GUACD_LOG_LEVEL=debug

ARG RUNTIME_DEPENDENCIES="            \
        netcat-openbsd                \
        ca-certificates               \
        ghostscript                   \
        fonts-liberation              \
        fonts-dejavu                  \
        xfonts-terminus"

COPY --from=builder ${PREFIX_DIR} ${PREFIX_DIR}

RUN curl -o /etc/apt/sources.list "https://mirrors.163.com/.help/sources.list.stretch"

# Bring runtime environment up to date and install runtime dependencies
RUN apt-get update                                                                  && \
    apt-get install -y --no-install-recommends $RUNTIME_DEPENDENCIES                && \
    apt-get install -y --no-install-recommends $(cat "${PREFIX_DIR}"/DEPENDENCIES)  && \
    rm -rf /var/lib/apt/lists/*

# Link FreeRDP plugins into proper path
RUN ${PREFIX_DIR}/bin/link-freerdp-plugins.sh \
        ${PREFIX_DIR}/lib/freerdp2/libguac*.so

ADD http://download.jumpserver.org/public/s6-overlay-${ARCH}.tar.gz /tmp/

RUN tar -xzf /tmp/s6-overlay-${ARCH}.tar.gz -C / \ 
    && tar -xzf /tmp/s6-overlay-${ARCH}.tar.gz -C /usr ./bin \
    && rm -rf /tmp/s6-overlay-${ARCH}.tar.gz

WORKDIR ${GUACAMOLE_HOME}

RUN rm -rf ${CATALINA_HOME}/webapps/ROOT \
    && mkdir -p ${GUACAMOLE_HOME}/extensions

COPY etc /etc/
COPY guacamole.properties ${GUACAMOLE_HOME}/
ADD http://download.jumpserver.org/public/ssh-forward.tar.gz /tmp/
RUN tar xvf /tmp/ssh-forward.tar.gz -C /bin/ && chmod +x /bin/ssh-forward

ADD http://download.jumpserver.org/release/${JMS_VERSION}/guacamole-client-${JMS_VERSION}.tar.gz /tmp/

RUN tar -xzf /tmp/guacamole-client-${JMS_VERSION}.tar.gz \
    && cp guacamole-client-${JMS_VERSION}/guacamole-*.war ${CATALINA_HOME}/webapps/ROOT.war \
    && cp guacamole-client-${JMS_VERSION}/guacamole-*.jar ${GUACAMOLE_HOME}/extensions/ \
    && rm -rf /tmp/guacamole-client-${JMS_VERSION}.tar.gz guacamole-client-${JMS_VERSION}

ENTRYPOINT ["/init"]