#!/bin/bash
set -euo pipefail

# Pipe children run without root, Postfix or Kubernetes credentials.
chown 65534:65534 /var/mail-state/oci-relay /var/mail-state/oci-relay/relay.json
chmod 0500 /var/mail-state/oci-relay
chmod 0400 /var/mail-state/oci-relay/relay.json
postconf -M 'ociforward/unix=ociforward unix - n n - 2 pipe flags=Rq user=nobody argv=/usr/bin/python3 /opt/oci-forward/forward.py --config=/var/mail-state/oci-relay/relay.json --recipient=${recipient}'
postconf -e 'transport_maps = texthash:/tmp/docker-mailserver/oci-transport.cf'
postconf -e 'ociforward_destination_recipient_limit = 1'
# Any missing transport entry must fail locally, never fall back to direct TCP/25.
postconf -e 'default_transport = error:Delivery destination is not allowlisted'
postconf -e 'relay_transport = error:Delivery destination is not allowlisted'
# An original plus its byte-preserving attachment must fit OCI's 2 MB default.
postconf -e 'message_size_limit = 1000000'
# Dedicated private backend for OCI listener 25 with original client IP metadata.
# Local health checks and administrative probes retain the ordinary port 25.
postconf -M '2525/inet=2525 inet n - n - - smtpd'
postconf -P '2525/inet/smtpd_upstream_proxy_protocol=haproxy'
postfix check
