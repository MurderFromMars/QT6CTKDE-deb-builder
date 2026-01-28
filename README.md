# QT6CT KDE DEB BUILDER

A simple builder that packages QT6CT KDE into a Debian package with an integrated updater service and timer.  
The script compiles from source, installs cleanly, and places the finished package in your Downloads folder.

## Why This Project Exists

QT6CT KDE is available on the AUR but not packaged for Debian or Ubuntu. Building it manually is repetitive and there is no native update path.  
This project fills that gap by creating a proper Debian package and adding an automatic updater so you get a clean install and seamless updates without rebuilding or reinstalling.


## Install

```sh
curl -fsSL https://raw.githubusercontent.com/MurderFromMars/QT6CTKDE-deb-builder/main/QT6KDE.sh | bash
```

Works in any shell because it streams directly into bash.

## Features

- Builds QT6CT KDE from the upstream AUR repository  
- Installs an updater script in usr local bin  
- Includes a systemd service and timer for daily updates  
- Updates in place without reinstalling the package  
- Cleans up after itself  
- Outputs to Downloads
- Automatically installs all dependencies for building

## Enabling the Updater

```sh
sudo systemctl enable --now qt6ct-kde-update.timer
```

## Uninstall

```sh
sudo apt remove qt6ct-kde
sudo rm -rf /var/lib/qt6ct-kde
```

