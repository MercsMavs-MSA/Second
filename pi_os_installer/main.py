# Automated Self-Install Script for an Attendance Tracker Kiosk
import platform
import sys
import os
import subprocess
import time
import venv
import shutil
import pwd
import grp
import tarfile
from shutil import which
from typing import Callable

try:
    from rich.console import Console
    from prompt_toolkit import choice
    from prompt_toolkit.formatted_text import HTML
    from prompt_toolkit.shortcuts import ProgressBar
    import requests
except ImportError:
    Console = None
    choice = None
    HTML = None
    ProgressBar = None
    requests = None

ENV_PATH: str = os.environ.get("ENV_PATH", "/tmp/attendanceTrackerInstallerEnv")
SKIP_CHECKS: bool = os.environ.get("SKIP_CHECKS", False)

DEPS: list[str] = ["rich~=14.1.0", "prompt-toolkit~=3.0.52", "requests~=2.32.5"]

GH_REPO: str = "MercsMavs-MSA/Second"
APP_PROCESS_NAME: str = "/home/pi/attendance-tracker/second"

CHECKS: dict[str, Callable[[], bool]] = {
    "Installer is running as root": lambda: is_root(),
    "Available disk space is above 2GB": lambda: get_free_mb() > 2048,
    "APT is available": lambda: has_apt(),
    "No application instances running": lambda: not is_process_or_child_running(APP_PROCESS_NAME)
}


def env_exists(env_dir):
    """Return True if env already exists and looks intact"""
    python_bin = os.path.join(env_dir, "bin", "python")
    pip_bin = os.path.join(env_dir, "bin", "pip")
    return os.path.exists(python_bin) and os.path.exists(pip_bin)


def create_env(env_dir):
    print(f"[*] Creating temporary environment: {env_dir}")
    venv.create(env_dir, with_pip=True)
    python_bin = os.path.join(env_dir, "bin", "python")
    print(f"[*] Installing dependencies: {DEPS}")
    subprocess.check_call([python_bin, "-m", "pip", "install"] + DEPS)
    print("[*] Environment setup complete.")
    return python_bin


def relaunch(env_dir, python_bin):
    print("[*] Relaunching installer inside the temporary environment...")
    os.environ["ENV_PATH"] = env_dir
    os.execv(python_bin, [python_bin] + sys.argv)


def get_default_user():
    """Try to detect default non-root user (UID 1000)"""
    try:
        user_info = pwd.getpwuid(1000)
        return user_info.pw_name
    except KeyError:
        return None


def get_arch():
    arch = platform.machine().lower()
    if arch in ("x86_64", "amd64"):
        return "x86_64"
    elif arch in ("aarch64", "arm64"):
        return "arm64"
    else:
        return None


def get_free_mb(path="/"):
    total, used, free = shutil.disk_usage(path)
    return free // 1024 // 1024


def is_root():
    return os.getuid() == 0

def has_apt():
    return which("apt") is not None and which("apt-get") is not None

def get_proc_name(pid: str) -> str | None:
    """Get process name from /proc/[pid]/comm."""
    try:
        with open(f"/proc/{pid}/comm", "r") as f:
            return f.read().strip()
    except (FileNotFoundError, PermissionError):
        return None

def get_proc_ppid(pid: str) -> int | None:
    """Get parent PID from /proc/[pid]/stat."""
    try:
        with open(f"/proc/{pid}/stat", "r") as f:
            fields = f.read().split()
            return int(fields[3])  # 4th field is PPID
    except (FileNotFoundError, PermissionError, IndexError, ValueError):
        return None

def is_process_or_child_running(name: str) -> bool:
    """
    Check if a process with the given name or any subprocess it spawned is running.
    """
    # First, find all PIDs with the target name
    target_pids = []
    for pid in os.listdir("/proc"):
        if pid.isdigit():
            proc_name = get_proc_name(pid)
            if proc_name == name:
                target_pids.append(int(pid))

    if not target_pids:
        return False

    # Build parent->children mapping
    children = {}
    for pid in os.listdir("/proc"):
        if pid.isdigit():
            ppid = get_proc_ppid(pid)
            if ppid is not None:
                children.setdefault(ppid, []).append(int(pid))

    # DFS to see if any child exists for our target processes
    seen = set()
    stack = list(target_pids)
    while stack:
        cur = stack.pop()
        if cur in seen:
            continue
        seen.add(cur)
        if cur in children:
            stack.extend(children[cur])

    return bool(seen)


def install_countdown(console: Console, seconds: int = 5) -> bool:
    try:
        for remaining in range(seconds, 0, -1):
            console.print(
                f"[dim]Press Ctrl+C to cancel.[/dim] "
                f"Installing in [bold yellow]{remaining}[/]...",
                end="\r",
                highlight=False,
            )
            time.sleep(1)
        return True

    except KeyboardInterrupt:
        console.print("\n[bold red]Cancelled by user (Ctrl+C)[/]")
        return False

def update_packages(console):
    try:
        console.print("[*] Updating apt cache...")
        update_proc = subprocess.Popen(
            ["apt-get", "update"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        for line in update_proc.stdout:
            console.print(line, end="")
        update_proc.wait()
        if update_proc.returncode != 0:
            raise subprocess.CalledProcessError(update_proc.returncode, "apt-get update")

        console.print("[*] Cache updated")

    except subprocess.CalledProcessError as e:
        console.print(f"[red]Error during package update: {e}[/red]", file=sys.stderr)
        return False

    return True

def install_packages(console, packages):
    try:
        console.print(f"[*] Installing packages: {' '.join(packages)}")
        time.sleep(1)
        update_proc = subprocess.Popen(
            ["apt-get", "install", *packages, "-y", "--no-install-recommends"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        for line in update_proc.stdout:
            console.print(line.replace("\r\n", "\n").replace("\r", "\n"), end="")
        update_proc.wait()
        if update_proc.returncode != 0:
            raise subprocess.CalledProcessError(update_proc.returncode, "apt-get install")

        console.print("[*] Cache updated")

    except subprocess.CalledProcessError as e:
        console.print(f"[red]Error during package install: {e}[/red]", file=sys.stderr)
        return False

    return True

def run_installer():
    console = Console()
    console.clear()
    console.print("[green]Welcome to the SECOND Installer![/green]")

    console.print("Running pre-install checks...")

    for name, check in CHECKS.items():
        if check():
            console.print(f"{name}: [green]v[/green]")
        else:
            console.print(f"{name}: [red]x[/red]")
            console.print(
                "[bold red]Installation failed! Check the above logs for more info[/bold red]"
            )
            return 1
    console.print("[bold green]All checks passed![/bold green]")
    console.print(
        "[bold yellow]It is recommended to use the default settings below. Modifying them may result in installation failure, and/or a non-functional kiosk.[/bold yellow]"
    )

    user_account = choice(
        message="Please choose a UNIX user to install to:",
        options=[
            (user.pw_name, user.pw_name) for user in pwd.getpwall() if user.pw_shell
            not in (
                "/usr/bin/nologin",
                "/usr/sbin/nologin",
                "/sbin/nologin",
                "/bin/nologin",
            )
            and user.pw_uid != 0
        ],
        default=get_default_user(),
    )

    console.print(f"Fetching releases from {GH_REPO}")
    try:
        releases_url = f"https://api.github.com/repos/{GH_REPO}/releases"
        response = requests.get(releases_url, timeout=5)
        releases = response.json()
        valid_releases = []

        for release in releases:
            version = release["tag_name"]
            title = release["name"]
            pre_release = release["prerelease"]
            assets = release["assets"]
            dl_url = None
            for asset in assets:
                if asset["name"] == f"linux-{get_arch()}-{version}.tar.gz":
                    dl_url = asset["browser_download_url"]
            if not dl_url:
                console.print(f"[yellow]Invalid release tag: {version}[/yellow]")

            if dl_url:
                release_info = {
                    "version": version,
                    "title": title,
                    "prerelease": pre_release,
                    "dl_url": dl_url,
                }
                valid_releases.append(release_info)
    except Exception as e:
        console.print(f"[bold red]Error fetching releases: {repr(e)}[/bold red]")
        return 1

    release_choice = choice(
        message="Choose your desired version:",
        options=[
            (
                rel["version"],
                HTML(
                    f"{'<ansiyellow>' if rel['prerelease'] else ''}"
                    f"{rel['title']} [{rel['version']}]"
                    f"{' [PR]</ansiyellow>' if rel['prerelease'] else ''}"
                )
            )
            for rel in valid_releases
        ],
    )

    # countdown
    ret = install_countdown(console)
    if not ret:
        return 2

    console.print(
        f"[cyan]Installing SECOND for user: {user_account}[/cyan]"
    )

    # download release
    release = next(rel for rel in valid_releases if rel["version"] == release_choice)
    dl_url = release["dl_url"]

    home_dir = os.path.expanduser(f"~{user_account}")
    os.makedirs(home_dir, exist_ok=True)
    dest_path = os.path.join(home_dir, f"attendance-tracker-{release_choice}.tar.gz")

    console.print(f"[cyan]Downloading {dl_url} → {dest_path}[/cyan]")

    try:
        with requests.get(dl_url, stream=True, timeout=10) as r:
            r.raise_for_status()
            total = int(r.headers.get("Content-Length", 0))
            with open(dest_path, "wb") as f, ProgressBar() as pb:
                for chunk in pb(r.iter_content(chunk_size=8192), total=total // 8192):
                    if chunk:
                        f.write(chunk)
    except Exception as e:
        console.print(f"[red]Error downloading release: {repr(e)}[/red]")
        return 1

    # Fix ownership (assume group == username)
    try:
        uid = pwd.getpwnam(user_account).pw_uid
        gid = grp.getgrnam(user_account).gr_gid
        os.chown(dest_path, uid, gid)
    except Exception as e:
        console.print(f"[red]Warning: Could not change file ownership: {repr(e)}[/red]")

    console.print("[green]Download complete.[/green]")

    extract_dir = os.path.join(home_dir, f"attendance-tracker")
    os.makedirs(extract_dir, exist_ok=True)
    console.print(f"[cyan]Extracting to {extract_dir}[/cyan]")

    try:
        with tarfile.open(dest_path, "r:gz") as tar:
            members = tar.getmembers()
            total_members = len(members)

            with ProgressBar() as pb:
                for member in pb(members, total=total_members):
                    tar.extract(member, path=extract_dir)
    except Exception as e:
        console.print(f"[red]Error extracting tarball: {repr(e)}[/red]")
        return 1

    try:
        uid = pwd.getpwnam(user_account).pw_uid
        gid = grp.getgrnam(user_account).gr_gid

        for root, dirs, files in os.walk(extract_dir):
            os.chown(root, uid, gid)
            for d in dirs:
                os.chown(os.path.join(root, d), uid, gid)
            for f_name in files:
                os.chown(os.path.join(root, f_name), uid, gid)

        console.print(f"Files ownership set to {user_account}:{user_account}")
    except Exception as e:
        console.print(f"[red]Warning: Could not set ownership: {repr(e)}[/red]")

    console.print("[green]Extraction complete.[/green]")

    console.print("Installing dependencies for Attendance Tracker Runtime")

    ret = update_packages(console)
    if not ret:
        console.print("[bold red]Installation failed![/bold red]")
        return 0

    ret = install_packages(console, ["libgtk-3-0", "libgstreamer-plugins-base1.0-0", "fonts-noto-color-emoji", "libvorbisfile3"])
    if not ret:
        console.print("[bold red]Installation failed![/bold red]")
        return 0

    console.print("Installing dependencies for X11 GUI")

    ret = install_packages(console, ["xorg", "ratpoison", "lightdm", "pulseaudio", "xdg-desktop-portal-gtk", "udisks2", "udiskie", "gldriver-test"]) # TODO: Test this on Pi4, Pi5 works
    if not ret:
        console.print("[bold red]Installation failed![/bold red]")
        return 0

    console.print("[green]X11 GUI dependencies installed[/green]")

    # create .xsession
    xsession_path = os.path.join(home_dir, ".xsession")
    with open(xsession_path, "w") as xsession:
        xsession.write("#!/bin/sh\nexec pulseaudio --start\nexec ratpoison\n")
    console.print(f"[green]Created user XSession for {user_account}[/green]")

    try:
        uid = pwd.getpwnam(user_account).pw_uid
        gid = grp.getgrnam(user_account).gr_gid

        os.chown(xsession_path, uid, gid)
        os.chmod(xsession_path, 0o764)

        console.print(f"XSession ownership set to {user_account}:{user_account} and marked as 0o764")
    except Exception as e:
        console.print(f"[red]Warning: Could not set ownership: {repr(e)}[/red]")

    # configure lightdm
    with open("/usr/share/xsessions/ratpoison.desktop", "w") as ratpoison_xsession:
        ratpoison_xsession.write(
            """
[Desktop Entry]
Name=Ratpoison
Comment=Ratpoison window manager
Exec=ratpoison
TryExec=ratpoison
Type=Application
"""
        )
    console.print(f"[green]Configured ratpoison desktop session: {user_account}[/green]")

    os.makedirs("/etc/lightdm", exist_ok=True)
    with open("/etc/lightdm/lightdm.conf", "w") as lightdm_conf:
        lightdm_conf.write(
            f"""[Seat:*]
autologin-user={user_account}
autologin-user-timeout=0
user-session=ratpoison
greeter-session=lightdm-gtk-greeter
"""
        )
    console.print(f"[green]Configured LightDM autologin for user: {user_account}[/green]")

    # set default boot target
    update_proc = subprocess.Popen(
        ["systemctl", "set-default", "graphical.target"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    for line in update_proc.stdout:
        console.print(line, end="")
    update_proc.wait()
    if update_proc.returncode != 0:
        raise subprocess.CalledProcessError(update_proc.returncode, "systemctl set-default graphical.target")
    console.print(f"[green]Default target is set to graphical[/green]")

    with open(os.path.join(home_dir, ".ratpoisonrc"), "w") as lightdm_conf:
        lightdm_conf.write(
            f"""
exec udiskie -a -n -t &
exec ~/attendance-tracker/second
"""
        )
    try:
        uid = pwd.getpwnam(user_account).pw_uid
        gid = grp.getgrnam(user_account).gr_gid

        os.chown(os.path.join(home_dir, ".ratpoisonrc"), uid, gid)
        os.chmod(os.path.join(home_dir, ".ratpoisonrc"), 0o764)

        console.print(f"ratpoisonrc ownership set to {user_account}:{user_account} and marked as 0o644")
    except Exception as e:
        console.print(f"[red]Warning: Could not set ownership: {repr(e)}[/red]")
    console.print(f"[green]Configured Attendance Tracker auto-start on login: {user_account}[/green]")

    console.print("[green]Installation complete.[/green]")
    return 0


if __name__ == "__main__":
    if os.environ.get("INSTALLER_ENV_ACTIVE") != "1":
        if env_exists(ENV_PATH):
            print(f"[*] Using existing environment: {ENV_PATH}")
            python_bin = os.path.join(ENV_PATH, "bin", "python")
        else:
            python_bin = create_env(ENV_PATH)

        os.environ["INSTALLER_ENV_ACTIVE"] = "1"
        relaunch(ENV_PATH, python_bin)
    else:
        sys.exit(run_installer())
