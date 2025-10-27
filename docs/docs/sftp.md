Here's a **detailed walkthrough** to set up a **VM as an SFTP server** on **Ubuntu** (works for Ubuntu 20.04/22.04 LTS). This guide covers installation, user setup, directory permissions, and administrative tasks.

---

## 🧰 Prerequisites

- Ubuntu-based VM (e.g., running on AWS EC2, Azure VM, VirtualBox, or local)
- Root or sudo access
- Basic networking setup (open port 22 if using a cloud provider)

---

## 🔧 Step 1: Install OpenSSH Server

SFTP runs over SSH, so you need to have the SSH server installed:

```bash
sudo apt update
sudo apt install openssh-server -y
```

Verify that SSH is running:

```bash
sudo systemctl status ssh
```

---

## 📁 Step 2: Create SFTP Group and Users

### Create a dedicated group for SFTP users:

```bash
sudo groupadd sftpusers
```

### Add a user to the group:

```bash
sudo useradd -m -d /home/sftpuser1 -s /sbin/nologin -G sftpusers sftpuser1
sudo passwd sftpuser1
```

> `-s /sbin/nologin` prevents the user from SSH login while still allowing SFTP access.

---

## 🛠 Step 3: Set Up Directory Structure

You need to restrict access to the home folder, and then allow access to a subfolder for uploads.

```bash
# Create a directory for uploads
sudo mkdir -p /home/sftpuser1/uploads

# Set ownership and permissions
sudo chown root:root /home/sftpuser1
sudo chmod 755 /home/sftpuser1

# Allow user access to 'uploads'
sudo chown sftpuser1:sftpusers /home/sftpuser1/uploads
```

---

## ⚙️ Step 4: Configure SSH for SFTP-Only Access

Edit the SSH configuration file:

```bash
sudo nano /etc/ssh/sshd_config
```

Add the following block at the end:

```text
Match Group sftpusers
    ChrootDirectory /home/%u
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
```

> `%u` dynamically matches the username (e.g., `/home/sftpuser1`).

Restart the SSH service:

```bash
sudo systemctl restart ssh
```

---

## 🔐 Step 5: Test SFTP Connection

From a remote machine or using `sftp`:

```bash
sftp sftpuser1@your.server.ip
```

Try uploading a file:

```bash
cd uploads
put somefile.txt
```

---

## 🔁 Step 6: Managing Users

### Add more users:

Repeat the user creation steps for `sftpuser2`, `sftpuser3`, etc.

```bash
sudo useradd -m -d /home/sftpuser2 -s /sbin/nologin -G sftpusers sftpuser2
sudo passwd sftpuser2
sudo mkdir /home/sftpuser2/uploads
sudo chown root:root /home/sftpuser2
sudo chmod 755 /home/sftpuser2
sudo chown sftpuser2:sftpusers /home/sftpuser2/uploads
```

---

## 🧹 Optional Admin Tasks

### Monitor SFTP Activity:

View logs using:

```bash
sudo journalctl -u ssh
# or more specific logs
sudo grep sftp /var/log/auth.log
```

### Limit bandwidth or connection rate:

Use `sshd_config` and tools like `tc`, `iptables`, or `fail2ban`.

---

## 📤 File Ownership & Quotas (Advanced)

For finer control:

- Use `setfacl` for access control lists
- Use `quotas` to limit disk usage (`sudo apt install quota`)

---

## 🔒 Security Tips

- Use SSH keys instead of passwords
- Configure Fail2Ban to block brute force
- Disable root login: set `PermitRootLogin no` in `/etc/ssh/sshd_config`
- Only expose port 22 to trusted IPs (via firewall)

---

## ✅ Summary

| Task                 | Command / Tool                    |
| -------------------- | --------------------------------- |
| Install SSH          | `sudo apt install openssh-server` |
| Add user             | `useradd` + `passwd`              |
| Set up folders       | `mkdir`, `chown`, `chmod`         |
| Restrict SSH to SFTP | Edit `/etc/ssh/sshd_config`       |
| Restart SSH service  | `sudo systemctl restart ssh`      |
| Monitor access       | `journalctl`, `/var/log/auth.log` |

---

Would you like a script or Ansible playbook to automate this setup?
