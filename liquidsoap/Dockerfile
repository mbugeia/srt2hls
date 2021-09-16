FROM savonet/liquidsoap:main

USER root

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update \
    && apt-get install -y \
       dumb-init \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -g 2000 radio \
    && useradd -m -u 2001 -g radio radio

USER radio

ENTRYPOINT ["/usr/bin/dumb-init", "--", "liquidsoap"]

CMD ["/radio/live.liq"]
