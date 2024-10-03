ARG MCROUTER_UPSTREAM_IMAGE_TAG="2023.07.17.00-1-20240929"
FROM docker-registry.wikimedia.org/mcrouter:${MCROUTER_UPSTREAM_IMAGE_TAG} AS upstream

USER root
RUN apt -y update && \
    apt -y dist-upgrade && \
    apt -y install --no-install-recommends \
      dnsutils \
      jq \
      vim && \
    apt -y autoremove && \
    rm -rf /var/cache/*

ENV PATH="/scripts:$PATH"
COPY --chown=root:root ./scripts /scripts

USER mcrouter
ENTRYPOINT ["/bin/bash"]
