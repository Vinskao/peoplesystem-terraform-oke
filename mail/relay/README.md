# OCI Email Delivery forwarding

Chosen on 2026-10-28: accept mail for
`tianyikao@peoplesystem.tatdvsonorth.com` and submit a new message to OCI Email
Delivery using that approved address as both header From and envelope MAIL FROM.
Only `tianyikao@gmail.com` is a permitted delivery destination. The original sender
or valid original Reply-To becomes Reply-To. The full original bytes are attached
as `original.eml`, including all original attachments; an inert plain-text preview
keeps verification links usable. Original external addresses are not submitted as
OCI approved senders.

## Sending path

Postfix queue -> unprivileged `ociforward` pipe -> certificate-verified TLS on
`smtp.email.ap-singapore-2.oci.oraclecloud.com:465` -> OCI -> Gmail.

Both port 465 and STARTTLS on port 587 were verified from the existing mail pod
with TLS 1.3 on 2026-10-28. Port 465 is used to require encryption before SMTP
authentication. No direct TCP/25 fallback is configured in this overlay. An SMTP
failure returns EX_TEMPFAIL (75), retaining the original in the Postfix queue.

The initial inbound size limit is **1,000,000 bytes**, allowing the original plus
base64 attachment and preview to fit OCI's default 2 MB submission limit. Larger
mail is rejected during SMTP submission, before acceptance. Increase the OCI
message-size quota and both application limits together before accepting larger
messages. This overlay does not change or publish inbound ingress.

## Authentication and DNS

Use a dedicated IAM user `ty-mail-relay`, without a Console password or API key.
Its group should receive only `use approved-senders` in a dedicated non-root
compartment and only for `peoplesystem.tatdvsonorth.com`. It must not receive
Compute, Object Storage, IAM administration, or other domain permissions.

Generate a dedicated SMTP credential, then store the following JSON as key
`relay.json` in Secret `mail-system/oci-smtp`. Do not place real credentials in
this repository, command arguments, screenshots, logs, or Git:

```json
{"host":"smtp.email.ap-singapore-2.oci.oraclecloud.com","username":"GENERATED_SMTP_USERNAME","password":"GENERATED_SMTP_PASSWORD"}
```

The init container copies that secret to a private file accessible to the
unprivileged pipe user. Rotate it by replacing the Kubernetes Secret and restarting
the StatefulSet. Confirm the relay works before revoking the old credential.

Create the email domain and one exact approved sender in ap-singapore-2. Publish
the OCI-generated DKIM CNAME and the regional SPF include for the **subdomain**.
Preserve root-domain Hostinger MX and SPF. Inbound MX, public TLS and ingress are
still separate prerequisites. Do not close SR 4-0004161116 until the relay is
verified; direct TCP/25 egress and an egress PTR are not needed for this sending
path.

## Validation and deployment

```sh
python3 -m unittest discover -s mail/tests -p test_oci_forward.py -v
kubectl apply --dry-run=server -k mail/oci-relay
kubectl apply -k mail/oci-relay
kubectl -n mail-system rollout status statefulset/ty-mail --timeout=300s
kubectl -n mail-system exec -i ty-mail-0 -- python3 - < mail/tests/verify_smtp.py
```

Before real submission, verify `postconf -M ociforward/unix`, `postfix check`,
the exact recipient's transport lookup and the credential file's ownership/mode.
Then send one uniquely identified test message to the allowlisted inbox and verify
receipt in Gmail, original attachment bytes, Reply-To, and DKIM/DMARC results.
Keep public inbound routing disabled until all these checks pass.

The `mail/production` overlay now extends this relay mode and mounts the trusted
inbound certificate. After `certificate/mail-public` is Ready, use
`kubectl apply -k mail/production`. Production adds a dedicated NodePort 31225
targeting Postfix 2525, which requires PROXY protocol. The existing OCI load
balancer can route TCP 25 to this backend with PROXY v1 while STARTTLS remains
terminated by Postfix. Existing ingress-nginx HTTP, HTTPS and PostgreSQL mappings
are not changed. Public listener and security rules require a separate verified
publication step; publish the subdomain MX only after an external SMTP probe.

## Deployment record (2026-10-29)

Dedicated SMTP identity, restricted policy, approved sender, SPF and active DKIM
are configured. The SMTP credential was imported to `mail-system/oci-smtp` without
plaintext local files or command arguments. Since the browser process could not
start SSH correctly, an ephemeral RSA-OAEP key encrypted the transport; the
server decrypted directly into the Secret importer's stdin. Transport ciphertext
and temporary key files were removed after successful import.

Production relay and the Let's Encrypt certificate are deployed. A uniquely named
synthetic message was accepted by OCI and received in the owner's Gmail inbox,
showing the domain's DKIM signature, TLS and `original.eml`. The private PROXY
backend passed four integration checks locally and through NodePort: trusted TLS,
owner address acceptance, unknown recipient rejection and external relay denial.
The owner subsequently approved public receiving. The existing LB now has TCP25
with PROXYv1, narrow LB/backend network rules, and the subdomain MX is public.
An external Gmail roundtrip was received back in Gmail Inbox; Postfix queue ID
39E57243B882 retained Google's original source IP. Public TLS1.3 and recipient
policy probes passed. Gmail Send-as is only a temporary option: Google announced
third-party address support will end in January2027; use an independent SMTP
identity in a mail client for a longer-term custom sender setup.

## Cost and source references

Oracle live agent Sergiu confirmed on 2026-10-28 that TCP/25 unblocking has no
cost and that its review belongs with CAM via the existing SR. The account owner
confirmed the tenancy is already PAYG. For the chosen managed relay, the first
3,000 monthly Email Delivery billing units per tenancy are free; additional units
cost US$0.085 per 1,000. Each recipient and each 2 MB chunk counts separately.
The planned 100 ordinary, single-recipient messages/month are within that free
allocation, assuming other tenancy usage does not consume it.

* https://docs.oracle.com/en-us/iaas/Content/Email/Reference/gettingstarted_topic-Create_an_approved_sender.htm
* https://docs.oracle.com/en-us/iaas/Content/Identity/policyreference/emailpolicyreference.htm
* https://docs.oracle.com/en-us/iaas/Content/Email/Reference/gettingstarted_topic-Configure_the_SMTP_connection.htm
* https://www.oracle.com/cloud/price-list/
* https://docker-mailserver.github.io/docker-mailserver/latest/faq/
