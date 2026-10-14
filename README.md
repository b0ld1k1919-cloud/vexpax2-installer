# vexpax2 installer

These are the standalone Linux and Windows installers for the vexpax2 desktop connection. They contain the PHP TLS gateway and process manager. The order engine is transferred by the desktop application after the connection key is entered; this public repository contains no plugin source, account data, access keys, or private configuration.

Run the appropriate installer from the parent directory where you want a new vexpax2 folder. On success it prints only a short message and the compact connection key. Reinstalling in the same directory preserves the token and certificate; older long-format keys continue to work after upgrading.

Linux requires Ubuntu or Debian with systemd. Windows requires PowerShell. The Windows installer downloads PHP and signed Python installers. The desktop application uploads the engine archive over the pinned TLS connection, then the local worker installs its Python dependencies and starts the engine in the background.

After installation, use vexpax2/manage.sh or vexpax2/manage.ps1 with start, stop, restart, status, key, or uninstall. The uninstall command removes the worker folder and its saved configuration.
