# deb2rpm

Converts a `.deb` package to `.rpm`, strips the `/usr/bin` directory ownership entry that causes install conflicts, and drops the result next to your original file.

Built and tested for installing [Bitwig Studio](https://www.bitwig.com) on RPM-based distros (Fedora, openSUSE, etc.), since Bitwig only ships `.deb` packages.

## Dependencies

```
sudo apt install alien rpm rpm-build rpmrebuild
```

## Usage

```bash
chmod +x deb2rpm.sh
./deb2rpm.sh bitwig-studio-*.deb
```

The final `.rpm` is placed in the same directory as the input file.

## What it does

1. Checks that `alien`, `rpmrebuild`, and `rpmbuild` are present.
2. Runs `sudo alien -kr` on the input file.
3. Rebuilds the RPM with `rpmrebuild`, patching the spec to remove:
   ```
   %dir %attr(0755, root, root) "/usr/bin"
   ```
4. Copies the result next to the original `.deb`.

## Bitwig dependencies

Bitwig may pull in libraries that are outdated or no longer in the default repos of current distro releases. At the time of writing, these are still available via [COPR](https://copr.fedorainfracloud.org/) — search there if `dnf` complains about missing dependencies after installing the converted package.
