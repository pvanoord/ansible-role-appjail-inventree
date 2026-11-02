# Ansible role: AppJail + InvenTree

Production-oriented deployment of InvenTree on a FreeBSD AppJail host. The role installs and configures AppJail and AppJail Director and deploys four jails:

- **InvenTree** application and background workers;
- **MariaDB** database;
- **Redis** cache / job queue;
- **Nginx** reverse proxy and static/media server.

InvenTree runs from a FreeBSD-native OCI image built by this repository and hosted at `ghcr.io/pvanoord/inventree-freebsd`. MariaDB, Redis and Nginx remain separate AppJail services. SQLite is deliberately not supported by this role.

## What the role manages

- FreeBSD packages: `appjail-devel`, `py312-director`, `dnsmasq`, `git`, `ca_root_nss`;
- AppJail host configuration, release bootstrap, virtual-network defaults and IPv4 forwarding;
- creates `/etc/localtime` from the configured timezone only when the host file is missing;
- AppJail DNS using `dnsmasq` and a dedicated `ajdns` interface;
- only the three required AppJail PF anchors; the existing PF ruleset is not replaced;
- a root-only AppJail Director project and `.env` file;
- persistent application, media, static and MariaDB volumes;
- Nginx, Gunicorn and AppJail health-check configuration;
- optional internal TLS;
- optional daily logical MariaDB and application-data backups;
- idempotent reconciliation when configuration changes or a jail is stopped;
- final Director status and HTTP endpoint validation.

## Requirements

- FreeBSD 14 or newer;
- root privileges through `become`;
- Python 3.12 on the managed host (the example playbook bootstraps it);
- an Internet connection from the host for FreeBSD packages, GHCR and Makejails;
- an unused RFC1918 range for `appjail_inventree_network_cidr`;
- DNS for the chosen public FQDN, or a suitable local hosts record;
- the Ansible controller must be able to reach `appjail_inventree_public_url` when endpoint validation is enabled.

The defaults use `appjail-devel`, because the AppJail Makejail collection targets current AppJail features. Pin or override `appjail_inventree_appjail_package` with `appjail` only after validating the role with the stable package version in your FreeBSD repository.

## Build and publish the FreeBSD OCI image

The old upstream InvenTree AJSPEC references an unavailable image host. This
repository instead builds its own FreeBSD-native OCI image from the upstream
InvenTree `build.makejail` dependency list and pinned application source. It
does not use the Linux Docker image. The OCI image uses FreeBSD's Python 3.12
packages, matching the current FreeBSD ports default. LLVM/Clang is installed
to compile Python dependencies such as `cffi` and `cryptography` that do not
provide compatible prebuilt wheels.

The workflow in `.github/workflows/build-inventree-image.yml` builds on a
FreeBSD 15.1 runner and builds from an `inventree-freebsd` context so dbuild
publishes `ghcr.io/pvanoord/inventree-freebsd:15.1` when image files are pushed
to `main`. Changes to the dbuild configuration also trigger a rebuild. Pull
requests build without publishing.
After the first successful push, set the GHCR package visibility to **Public**
in GitHub Packages; until then the package is private by default and the VM
cannot pull it anonymously.

Once the package is public, deploy with the defaults or set:

```yaml
appjail_inventree_oci_image: ghcr.io/pvanoord/inventree-freebsd
appjail_inventree_oci_tag: "15.1"
```

The image build is separate from Ansible deployment. Publish and verify the
image before running the playbook; Director may recreate the InvenTree jail
when its OCI Makejail changes, while the host-mounted data volume is retained.

## Quick start

Copy the role to `roles/appjail_inventree`, or install the role through your normal Galaxy workflow.

```ini
# inventory.ini
[appjail_hosts]
inventree-host ansible_host=192.0.2.10 ansible_user=ansible ansible_become=true ansible_python_interpreter=/usr/local/bin/python3.12
```

```yaml
# playbook.yml
---
- name: Bootstrap Python
  hosts: appjail_hosts
  gather_facts: false
  become: true
  tasks:
    - name: Install Python when absent
      ansible.builtin.raw: test -x /usr/local/bin/python3.12 || pkg install -y python312
      changed_when: false

- name: Deploy InvenTree
  hosts: appjail_hosts
  gather_facts: true
  become: true
  roles:
    - role: appjail_inventree
      vars:
        appjail_inventree_fqdn: inventree.example.com
        appjail_inventree_public_url: http://inventree.example.com:8080
        appjail_inventree_expose: "8080:80"
        appjail_inventree_admin_email: admin@example.com
        appjail_inventree_backup_enabled: true
```

## Provision the Azure VM with Terraform

The `terraform/` directory provisions `INAZEUWS012` before running the Ansible
playbook. Terraform creates the `rsg-inventree-prod` resource group for the VM
and NIC in the same Azure region as the existing `vnet-Intero-WestEU-Prod`
virtual network. It looks up the existing `BackendSubnetWestEU` subnet in
`rsg-Intero-Europe-Prod` and attaches the VM NIC to it. Terraform does not
create or modify the VNet, subnet, NSG or a public IP address.

Terraform tags the resource group, VM, NIC and OS disk with
`Environment=Production`, `ManagedBy=Terraform`, `Application=InvenTree` and
`Server=INAZEUWS012`. Override the `tags` map in `terraform/variables.tf` (or
provide it through a tfvars file) to match your organization's tagging policy.
The AzAPI provider applies tags to the OS disk created with the VM.

The VM uses `Standard_B2als_v2`, a 64-GiB Standard SSD OS disk, and the static
private IP `10.52.1.93`. Confirm that this address is unused and belongs to the
subnet. Both SSH key and password authentication are enabled for `interoadmin`.
Terraform reads the password from the pinned `interoAdmin` secret version in
`kv-intero-global` (`rsg-kv-intero_global`).

Set the subscription context and SSH public key, then supply the Marketplace
publisher, offer and SKU identifiers for the FreeBSD image available to your
subscription. The identity running Terraform needs permission to read secrets
in the Key Vault (for example, the **Key Vault Secrets User** role), as well as
permission to create the resource group, VM and NIC.

```sh
export ARM_SUBSCRIPTION_ID="<subscription-id>"
export TF_VAR_admin_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
export TF_VAR_key_vault_resource_group_name="rsg-kv-intero_global"
cd terraform
terraform init
```

Before provisioning a Marketplace image, inspect its legal terms. The failed
request in this deployment identifies **FreeBSD 15.1**
(`freebsd:freebsd-15_1:15_1-release-amd64-gen2-zfs`), although the original
request specified FreeBSD 15.2. Do not accept the 15.1 terms if the VM must run
15.2; first choose the correct 15.2 Marketplace image and use its publisher,
offer and SKU consistently for both the Terraform image reference and plan.

If FreeBSD 15.1 is intended, review the terms and explicitly accept them for
the target subscription before continuing:

```sh
az vm image terms show \
  --subscription "$ARM_SUBSCRIPTION_ID" \
  --publisher freebsd \
  --offer freebsd-15_1 \
  --plan 15_1-release-amd64-gen2-zfs

# Run only after reviewing and agreeing to the Marketplace terms:
az vm image terms accept \
  --subscription "$ARM_SUBSCRIPTION_ID" \
  --publisher freebsd \
  --offer freebsd-15_1 \
  --plan 15_1-release-amd64-gen2-zfs
```

After the terms are accepted, use the matching image identifiers in Terraform:

```sh
terraform plan \
  -var="image_publisher=<publisher>" \
  -var="image_offer=<offer>" \
  -var="image_sku=<freebsd-15.2-sku>"
terraform apply \
  -var="image_publisher=<publisher>" \
  -var="image_offer=<offer>" \
  -var="image_sku=<freebsd-15.2-sku>"
```

Verify that the selected Marketplace image supports the VM size in the target
Azure region before applying. Review the Terraform plan carefully. The Key
Vault data source supplies the password to the VM resource,
so Terraform state and plan files can contain the secret even though Terraform
marks it sensitive. Do not commit or share state/plan files; store state in a
protected remote backend with strict access controls, and rotate the password
if state has been exposed. After provisioning, use the resulting private IP in
`examples/inventory.ini` and run the Ansible playbook as usual.

The VM's Marketplace `plan` block uses the same values as the image reference:
publisher, offer as product, and SKU as plan name. If the Marketplace image
listing shows different plan metadata, those values must match the listing or
Azure will reject VM creation. Marketplace legal terms must be inspected and
accepted for the subscription by an authorized user before provisioning.

Create a Vault file:

```yaml
---
appjail_inventree_admin_password: "a-long-random-admin-password"
appjail_inventree_db_password: "a-long-random-database-password"
appjail_inventree_db_root_password: "a-different-long-root-password"
appjail_inventree_secret_key: "a-random-application-secret-of-at-least-32-characters"
```

```sh
ansible-vault encrypt group_vars/appjail_hosts/vault.yml
ansible-playbook -i inventory.ini playbook.yml --ask-vault-pass
```

## Important variables

| Variable | Default | Purpose |
|---|---:|---|
| `appjail_inventree_external_interface` | auto-detect | Interface used for NAT/PF. Leave empty to detect the default-route interface; set explicitly only after verifying its name with `ifconfig`. |
| `appjail_inventree_network_cidr` | `10.77.0.0/24` | AppJail private virtual network. |
| `appjail_inventree_dns_address` | `172.16.0.1` | Host-side DNS address for jails. |
| `appjail_inventree_fqdn` | required | Nginx `server_name`. |
| `appjail_inventree_public_url` | required | Canonical InvenTree URL and trusted origin. |
| `appjail_inventree_expose` | `8080:80` | Host-to-jail HTTP port mapping. |
| `appjail_inventree_oci_image` | `ghcr.io/pvanoord/inventree-freebsd` | Public GHCR image name. |
| `appjail_inventree_oci_tag` | `15.1` | FreeBSD release/image tag. |
| `appjail_inventree_language` | `nl-NL` | InvenTree language. |
| `appjail_inventree_timezone` | `Europe/Amsterdam` | Application timezone. |
| `appjail_inventree_background_workers` | `4` | InvenTree background workers. |
| `appjail_inventree_enable_zfs` | `false` | Enables AppJail's ZFS integration. Do not change after jails exist without a migration plan. |
| `appjail_inventree_manage_pf` | `true` | Adds AppJail NAT/RDR anchors to `/etc/pf.conf`. |
| `appjail_inventree_backup_enabled` | `false` | Installs and schedules the backup script. |
| `appjail_inventree_wait_for_http` | `true` | Verifies the public endpoint after deployment. |

All defaults are documented in `defaults/main.yml`.

## TLS modes

### External TLS termination (recommended when already available)

Keep `appjail_inventree_tls_enabled: false` and publish the HTTP endpoint only to a trusted reverse proxy or load balancer. Set `appjail_inventree_public_url` to the external HTTPS URL and ensure the proxy forwards the original `Host` and `X-Forwarded-Proto` headers.

### TLS in the AppJail Nginx jail

```yaml
appjail_inventree_tls_enabled: true
appjail_inventree_public_url: https://inventree.example.com:8443
appjail_inventree_expose: "8080:80"
appjail_inventree_tls_expose: "8443:443"
appjail_inventree_tls_certificate_src: files/fullchain.pem
appjail_inventree_tls_private_key_src: files/privkey.pem
```

The certificate and key are copied to a root-only host volume. Certificate changes restart the Nginx jail. This role does not obtain or renew certificates.

## PF and network safety

When host networking is enabled, the role:

1. enables IPv4 forwarding;
2. loads `if_bridge` and `bridgestp`;
3. loads the PF kernel module at boot and immediately, then enables PF and pflog;
4. inserts only these anchors into `/etc/pf.conf`:

```pf
nat-anchor "appjail-nat/jail/*"
nat-anchor "appjail-nat/network/*"
rdr-anchor "appjail-rdr/*"
```

The file is validated with `pfctl -nf` before replacement. Existing filtering policy is retained. The role does **not** create a complete host firewall policy. If PF is managed elsewhere, set `appjail_inventree_manage_pf: false` and add the anchors there.

## Persistent data

By default, data is stored below `/var/appjail-volumes/inventree`:

```text
inventree/data/          InvenTree data, static files and media
mariadb/db/              MariaDB data
mariadb/done/            Makejail initialization marker
nginx/tls/               Optional TLS material
```

Director treats jails as ephemeral. The role therefore keeps all state outside the jail roots. Changing a Director service definition can recreate the jail without deleting these volume paths.

## Backups

With `appjail_inventree_backup_enabled: true`, the role installs `/usr/local/sbin/backup-inventree-appjail` and a root cron job. Each backup contains:

- `database.sql`: a single-transaction logical MariaDB dump;
- `inventree-data.tar.gz`: the persistent InvenTree data volume;
- `SHA256`: integrity hashes.

The default retention period is 14 days. Backups remain on the same host by default; copy them to separate, access-controlled storage and test restoration regularly.

A restore is intentionally not automated because it is destructive. At minimum: stop the Director project, verify `SHA256`, preserve the current volumes, restore the data archive with numeric ownership, start MariaDB, import `database.sql`, then start and validate the complete project.

## Updating

- Set `appjail_inventree_update_release: true` for a deliberate FreeBSD release update run; return it to `false` afterwards.
- Rebuild and publish the FreeBSD OCI image after updating the pinned InvenTree source or image build files. Director uses the configured image tag when recreating the InvenTree service.
- Back up and test in a non-production environment before changing the FreeBSD release, Makejail sources or database major version.

## Operational commands

```sh
appjail-director --env-file /usr/local/etc/appjail/projects/inventree/.env info --project inventree
appjail jail list
appjail healthcheck list inventree
appjail logs inventree
service appjail-health status
```

Stop without deleting volumes:

```sh
appjail-director --env-file /usr/local/etc/appjail/projects/inventree/.env down --project inventree
```

Reconcile/start again:

```sh
appjail-director \
  --env-file /usr/local/etc/appjail/projects/inventree/.env \
  up \
  --file /usr/local/etc/appjail/projects/inventree/appjail-director.yml \
  --project inventree
```

## Tags

- `preflight`
- `packages`
- `host`
- `project`
- `deploy`
- `appjail_inventree`

Running only `project` or `deploy` assumes the host setup has already completed.

## Validation scope

The role includes syntax- and lint-friendly YAML and renders a Director configuration for the custom OCI image. Automated image builds and end-to-end jail creation require FreeBSD and cannot be executed on a macOS/Linux Ansible controller. Use GitHub Actions and a disposable FreeBSD test host before production rollout.

Run the included offline structural and template tests with:

```sh
python3 -m pip install -r tests/requirements.txt
python3 tests/validate_role.py
```

## License

BSD-3-Clause.
