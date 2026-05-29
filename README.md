# LokaleKI Quick Installer

Public bootstrap for the private LokaleKI customer runtime package.

```bash
curl -fsSL https://raw.githubusercontent.com/slavko-at-klincov-it/localeki-install/main/install.sh | bash
```

The script asks for a GitHub token in the terminal, downloads the private customer release asset, verifies its GitHub SHA256 digest, extracts it under `~/LokaleKI/installer`, and starts `./lokale-ki-setup`.

It does not contain customer secrets or the private runtime package.
