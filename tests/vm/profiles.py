"""Explicit guest profiles. Inclusion in this matrix does not mean verified support."""
APT_PACKAGES = ["hyprland", "quickshell", "libqt6svg6", "qt6-wayland", "libgl1-mesa-dri",
                "qml6-module-qtquick", "qml6-module-qtquick-window", "qml6-module-qtquick-controls",
                "qml6-module-qtquick-layouts", "qml6-module-qtquick-dialogs", "qml6-module-qtquick-effects",
                "qml6-module-qtquick-shapes", "qml6-module-qtmultimedia", "openssh-server", "python3",
                "fonts-dejavu-core", "dbus-x11", "sudo"]
PROFILES = {
    "arch": {"name": "Arch Linux", "os_id": "arch", "admin_group": "wheel", "ssh_service": "sshd",
             "packages": ["hyprland", "quickshell", "qt6-svg", "qt6-multimedia", "mesa", "openssh", "python", "ttf-dejavu", "swayidle", "grim"]},
    "fedora": {"name": "Fedora 44", "os_id": "fedora", "compositor": "Sway", "version_id": "44", "admin_group": "wheel", "ssh_service": "sshd",
               "packages": ["sway", "quickshell", "qt6-qtsvg", "qt6-qtmultimedia", "qt6-qtwayland",
                            "mesa-dri-drivers", "mesa-libEGL", "openssh-server", "python3", "dejavu-sans-fonts", "dbus-x11", "sudo", "util-linux", "swayidle", "grim", "rpm-build"],
               "image_url": "https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2",
               "sums_url": "https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/Fedora-Cloud-44-1.7-x86_64-CHECKSUM",
               "key_url": "https://fedoraproject.org/fedora.gpg", "fingerprint": "36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6", "hash": "sha256", "immutable_checksums": True},
    "ubuntu": {"name": "Ubuntu 26.04 LTS", "os_id": "ubuntu", "version_id": "26.04", "admin_group": "sudo", "ssh_service": "ssh",
               "packages": APT_PACKAGES,
               "image_url": "https://cloud-images.ubuntu.com/releases/resolute/release/ubuntu-26.04-server-cloudimg-amd64.img",
               "sums_url": "https://cloud-images.ubuntu.com/releases/resolute/release/SHA256SUMS",
               "signature_url": "https://cloud-images.ubuntu.com/releases/resolute/release/SHA256SUMS.gpg",
               "key_url": "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xD2EB44626FDDC30B513D5BB71A5D6C4C7DB87C81",
               "fingerprint": "D2EB44626FDDC30B513D5BB71A5D6C4C7DB87C81", "hash": "sha256"},
    "debian": {"name": "Debian 13", "os_id": "debian", "version_id": "13", "admin_group": "sudo", "ssh_service": "ssh",
               "image_blocked_reason": "Official cloud directory has checksums but no detached signature; signed installer adapter required",
               "packages": APT_PACKAGES,
               "image_url": "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2",
               "sums_url": "https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS",
               "key_url": "https://keyring.debian.org/pks/lookup?op=get&search=0xDF9B9C49EAA9298432589D76DA87E80D6294BE9B",
               "fingerprint": "DF9B9C49EAA9298432589D76DA87E80D6294BE9B", "hash": "sha512"},
    "cachyos": {"name": "CachyOS", "os_id": "cachyos", "admin_group": "wheel", "ssh_service": "sshd",
                "packages": [], "installer": "https://github.com/CachyOS/New-Cli-Installer",
                "bootstrap": "arch", "requires_kernel": "cachyos"},
}


def get(name):
    if name not in PROFILES:
        raise ValueError("Unknown guest distribution")
    return PROFILES[name]


def verify_identity(name, identity, kernel):
    expected = get(name)
    if identity.get('ID') != expected['os_id'] or (expected.get('version_id') and identity.get('VERSION_ID') != expected['version_id']):
        raise ValueError('Guest distribution identity mismatch')
    if expected.get('requires_kernel') and expected['requires_kernel'] not in kernel:
        raise ValueError('Expected distribution kernel is not running')
