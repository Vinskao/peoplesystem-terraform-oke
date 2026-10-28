# OKE forwarding mail gateway

Address: `hello@peoplesystem.tatdvsonorth.com` → `tianyikao@gmail.com`.
`postmaster` and `abuse` at the same domain also forward there. No catch-all.

## Deployment and current boundary

Uses the upstream Docker Mailserver 16.0.1 ARM64 image to run Postfix, Rspamd,
Redis and PostSRSd together. SMTP-only mode disables mailboxes. Only port 25 is
exposed through a **ClusterIP** Service. No public LoadBalancer, NodePort, TCP
ingress mapping or DNS record is created by this Kustomize root.

```sh
kubectl apply -f mail/base/namespace.yaml
python3 mail/bootstrap-secrets.py
kubectl apply --dry-run=server -k mail
kubectl apply -k mail
kubectl -n mail-system rollout status statefulset/ty-mail --timeout=300s
kubectl -n mail-system exec -i ty-mail-0 -- python3 - < mail/tests/verify_smtp.py
kubectl -n mail-system exec -i ty-mail-0 -- python3 - < mail/tests/verify_forward.py
```

On Windows, copy `mail/` to the SSH operator and run these commands there.
The application remains internal while external-delivery prerequisites are missing.
The SMTP policy test does not submit DATA. The forwarding test refuses a non-empty
queue, temporarily points outbound delivery to a loopback-only SMTP sink and checks
SRS, bounce handling, ARC and original From/body preservation. It restores routing
in a finally block and removes only a uniquely identified synthetic test message if
needed. Neither test sends mail to Gmail. Do not run the forwarding test on a live
service receiving real mail.

## Storage and keys

State is node-local at `/var/lib/ty-mail` on worker `10.0.158.183`. It survives pod
recreation, **not worker/boot-volume loss**. This avoids provisioning another paid
50 GiB OCI volume for staging. Before production, arrange an encrypted backup or
move the state to a dedicated retained PVC and document its recovery procedure.

The init container generates an ARC private key and a 14-day self-signed staging
TLS certificate directly on that node. They never belong in Git or command output.
`bootstrap-secrets.py` creates a unique SRS secret in Kubernetes through stdin;
it never prints the value and retains an existing secret when rerun.
The deployed SMTP certificate must be replaced by a trusted certificate before
publishing. Configuration changes require reapplying Kustomize; its ConfigMap hash
causes a pod restart. Existing private keys are retained.

## Preflight evidence (2026-10-28)

* SSH alias `oke-node` connects to the operator at `10.0.0.69`; it is not a worker.
* The cluster workers are ARM64, `10.0.158.183` and `10.0.159.167`.
* Public HTTP ingress IP: `140.245.52.231`.
* Operator outbound IP: `140.245.44.81`; PTR missing.
* Operator IPv4 connections to two Gmail MX hosts on TCP 25 timed out;
  `smtp.gmail.com:587` was reachable. The same checks from the running mail pod
  confirmed the same egress IP, both TCP/25 timeouts and working TCP/587.
* Root domain `tatdvsonorth.com` uses Hostinger MX and SPF. Preserve these records.
* Existing ingress TCP mapping includes PostgreSQL on 5432. Preserve it if adding SMTP.

## Completed staging verification (2026-10-28)

The live `mail-system/ty-mail-0` pod is Ready on worker `10.0.158.183`.
Eight SMTP tests pass: the allowlisted alias, rejection of unknown recipients,
forged SRS recipients and arbitrary external relay, trusted staging TLS handshake,
Rspamd config validation, no catch-all and a loopback-only Rspamd controller.
An initial controller-binding test failed and passed after binding port 11334 to
127.0.0.1. The full forwarding test initially exposed an ARC key-directory permission
error; after correcting traversal permissions it passes SRS rewriting, valid SRS
bounce acceptance, destination Gmail address, original From/body preservation and
ARC headers against a loopback SMTP sink. Outbound TLS enforcement is restored
after that test and the synthetic queue is empty. No real external message has
been sent or delivered to Gmail.

## Required before publishing

1. Verify outbound TCP 25 from the mail pod. OCI blocks it by default for many
   tenancies; a node firewall rule does not remove the tenancy restriction.
2. Confirm the actual stable SMTP egress IP, then ask Oracle to set its PTR to
   `smtp-out.peoplesystem.tatdvsonorth.com`. Add an A record for that name pointing
   back to the same IP. This differs from the **ingress** IP behind the load balancer.
   Set Postfix `smtp_helo_name` to that verified egress hostname before publication.
3. In Hostinger DNS, add the records below. Confirm control of the zone first.
   Do not replace the root-domain MX or root SPF.
4. Issue a trusted TLS certificate for the inbound hostname using cert-manager
   and the existing HTTP ingress; mount it at the SSL_CERT_PATH / SSL_KEY_PATH
   configured in the StatefulSet. Do not use the staging self-signed certificate.
   After inbound A records resolve to the load balancer, apply
   `mail/production/certificate.yaml`, wait for `certificate/mail-public` to be Ready,
   then apply `kubectl apply -k mail/production` to mount the trusted certificate.
   The production overlay also keeps SMTP private until the explicit ingress step.
5. Validate no-open-relay, rejected unknown recipient, SRS envelope rewriting,
   ARC signatures and preservation of original message headers using a local SMTP
   sink. Then validate one real inbound message and receipt in the destination Gmail.
6. Only after these checks, merge port 25 into the existing ingress TCP ConfigMap
   and its Service/Deployment port lists. Preserve every existing port and mapping.
   Preserve client source IPs with PROXY protocol, or equivalent trusted forwarding;
   test the corresponding Postfix listener configuration before public exposure.

DNS plan (TTL 300 during rollout):

| Name | Type | Value |
| --- | --- | --- |
| mx.peoplesystem | A | 140.245.52.231 |
| smtp-out.peoplesystem | A | verified SMTP egress IP |
| smtp-out.peoplesystem | TXT | v=spf1 ip4:VERIFIED_EGRESS_IP -all |
| peoplesystem | MX | 10 mx.peoplesystem.tatdvsonorth.com. |
| peoplesystem | TXT | v=spf1 ip4:VERIFIED_EGRESS_IP -all |
| arc2026._domainkey.peoplesystem | TXT | v=DKIM1; k=rsa; p=PUBLIC_ARC_KEY |
| _dmarc.peoplesystem | TXT | v=DMARC1; p=none |

Export only the ARC **public** key for DNS, not `arc.key`:

```sh
kubectl -n mail-system exec ty-mail-0 -- openssl pkey \
  -in /tmp/docker-mailserver/rspamd/dkim/arc.key -pubout
```

SRS rewrites the envelope sender; the original From and DKIM headers must stay
intact. ARC records the authentication checks before forwarding. Neither guarantees
that Gmail will trust a new forwarding IP. Measure actual acceptance and spam-folder
placement before relying on this address for an application.

## OCI support request draft

> Please review the outbound SMTP TCP/25 restriction for my tenancy in
> ap-singapore-2. I am setting up an allowlisted, single-domain inbound mail
> forwarder on my OKE cluster, forwarding only to my own Gmail inbox.
> Postfix rejects unknown recipients and external relay attempts, with Rspamd
> filtering, SRS and ARC. Please confirm whether an SMTP exemption is available
> and whether a PTR can be set on my verified egress public IP to
> smtp-out.peoplesystem.tatdvsonorth.com. The operator currently uses
> 140.245.44.81; I will supply the mail pod's verified egress IP.

This text is a draft, not a submitted support request.

## References

* https://github.com/docker-mailserver/docker-mailserver/releases/tag/v16.0.1
* https://docker-mailserver.github.io/docker-mailserver/latest/config/security/rspamd/
* https://docs.rspamd.com/modules/arc/
* https://docs.oracle.com/en-us/iaas/releasenotes/changes/f7e95770-9844-43db-916c-6ccbaf2cfe24/
* https://docs.oracle.com/en-us/iaas/Content/DNS/Tasks/reversedns.htm
* https://support.google.com/mail/answer/81126
