# Installing OpenBolt

Packaged versions of OpenBolt are available for several Linux distributions, macOS,
and Microsoft Windows.

| Operating system          | Versions            |
| ------------------------- | ------------------- |
| Debian                    | 10, 11              |
| Fedora                    | 36                  |
| macOS                     | 11, 12              |
| Microsoft Windows*        | 10 Enterprise       |
| Microsoft Windows Server* | 2012R2, 2019        |
| RHEL                      | 6, 7, 8, 9          |
| SLES                      | 12, 15              |
| Ubuntu                    | 18.04, 20.04, 22.04 |

> **Note:** Windows packages are automatically tested on the versions listed
> above, but might be installable on other versions.

## Install OpenBolt on Linux

### Debian/Ubuntu

Download and install the appropriate file for the OS you have

```shell
# Debian 10
wget https://apt.voxpupuli.org/openvox8-release-debian10.deb
sudo dpkg -i openvox8-release-debian10.deb
# Debian 11
wget https://apt.voxpupuli.org/openvox8-release-debian11.deb
sudo dpkg -i openvox8-release-debian11.deb
# Debian 12
wget https://apt.voxpupuli.org/openvox8-release-debian12.deb
sudo dpkg -i openvox8-release-debian12.deb
# Debian 13
wget https://apt.voxpupuli.org/openvox8-release-debian13.deb
sudo dpkg -i openvox8-release-debian13.deb
# Ubuntu 18.04
wget https://apt.voxpupuli.org/openvox8-release-ubuntu18.04.deb
sudo dpkg -i openvox8-release-ubuntu18.04.deb
# Ubuntu 20.04
wget https://apt.voxpupuli.org/openvox8-release-ubuntu20.04.deb
sudo dpkg -i openvox8-release-ubuntu20.04.deb
# Ubuntu 22.04
wget https://apt.voxpupuli.org/openvox8-release-ubuntu22.04.deb
sudo dpkg -i openvox8-release-ubuntu22.04.deb
# Ubuntu 24.04
wget https://apt.voxpupuli.org/openvox8-release-ubuntu24.04.deb
sudo dpkg -i openvox8-release-ubuntu24.04.deb
# Ubuntu 25.04
wget https://apt.voxpupuli.org/openvox8-release-ubuntu25.04.deb
sudo dpkg -i openvox8-release-ubuntu25.04.deb
```

Then install OpenBolt:

```shell
sudo apt-get update
sudo apt-get install openbolt
```

### Enterprise Linux family

Download and install the appropriate file for the OS you have

```shell
# Amazon Linux 2
sudo rpm -Uvh https://yum.voxpupuli.org/openvox8-release-amazon-2.noarch.rpm
# Amazon Linux 2023
sudo rpm -Uvh https://yum.voxpupuli.org/openvox8-release-amazon-2023.noarch.rpm
# EL8
sudo rpm -Uvh https://yum.voxpupuli.org/openvox8-release-el-8.noarch.rpm
# EL9
sudo dnf install https://yum.voxpupuli.org/openvox8-release-el-9.noarch.rpm
# EL8 FIPS
sudo rpm -Uvh https://yum.voxpupuli.org/openvox8-release-redhatfips-8.noarch.rpm
# EL9 FIPS
sudo dnf install https://yum.voxpupuli.org/openvox8-release-redhatfips-9.noarch.rpm
# Fedora 36
sudo rpm -Uvh https://yum.voxpupuli.org/openvox8-release-fedora-36.noarch.rpm
# Fedora 40
sudo dnf install https://yum.voxpupuli.org/openvox8-release-fedora-40.noarch.rpm
# Fedora 41
sudo dnf install https://yum.voxpupuli.org/openvox8-release-fedora-41.noarch.rpm
# Fedora 42
sudo dnf install https://yum.voxpupuli.org/openvox8-release-fedora-42.noarch.rpm
# Fedora 43
sudo dnf install https://yum.voxpupuli.org/openvox8-release-fedora-43.noarch.rpm
# SLES 15
sudo zypper install https://yum.voxpupuli.org/openvox8-release-sles-15.noarch.rpm
```

Then install OpenBolt:

```shell
# Amazon/EL/Fedora
sudo dnf install openbolt
# SLES
sudo zypper install openbolt
```

## Install OpenBolt on macOS

You can install OpenBolt packages for macOS using either Homebrew or the
macOS installer.

### Homebrew

Not available yet.

### macOS installer (DMG)

**Install OpenBolt**

Use the Apple Disk Image (DMG) to install OpenBolt on macOS:

1. Download the OpenBolt installer package for your macOS version from `https://downloads.voxpupuli.org/mac`.
2. Double-click the `openbolt-[version].dmg` file to mount the installer and
   then double-click `openbolt-[version]-installer.pkg` to run the installer.

If you get a message that the installer "can't be opened because Apple cannot check it for malicious software:"
1. Click **** > **System Preferences** > **Security & Privacy**.
1. From the **General** tab, click the lock icon to allow changes to your security settings and enter your macOS password.
1. Look for a message that says the OpenBolt installer "was blocked from use because it is not from an identified developer" and click "Open Anyway".
1. Click the lock icon again to lock your security settings.

**Upgrade OpenBolt**

To upgrade OpenBolt to the latest version, download the DMG again and repeat the
installation steps.

**Uninstall OpenBolt**

To uninstall OpenBolt, remove OpenBolt's files and executable:

```shell
sudo rm -rf /opt/puppetlabs/bolt /opt/puppetlabs/bin/bolt
```

## Install OpenBolt on Microsoft Windows

Use one of the supported Windows installation methods to install OpenBolt.

### Chocolatey

Not available yet.

### Windows installer (MSI)

Not available yet.

### OpenBolt PowerShell module

Not available yet.

## Install OpenBolt as a gem

To install OpenBolt reliably and with all dependencies, use one of the OpenBolt
installation packages instead of a gem. Gem installations do not include core
modules which are required for common OpenBolt actions.

To install OpenBolt as a gem:

```shell
gem install bolt
```

## Install gems in OpenBolt's Ruby environment

OpenBolt packages include their own copy of Ruby.

When you install gems for use with OpenBolt, use the `--user-install` command-line
option to avoid requiring privileged access for installation. This option also
enables sharing gem content with Puppet installations — such as when running
`apply` on `localhost` — that use the same Ruby version.

To install a gem for use with OpenBolt, use the command appropriate to your
operating system:
- On Windows with the default install location:
    ```
    "C:/Program Files/OpenVox/OpenBolt/bin/gem.bat" install --user-install <GEM>
    ```
- On other platforms:
    ```
    /opt/puppetlabs/bolt/bin/gem install --user-install <GEM>
    ```
