"""Signed official cloud images; never boot a checksum-only or unverified image."""
import hashlib
from pathlib import Path
import re
import subprocess
from urllib.parse import urlsplit
from tools import fetch, private_directory, environment, IMAGE, METADATA, SIGNATURE
from profiles import get


class ImageUnavailable(RuntimeError):
    """The profile has no authenticated image source available to this driver."""


def checksum_for(text, filename, algorithm):
    length = 64 if algorithm == 'sha256' else 128
    matches = []
    for line in text.splitlines():
        gnu = re.fullmatch(r'([0-9a-fA-F]{' + str(length) + r'})\s+\*?(.+)', line.strip())
        bsd = re.fullmatch(algorithm.upper() + r' \((.+)\) = ([0-9a-fA-F]{' + str(length) + r'})', line.strip())
        if gnu and gnu[2] == filename: matches.append(gnu[1].lower())
        if bsd and bsd[1] == filename: matches.append(bsd[2].lower())
    if len(matches) != 1:
        raise ValueError('Signed checksum must identify exactly one selected image')
    return matches[0]


def prepare_image(cache, name):
    profile = get(name)
    if profile.get('image_blocked_reason'):
        raise ImageUnavailable(profile['image_blocked_reason'])
    if 'image_url' not in profile:
        raise ValueError('This profile requires its dedicated installer path')
    work = cache / 'images' / name
    private_directory(work)
    home = work / 'verification'
    private_directory(home)
    key = home / 'public-key'
    if not key.exists(): fetch(profile['key_url'], key, METADATA)
    info = subprocess.run(['gpg', '--homedir', str(home), '--batch', '--with-colons', '--show-keys', str(key)], check=True, capture_output=True, text=True)
    fingerprints = [line.split(':')[9] for line in info.stdout.splitlines() if line.startswith('fpr:')]
    if profile['fingerprint'] not in fingerprints:
        raise ValueError('Distribution signing-key fingerprint mismatch')
    subprocess.run(['gpg', '--homedir', str(home), '--batch', '--import', str(key)], check=True, capture_output=True)
    ring = home / 'verified-keyring.gpg'
    export = subprocess.run(['gpg', '--homedir', str(home), '--batch', '--export', profile['fingerprint']], check=True, capture_output=True)
    ring.write_bytes(export.stdout)
    sums = work / 'checksums'
    if not profile.get('immutable_checksums') or not sums.exists():
        fetch(profile['sums_url'], sums, METADATA)
    if profile.get('signature_url'):
        signature = work / 'checksums.sig'; fetch(profile['signature_url'], signature, SIGNATURE)
        subprocess.run(['gpgv', '--homedir', str(home), '--keyring', str(ring), str(signature), str(sums)], check=True, capture_output=True)
        text = sums.read_text()
    else:
        verified = work / 'verified-checksums'
        verified.unlink(missing_ok=True)
        subprocess.run(['gpgv', '--homedir', str(home), '--keyring', str(ring), '--output', str(verified), str(sums)], check=True, capture_output=True)
        text = verified.read_text()
    filename = Path(urlsplit(profile['image_url']).path).name
    digest = checksum_for(text, filename, profile['hash'])
    destination = work / filename
    def valid():
        if not destination.is_file(): return False
        with destination.open('rb') as stream:
            return hashlib.file_digest(stream, profile['hash']).hexdigest() == digest
    if not valid():
        print('Downloading official ' + profile['name'] + ' image', flush=True)
        fetch(profile['image_url'], destination, IMAGE)
    if not valid(): raise ValueError('Distribution image checksum mismatch')
    probe = subprocess.run([str(cache / 'tools/usr/bin/qemu-img'), 'info', '--output=json', str(destination)],
                           env=environment(cache / 'tools'), capture_output=True, text=True, check=True)
    import json
    info = json.loads(probe.stdout)
    if info.get('format') != 'qcow2' or info.get('backing-filename') or info.get('data-file'):
        raise ValueError('Distribution image must be a standalone qcow2 image')
    print(profile['name'] + ': signed image verified', flush=True)
    return destination
