# Copying an SSH key

## Create

```bash
ssh-keygen -f /Users/paul/.ssh/keys/<file-name> -t ed25519 -C "your_email@example.com"
```

## Copy

```bash
ssh-copy-id -i ~/.ssh/mykey user@host
```

## Test

```bash
ssh -i ~/.ssh/mykey user@host
```

## Setting up an alias

This will allow you to log in just using `li <hostname>` using the ssh key

```bash
li() {
    ssh -i /Users/paul/.ssh/keys/home-ops sysadm@"$1"
}
```
