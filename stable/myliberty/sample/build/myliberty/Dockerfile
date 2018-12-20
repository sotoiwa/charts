FROM websphere-liberty:18.0.0.4-javaee8
# Change locale and timezone
USER 0
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    language-pack-ja \
    tzdata && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata
USER 1001
# Install features
RUN /opt/ibm/wlp/bin/installUtility install wmqJmsClient-2.0 --acceptLicense
# Copy libraries
COPY --chown=1001:0 db2jcc* /opt/ibm/wlp/bin/shared/resources/jdbc/db2/
COPY --chown=1001:0 wmq* /opt/ibm/wlp/bin/shared/resources/jms/wmq/
ENV LANG ja_JP.UTF-8
ENV TZ Asia/Tokyo
