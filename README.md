# vexpax2 installer

These are the standalone Linux and Windows installers for the first-stage vexpax2 desktop connection. They contain only a minimal PHP health-check worker and management scripts. They contain no account data, access keys, existing vexpax plugins, or configuration.

Run the appropriate installer from the parent directory where you want a new vexpax2 folder. The installer prints a connection key. A repeated installation in the same directory preserves the token and certificate, so the key stays the same.

Linux requires Ubuntu or Debian with systemd. Windows requires PowerShell. The Windows installer downloads an official PHP archive and verifies its SHA-256 hash before extracting it.

After installation, use vexpax2/manage.sh or vexpax2/manage.ps1 with start, stop, restart, status, key, or uninstall. The uninstall command removes the worker folder and its saved configuration.

