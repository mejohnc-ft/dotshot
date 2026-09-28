# Connect a destination over SSH

dotshot sends files with the `scp` command already included with macOS. It does
not run a receiving service or store passwords, private keys, or Tailscale
credentials.

You need:

1. An SSH server on the destination device.
2. A network address that this Mac can reach.
3. Key authentication that works without a password prompt.
4. A folder the destination account can write to.

An SSH alias is optional. A direct address such as `john@mac-studio.local`,
`john@100.64.0.10`, or `john@mac-studio` works.

## 1. Enable SSH on the destination

### Destination is a Mac

Open **System Settings → General → Sharing**, enable **Remote Login**, and allow
the account that should receive captures.

On that Mac, find the account name:

```bash
whoami
```

Its local network address is commonly:

```text
username@computer-name.local
```

### Destination is Linux

Install and enable the OpenSSH server using your distribution's package and
service manager. For Ubuntu or Debian:

```bash
sudo apt update
sudo apt install openssh-server
sudo systemctl enable --now ssh
```

Confirm the destination account with `whoami`.

## 2. Create a key on the Mac running dotshot

Check for the recommended Ed25519 public key:

```bash
test -f ~/.ssh/id_ed25519.pub && echo "Key already exists"
```

If it does not exist:

```bash
ssh-keygen -t ed25519 -C "dotshot@$(scutil --get LocalHostName)"
```

Accept the default file location. A passphrase provides additional protection,
and macOS can remember it in Keychain. Never copy or share the private file
`~/.ssh/id_ed25519`.

The file ending in `.pub` is the public key and is safe to install on a
destination you control.

## 3. Connect once and authorize the key

First connect normally so you can review and accept the destination's host
fingerprint:

```bash
ssh username@device
```

Then authorize this Mac's public key. This portable command works even when
`ssh-copy-id` is not installed:

```bash
cat ~/.ssh/id_ed25519.pub | ssh username@device \
  'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys'
```

The destination may ask for the account password this one time.

Verify non-interactive authentication:

```bash
ssh -o BatchMode=yes username@device true && echo "SSH is ready"
```

## 4. Choose a receiving folder

dotshot can create the folder during its connection test. To create it
yourself:

```bash
ssh username@device 'mkdir -p ~/inbound && chmod 700 ~/inbound'
```

In dotshot, enter `~/inbound`. A successful test resolves it to an absolute
path such as `/Users/username/inbound` or `/home/username/inbound`, which is the
path dotshot copies for your agent.

## Tailscale

The simplest option is ordinary OpenSSH over the private Tailscale network:

1. Sign both devices into the same tailnet.
2. Enable Remote Login or OpenSSH on the destination.
3. Use `username@device-name` when MagicDNS is enabled, or use the destination's
   `100.x.y.z` Tailscale address.
4. Configure the same SSH key authentication described above.

[MagicDNS](https://tailscale.com/docs/features/magicdns) lets SSH clients use a
device name instead of its Tailscale IP.

[Tailscale SSH](https://tailscale.com/docs/features/tailscale-ssh) is a separate,
optional authentication mode. It can remove the public-key step when enabled
and allowed by tailnet policy. Its server currently supports Linux and macOS
devices using the open-source `tailscale` + `tailscaled` variant; the standard
macOS GUI variants can still be clients. Ordinary OpenSSH over Tailscale works
with the standard macOS clients.

## Optional SSH alias

Aliases keep destination entries short but are not required. Add an entry to
`~/.ssh/config`:

```sshconfig
Host studio
    HostName mac-studio
    User john
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

Then secure the file and test the alias:

```bash
chmod 600 ~/.ssh/config
ssh studio
```

Enter `studio` as the SSH address in dotshot.

## Troubleshooting

### Host not found

- Check the spelling of the hostname or alias.
- Try the IP address.
- For Tailscale, confirm both devices are connected and MagicDNS is enabled.

### Connection refused

- Enable Remote Login on macOS or start the OpenSSH server on Linux.
- Confirm SSH is listening on the expected port.

### Permission denied

- Confirm the destination username.
- Run the public-key authorization command again.
- Connect with `ssh username@device` in Terminal to see the full authentication
  error.

### Host key verification failed

Connect once in Terminal, verify the fingerprint with the destination owner,
and accept it. If SSH warns that an existing identity changed, investigate
before removing any `known_hosts` entry.

### Folder is not writable

Choose a folder owned by the destination account, such as `~/inbound`, or fix
its ownership and permissions on the destination.

## Security boundary

- dotshot invokes the system `ssh` and `scp` tools.
- Private keys remain in your normal `~/.ssh` configuration.
- Password prompts are disabled during dotshot tests and transfers.
- Host-key verification remains enforced.
- Only the destinations in your local configuration receive files.
