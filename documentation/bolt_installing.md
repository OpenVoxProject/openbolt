# Installing Bolt

Packaged versions of Bolt are available for several Linux distributions and macOS. Windows is currently (year 2026) supported as target.

An up to date list of supported platforms can be retrieved on [voxpupuli-artifacts](https://artifacts.voxpupuli.org/openbolt/5.4.0/)

Excerpt from [voxpupuli-artifacts](https://artifacts.voxpupuli.org/openbolt/5.4.0/) (2026)

| Operating system          | Versions            |
| ------------------------- | ------------------- |
| Debian                    | 11, 12, 13          |
| Fedora                    | 42, 43              |
| macOS                     | *                   |
| RHEL                      | 8, 9, 10            |
| SLES                      | 15, 16              |
| Ubuntu                    | 22, 24, 25, 26      |
| Amazon-Linux              | 2, 2023             |


## Install Bolt on Debian

**Install Bolt**

- _Debian_
  ```shell
  # https://artifacts.voxpupuli.org/openbolt/5.4.0/openbolt_5.4.0-1%2Bdebian11_amd64.deb
  source /etc/os-release
  source <( dpkg-architecture --list)
  packagename="openbolt_5.4.0-1+debian${VERSION_ID}_${DEB_HOST_ARCH}.deb"
  wget "https://artifacts.voxpupuli.org/openbolt/5.4.0/$packagename"
  sudo dpkg -i "$packagename"
  ```

**Uninstall Bolt**

To uninstall Bolt, run the following command:

```shell
sudo apt remove openbolt
```

## Install Bolt on Fedora

**Install Bolt**

To install Bolt, run the appropriate command for the version of Fedora you
have installed:

- _Fedora 43_

  ```shell
  sudo rpm -Uvh https://artifacts.voxpupuli.org/openbolt/5.4.0/openbolt-5.4.0-1.fc43.x86_64.rpm
  ```

**Upgrade Bolt**

To upgrade Bolt to the latest version, run the following command:

```shell
sudo dnf upgrade puppet-bolt
```

**Uninstall Bolt**

To uninstall Bolt, run the following command:

```shell
sudo dnf remove puppet-bolt
```

## Install Bolt on macOS

You can install Bolt packages for macOS using either Homebrew or the
macOS installer.

### Homebrew

**Install Bolt**

To install Bolt with Homebrew, you must have the [Homebrew package
manager](https://brew.sh/) installed.

1. Tap the Puppet formula repository:

   ```shell
   brew tap puppetlabs/puppet
   ```

1. Install Bolt:

   ```shell
   brew install --cask puppet-bolt
   ```

**Upgrade Bolt**

To upgrade Bolt to the latest version, run the following command:

```shell
brew upgrade --cask puppet-bolt
```

**Uninstall Bolt**

To uninstall Bolt, run the following command:

```shell
brew uninstall --cask puppet-bolt
```

### macOS installer (DMG)

**Install Bolt**

Use the Apple Disk Image (DMG) to install Bolt on macOS:

1. Download the Bolt installer package for your macOS version.

   - [26 Tahoe x86](https://artifacts.voxpupuli.org/openbolt/5.4.0/openbolt-5.4.0-1.macos.all.x86_64.dmg)
   - [26 Tahoe arm64](https://artifacts.voxpupuli.org/openbolt/5.4.0/openbolt-5.4.0-1.macos.all.arm64.dmg)
   - [any x86](https://artifacts.voxpupuli.org/openbolt/5.4.0/openbolt-5.4.0-1.macos.all.x86_64.dmg)
   - [any arm64](https://artifacts.voxpupuli.org/openbolt/5.4.0/openbolt-5.4.0-1.macos.all.arm64.dmg)

1. Double-click the `puppet-bolt-latest.dmg` file to mount the installer and
   then double-click `puppet-bolt-[version]-installer.pkg` to run the installer.

If you get a message that the installer "can't be opened because Apple cannot check it for malicious software:"
1. Click **** > **System Preferences** > **Security & Privacy**.
1. From the **General** tab, click the lock icon to allow changes to your security settings and enter your macOS password.
1. Look for a message that says the Bolt installer "was blocked from use because it is not from an identified developer" and click "Open Anyway".
1. Click the lock icon again to lock your security settings.

**Upgrade Bolt**

To upgrade Bolt to the latest version, download the DMG again and repeat the
installation steps.

**Uninstall Bolt**

To uninstall Bolt, remove Bolt's files and executable:

```shell
sudo rm -rf /opt/puppetlabs/bolt /opt/puppetlabs/bin/bolt
```


## Install Bolt on RHEL

**Install Bolt**

To install Bolt, run the appropriate command for the version of RHEL you
have installed:

- _RHEL 10_

  ```shell
  sudo rpm -Uvh https://artifacts.voxpupuli.org/openbolt/5.4.0/openbolt-5.4.0-1.el10.x86_64.rpm
  ```

- _RHEL 9_

  ```shell
  sudo rpm -Uvh https://artifacts.voxpupuli.org/openbolt/5.4.0/openbolt-5.4.0-1.el9.x86_64.rpm
  ```
- _RHEL 8_

  ```shell
  sudo rpm -Uvh https://artifacts.voxpupuli.org/openbolt/5.4.0/openbolt-5.4.0-1.el8.x86_64.rpm
  ```

**Uninstall Bolt**

To uninstall Bolt, run the following command:

```shell
sudo yum remove openbolt
```

## Install Bolt on SLES

**Install Bolt**

To install Bolt, run the appropriate command for the version of SLES you
have installed:

- _SLES 16_

  ```shell
  sudo rpm -Uvh https://artifacts.voxpupuli.org/openbolt/5.4.0/openbolt-5.4.0-1.sles16.x86_64.rpm
  ```
- _SLES 15_

  ```shell
  sudo rpm -Uvh https://artifacts.voxpupuli.org/openbolt/5.4.0/openbolt-5.4.0-1.sles15.x86_64.rpm
  sudo zypper install puppet-bolt
  ```

**Uninstall Bolt**

To uninstall Bolt, run the following command:

```shell
sudo zypper remove openbolt
```

## Install Bolt on Ubuntu

**Install Bolt**

To install Bolt, run the appropriate command for the version of Ubuntu you
have installed:

- _Ubuntu 26.04_ _Ubuntu 25.04_ _Ubuntu 14.04_ _Ubuntu 22.04_ 

  ```shell
  # https://artifacts.voxpupuli.org/openbolt/5.4.0/openbolt_5.4.0-1%2Bubuntu26.04_amd64.deb
  source /etc/os-release
  source <( dpkg-architecture --list)
  packagename="openbolt_5.4.0-1+ubuntu${VERSION_ID}_${DEB_HOST_ARCH}.deb"
  wget "https://artifacts.voxpupuli.org/openbolt/5.4.0/$packagename"
  sudo dpkg -i "$packagename"
  ```

**Uninstall Bolt**

To uninstall Bolt, run the following command:

```shell
sudo apt remove openbolt
```

## Install Bolt as a gem

To install Bolt reliably and with all dependencies, use one of the Bolt
installation packages instead of a gem. Gem installations do not include core
modules which are required for common Bolt actions.

To install Bolt as a gem:

```shell
gem install bolt
```

## Install gems in Bolt's Ruby environment

Bolt packages include their own copy of Ruby.

When you install gems for use with Bolt, use the `--user-install` command-line
option to avoid requiring privileged access for installation. This option also
enables sharing gem content with Puppet installations — such as when running
`apply` on `localhost` — that use the same Ruby version.

To install a gem for use with Bolt, use the command appropriate to your
operating system:
- On Windows with the default install location:
    ```
    "C:/Program Files/Puppet Labs/Bolt/bin/gem.bat" install --user-install <GEM>
    ```
- On other platforms:
    ```
    /opt/puppetlabs/bolt/bin/gem install --user-install <GEM>
    ```
